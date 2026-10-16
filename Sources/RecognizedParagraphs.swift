import Foundation
import CoreGraphics

struct RecognizedLine {
    let text: String
    let box: CGRect
}

enum RecognizedParagraphs {
    /// Vision reports visual rows. Reflow rows in the same block while keeping
    /// paragraph gaps, list items, labels and separate columns distinct.
    static func text(from input: [RecognizedLine]) -> String {
        let lines = input.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted {
            if abs($0.box.midY - $1.box.midY) < min($0.box.height, $1.box.height) * 0.35 {
                return $0.box.minX < $1.box.minX
            }
            return $0.box.midY > $1.box.midY
        }
        guard let first = lines.first else { return "" }
        let widest = lines.map(\.box.width).max() ?? 1
        var paragraphs = [first.text.trimmingCharacters(in: .whitespacesAndNewlines)]
        for index in 1..<lines.count {
            let previous = lines[index - 1]
            let current = lines[index]
            let height = max(previous.box.height, current.box.height)
            let gap = previous.box.minY - current.box.maxY
            let sameRow = abs(previous.box.midY - current.box.midY) < height * 0.35
            let separateColumn = sameRow && current.box.minX - previous.box.maxX > height * 1.5
            let distantIndent = abs(previous.box.minX - current.box.minX) > max(height * 2, 0.08)
            let changedSize = abs(previous.box.height - current.box.height) > height * 0.35
            let shortLabel = previous.text.split(separator: " ").count <= 4
                && previous.box.width < widest * 0.45 && !isList(previous.text)
                && !previous.text.hasSuffix(",")
            let text = current.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if gap > height * 0.85 || separateColumn || distantIndent || changedSize || isList(text) || shortLabel {
                paragraphs.append(text)
            } else {
                let separator = paragraphs[paragraphs.count - 1].hasSuffix("-") ? "" : " "
                paragraphs[paragraphs.count - 1] += separator + text
            }
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func isList(_ text: String) -> Bool {
        text.range(of: #"^\s*(?:[•▪◦*\-]|\d+[.)])\s+"#, options: .regularExpression) != nil
    }
}
