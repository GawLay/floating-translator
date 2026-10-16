import Foundation
import CoreGraphics

@main
struct ParagraphFormattingTests {
    static func line(_ text: String, _ y: Double, x: Double = 0.1, width: Double = 0.8,
                     height: Double = 0.04) -> RecognizedLine {
        RecognizedLine(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    static func expect(_ name: String, _ lines: [RecognizedLine], _ expected: String) {
        let result = RecognizedParagraphs.text(from: lines)
        guard result == expected else { fatalError("\(name): expected \(expected.debugDescription), got \(result.debugDescription)") }
        print("PASS \(name)")
    }

    static func main() {
        expect("empty input", [], "")
        expect("one row", [line("Hello, world!", 0.8)], "Hello, world!")
        expect("wrapped paragraph", [line("This is a longer sentence", 0.8), line("that wraps across visual rows.", 0.75)],
               "This is a longer sentence that wraps across visual rows.")
        expect("paragraph gap", [line("This is the first paragraph.", 0.8), line("This is another paragraph.", 0.64)],
               "This is the first paragraph.\n\nThis is another paragraph.")
        expect("list items and continuation", [line("• A longer item that wraps", 0.8),
                line("onto its next visual row.", 0.75, x: 0.12), line("• A second list item", 0.70)],
               "• A longer item that wraps onto its next visual row.\n\n• A second list item")
        expect("sender label", [line("Lan", 0.8, width: 0.16), line("Chiều nay mình gặp nhau", 0.75),
                line("ở quán cà phê nhé.", 0.70)],
               "Lan\n\nChiều nay mình gặp nhau ở quán cà phê nhé.")
        expect("separate columns", [line("Left column", 0.8, x: 0.05, width: 0.3),
                line("Right column", 0.8, x: 0.6, width: 0.3)], "Left column\n\nRight column")
        expect("heading size", [line("A heading", 0.8, height: 0.08), line("A paragraph of normal text.", 0.74)],
               "A heading\n\nA paragraph of normal text.")
    }
}
