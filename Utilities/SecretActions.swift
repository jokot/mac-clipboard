import Foundation

/// One fact about a secret that is safe to show while the clip is hidden.
struct SecretFact: Equatable {
    let label: String
    let value: String
    /// Orange text: a live Stripe key, an expired JWT.
    var isWarning: Bool = false
}

/// A ⌘K action for a detected secret.
enum SecretAction: Equatable {
    case copyMasked, copyRedacted
    case copyFormat(SecretFormat)
    case copyKeyOnly, copyValueOnly
    case copyLinkWithoutPassword, copyPasswordOnly, copyUser
    case decodeJWT, copyJWTHeader, copyJWTPayload
    case copyPublicKey, copyFingerprint, saveKeyFile
    case openKeyPage(provider: String, url: URL)

    var title: String {
        switch self {
        case .copyMasked: return "Copy Masked"
        case .copyRedacted: return "Copy Redacted Text"
        case .copyFormat(let format): return format.title
        case .copyKeyOnly: return "Copy Key Only"
        case .copyValueOnly: return "Copy Value Only"
        case .copyLinkWithoutPassword: return "Copy Link Without Password"
        case .copyPasswordOnly: return "Copy Password Only"
        case .copyUser: return "Copy User"
        case .decodeJWT: return "Decode JWT"
        case .copyJWTHeader: return "Copy Header"
        case .copyJWTPayload: return "Copy Payload"
        case .copyPublicKey: return "Copy Public Key"
        case .copyFingerprint: return "Copy Fingerprint"
        case .saveKeyFile: return "Save as File\u{2026}"
        case .openKeyPage(let provider, _): return "Open Key Page on \(provider)"
        }
    }

    /// The copied text holds the secret, so the new clip must be concealed.
    var holdsSecret: Bool {
        switch self {
        case .copyFormat, .copyValueOnly, .copyPasswordOnly: return true
        default: return false
        }
    }
}

enum SecretActions {
    /// The actions that apply to the clip, in the order of the spec table.
    static func actions(for text: String, kind: SecretKind) -> [SecretAction] {
        var actions: [SecretAction] = []
        let otherText = SecretMask.hasOtherText(text)
        if kind != .privateKey || otherText { actions.append(.copyMasked) }
        if otherText { actions.append(.copyRedacted) }
        if kind != .privateKey, kind != .jwt {
            for format in [SecretFormat.env, .shellExport] where SecretExport.text(for: text, kind: kind, format: format) != nil {
                actions.append(.copyFormat(format))
            }
        }
        switch kind {
        case .keyValue:
            actions += [.copyFormat(.json), .copyFormat(.yaml), .copyKeyOnly, .copyValueOnly]
        case .linkPassword:
            actions += [.copyLinkWithoutPassword, .copyPasswordOnly, .copyUser]
        case .jwt:
            if JWTDecoder.decode(text) != nil { actions += [.decodeJWT, .copyJWTHeader, .copyJWTPayload] }
        case .privateKey:
            if PrivateKeyInspector.inspect(text)?.publicKeyLine != nil { actions += [.copyPublicKey, .copyFingerprint] }
            actions.append(.saveKeyFile)
        default:
            break
        }
        if let page = keyPage(for: text, kind: kind) {
            actions.append(.openKeyPage(provider: page.provider, url: page.url))
        }
        return actions
    }

    /// The text that a copy action copies. Nil for an action that does not copy.
    static func copyText(for action: SecretAction, text: String, kind: SecretKind) -> String? {
        let main = SecretDetector.mainMatch(in: text, kind: kind)
        switch action {
        case .copyMasked: return SecretMask.masked(text)
        case .copyRedacted: return SecretMask.redacted(text)
        case .copyFormat(let format): return SecretExport.text(for: text, kind: kind, format: format)
        case .copyKeyOnly: return main?.key
        case .copyValueOnly: return main?.value
        case .copyLinkWithoutPassword:
            guard let main else { return nil }
            let password = String(text[main.range])
            guard let r = main.value.range(of: ":" + password + "@") else { return nil }
            return main.value.replacingCharacters(in: r, with: "@")
        case .copyPasswordOnly:
            guard let main else { return nil }
            let password = String(text[main.range])
            return password.removingPercentEncoding ?? password
        case .copyUser:
            return main.flatMap { LinkParts($0.value)?.user }
        case .copyJWTHeader: return JWTDecoder.decode(text)?.headerJSON
        case .copyJWTPayload: return JWTDecoder.decode(text)?.payloadJSON
        case .copyPublicKey: return PrivateKeyInspector.inspect(text)?.publicKeyLine
        case .copyFingerprint: return PrivateKeyInspector.inspect(text)?.fingerprint
        case .decodeJWT, .saveKeyFile, .openKeyPage: return nil
        }
    }

    /// A fixed page where the user can see and revoke keys. The URL never holds the secret.
    static func keyPage(for text: String, kind: SecretKind) -> (provider: String, url: URL)? {
        let value = SecretDetector.mainMatch(in: text, kind: kind)?.value ?? ""
        let page: (String, String)?
        switch kind {
        case .githubToken:
            if value.hasPrefix("ghp_") { page = ("GitHub", "https://github.com/settings/tokens") }
            else if value.hasPrefix("github_pat_") { page = ("GitHub", "https://github.com/settings/personal-access-tokens") }
            else { page = ("GitHub", "https://github.com/settings/applications") }
        case .gitlabToken: page = ("GitLab", "https://gitlab.com/-/user_settings/personal_access_tokens")
        case .awsAccessKey: page = ("AWS", "https://console.aws.amazon.com/iam/home#/security_credentials")
        case .slackToken, .slackWebhook: page = ("Slack", "https://api.slack.com/apps")
        case .stripeKey:
            page = ("Stripe", value.contains("_live_") ? "https://dashboard.stripe.com/apikeys"
                                                         : "https://dashboard.stripe.com/test/apikeys")
        case .anthropicKey: page = ("Anthropic", "https://console.anthropic.com/settings/keys")
        case .openAIKey: page = ("OpenAI", "https://platform.openai.com/api-keys")
        case .googleAPIKey: page = ("Google Cloud", "https://console.cloud.google.com/apis/credentials")
        case .privateKey, .discordWebhook, .npmToken, .jwt, .linkPassword, .keyValue: page = nil
        }
        guard let (provider, address) = page, let url = URL(string: address) else { return nil }
        return (provider, url)
    }
}

enum SecretFacts {
    /// The facts list of the preview. It never contains the value.
    static func facts(for text: String, kind: SecretKind, now: Date) -> [SecretFact] {
        let value = SecretDetector.mainMatch(in: text, kind: kind)?.value ?? ""
        func type(_ name: String) -> [SecretFact] { [SecretFact(label: "Type", value: name)] }
        switch kind {
        case .githubToken:
            let names = [("ghp_", "Classic personal access token"), ("github_pat_", "Fine-grained personal access token"),
                         ("gho_", "OAuth token"), ("ghu_", "User-to-server token"),
                         ("ghs_", "Server-to-server token"), ("ghr_", "Refresh token")]
            return names.first { value.hasPrefix($0.0) }.map { type($0.1) } ?? []
        case .awsAccessKey:
            return type(value.hasPrefix("ASIA") ? "Temporary session key" : "Long-term access key")
        case .stripeKey:
            let live = value.contains("_live_")
            return [SecretFact(label: "Mode", value: live ? "Live" : "Test", isWarning: live),
                    SecretFact(label: "Type", value: value.hasPrefix("rk_") ? "Restricted key" : "Secret key")]
        case .slackToken:
            let names = ["xoxb": "Bot token", "xoxp": "User token", "xoxa": "App token",
                         "xoxr": "Refresh token", "xoxs": "Session token"]
            return names[String(value.prefix(4))].map(type) ?? []
        case .slackWebhook:
            let parts = value.components(separatedBy: "/services/").last?.split(separator: "/") ?? []
            guard parts.count >= 2 else { return [] }
            return [SecretFact(label: "Team", value: String(parts[0])), SecretFact(label: "Webhook", value: String(parts[1]))]
        case .discordWebhook:
            let parts = value.components(separatedBy: "/webhooks/").last?.split(separator: "/") ?? []
            return parts.first.map { [SecretFact(label: "Webhook ID", value: String($0))] } ?? []
        case .anthropicKey:
            return type(value.hasPrefix("sk-ant-admin") ? "Admin key" : "API key")
        case .openAIKey:
            if value.hasPrefix("sk-proj-") { return type("Project key") }
            if value.hasPrefix("sk-svcacct-") { return type("Service account key") }
            return type("User key")
        case .jwt:
            guard let jwt = JWTDecoder.decode(text) else { return [] }
            let status = jwt.status(now: now)
            var facts: [SecretFact] = []
            if let alg = jwt.algorithm { facts.append(SecretFact(label: "Algorithm", value: alg, isWarning: jwt.isUnsigned)) }
            facts.append(SecretFact(label: "Expiry", value: status.text(now: now), isWarning: status.isWarning))
            return facts
        case .privateKey:
            guard let info = PrivateKeyInspector.inspect(text) else { return [] }
            var facts = type(info.typeText)
            if let fingerprint = info.fingerprint { facts.append(SecretFact(label: "Fingerprint", value: fingerprint)) }
            facts.append(SecretFact(label: "Passphrase", value: info.isEncrypted ? "Yes" : "No"))
            return facts
        case .linkPassword:
            guard let parts = LinkParts(value) else { return [] }
            return [("Service", parts.service), ("User", parts.user), ("Host", parts.host),
                    ("Port", parts.port), ("Database", parts.database)]
                .compactMap { label, v in v.map { SecretFact(label: label, value: $0) } }
        case .keyValue:
            guard let key = SecretDetector.mainMatch(in: text, kind: .keyValue)?.key else { return [] }
            var facts = [SecretFact(label: "Key", value: key)]
            let lines = SecretExport.pairs(in: text).count
            if lines > 1 { facts.append(SecretFact(label: "Lines", value: "\(lines)")) }
            return facts
        case .gitlabToken, .googleAPIKey, .npmToken:
            return []
        }
    }

    /// The pill after the kind on the row. Only a live Stripe key has one.
    static func rowBadge(for text: String, kind: SecretKind) -> String? {
        guard kind == .stripeKey,
              SecretDetector.mainMatch(in: text, kind: .stripeKey)?.value.contains("_live_") == true else { return nil }
        return "LIVE"
    }
}

/// The parts of a link with a password, for the facts list and Copy User.
struct LinkParts {
    let service: String?
    let user: String?
    let host: String?
    let port: String?
    let database: String?

    private static let services = ["postgres": "PostgreSQL", "postgresql": "PostgreSQL", "mysql": "MySQL",
                                   "mariadb": "MariaDB", "mongodb": "MongoDB", "mongodb+srv": "MongoDB",
                                   "redis": "Redis", "rediss": "Redis", "amqp": "RabbitMQ", "amqps": "RabbitMQ"]

    init?(_ link: String) {
        guard let components = URLComponents(string: link), let scheme = components.scheme else { return nil }
        service = Self.services[scheme.lowercased()] ?? scheme
        user = components.user.flatMap { $0.isEmpty ? nil : $0 }
        host = components.host.flatMap { $0.isEmpty ? nil : $0 }
        port = components.port.map(String.init)
        let path = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : components.path
        database = path.isEmpty ? nil : path
    }
}
