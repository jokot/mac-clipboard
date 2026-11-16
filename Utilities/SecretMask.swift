import Foundation

/// Masks and redacts the secrets in a text. Both check the whole text, not only the
/// first 65,536 characters, because they run only when the user asks.
enum SecretMask {
    static let dots = "\u{2022}\u{2022}\u{2022}\u{2022}"

    /// The known start of a token, which a mask keeps.
    private static let knownPrefix = try! NSRegularExpression(pattern:
        #"^(?:github_pat_|gh[pousr]_|glpat-|xox[abprs]-|[sr]k_(?:live|test)_|sk-ant-|sk-proj-|sk-svcacct-|sk-|AKIA|ASIA|AIza|npm_|eyJ)"#)

    /// The text with each secret masked: `ghp_••••a1b2`, `DB_PASSWORD=••••`, `[Private key]`.
    static func masked(_ text: String) -> String {
        replacing(text) { match, secret in
            if match.kind == .privateKey { return "[Private key]" }
            return mask(secret, keepPrefix: match.kind != .keyValue && match.kind != .linkPassword)
        }
    }

    /// The text with each secret replaced by `[REDACTED GitHub token]`.
    static func redacted(_ text: String) -> String {
        replacing(text) { match, _ in "[REDACTED \(match.kind.title)]" }
    }

    /// True when the text has characters other than spaces outside its secrets.
    static func hasOtherText(_ text: String) -> Bool {
        var rest = text
        for match in SecretDetector.matches(in: text, limit: nil).reversed() {
            rest.replaceSubrange(match.matchRange, with: " ")
        }
        return rest.contains { !$0.isWhitespace }
    }

    /// The known prefix, 4 dots, then the last 4 characters of a secret of 20 or more characters.
    static func mask(_ secret: String, keepPrefix: Bool) -> String {
        var prefix = ""
        if keepPrefix {
            let ns = secret as NSString
            if let m = knownPrefix.firstMatch(in: secret, range: NSRange(location: 0, length: ns.length)) {
                prefix = ns.substring(with: m.range)
            }
        }
        let tail = secret.count >= 20 ? String(secret.suffix(4)) : ""
        return prefix + dots + tail
    }

    private static func replacing(_ text: String, with replacement: (SecretMatch, String) -> String) -> String {
        var result = text
        // From the end, so the earlier ranges stay valid.
        for match in SecretDetector.matches(in: text, limit: nil).reversed() {
            result.replaceSubrange(match.range, with: replacement(match, String(text[match.range])))
        }
        return result
    }
}
