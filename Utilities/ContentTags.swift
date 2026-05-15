import Foundation
import AppKit

enum ContentTag: String, CaseIterable {
    case url, email, phone, json, code, color, diff

    var symbolName: String {
        switch self {
        case .url:   return "link"
        case .email: return "envelope"
        case .phone: return "phone"
        case .json:  return "curlybraces"
        case .code:  return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .diff:  return "plus.slash.minus"
        }
    }

    var displayName: String {
        switch self {
        case .url:   return "URL"
        case .email: return "Email"
        case .phone: return "Phone"
        case .json:  return "JSON"
        case .code:  return "Code"
        case .color: return "Color"
        case .diff:  return "Diff"
        }
    }
}

@MainActor
enum ContentTagDetector {
    private static var cache: [UUID: Set<ContentTag>] = [:]

    static func tags(for item: ClipboardItem) -> Set<ContentTag> {
        if let cached = cache[item.id] { return cached }
        let detected = computeTags(for: item)
        cache[item.id] = detected
        return detected
    }

    static func clearCache() {
        cache.removeAll()
    }

    /// Returns the highest-priority detected tag, or nil if the item has no tags.
    /// Priority order favors specificity: url > email > phone > color > json > diff > code.
    static func primaryTag(for item: ClipboardItem) -> ContentTag? {
        let tags = tags(for: item)
        let priority: [ContentTag] = [.url, .email, .phone, .color, .json, .diff, .code]
        for tag in priority where tags.contains(tag) {
            return tag
        }
        return nil
    }

    private static func computeTags(for item: ClipboardItem) -> Set<ContentTag> {
        switch item.content {
        case .url:
            return [.url]
        case .image:
            return []
        case .text(let text):
            return detectTextTags(text)
        }
    }

    private static func detectTextTags(_ raw: String) -> Set<ContentTag> {
        let text = raw.count > 65_536 ? String(raw.prefix(65_536)) : raw

        var tags: Set<ContentTag> = []
        if matchesURL(text)   { tags.insert(.url) }
        if matchesEmail(text) { tags.insert(.email) }
        if matchesPhone(text) { tags.insert(.phone) }
        if isJSON(text)       { tags.insert(.json) }
        if matchesColor(text) { tags.insert(.color) }
        if looksLikeDiff(text){ tags.insert(.diff) }
        if !tags.contains(.json) && looksLikeCode(text) { tags.insert(.code) }
        return tags
    }

    // MARK: - Per-tag rules

    private static func matchesURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return URLUtils.linkURL(from: trimmed) != nil
    }

    private static let emailRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^[\w.+-]+@[\w-]+\.[\w.-]+$"#, options: [])
    }()

    private static func matchesEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = emailRegex else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    private static let phoneRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^[+()0-9\s\-]{7,20}$"#, options: [])
    }()

    private static func matchesPhone(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = phoneRegex else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard regex.firstMatch(in: trimmed, options: [], range: range) != nil else { return false }
        let digits = trimmed.filter { $0.isNumber }
        return digits.count >= 7
    }

    private static func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static let colorRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#, options: [])
    }()

    private static func matchesColor(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = colorRegex else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    private static func looksLikeDiff(_ text: String) -> Bool {
        let snippet = text.prefix(16_384)
        if snippet.hasPrefix("diff --git") { return true }
        let lines = snippet.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else { return false }
        let diffLines = lines.filter { line in
            line.hasPrefix("+ ") || line.hasPrefix("- ")
        }
        return diffLines.count >= 2
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let snippet = String(text.prefix(16_384))
        var score = 0

        let lines = snippet.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count >= 3 { score += 1 }

        let openCurly = snippet.filter { $0 == "{" }.count
        let closeCurly = snippet.filter { $0 == "}" }.count
        let openParen = snippet.filter { $0 == "(" }.count
        let closeParen = snippet.filter { $0 == ")" }.count
        let hasBrackets = (openCurly > 0 && openCurly == closeCurly)
            || (openParen > 0 && openParen == closeParen)
        if hasBrackets { score += 1 }

        let keywords = [
            "function ", "def ", "class ", "import ", "let ", "var ",
            "const ", "return ", "for ", "while ", "if ", "else", "=>"
        ]
        if keywords.contains(where: { snippet.contains($0) }) { score += 1 }

        let indentedLines = lines.filter { line in
            line.hasPrefix("    ") || line.hasPrefix("  ") || line.hasPrefix("\t")
        }
        if indentedLines.count >= 2 { score += 1 }

        return score >= 2
    }
}
