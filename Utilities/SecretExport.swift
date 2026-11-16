import Foundation

/// A format that a secret can be copied in.
enum SecretFormat: CaseIterable {
    case env, shellExport, json, yaml

    var title: String {
        switch self {
        case .env: return "Copy as .env"
        case .shellExport: return "Copy as Shell Export"
        case .json: return "Copy as JSON"
        case .yaml: return "Copy as YAML"
        }
    }
}

/// Copies a secret as `.env`, shell export, JSON or YAML text.
enum SecretExport {
    /// The common environment variable name of a secret. Nil for a private key and a JWT.
    static func variableName(for match: SecretMatch) -> String? {
        switch match.kind {
        case .awsAccessKey: return "AWS_ACCESS_KEY_ID"
        case .githubToken: return "GITHUB_TOKEN"
        case .gitlabToken: return "GITLAB_TOKEN"
        case .slackToken: return "SLACK_TOKEN"
        case .slackWebhook: return "SLACK_WEBHOOK_URL"
        case .discordWebhook: return "DISCORD_WEBHOOK_URL"
        case .stripeKey: return match.value.hasPrefix("rk_") ? "STRIPE_RESTRICTED_KEY" : "STRIPE_SECRET_KEY"
        case .anthropicKey: return "ANTHROPIC_API_KEY"
        case .openAIKey: return "OPENAI_API_KEY"
        case .googleAPIKey: return "GOOGLE_API_KEY"
        case .npmToken: return "NPM_TOKEN"
        case .linkPassword:
            let scheme = match.value.prefix { $0 != ":" }.lowercased()
            if scheme == "redis" || scheme == "rediss" { return "REDIS_URL" }
            if scheme == "amqp" || scheme == "amqps" { return "AMQP_URL" }
            return "DATABASE_URL"
        case .keyValue: return match.key
        case .privateKey, .jwt: return nil
        }
    }

    private static let anyKeyValue = try! NSRegularExpression(pattern: SecretDetector.keyValuePattern,
                                                              options: [.anchorsMatchLines])

    /// Every key-value line of the text, secret or not: `KEY=value`, `export KEY=value`,
    /// `KEY: value` and `"KEY": "value",`. Other lines, such as comments, are left out.
    static func pairs(in text: String) -> [(key: String, value: String)] {
        let ns = text as NSString
        return anyKeyValue.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let key = ns.substring(with: m.range(at: 2))
            guard let value = SecretDetector.cleanValue(ns.substring(with: m.range(at: 3))) else { return nil }
            return (key, value)
        }
    }

    /// The text that a format action copies. Nil when the kind has no name or the text has no pair.
    static func text(for text: String, kind: SecretKind, format: SecretFormat) -> String? {
        if kind == .keyValue {
            let found = pairs(in: text)
            return found.isEmpty ? nil : render(found, as: format)
        }
        guard let match = SecretDetector.mainMatch(in: text, kind: kind),
              let name = variableName(for: match) else { return nil }
        return render([(name, match.value)], as: format)
    }

    static func render(_ pairs: [(key: String, value: String)], as format: SecretFormat) -> String {
        switch format {
        case .env:
            return pairs.map { "\($0.key)=\(isSafe($0.value) ? $0.value : doubleQuoted($0.value))" }
                .joined(separator: "\n")
        case .shellExport:
            return pairs.map { "export \($0.key)=\(isSafe($0.value) ? $0.value : singleQuoted($0.value))" }
                .joined(separator: "\n")
        case .json:
            var dict: [String: String] = [:]
            for pair in pairs { dict[pair.key] = pair.value }
            let data = (try? JSONSerialization.data(withJSONObject: dict,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        case .yaml:
            return pairs.map { "\($0.key): \(isSafeYAML($0.value) ? $0.value : jsonString($0.value))" }
                .joined(separator: "\n")
        }
    }

    private static let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_./:@%+=,-"))

    private static func isSafe(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { safe.contains($0) && $0.isASCII }
    }

    /// YAML gives a meaning to some characters at the start of a value, so those values get quotes.
    private static func isSafeYAML(_ value: String) -> Bool {
        guard isSafe(value), let first = value.first else { return false }
        return first.isLetter || first.isNumber || first == "_" || first == "." || first == "/"
    }

    private static func doubleQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func jsonString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])) ?? Data()
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
}
