import AppKit
import SwiftUI
import ScreenCaptureKit
import Vision
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = TranslatorModel()
    private var statusItem: NSStatusItem!
    private var panel: UtilityPanel!
    private var scanFrame: ScanFrameController?
    private let picker = AreaPicker()
    private var liveTimer: Timer?
    private var pendingScan: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var captureGeneration = 0
    private var lastOCRText = ""
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "FloatingTranslator.MenuBar"
        statusItem.isVisible = true
        let image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Floating Translator")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = image
        statusItem.button?.title = image == nil ? "T" : ""
        statusItem.button?.toolTip = "Floating Translator (⌥⌘T)"
        statusItem.button?.setAccessibilityLabel("Floating Translator")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        createResultsPanel()
        model.needsScreenAccess = !CGPreflightScreenCaptureAccess()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        installHotKeys()
        showPanel()
    }

    private func createResultsPanel() {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let height = min(740, screen.height - 40)
        panel = UtilityPanel(contentRect: CGRect(x: screen.maxX - 490, y: screen.midY - height / 2,
                                                width: 460, height: height),
                             styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.title = "Floating Translator"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 400, height: 620)
        panel.maxSize = NSSize(width: 1200, height: 1400)
        panel.setFrameAutosaveName("FloatingTranslator.ResultsV2")
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ResultsCard(model: model))
        panel.level = model.isPinned ? .floating : .normal
        model.newAreaHandler = { [weak self] in self?.chooseNewArea() }
        model.showAreaHandler = { [weak self] in self?.showLastArea() }
        model.closeHandler = { [weak self] in self?.hideAll() }
        model.captureHandler = { [weak self] in self?.refresh() }
        model.screenAccessHandler = { [weak self] in self?.enableScreenAccess() }
        model.pasteHandler = { [weak self] text in self?.receiveText(text) }
        model.liveScanHandler = { [weak self] enabled in self?.setLiveScan(enabled) }
        model.pinHandler = { [weak self] in
            guard let self else { return }
            self.panel.level = self.model.isPinned ? .floating : .normal
        }
        model.languageChangeHandler = { [weak self] in self?.cancelCapture(); self?.lastOCRText = "" }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        liveTimer?.invalidate()
        pendingScan?.cancel()
        captureTask?.cancel()
        scanFrame?.hide()
        picker.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !autoCapturePaused, model.needsScreenAccess, CGPreflightScreenCaptureAccess() {
            model.needsScreenAccess = false
            model.status = "Access enabled. Refresh to read your area."
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hideAll(); return false }

    @objc func translateSelection(_ pasteboard: NSPasteboard, userData: String?,
                                 error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Select some text, then choose Translate with Floating Translator." as NSString
            return
        }
        receiveText(text)
    }

    private func receiveText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.status = "There is no text to translate."
            return
        }
        picker.close()
        cancelCapture()
        model.liveScan = false
        model.isEditing = false
        model.inputMode = .text
        scanFrame?.hide()
        showPanel()
        model.translate(text)
    }

    private func chooseNewArea() {
        cancelCapture()
        model.liveScan = false
        model.isEditing = false
        scanFrame?.hide()
        panel.orderOut(nil)
        picker.onSelect = { [weak self] rect in
            guard let self else { return }
            self.installScanFrame(region: rect)
            self.positionResults(near: rect)
            self.showPanel()
            // Give WindowServer time to remove the temporary selection windows.
            self.pendingScan = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                self?.capture()
            }
        }
        picker.onCancel = { [weak self] in
            self?.model.status = "Area selection cancelled."
            self?.showPanel()
        }
        picker.show()
    }

    private func installScanFrame(region selected: CGRect) {
        var region = selected
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(selected.midpoint) }) {
            region.size.width = min(region.width, screen.frame.width - 24)
            region.size.height = min(region.height, screen.frame.height - 76)
            region.origin.x = min(max(region.minX, screen.frame.minX + 12), screen.frame.maxX - region.width - 12)
            region.origin.y = min(max(region.minY, screen.frame.minY + 32), screen.frame.maxY - region.height - 44)
        }
        scanFrame?.hide()
        let controller = ScanFrameController(region: region)
        controller.onChange = { [weak self] rect in
            guard let self else { return }
            self.cancelCapture()
            self.lastOCRText = ""
            UserDefaults.standard.set(NSStringFromRect(rect), forKey: "lastScanArea")
            self.model.status = self.model.liveScan ? "Area moved. Reading shortly…" : "Area moved. Refresh to read it."
            if self.model.liveScan {
                self.pendingScan = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    guard !Task.isCancelled else { return }
                    self?.capture(automatic: true)
                }
            }
        }
        controller.onClose = { [weak self] in
            self?.cancelCapture()
            self?.model.hasArea = false
            self?.model.liveScan = false
            self?.model.status = "Area hidden. Choose New area or Show last scan area."
        }
        scanFrame = controller
        model.inputMode = .area
        model.hasArea = true
        lastOCRText = ""
        UserDefaults.standard.set(NSStringFromRect(region), forKey: "lastScanArea")
        controller.show()
    }

    private func showLastArea() {
        guard let value = UserDefaults.standard.string(forKey: "lastScanArea") else { chooseNewArea(); return }
        let rect = NSRectFromString(value)
        guard rect.width >= 80, rect.height >= 40,
              NSScreen.screens.contains(where: { $0.frame.contains(rect) }) else { chooseNewArea(); return }
        cancelCapture()
        model.liveScan = false
        installScanFrame(region: rect)
        showPanel()
        model.status = "Area restored. Refresh to read it."
    }

    private func positionResults(near rect: CGRect) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rect.midpoint) }) else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        if rect.maxX + 20 + frame.width <= visible.maxX { frame.origin.x = rect.maxX + 20 }
        else if rect.minX - frame.width - 20 >= visible.minX { frame.origin.x = rect.minX - frame.width - 20 }
        else { frame.origin.x = visible.maxX - frame.width - 12 }
        frame.origin.x = max(visible.minX, frame.minX)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.y = min(max(rect.maxY - frame.height, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }

    private func refresh() {
        if model.inputMode == .text {
            if model.sourceText.isEmpty { model.status = "Paste text, send a selection, or choose New area." }
            else { model.retranslate() }
        } else if model.hasArea { capture() }
        else { chooseNewArea() }
    }

    private func setLiveScan(_ enabled: Bool) {
        liveTimer?.invalidate()
        liveTimer = nil
        pendingScan?.cancel()
        guard enabled else { return }
        liveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.model.isReading, !self.model.isEditing,
                      self.panel.isVisible, self.scanFrame?.window.isVisible == true,
                      self.scanFrame?.view.isDragging == false else { return }
                self.capture(automatic: true)
            }
        }
    }

    private func cancelCapture() {
        captureGeneration += 1
        pendingScan?.cancel()
        captureTask?.cancel()
        model.invalidateWork()
    }

    private func enableScreenAccess() {
        if CGPreflightScreenCaptureAccess() {
            autoCapturePaused = false
            model.needsScreenAccess = false
            if model.hasArea { capture() } else { chooseNewArea() }
            return
        }
        if !requestedScreenAccess {
            requestedScreenAccess = true
            if CGRequestScreenCaptureAccess() {
                autoCapturePaused = false
                model.needsScreenAccess = false
                if model.hasArea { capture() } else { chooseNewArea() }
                return
            }
        }
        model.openScreenRecordingSettings()
        model.status = "Enable Floating Translator in Screen Recording settings, then quit and reopen."
    }

    private func capture(automatic: Bool = false) {
        pendingScan?.cancel()
        guard model.inputMode == .area, model.hasArea, let scanFrame,
              !model.isWorking, !model.isEditing, !automatic || !autoCapturePaused else { return }
        guard CGPreflightScreenCaptureAccess() else {
            model.needsScreenAccess = true
            model.status = "Enable capture to read your area. Paste and selected text work without it."
            return
        }
        model.needsScreenAccess = false
        let rect = scanFrame.region
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rect) }),
              let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            model.status = "Keep the whole scan area on one display."
            return
        }
        let generation = captureGeneration
        let sourceCode = model.sourceCode
        model.isWorking = true
        if !automatic { model.status = "Reading your area…" }
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await Self.captureDisplay(displayID: display.uint32Value, screen: screen, rect: rect)
                try Task.checkCancellation()
                let text = try await Self.recognize(image, sourceCode: sourceCode)
                guard generation == captureGeneration, !Task.isCancelled else { return }
                autoCapturePaused = false
                if automatic && text == lastOCRText {
                    model.isWorking = false
                    return
                }
                // Reading/selecting a result must not replace it beneath the pointer.
                if automatic && model.isReading { model.isWorking = false; return }
                lastOCRText = text
                model.translate(text)
            } catch {
                guard generation == captureGeneration, !Task.isCancelled else { return }
                model.isWorking = false
                let failure = error as NSError
                if failure.domain == SCStreamErrorDomain,
                   failure.code == SCStreamError.Code.userDeclined.rawValue {
                    autoCapturePaused = true
                    model.needsScreenAccess = true
                    model.liveScan = false
                    model.status = "Screen access was declined. Use Enable capture to authorize it."
                } else { model.status = "Capture failed: \(error.localizedDescription)" }
            }
        }
    }

    private static func captureDisplay(displayID: CGDirectDisplayID, screen: NSScreen,
                                       rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        // Exclude every window owned by this process, including the scan frame
        // and results card, without hiding either or changing source-app focus.
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
        configuration.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let scaleX = CGFloat(image.width) / screen.frame.width
        let scaleY = CGFloat(image.height) / screen.frame.height
        let crop = CGRect(x: (rect.minX - screen.frame.minX) * scaleX,
                          y: (screen.frame.maxY - rect.maxY) * scaleY,
                          width: rect.width * scaleX, height: rect.height * scaleY).integral
        guard let result = image.cropping(to: crop.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))) else {
            throw CaptureError.invalidRegion
        }
        return result
    }

    private static func recognize(_ image: CGImage, sourceCode: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.005
            request.automaticallyDetectsLanguage = sourceCode == "auto"
            let codes = ["vi": "vi-VT", "en": "en-US", "fr": "fr-FR", "de": "de-DE", "es": "es-ES",
                         "ja": "ja-JP", "ko": "ko-KR", "zh-Hans": "zh-Hans", "th": "th-TH", "ms": "ms-MY"]
            if let preferred = codes[sourceCode] {
                let supported = try request.supportedRecognitionLanguages()
                request.recognitionLanguages = Array(NSOrderedSet(array: [preferred, "en-US", "vi-VT"]))
                    .compactMap { $0 as? String }.filter { supported.contains($0) }
            }
            try VNImageRequestHandler(cgImage: image).perform([request])
            return RecognizedParagraphs.text(from: (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return RecognizedLine(text: text, box: observation.boundingBox)
            })
        }.value
    }

    private func installHotKeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr else { return result }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.handleHotKey(identifier.id) }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                                  Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler) == noErr else { return }
        let modifiers = UInt32(cmdKey | optionKey)
        let keys: [(UInt32, UInt32, UInt32)] = [
            (1, UInt32(kVK_ANSI_T), modifiers), (2, UInt32(kVK_ANSI_R), modifiers),
            (3, UInt32(kVK_ANSI_A), modifiers), (4, UInt32(kVK_ANSI_N), modifiers),
            (5, UInt32(kVK_ANSI_T), modifiers | UInt32(controlKey))
        ]
        for (id, keyCode, flags) in keys {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: 0x46544C4E, id: id)
            if RegisterEventHotKey(keyCode, flags, identifier, GetApplicationEventTarget(), 0, &reference) == noErr,
               let reference { hotKeys.append(reference) }
        }
        if hotKeys.count < keys.count { model.status = "A shortcut is in use. The menu bar and buttons still work." }
    }

    private func handleHotKey(_ id: UInt32) {
        switch id {
        case 1: togglePanel()
        case 2: showPanel(); refresh()
        case 3:
            showPanel()
            if model.inputMode == .area && model.hasArea { model.liveScan.toggle() }
            else { model.status = "Choose an area before enabling Live scan." }
        case 4: chooseNewArea()
        case 5: showPanel(); model.pasteText()
        default: break
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible { hideAll() } else { showPanel() }
    }

    private func hideAll() {
        cancelCapture()
        model.liveScan = false
        model.isReading = false
        picker.close()
        scanFrame?.hide()
        panel.orderOut(nil)
    }

    private func showPanel() {
        guard let panel else { return }
        model.isReading = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if model.inputMode == .area && model.hasArea { scanFrame?.show() }
    }

    private func writeCaptureDiagnostic() {
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
}

private enum CaptureError: LocalizedError {
    case displayNotFound, invalidRegion
    var errorDescription: String? {
        switch self {
        case .displayNotFound: "Display not found"
        case .invalidRegion: "Scan area is outside the display"
        }
    }
}

@main
private struct FloatingTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
