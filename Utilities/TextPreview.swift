import Foundation

enum TextPreview {
    static func preview(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 300 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 300)
        return String(trimmed[..<idx]) + "…"
    }
}