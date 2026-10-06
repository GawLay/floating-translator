import AppKit
import SwiftUI
import Vision
import ScreenCaptureKit
import Translation
import Carbon

private struct LanguageChoice: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
    var language: Locale.Language? {
        code == "auto" ? nil : Locale.Language(identifier: code)
    }
}

private let sourceLanguages: [LanguageChoice] = [
    .init(code: "vi", name: "Vietnamese"),
    .init(code: "auto", name: "Detect language"),
    .init(code: "en", name: "English"),
    .init(code: "fr", name: "French"),
    .init(code: "de", name: "German"),
    .init(code: "es", name: "Spanish"),
    .init(code: "ja", name: "Japanese"),
    .init(code: "ko", name: "Korean"),
    .init(code: "zh-Hans", name: "Chinese"),
    .init(code: "th", name: "Thai"),
    .init(code: "ms", name: "Malay")
]

private let targetLanguages = sourceLanguages.filter { $0.code != "auto" }

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var sourceCode = "vi"
    @Published var targetCode = "en"
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var status = "Move the lens over text to scan, or click Capture."
    @Published var isWorking = false
    @Published var autoScan = true
    @Published var needsScreenAccess = false
    @Published var configuration: TranslationSession.Configuration?
    private var translationRequestID = 0

    weak var lensView: NSView?
    var captureHandler: (() -> Void)?
    var screenAccessHandler: (() -> Void)?

    func translate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translationRequestID += 1
            configuration = nil
            status = "No text found. Move the lens or use Paste text."
            isWorking = false
            return
        }
        sourceText = trimmed
        status = "Translating…"
        isWorking = true
        translationRequestID += 1
        let requestID = translationRequestID
        let source = sourceLanguages.first { $0.code == sourceCode }?.language
        let target = targetLanguages.first { $0.code == targetCode }?.language
        let previousConfiguration = configuration
        configuration = nil
        if source == target, source != nil {
            status = "Choose two different languages."
            isWorking = false
            return
        }
        Task {
            if let source, let target {
                let availability = LanguageAvailability()
                let support = await availability.status(from: source, to: target)
                guard requestID == translationRequestID else { return }
                if support == .unsupported {
                    status = "This language pair is unavailable on this macOS version."
                    isWorking = false
                    return
                }
            }
            guard requestID == translationRequestID else { return }
            if var previousConfiguration,
               previousConfiguration.source == source,
               previousConfiguration.target == target {
                previousConfiguration.invalidate()
                configuration = previousConfiguration
            } else {
                configuration = TranslationSession.Configuration(source: source, target: target)
            }
        }
    }

    func retranslate() {
        guard !sourceText.isEmpty else { return }
        translate(sourceText)
    }

    func runTranslation(_ session: TranslationSession) async {
        let text = sourceText
        let requestID = translationRequestID
        guard !text.isEmpty else { return }
        do {
            let response = try await session.translate(text)
            guard requestID == translationRequestID else { return }
            translatedText = response.targetText
            status = "Ready"
        } catch {
            guard requestID == translationRequestID else { return }
            status = "Translation unavailable: \(error.localizedDescription)"
        }
        isWorking = false
    }

    func pasteText() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            status = "Clipboard has no text."
            return
        }
        translate(value)
    }

    func copyResult() {
        guard !translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
        status = "Translation copied."
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

private final class LensAnchorView: NSView {
    weak var model: TranslatorModel?
    override var isFlipped: Bool { false }
}

private struct LensAnchor: NSViewRepresentable {
    @ObservedObject var model: TranslatorModel

    func makeNSView(context: Context) -> LensAnchorView {
        let view = LensAnchorView()
        view.model = model
        model.lensView = view
        return view
    }

    func updateNSView(_ view: LensAnchorView, context: Context) {
        model.lensView = view
    }
}

private struct LensView: View {
    @ObservedObject var model: TranslatorModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "character.viewfinder")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.78, green: 0.30, blue: 0.20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Translate anywhere")
                        .font(.headline)
                    Text("A tiny lens for text in other apps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Capture") { model.captureHandler?() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(model.isWorking)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.77, green: 0.29, blue: 0.20))
                    .help("Capture the lens (Return or ⌥⌘R)")
            }
            .padding(12)
            .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Picker("From", selection: $model.sourceCode) {
                    ForEach(sourceLanguages) { Text($0.name).tag($0.code) }
                }
                .onChange(of: model.sourceCode) { _, _ in model.retranslate() }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Picker("To", selection: $model.targetCode) {
                    ForEach(targetLanguages) { Text($0.name).tag($0.code) }
                }
                .onChange(of: model.targetCode) { _, _ in model.retranslate() }
            }
            .labelsHidden()
            .padding(7)
            .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Text("SCAN MODE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Picker("Scan mode", selection: $model.autoScan) {
                    Text("Manual").tag(false)
                    Text("Auto").tag(true)
                }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    .onChange(of: model.autoScan) { _, enabled in
                        model.status = enabled
                            ? "Auto scan is on. Move the lens over text."
                            : "Manual mode. Click Capture when ready."
                    }
                Spacer()
                Text("⌥⌘A to switch")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 10))

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.orange.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                VStack(spacing: 5) {
                    Image(systemName: "text.viewfinder")
                    Text(model.needsScreenAccess
                         ? "Enable screen capture once to read other apps"
                         : "Text beneath this lens will be read")
                        .font(.caption)
                    if model.needsScreenAccess {
                        Button("Enable capture") { model.screenAccessHandler?() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                .foregroundStyle(.orange)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, minHeight: 128, maxHeight: .infinity)
            .background(LensAnchor(model: model))
            .overlay(alignment: .bottomTrailing) {
                Label("Resize window for a larger lens", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(7)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                    .padding(8)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ORIGINAL")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    Text(model.sourceText.isEmpty ? "Text read from the lens will appear here." : model.sourceText)
                        .font(.subheadline)
                        .foregroundStyle(model.sourceText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: 64)
                Divider()
                HStack {
                    Text("TRANSLATION")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    if model.isWorking {
                        ProgressView().controlSize(.mini)
                    }
                }
                ScrollView(.vertical) {
                    Text(model.translatedText.isEmpty ? "Your translation will appear here." : model.translatedText)
                        .font(.body)
                        .foregroundStyle(model.translatedText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: 96)
                HStack {
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Paste text") { model.pasteText() }
                    Button("Copy") { model.copyResult() }
                        .disabled(model.translatedText.isEmpty)
                    Button("Quit") { NSApp.terminate(nil) }
                }
                .controlSize(.small)
            }
            .padding(14)
            .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .frame(minWidth: 500, maxWidth: .infinity,
               minHeight: 700, maxHeight: .infinity)
        .background(Color.clear)
        .preferredColorScheme(.light)
        .translationTask(model.configuration) { session in
            await model.runTranslation(session)
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = TranslatorModel()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var pendingScan: Task<Void, Never>?
    private var autoScanEnabledAt = Date.distantFuture
    private var requestedScreenAccess = false
    private var autoCapturePaused = false
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--diagnose-screen-access") {
            writeCaptureDiagnostic()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menuIcon = NSImage(systemSymbolName: "character.viewfinder", accessibilityDescription: "Floating Translator")
        menuIcon?.isTemplate = true
        statusItem.button?.image = menuIcon
        statusItem.button?.title = " Translate"
        statusItem.button?.toolTip = "Show or hide Floating Translator"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 500, height: 700),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
        window.title = "Floating Translator"
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentMinSize = NSSize(width: 500, height: 700)
        window.maxSize = NSSize(width: 1000, height: 1000)
        window.contentView = NSHostingView(rootView: LensView(model: model))
        window.center()
        window.delegate = self
        panel = window
        model.captureHandler = { [weak self] in self?.capture() }
        model.screenAccessHandler = { [weak self] in self?.enableScreenAccess() }
        model.needsScreenAccess = !CGPreflightScreenCaptureAccess()
        if model.needsScreenAccess {
            model.status = "Auto is ready. Click Enable capture to authorize this app once."
        }
        installHotKeys()
        showPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !autoCapturePaused, model.needsScreenAccess, CGPreflightScreenCaptureAccess() {
            model.needsScreenAccess = false
            model.status = "Access enabled. Move the lens over text or click Capture."
        }
    }

    private func enableScreenAccess() {
        if CGPreflightScreenCaptureAccess() {
            autoCapturePaused = false
            model.needsScreenAccess = false
            capture()
            return
        }
        // A consent request must come from this explicit button, never a drag.
        if !requestedScreenAccess {
            requestedScreenAccess = true
            if CGRequestScreenCaptureAccess() {
                model.needsScreenAccess = false
                capture()
                return
            }
        }
        model.openScreenRecordingSettings()
        model.status = "Enable Floating Translator in Screen Recording settings, then quit and reopen."
    }

    private func writeCaptureDiagnostic() {
        // Read-only permission check; this mode never creates a lens or captures.
        let state: [String: Any] = [
            "appPath": Bundle.main.bundlePath,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "screenAccessGranted": CGPreflightScreenCaptureAccess()
        ]
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let destination = directory.appendingPathComponent("Floating Translator")
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted]) {
            try? data.write(to: destination.appendingPathComponent("capture-status.json"), options: .atomic)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func windowDidMove(_ notification: Notification) {
        // Ignore initial WindowServer positioning. Only a user's drag scans automatically.
        guard model.autoScan, Date() >= autoScanEnabledAt,
              NSEvent.pressedMouseButtons != 0 else { return }
        pendingScan?.cancel()
        guard panel.isVisible else { return }
        pendingScan = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            self?.capture(automatic: true)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard model.autoScan else { return }
        pendingScan?.cancel()
        pendingScan = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            self?.capture(automatic: true)
        }
    }

    private func installHotKeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil,
                                           &identifier)
            guard result == noErr else { return result }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            let keyID = identifier.id
            Task { @MainActor in delegate.handleHotKey(keyID) }
            return noErr
        }
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), callback, 1,
                                                &eventType,
                                                Unmanaged.passUnretained(self).toOpaque(),
                                                &hotKeyHandler)
        guard handlerStatus == noErr else { return }

        let modifiers = UInt32(cmdKey | optionKey)
        let shortcuts: [(UInt32, UInt32)] = [
            (1, UInt32(kVK_ANSI_T)), // ⌥⌘T: show or hide
            (2, UInt32(kVK_ANSI_R)), // ⌥⌘R: capture
            (3, UInt32(kVK_ANSI_A))  // ⌥⌘A: Auto Scan on or off
        ]
        for (id, keyCode) in shortcuts {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: 0x46544C4E, id: id)
            let result = RegisterEventHotKey(keyCode, modifiers, identifier,
                                             GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotKeys.append(reference) }
        }
        if hotKeys.count != shortcuts.count {
            model.status = "Some shortcuts are already used by another app. The menu bar button still works."
        }
    }

    private func handleHotKey(_ id: UInt32) {
        switch id {
        case 1: togglePanel()
        case 2:
            if panel.isVisible { capture() }
            else { showPanel() }
        case 3:
            model.autoScan.toggle()
            showPanel()
        default: break
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) }
        else { showPanel() }
    }

    private func showPanel() {
        autoScanEnabledAt = Date().addingTimeInterval(1.5)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func capture(automatic: Bool = false) {
        pendingScan?.cancel()
        guard !automatic || !autoCapturePaused else { return }
        guard !model.isWorking, let lens = model.lensView, let window = lens.window else { return }
        // This passive check cannot show a system permission dialog. The stable
        // signing certificate makes the result consistent across local updates.
        guard CGPreflightScreenCaptureAccess() else {
            model.needsScreenAccess = true
            model.status = "Auto is paused. Click Enable capture to allow the lens to read text."
            return
        }
        model.needsScreenAccess = false
        let localRect = lens.convert(lens.bounds, to: nil)
        let screenRect = window.convertToScreen(localRect)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(screenRect.midpoint) }),
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            model.status = "Move the lens fully onto a display and try again."
            return
        }
        model.isWorking = true
        model.status = "Reading text…"
        Task {
            do {
                let image = try await Self.captureDisplay(displayID: displayNumber.uint32Value,
                                                          screen: screen, rect: screenRect)
                autoCapturePaused = false
                let text = try await Self.recognize(image, sourceCode: model.sourceCode)
                model.translate(text)
            } catch {
                model.isWorking = false
                let captureError = error as NSError
                if captureError.domain == SCStreamErrorDomain,
                   captureError.code == SCStreamError.Code.userDeclined.rawValue {
                    autoCapturePaused = true
                    model.needsScreenAccess = true
                    model.status = "Screen access was declined. Click Enable capture to open Settings."
                } else {
                    model.status = "Capture failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func captureDisplay(displayID: CGDirectDisplayID, screen: NSScreen,
                                       rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        // WindowServer composites the text underneath us without hiding the lens
        // or changing focus in the source app.
        let ownApps = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
        configuration.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let screenshot = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                   configuration: configuration)
        let scaleX = CGFloat(screenshot.width) / screen.frame.width
        let scaleY = CGFloat(screenshot.height) / screen.frame.height
        let crop = CGRect(x: (rect.minX - screen.frame.minX) * scaleX,
                          y: (screen.frame.maxY - rect.maxY) * scaleY,
                          width: rect.width * scaleX, height: rect.height * scaleY).integral
        guard let clipped = screenshot.cropping(to: crop.intersection(CGRect(x: 0, y: 0,
            width: screenshot.width, height: screenshot.height))) else {
            throw CaptureError.invalidRegion
        }
        return clipped
    }

    private static func recognize(_ image: CGImage, sourceCode: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.005
            let codes: [String: String] = [
                "vi": "vi-VT", "en": "en-US", "fr": "fr-FR", "de": "de-DE",
                "es": "es-ES", "ja": "ja-JP", "ko": "ko-KR",
                "zh-Hans": "zh-Hans", "th": "th-TH", "ms": "ms-MY"
            ]
            let preferred = codes[sourceCode] ?? "vi-VT"
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = [preferred, "en-US", "vi-VT"]
                .filter { supported.contains($0) }
                .uniqued()
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).sorted {
                $0.boundingBox.midY > $1.boundingBox.midY
            }.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

private enum CaptureError: LocalizedError {
    case displayNotFound, invalidRegion
    var errorDescription: String? {
        switch self {
        case .displayNotFound: "Display not found"
        case .invalidRegion: "Lens is outside the display"
        }
    }
}

private extension CGRect {
    var midpoint: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

@main
private struct FloatingTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
