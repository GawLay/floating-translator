import AppKit
import SwiftUI

struct ResultsCard: View {
    @ObservedObject var model: TranslatorModel

    var body: some View {
        VStack(spacing: 12) {
            titleBar
            HStack(spacing: 10) {
                Button { model.newAreaHandler?() } label: {
                    Label("New area", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .help("Draw a new capture area (⌥⌘N)")
                Button { model.pasteText() } label: {
                    Label("Paste text", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .help("Translate copied text (⌃⌥⌘T)")
            }
            LanguageBar(model: model)
            if model.needsScreenAccess && model.inputMode == .area {
                HStack(spacing: 10) {
                    Text("Enable screen access to read this area.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Enable capture") { model.screenAccessHandler?() }
                }
                .padding(10)
                .background(fieldColor, in: RoundedRectangle(cornerRadius: 10))
            }
            textPanes
            statusBar
            HStack(spacing: 10) {
                Button { model.captureHandler?() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(model.isWorking || model.isEditing)
                .help(model.inputMode == .area ? "Read this area again (⌥⌘R)" : "Translate the original text again")
                Button { model.copyResult() } label: {
                    Label("Copy translation", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MonochromeButtonStyle(prominent: true, large: true))
                .disabled(model.translatedText.isEmpty)
            }
            Divider()
            HStack(spacing: 8) {
                Toggle("Live scan", isOn: $model.liveScan)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(model.inputMode != .area || !model.hasArea)
                    .help("Read this area every two seconds. Pauses while you interact with this card.")
                Text(model.liveScan ? (model.isReading ? "Paused while reading" : "On") : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WindowResizeGrip().frame(width: 22, height: 22)
                    .help("Drag to resize the results card")
            }
        }
        .padding(18)
        .frame(minWidth: 400, minHeight: 620)
        .background(panelColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .buttonStyle(MonochromeButtonStyle(large: true))
        .foregroundStyle(.white)
        .tint(accent)
        .accentColor(accent)
        .preferredColorScheme(.dark)
        .onHover { model.isReading = $0 }
        .onDisappear { model.isReading = false }
        .translationTask(model.configuration) { session in
            await model.runTranslation(session)
        }
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "text.viewfinder").font(.title3)
                Text("Floating Translator")
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
            }
            .background(WindowDragRegion())
            Menu {
                Button("New area") { model.newAreaHandler?() }
                Button("Translate copied text") { model.pasteText() }
                Button("Show last scan area") { model.showAreaHandler?() }
                Divider()
                Text("Selected text: Services → Translate with Floating Translator")
                Divider()
                Button("Quit Floating Translator") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button { model.isPinned.toggle() } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(model.isPinned ? accent : .secondary)
            }
            .buttonStyle(.plain)
            .help(model.isPinned ? "Unpin results from above other apps" : "Keep results above other apps")
            .accessibilityLabel(model.isPinned ? "Unpin results" : "Pin results")
            Button { model.closeHandler?() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Hide Floating Translator (⌥⌘T)")
        }
        .padding(.bottom, 4)
    }

    private var textPanes: some View {
        GeometryReader { geometry in
            let available = geometry.size.height
            let originalHeight = min(max(80, available * model.originalFraction), max(80, available - 110))
            VStack(spacing: 0) {
                if model.originalExpanded {
                    originalPane
                        .frame(height: originalHeight)
                    resizeDivider(availableHeight: available)
                } else {
                    originalHeader.padding(.bottom, 12)
                }
                translationPane
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var originalHeader: some View {
        HStack(spacing: 8) {
            Button {
                if !model.isEditing { model.originalExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: model.originalExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Original").font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .help("Show or hide the original text")
            Spacer()
            if model.isEditing {
                Button("Cancel") { model.isEditing = false }
                    .buttonStyle(.plain)
                Button("Translate edit") { model.applyEditedText() }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button { model.startEditing() } label: { Image(systemName: "pencil") }
                    .buttonStyle(.plain)
                    .disabled(model.sourceText.isEmpty || model.isWorking)
                    .help("Correct the recognized text")
                    .accessibilityLabel("Edit original text")
            }
        }
        .padding(.bottom, 10)
    }

    private var originalPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            originalHeader
            if model.isEditing {
                TextEditor(text: $model.originalDraft)
                    .font(.system(size: max(13, model.textSize - 3)))
                    .scrollContentBackground(.hidden)
                    .background(fieldColor, in: RoundedRectangle(cornerRadius: 8))
            } else {
                textPane(model.sourceText,
                         placeholder: "Choose New area, paste text, or send selected text through Services.",
                         size: max(13, model.textSize - 3))
            }
        }
    }

    private var translationPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Translation").font(.system(size: 13, weight: .medium))
                if model.isWorking { ProgressView().controlSize(.mini) }
                Spacer()
            }
            textPane(model.translatedText, placeholder: "Your translation will appear here.", size: model.textSize)
        }
    }

    private func textPane(_ text: String, placeholder: String, size: Double) -> some View {
        ScrollView(.vertical) {
            Text(text.isEmpty ? placeholder : text)
                .font(.system(size: text.isEmpty ? 15 : size))
                .lineSpacing(5)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
        }
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func resizeDivider(availableHeight: CGFloat) -> some View {
        ZStack {
            Divider()
            Image(systemName: "ellipsis")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .background(panelColor)
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .background(ResizeCursorRegion())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if model.startingFraction == nil { model.startingFraction = model.originalFraction }
                let initial = model.startingFraction ?? 0.28
                model.originalFraction = min(0.65, max(0.12, initial + value.translation.height / max(1, availableHeight)))
            }
            .onEnded { _ in model.startingFraction = nil })
        .accessibilityElement()
        .accessibilityLabel("Original text pane size")
        .accessibilityValue("\(Int(model.originalFraction * 100)) percent")
        .accessibilityAdjustableAction { direction in
            model.originalFraction = min(0.65, max(0.12, model.originalFraction + (direction == .increment ? 0.05 : -0.05)))
        }
        .help("Drag to resize Original and Translation")
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle().fill(model.isWorking ? accent : Color.white.opacity(0.45)).frame(width: 7, height: 7)
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(model.status)
            Spacer(minLength: 0)
            Button { model.showingTextSize.toggle() } label: { Text("Aa").font(.system(size: 17)) }
                .buttonStyle(.plain)
                .help("Adjust reading text size")
                .accessibilityLabel("Text size")
                .popover(isPresented: $model.showingTextSize) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Text size · \(Int(model.textSize)) pt").font(.headline)
                        Slider(value: $model.textSize, in: 14...30, step: 1)
                        Button("Reset to 19 pt") { model.textSize = 19 }
                    }
                    .padding(18)
                    .frame(width: 240)
                    .preferredColorScheme(.dark)
                }
        }
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}

private struct ResizeCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ nsView: CursorView, context: Context) {}
    final class CursorView: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct WindowResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ nsView: GripView, context: Context) {}
    final class GripView: NSView {
        private var initial = CGRect.zero
        private var start = CGPoint.zero
        override var mouseDownCanMoveWindow: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.lightGray.setStroke()
            for offset in [CGFloat(4), 10, 16] {
                let line = NSBezierPath()
                line.move(to: CGPoint(x: offset, y: 2))
                line.line(to: CGPoint(x: bounds.maxX - 2, y: bounds.maxY - offset))
                line.lineWidth = 1.2
                line.stroke()
            }
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all)) }
        override func mouseDown(with event: NSEvent) {
            initial = window?.frame ?? .zero
            start = NSEvent.mouseLocation
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let point = NSEvent.mouseLocation
            let width = min(1200, max(window.contentMinSize.width, initial.width + point.x - start.x))
            let height = min(window.screen?.visibleFrame.height ?? 1200,
                             max(window.contentMinSize.height, initial.height - point.y + start.y))
            window.setFrame(CGRect(x: initial.minX, y: initial.maxY - height, width: width, height: height), display: true)
        }
    }
}
