import Foundation

/// A kind of secret that MaClip finds in copied text. The order of the cases is the order
/// in which the detector checks the rules. The first rule that matches wins.
enum SecretKind: String, CaseIterable, Codable {
    case privateKey
    case awsAccessKey
    case githubToken
    case gitlabToken
    case slackToken
    case slackWebhook
    case discordWebhook
    case stripeKey
    case anthropicKey
    case openAIKey
    case googleAPIKey
    case npmToken
    case jwt
    case linkPassword
    case keyValue

    /// The name on the row, in sentence case.
    var title: String {
        switch self {
        case .privateKey: return "Private key"
        case .awsAccessKey: return "AWS access key"
        case .githubToken: return "GitHub token"
        case .gitlabToken: return "GitLab token"
        case .slackToken: return "Slack token"
        case .slackWebhook: return "Slack webhook"
        case .discordWebhook: return "Discord webhook"
        case .stripeKey: return "Stripe key"
        case .anthropicKey: return "Anthropic API key"
        case .openAIKey: return "OpenAI API key"
        case .googleAPIKey: return "Google API key"
        case .npmToken: return "npm token"
        case .jwt: return "JWT"
        case .linkPassword: return "Password in a link"
        case .keyValue: return "Secret value"
        }
    }

    /// The number and the name, for an alert: "1 GitHub token", "2 GitHub tokens".
    func count(_ n: Int) -> String {
        if self == .linkPassword {
            return n == 1 ? "1 password in a link" : "\(n) passwords in links"
        }
        let noun: String
        switch self {
        case .privateKey: noun = "private key"
        case .keyValue: noun = "secret value"
        default: noun = title
        }
        return "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

/// Finds secrets in text. A pure function with precompiled expressions.
enum SecretDetector {
    /// Detection reads at most this many characters of a clip.
    static let limit = 65_536

    struct Rule {
        let kind: SecretKind
        let regex: NSRegularExpression
        /// Checks a match that the expression alone cannot judge. Nil accepts every match.
        let accepts: ((NSTextCheckingResult, NSString) -> Bool)?
    }

    private static func re(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are constants, so a failure is a programming error.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// The words that make a key name a secret, compared without case.
    static let secretKeyWords = ["SECRET", "TOKEN", "PASSWORD", "PASSWD", "API_KEY", "APIKEY",
                                 "ACCESS_KEY", "PRIVATE_KEY", "AUTH_KEY"]

    /// Group 1: the opening quote of the key. Group 2: the key. Group 3: the raw value.
    static let keyValuePattern =
        #"^[ \t]*(?:export[ \t]+)?(["']?)([A-Za-z0-9_.\-]+)\1(?:=|:[ \t]+)([^\r\n]*)$"#

    static let rules: [Rule] = [
        Rule(kind: .privateKey,
             regex: re(#"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----"#),
             accepts: nil),
        Rule(kind: .awsAccessKey, regex: re(#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#), accepts: nil),
        Rule(kind: .githubToken,
             regex: re(#"\bgh[pousr]_[A-Za-z0-9]{36,}\b|\bgithub_pat_[A-Za-z0-9_]{22,}\b"#), accepts: nil),
        Rule(kind: .gitlabToken, regex: re(#"\bglpat-[A-Za-z0-9_\-]{20,}"#), accepts: nil),
        Rule(kind: .slackToken, regex: re(#"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#), accepts: nil),
        Rule(kind: .slackWebhook, regex: re(#"https://hooks\.slack\.com/services/[A-Za-z0-9/]+"#), accepts: nil),
        Rule(kind: .discordWebhook,
             regex: re(#"https://(?:canary\.)?discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_\-]+"#), accepts: nil),
        Rule(kind: .stripeKey, regex: re(#"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}\b"#), accepts: nil),
        Rule(kind: .anthropicKey, regex: re(#"\bsk-ant-[A-Za-z0-9_\-]{20,}"#), accepts: nil),
        Rule(kind: .openAIKey, regex: re(#"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_\-]{20,}"#), accepts: nil),
        Rule(kind: .googleAPIKey, regex: re(#"\bAIza[0-9A-Za-z_\-]{35}(?![0-9A-Za-z_\-])"#), accepts: nil),
        Rule(kind: .npmToken, regex: re(#"\bnpm_[A-Za-z0-9]{36}\b"#), accepts: nil),
        Rule(kind: .jwt, regex: re(#"\beyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{10,}"#), accepts: nil),
        Rule(kind: .linkPassword,
             regex: re(#"\b[A-Za-z][A-Za-z0-9+.\-]*://[^\s:/@]+:([^\s/@]{3,})@[^\s/@"'<>]+(?:[/?#][^\s"'<>]*)?"#),
             accepts: nil),
        Rule(kind: .keyValue, regex: re(keyValuePattern, [.anchorsMatchLines]), accepts: { match, text in
            let key = text.substring(with: match.range(at: 2))
            let raw = text.substring(with: match.range(at: 3))
            return isSecretKey(key) && cleanValue(raw).map(isRealValue) == true
        }),
    ]

    /// The first kind of secret in the first 65,536 characters of `text`, or nil.
    static func kind(in text: String) -> SecretKind? {
        let ns = String(text.prefix(limit)) as NSString
        let range = NSRange(location: 0, length: ns.length)
        for rule in rules {
            if let accepts = rule.accepts {
                var found = false
                rule.regex.enumerateMatches(in: ns as String, range: range) { match, _, stop in
                    if let match, accepts(match, ns) { found = true; stop.pointee = true }
                }
                if found { return rule.kind }
            } else if rule.regex.firstMatch(in: ns as String, range: range) != nil {
                return rule.kind
            }
        }
        return nil
    }

    // MARK: - keyValue checks

    static func isSecretKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        return secretKeyWords.contains { upper.contains($0) }
    }

    /// The value without spaces at the end, a comma at the end, and quotes around it.
    static func cleanValue(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasSuffix(",") { value.removeLast() }
        value = value.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    /// True when the value is long enough and is not a placeholder.
    static func isRealValue(_ value: String) -> Bool {
        guard value.count >= 8, let first = value.first else { return false }
        if "$<{%".contains(first) { return false }
        if value.contains("(") || value.contains(" ") { return false }
        if value.allSatisfy({ $0 == first }) { return false }
        let lower = value.lowercased()
        if ["changeme", "password", "null", "none", "true", "false"].contains(lower) { return false }
        if lower.hasPrefix("your") || lower.hasPrefix("example") { return false }
        return true
    }
}

// MARK: - Each secret in a text

/// One secret in a text.
struct SecretMatch: Equatable {
    let kind: SecretKind
    /// The whole text that the rule matched, for example the full `KEY=value` line.
    let matchRange: Range<String.Index>
    /// The characters that a mask hides: the token, the password of a link, the last part of a
    /// webhook, the value after a key, or the whole private key block.
    let range: Range<String.Index>
    /// The full credential that an export copies. The whole link for a webhook and a link
    /// with a password, else the secret part.
    let value: String
    /// The key of a `KEY=value` line. Nil for the other kinds.
    let key: String?
}

extension SecretDetector {
    /// A private key from its first line to its last line, or to the end of the text.
    private static let privateKeyBlock = try! NSRegularExpression(pattern:
        #"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----[\s\S]*?(?:-----END (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----|\z)"#)

    /// All secrets in `text`, in text order. When two matches overlap, the match of the rule
    /// that comes first in the table stays. `limit` nil checks the whole text.
    static func matches(in text: String, limit: Int? = SecretDetector.limit) -> [SecretMatch] {
        let checked = limit.map { String(text.prefix($0)) } ?? text
        let ns = checked as NSString
        let all = NSRange(location: 0, length: ns.length)
        var kept: [(whole: NSRange, match: SecretMatch)] = []
        for rule in rules {
            let regex = rule.kind == .privateKey ? privateKeyBlock : rule.regex
            regex.enumerateMatches(in: checked, range: all) { result, _, _ in
                guard let result else { return }
                if let accepts = rule.accepts, !accepts(result, ns) { return }
                let whole = result.range
                if kept.contains(where: { NSIntersectionRange($0.whole, whole).length > 0 }) { return }
                if let match = makeMatch(rule.kind, result, in: checked, ns) { kept.append((whole, match)) }
            }
        }
        return kept.sorted { $0.whole.location < $1.whole.location }.map(\.match)
    }

    /// The first secret of `kind` in the whole text. The actions for one secret use it.
    static func mainMatch(in text: String, kind: SecretKind) -> SecretMatch? {
        matches(in: text, limit: nil).first { $0.kind == kind }
    }

    private static func makeMatch(_ kind: SecretKind, _ result: NSTextCheckingResult,
                                  in text: String, _ ns: NSString) -> SecretMatch? {
        let whole = result.range
        var secret = whole
        var key: String?
        switch kind {
        case .linkPassword:
            secret = result.range(at: 1)
        case .slackWebhook, .discordWebhook:
            var end = whole.location + whole.length
            while end > whole.location, ns.character(at: end - 1) == 0x2F { end -= 1 }   // "/"
            let body = ns.substring(with: NSRange(location: whole.location, length: end - whole.location)) as NSString
            let slash = body.range(of: "/", options: .backwards)
            let start = whole.location + (slash.location == NSNotFound ? 0 : slash.location + 1)
            secret = NSRange(location: start, length: end - start)
        case .keyValue:
            key = ns.substring(with: result.range(at: 2))
            secret = cleanValueRange(result.range(at: 3), in: ns)
        default:
            break
        }
        guard secret.length > 0,
              let matchRange = Range(whole, in: text), let range = Range(secret, in: text) else { return nil }
        let value: String
        switch kind {
        case .linkPassword, .slackWebhook, .discordWebhook: value = String(text[matchRange])
        default: value = String(text[range])
        }
        return SecretMatch(kind: kind, matchRange: matchRange, range: range, value: value, key: key)
    }

    /// The range of the value without spaces, a comma at the end, and quotes around it.
    /// It follows `cleanValue(_:)`.
    private static func cleanValueRange(_ raw: NSRange, in ns: NSString) -> NSRange {
        func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }
        var s = raw.location, e = raw.location + raw.length
        while e > s, isSpace(ns.character(at: e - 1)) { e -= 1 }
        if e > s, ns.character(at: e - 1) == 0x2C { e -= 1 }   // ","
        while e > s, isSpace(ns.character(at: e - 1)) { e -= 1 }
        while s < e, isSpace(ns.character(at: s)) { s += 1 }
        if e - s >= 2 {
            let first = ns.character(at: s)
            if (first == 0x22 || first == 0x27), ns.character(at: e - 1) == first { s += 1; e -= 1 }
        }
        return NSRange(location: s, length: e - s)
    }
}
