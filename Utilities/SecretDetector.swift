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
             regex: re(#"\b[A-Za-z][A-Za-z0-9+.\-]*://[^\s:/@]+:([^\s/@]{3,})@[^\s/@]+"#), accepts: nil),
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
