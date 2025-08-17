import Foundation
import AppKit

enum URLUtils {
    // MARK: - URL detection (align with monitor behavior)
    static func sanitizedURLString(_ string: String) -> String {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
        }
        if (s.hasPrefix("<") && s.hasSuffix(">")) { s = String(s.dropFirst().dropLast()) }
        while let last = s.unicodeScalars.last, CharacterSet(charactersIn: ").,;:)]}").contains(last) {
            s = String(s.unicodeScalars.dropLast())
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func linkURL(from string: String) -> URL? {
        let s = sanitizedURLString(string)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = detector.matches(in: s, options: [], range: range).first,
               match.range.location == 0, match.range.length == ns.length,
               let url = match.url,
               let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
                return url
            }
        }
        let pattern = "^(?:https?://)?(?:www\\.)?[A-Za-z0-9.-]+\\.[A-Za-z]{2,}(?:/[^\\s]*)?$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = regex.firstMatch(in: s, options: [], range: range), m.range.location == 0, m.range.length == ns.length {
                if s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://") {
                    return URL(string: s)
                } else {
                    return URL(string: "https://" + s)
                }
            }
        }
        return nil
    }
}