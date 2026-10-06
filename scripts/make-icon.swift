import AppKit

@main
struct IconGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Usage: make-icon output.png")
        }

        let size = 1024
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Could not create icon canvas")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let background = NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872),
                                      xRadius: 214, yRadius: 214)
        withShadow(blur: 36, offset: NSSize(width: 0, height: -18),
                   color: NSColor(calibratedWhite: 0, alpha: 0.26)) {
            NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
            background.fill()
        }
        NSGradient(starting: NSColor(calibratedWhite: 0.12, alpha: 1),
                   ending: NSColor.black)?
            .draw(in: background, angle: 125)

        let first = NSBezierPath(roundedRect: NSRect(x: 155, y: 342, width: 510, height: 435),
                                 xRadius: 116, yRadius: 116)
        let firstTail = NSBezierPath()
        firstTail.move(to: NSPoint(x: 251, y: 403))
        firstTail.line(to: NSPoint(x: 229, y: 272))
        firstTail.line(to: NSPoint(x: 385, y: 355))
        firstTail.close()
        let ink = NSColor(calibratedWhite: 0.18, alpha: 1)
        withShadow(blur: 26, offset: NSSize(width: 0, height: -12),
                   color: NSColor(calibratedWhite: 0.15, alpha: 0.22)) {
            ink.setFill()
            firstTail.fill()
            first.fill()
        }

        let secondTail = NSBezierPath()
        secondTail.move(to: NSPoint(x: 706, y: 295))
        secondTail.line(to: NSPoint(x: 809, y: 210))
        secondTail.line(to: NSPoint(x: 805, y: 358))
        secondTail.close()
        let second = NSBezierPath(roundedRect: NSRect(x: 478, y: 230, width: 385, height: 365),
                                  xRadius: 104, yRadius: 104)
        let secondBubble = NSColor(calibratedWhite: 0.30, alpha: 1)
        withShadow(blur: 24, offset: NSSize(width: 0, height: -10),
                   color: NSColor(calibratedWhite: 0.12, alpha: 0.24)) {
            secondBubble.setFill()
            secondTail.fill()
            second.fill()
        }

        drawLetter("ă", in: NSRect(x: 191, y: 392, width: 415, height: 340), size: 295)
        drawLetter("A", in: NSRect(x: 510, y: 272, width: 325, height: 277), size: 248)

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not encode icon")
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }

    private static func withShadow(blur: CGFloat, offset: NSSize, color: NSColor,
                                   draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = offset
        shadow.shadowColor = color
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawLetter(_ letter: String, in rect: NSRect, size: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSAttributedString(string: letter, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ])
        text.draw(in: rect)
    }
}
