import AppKit
import SwiftUI
import Vision
import ScreenCaptureKit
import Translation

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
    .init(code: "th", name: "Thai")
]

private let targetLanguages = sourceLanguages.filter { $0.code != "auto" }

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var sourceCode = "vi"
    @Published var targetCode = "en"
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var status = "Place the lens over text, then click Capture."
    @Published var isWorking = false
    @Published var autoScan = false
    @Published var configuration: TranslationSession.Configuration?

    weak var lensView: NSView?
    var captureHandler: (() -> Void)?

    func translate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "No text found. Move the lens or use Paste text."
            isWorking = false
            return
        }
        sourceText = trimmed
        translatedText = ""
        status = "Translating…"
        isWorking = true
        let source = sourceLanguages.first { $0.code == sourceCode }?.language
        let target = targetLanguages.first { $0.code == targetCode }?.language
        var next = TranslationSession.Configuration(source: source, target: target)
        if let current = configuration, current.source == source, current.target == target {
            next = current
            next.invalidate()
        }
        configuration = next
    }

    func retranslate() {
        guard !sourceText.isEmpty else { return }
        translate(sourceText)
    }

    func runTranslation(_ session: TranslationSession) async {
        let text = sourceText
        guard !text.isEmpty else { return }
        do {
            let response = try await session.translate(text)
            guard text == sourceText else { return }
            translatedText = response.targetText
            status = "Ready"
        } catch {
            guard text == sourceText else { return }
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
                Toggle("Auto scan after moving", isOn: $model.autoScan)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: model.autoScan) { _, enabled in
                        model.status = enabled
                            ? "Auto scan is on. Move the lens over text."
                            : "Auto scan is off. Click Capture when ready."
                    }
                Spacer()
                Text("Off by default")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.orange.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                VStack(spacing: 5) {
                    Image(systemName: "text.viewfinder")
                    Text("Text beneath this lens will be read")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 128)
            .background(LensAnchor(model: model))

            VStack(alignment: .leading, spacing: 8) {
                Text("ORIGINAL")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(model.sourceText.isEmpty ? "Text read from the lens will appear here." : model.sourceText)
                    .font(.subheadline)
                    .foregroundStyle(model.sourceText.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                Divider()
                Text("TRANSLATION")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(model.translatedText.isEmpty ? "Your translation will appear here." : model.translatedText)
                    .font(.body)
                    .foregroundStyle(model.translatedText.isEmpty ? .secondary : .primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
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
        .frame(width: 470, height: 470)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menuIcon = NSImage(systemSymbolName: "character.viewfinder", accessibilityDescription: "Floating Translator")
        menuIcon?.isTemplate = true
        statusItem.button?.image = menuIcon
        statusItem.button?.title = " Vi·En"
        statusItem.button?.toolTip = "Show or hide Floating Translator"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 470, height: 470),
                             styleMask: [.titled, .closable],
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
        window.contentView = NSHostingView(rootView: LensView(model: model))
        window.center()
        window.delegate = self
        panel = window
        model.captureHandler = { [weak self] in self?.capture() }
        showPanel()
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
            self?.capture()
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

    private func capture() {
        pendingScan?.cancel()
        guard !model.isWorking, let lens = model.lensView, let window = lens.window else { return }
        let localRect = lens.convert(lens.bounds, to: nil)
        let screenRect = window.convertToScreen(localRect)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(screenRect.midpoint) }),
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            model.status = "Move the lens fully onto a display and try again."
            return
        }
        model.isWorking = true
        model.status = "Reading text…"
        panel.orderOut(nil)
        Task {
            // Let WindowServer remove the lens before taking a one-frame screenshot.
            try? await Task.sleep(nanoseconds: 180_000_000)
            do {
                let image = try await Self.captureDisplay(displayID: displayNumber.uint32Value,
                                                          screen: screen, rect: screenRect)
                let text = try await Self.recognize(image, sourceCode: model.sourceCode)
                panel.makeKeyAndOrderFront(nil)
                model.translate(text)
            } catch {
                panel.makeKeyAndOrderFront(nil)
                model.isWorking = false
                model.status = "Capture needs Screen Recording permission in System Settings → Privacy & Security. \(error.localizedDescription)"
            }
        }
    }

    private static func captureDisplay(displayID: CGDirectDisplayID, screen: NSScreen,
                                       rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
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
            let codes: [String: String] = [
                "vi": "vi-VT", "en": "en-US", "fr": "fr-FR", "de": "de-DE",
                "es": "es-ES", "ja": "ja-JP", "ko": "ko-KR",
                "zh-Hans": "zh-Hans", "th": "th-TH"
            ]
            let preferred = codes[sourceCode] ?? "vi-VT"
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = [preferred, "en-US", "vi-VT"]
                .filter { supported.contains($0) }
                .uniqued()
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
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
