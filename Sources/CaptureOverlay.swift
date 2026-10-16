import AppKit

/// The clear interior passes mouse input through to the source app. Only the
/// grip and the border receive mouse input; no global event tap is necessary.
@MainActor
final class ScanFrameController {
    let window: UtilityPanel
    let view = ScanFrameView()
    var onChange: ((CGRect) -> Void)?
    var onClose: (() -> Void)?
    private var hitTestTimer: Timer?

    var region: CGRect { window.convertToScreen(view.region) }

    init(region: CGRect) {
        window = UtilityPanel(contentRect: ScanFrameView.windowRect(for: region),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        window.contentView = view
        view.onChange = { [weak self] in
            guard let self else { return }
            self.onChange?(self.region)
        }
        view.onClose = { [weak self] in self?.hide(); self?.onClose?() }
    }

    func show() {
        window.orderFrontRegardless()
        hitTestTimer?.invalidate()
        hitTestTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHitTesting() }
        }
        updateHitTesting()
    }

    func hide() {
        hitTestTimer?.invalidate()
        hitTestTimer = nil
        window.orderOut(nil)
    }

    private func updateHitTesting() {
        guard !view.isDragging else { return }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        window.ignoresMouseEvents = !view.isInteractive(point)
    }
}

final class UtilityPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ScanFrameView: NSView {
    static let inset: CGFloat = 12
    static let bottom: CGFloat = 32
    static let top: CGFloat = 44
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var isDragging = false
    private var startPoint = CGPoint.zero
    private var startRegion = CGRect.zero
    private var activeEdges: Edges = []
    private var moving = false

    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let bottom = Edges(rawValue: 4)
        static let top = Edges(rawValue: 8)
    }

    var region: CGRect {
        CGRect(x: Self.inset, y: Self.bottom,
               width: bounds.width - Self.inset * 2,
               height: bounds.height - Self.bottom - Self.top)
    }

    var grip: CGRect {
        let width = min(232, bounds.width - 4)
        return CGRect(x: bounds.midX - width / 2, y: region.maxY + 8, width: width, height: 28)
    }

    private var closeButton: CGRect {
        CGRect(x: grip.maxX - 26, y: grip.minY, width: 26, height: grip.height)
    }

    static func windowRect(for region: CGRect) -> CGRect {
        CGRect(x: region.minX - inset, y: region.minY - bottom,
               width: region.width + inset * 2, height: region.height + bottom + top)
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var handles: [(CGPoint, Edges)] {
        [(CGPoint(x: region.minX, y: region.minY), [.left, .bottom]),
         (CGPoint(x: region.midX, y: region.minY), .bottom),
         (CGPoint(x: region.maxX, y: region.minY), [.right, .bottom]),
         (CGPoint(x: region.minX, y: region.midY), .left),
         (CGPoint(x: region.maxX, y: region.midY), .right),
         (CGPoint(x: region.minX, y: region.maxY), [.left, .top]),
         (CGPoint(x: region.midX, y: region.maxY), .top),
         (CGPoint(x: region.maxX, y: region.maxY), [.right, .top])]
    }

    private func edges(at point: CGPoint) -> Edges {
        for (center, edges) in handles {
            if CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26).contains(point) {
                return edges
            }
        }
        guard region.insetBy(dx: -9, dy: -9).contains(point),
              !region.insetBy(dx: 9, dy: 9).contains(point) else { return [] }
        if abs(point.x - region.minX) < 9 { return .left }
        if abs(point.x - region.maxX) < 9 { return .right }
        if abs(point.y - region.minY) < 9 { return .bottom }
        return .top
    }

    func isInteractive(_ point: CGPoint) -> Bool {
        grip.contains(point) || !edges(at: point).isEmpty
    }

    override func resetCursorRects() {
        addCursorRect(grip, cursor: .openHand)
        addCursorRect(closeButton, cursor: .pointingHand)
        for (center, edges) in handles {
            let position: NSCursor.FrameResizePosition
            if edges.contains(.top) {
                position = edges.contains(.left) ? .topLeft : edges.contains(.right) ? .topRight : .top
            } else if edges.contains(.bottom) {
                position = edges.contains(.left) ? .bottomLeft : edges.contains(.right) ? .bottomRight : .bottom
            } else { position = edges.contains(.left) ? .left : .right }
            let cursor = NSCursor.frameResize(position: position, directions: .all)
            addCursorRect(CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26), cursor: cursor)
        }
        addCursorRect(CGRect(x: region.minX - 8, y: region.minY + 14, width: 16, height: max(0, region.height - 28)), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: region.maxX - 8, y: region.minY + 14, width: 16, height: max(0, region.height - 28)), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: region.minX + 14, y: region.minY - 8, width: max(0, region.width - 28), height: 16), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: region.minX + 14, y: region.maxY - 8, width: max(0, region.width - 28), height: 16), cursor: .resizeUpDown)
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(rect: region)
        NSColor.black.setStroke()
        outline.lineWidth = 4
        outline.stroke()
        NSColor.white.setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
        for (point, _) in handles {
            let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            let handle = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.white.setFill()
            handle.fill()
            NSColor.black.setStroke()
            handle.lineWidth = 1.5
            handle.stroke()
        }
        NSColor(white: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: grip, xRadius: 8, yRadius: 8).fill()
        let label = (grip.width < 160 ? "⠿ Move" : grip.width < 220 ? "⠿  Move area" : "⠿  Drag to move area") as NSString
        label.draw(at: CGPoint(x: grip.minX + 12, y: grip.minY + 7), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
        ])
        ("×" as NSString).draw(at: CGPoint(x: closeButton.minX + 5, y: closeButton.minY + 4), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.lightGray
        ])
        let hintWidth = min(176, bounds.width - 4)
        let hint = CGRect(x: bounds.midX - hintWidth / 2, y: region.minY - 26, width: hintWidth, height: 22)
        NSColor(white: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: hint, xRadius: 6, yRadius: 6).fill()
        ((hintWidth < 160 ? "Resize edges" : "Resize from any edge") as NSString).draw(at: CGPoint(x: hint.minX + 13, y: hint.minY + 4), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.lightGray
        ])
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeButton.contains(point) { onClose?(); return }
        guard let window else { return }
        activeEdges = edges(at: point)
        moving = grip.contains(point)
        guard moving || !activeEdges.isEmpty else { return }
        isDragging = true
        startPoint = NSEvent.mouseLocation
        startRegion = window.convertToScreen(region)
        if moving { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window else { return }
        let delta = CGPoint(x: NSEvent.mouseLocation.x - startPoint.x,
                            y: NSEvent.mouseLocation.y - startPoint.y)
        var rect = startRegion
        if moving {
            rect.origin.x += delta.x
            rect.origin.y += delta.y
        } else {
            if activeEdges.contains(.left) {
                rect.origin.x = min(startRegion.minX + delta.x, startRegion.maxX - 80)
                rect.size.width = startRegion.maxX - rect.minX
            }
            if activeEdges.contains(.right) { rect.size.width = max(80, startRegion.width + delta.x) }
            if activeEdges.contains(.bottom) {
                rect.origin.y = min(startRegion.minY + delta.y, startRegion.maxY - 40)
                rect.size.height = startRegion.maxY - rect.minY
            }
            if activeEdges.contains(.top) { rect.size.height = max(40, startRegion.height + delta.y) }
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.screens.first { $0.frame.contains(startRegion.midpoint) }
        if let screen {
            rect.size.width = min(rect.width, screen.frame.width - 24)
            rect.size.height = min(rect.height, screen.frame.height - 76)
            rect.origin.x = min(max(rect.minX, screen.frame.minX + 12), screen.frame.maxX - rect.width - 12)
            rect.origin.y = min(max(rect.minY, screen.frame.minY + 32), screen.frame.maxY - rect.height - 44)
        }
        window.setFrame(Self.windowRect(for: rect), display: true)
        needsDisplay = true
        window.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        window?.invalidateCursorRects(for: self)
        onChange?()
    }

    override func keyDown(with event: NSEvent) {
        guard let window else { return }
        if event.keyCode == 53 { onClose?(); return }
        var rect = window.frame
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 1 : 10
        switch event.keyCode {
        case 123: rect.origin.x -= step
        case 124: rect.origin.x += step
        case 125: rect.origin.y -= step
        case 126: rect.origin.y += step
        default: super.keyDown(with: event); return
        }
        window.setFrame(rect, display: true)
        onChange?()
    }
}

/// A short-lived, per-display selection overlay. It draws UI only; it never
/// captures screen pixels and can be used before granting Screen Recording.
@MainActor
final class AreaPicker {
    private var windows: [UtilityPanel] = []
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    func show() {
        close()
        for screen in NSScreen.screens {
            let window = UtilityPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = AreaPickerView()
            view.onSelect = { [weak self, weak window] rect in
                guard let self, let window else { return }
                let selected = window.convertToScreen(rect)
                self.close()
                self.onSelect?(selected)
            }
            view.onCancel = { [weak self] in self?.close(); self?.onCancel?() }
            window.contentView = view
            windows.append(window)
            window.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
            }
        }
        NSCursor.crosshair.set()
    }

    func close() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
    }
}

final class AreaPickerView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var selection = CGRect.zero
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let mask = NSBezierPath(rect: bounds)
        if !selection.isEmpty { mask.append(NSBezierPath(rect: selection)) }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.18).setFill()
        mask.fill()
        if !selection.isEmpty {
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 2
            outline.stroke()
        }
        let hint = CGRect(x: bounds.midX - 180, y: bounds.maxY - 90, width: 360, height: 40)
        NSColor(white: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: hint, xRadius: 10, yRadius: 10).fill()
        ("Drag over text · Esc to cancel" as NSString).draw(at: CGPoint(x: hint.minX + 64, y: hint.minY + 12), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white
        ])
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(point.x - start.x), height: abs(point.y - start.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard selection.width >= 80, selection.height >= 40 else {
            selection = .zero
            start = nil
            needsDisplay = true
            return
        }
        onSelect?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        else { super.keyDown(with: event) }
    }
}

extension CGRect {
    var midpoint: CGPoint { CGPoint(x: midX, y: midY) }
}
