import XCTest
@testable import MaClip

final class SecretActionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_700_000)
    private var token: String { "ghp_" + String(repeating: "a", count: 32) + "a1b2" }
    private let link = "postgres://admin:" + "hunter22" + "@db.local:5432/app"
    private let env = "DB_PASSWORD=" + "s3cr3t-Pa55w0rd" + "\nDB_USER=app"

    private func jwt(_ payload: [String: Any] = ["sub": "user_1", "exp": 1_794_700_000 - 3 * 86_400]) -> String {
        func part(_ o: [String: Any]) -> String {
            let d = try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
            return d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return part(["alg": "HS256", "typ": "JWT"]) + "." + part(payload) + "." + String(repeating: "s", count: 20)
    }

    private func ed25519Key() -> String {
        func u32(_ n: Int) -> [UInt8] { [0, 0, UInt8(n >> 8 & 0xff), UInt8(n & 0xff)] }
        func str(_ d: [UInt8]) -> [UInt8] { u32(d.count) + d }
        let pub = [UInt8](repeating: 7, count: 32)
        var blob = str(Array("ssh-ed25519".utf8))
        blob += str(pub)
        var body: [UInt8] = Array("openssh-key-v1".utf8)
        body += [0]
        body += str(Array("none".utf8))
        body += str(Array("none".utf8))
        body += str([])
        body += u32(1)
        body += str(blob)
        body += str([UInt8](repeating: 1, count: 40))
        return "-----" + "BEGIN OPENSSH PRIVATE KEY-----\n" + Data(body).base64EncodedString()
            + "\n-----" + "END OPENSSH PRIVATE KEY-----"
    }

    private func titles(_ text: String, _ kind: SecretKind) -> [String] {
        SecretActions.actions(for: text, kind: kind).map(\.title)
    }

    /// Each list equals the menu of its kind on the canvas board "Secret actions — menus by kind".
    func test_menuOfEachKind() {
        XCTAssertEqual(titles(token, .githubToken),
                       ["Copy Masked", "Copy as .env", "Copy as Shell Export", "Open Key Page on GitHub"])
        XCTAssertEqual(titles(link, .linkPassword),
                       ["Copy Masked", "Copy as .env", "Copy as Shell Export",
                        "Copy Link Without Password", "Copy Password Only", "Copy User"])
        XCTAssertEqual(titles("DB_PASSWORD=" + "s3cr3t-Pa55w0rd", .keyValue),
                       ["Copy Masked", "Copy as .env", "Copy as Shell Export", "Copy as JSON", "Copy as YAML",
                        "Copy Key Only", "Copy Value Only"])
        XCTAssertEqual(titles("curl -H \"Authorization: Bearer " + token + "\"", .githubToken),
                       ["Copy Masked", "Copy Redacted Text", "Copy as .env", "Copy as Shell Export", "Open Key Page on GitHub"])
        XCTAssertEqual(titles(jwt(), .jwt), ["Copy Masked", "Decode JWT", "Copy Header", "Copy Payload"])
        XCTAssertEqual(titles(ed25519Key(), .privateKey), ["Copy Public Key", "Copy Fingerprint", "Save as File\u{2026}"])
    }

    func test_keyPages() {
        func page(_ text: String, _ kind: SecretKind) -> URL? {
            for case .openKeyPage(_, let url) in SecretActions.actions(for: text, kind: kind) { return url }
            return nil
        }
        XCTAssertEqual(page(token, .githubToken), URL(string: "https://github.com/settings/tokens"))
        XCTAssertEqual(page("github_pat_" + String(repeating: "A1_", count: 10), .githubToken),
                       URL(string: "https://github.com/settings/personal-access-tokens"))
        XCTAssertEqual(page("gho_" + String(repeating: "a", count: 36), .githubToken),
                       URL(string: "https://github.com/settings/applications"))
        XCTAssertEqual(page("glpat-" + String(repeating: "x1", count: 10), .gitlabToken),
                       URL(string: "https://gitlab.com/-/user_settings/personal_access_tokens"))
        XCTAssertEqual(page("AKIAIOSFODNN7EXAMPLE", .awsAccessKey),
                       URL(string: "https://console.aws.amazon.com/iam/home#/security_credentials"))
        XCTAssertEqual(page("xoxb-" + String(repeating: "1", count: 12), .slackToken), URL(string: "https://api.slack.com/apps"))
        XCTAssertEqual(page("sk_" + "live_" + String(repeating: "a", count: 24), .stripeKey),
                       URL(string: "https://dashboard.stripe.com/apikeys"))
        XCTAssertEqual(page("sk_" + "test_" + String(repeating: "a", count: 24), .stripeKey),
                       URL(string: "https://dashboard.stripe.com/test/apikeys"))
        XCTAssertEqual(page("sk-" + "ant-" + String(repeating: "a", count: 30), .anthropicKey),
                       URL(string: "https://console.anthropic.com/settings/keys"))
        XCTAssertEqual(page("sk-" + "proj-" + String(repeating: "a", count: 30), .openAIKey),
                       URL(string: "https://platform.openai.com/api-keys"))
        XCTAssertEqual(page("AIza" + String(repeating: "a", count: 35), .googleAPIKey),
                       URL(string: "https://console.cloud.google.com/apis/credentials"))
        XCTAssertNil(page("npm_" + String(repeating: "a", count: 36), .npmToken))
        XCTAssertNil(page("https://discord.com/api/webhooks/1/" + String(repeating: "a", count: 30), .discordWebhook))
        XCTAssertNil(page("DB_PASSWORD=" + "s3cr3t-Pa55w0rd", .keyValue))
    }

    func test_holdsSecret() {
        XCTAssertTrue(SecretAction.copyFormat(.env).holdsSecret)
        XCTAssertTrue(SecretAction.copyValueOnly.holdsSecret)
        XCTAssertTrue(SecretAction.copyPasswordOnly.holdsSecret)
        for action: SecretAction in [.copyMasked, .copyRedacted, .copyKeyOnly, .copyLinkWithoutPassword, .copyUser,
                                     .copyJWTHeader, .copyJWTPayload, .copyPublicKey, .copyFingerprint] {
            XCTAssertFalse(action.holdsSecret, action.title)
        }
    }

    private func facts(_ text: String, _ kind: SecretKind) -> [String] {
        SecretFacts.facts(for: text, kind: kind, now: now).map { "\($0.label): \($0.value)" }
    }

    func test_factsOfEachKind() {
        let a36 = String(repeating: "a", count: 36)
        XCTAssertEqual(facts("ghp_" + a36, .githubToken), ["Type: Classic personal access token"])
        XCTAssertEqual(facts("github_pat_" + String(repeating: "A1_", count: 10), .githubToken),
                       ["Type: Fine-grained personal access token"])
        XCTAssertEqual(facts("gho_" + a36, .githubToken), ["Type: OAuth token"])
        XCTAssertEqual(facts("ghu_" + a36, .githubToken), ["Type: User-to-server token"])
        XCTAssertEqual(facts("ghs_" + a36, .githubToken), ["Type: Server-to-server token"])
        XCTAssertEqual(facts("ghr_" + a36, .githubToken), ["Type: Refresh token"])
        XCTAssertEqual(facts("AKIAIOSFODNN7EXAMPLE", .awsAccessKey), ["Type: Long-term access key"])
        XCTAssertEqual(facts("ASIA" + "IOSFODNN7EXAMPLE", .awsAccessKey), ["Type: Temporary session key"])
        XCTAssertEqual(facts("sk_" + "live_" + String(repeating: "a", count: 24), .stripeKey), ["Mode: Live", "Type: Secret key"])
        XCTAssertEqual(facts("rk_" + "test_" + String(repeating: "a", count: 24), .stripeKey), ["Mode: Test", "Type: Restricted key"])
        XCTAssertEqual(SecretFacts.facts(for: "sk_" + "live_" + String(repeating: "a", count: 24), kind: .stripeKey, now: now)
                        .first?.isWarning, true)
        for (prefix, name) in [("xoxb", "Bot token"), ("xoxp", "User token"), ("xoxa", "App token"),
                               ("xoxr", "Refresh token"), ("xoxs", "Session token")] {
            XCTAssertEqual(facts(prefix + "-" + String(repeating: "1", count: 12), .slackToken), ["Type: " + name])
        }
        XCTAssertEqual(facts("https://hooks.slack.com/services/" + "T0AB12/B0CD34/" + String(repeating: "X", count: 24), .slackWebhook),
                       ["Team: T0AB12", "Webhook: B0CD34"])
        XCTAssertEqual(facts("https://discord.com/api/webhooks/123456/" + String(repeating: "a", count: 30), .discordWebhook),
                       ["Webhook ID: 123456"])
        XCTAssertEqual(facts("sk-" + "ant-admin01-" + String(repeating: "a", count: 30), .anthropicKey), ["Type: Admin key"])
        XCTAssertEqual(facts("sk-" + "ant-api03-" + String(repeating: "a", count: 30), .anthropicKey), ["Type: API key"])
        XCTAssertEqual(facts("sk-" + "proj-" + String(repeating: "a", count: 30), .openAIKey), ["Type: Project key"])
        XCTAssertEqual(facts("sk-" + "svcacct-" + String(repeating: "a", count: 30), .openAIKey), ["Type: Service account key"])
        XCTAssertEqual(facts("sk-" + String(repeating: "a", count: 30), .openAIKey), ["Type: User key"])
        XCTAssertEqual(facts(link, .linkPassword),
                       ["Service: PostgreSQL", "User: admin", "Host: db.local", "Port: 5432", "Database: app"])
        XCTAssertEqual(facts("redis://default:" + "hunter22" + "@cache", .linkPassword),
                       ["Service: Redis", "User: default", "Host: cache"])
        XCTAssertEqual(facts("DB_PASSWORD=" + "s3cr3t-Pa55w0rd\nDB_USER=app\nDB_HOST=x", .keyValue),
                       ["Key: DB_PASSWORD", "Lines: 3"])
        XCTAssertEqual(facts("DB_PASSWORD=" + "s3cr3t-Pa55w0rd", .keyValue), ["Key: DB_PASSWORD"])
        XCTAssertEqual(facts(jwt(), .jwt), ["Algorithm: HS256", "Expiry: Expired 3 days ago"].map { $0 })
        XCTAssertEqual(facts(ed25519Key(), .privateKey).first, "Type: Ed25519")
        XCTAssertEqual(facts(ed25519Key(), .privateKey).last, "Passphrase: No")
        XCTAssertEqual(facts("npm_" + a36, .npmToken), [])
    }

    func test_rowBadge() {
        XCTAssertEqual(SecretFacts.rowBadge(for: "sk_" + "live_" + String(repeating: "a", count: 24), kind: .stripeKey), "LIVE")
        XCTAssertNil(SecretFacts.rowBadge(for: "sk_" + "test_" + String(repeating: "a", count: 24), kind: .stripeKey))
        XCTAssertNil(SecretFacts.rowBadge(for: token, kind: .githubToken))
    }

    func test_jwtWithoutJSONHasNoJWTActions() {
        let bad = "eyJ" + "notjson!!" + ".eyJ" + "zdWIiOiIxMjM0In0" + "." + String(repeating: "s", count: 20)
        let actions = SecretActions.actions(for: bad, kind: .jwt)
        XCTAssertFalse(actions.contains(.decodeJWT))
        XCTAssertFalse(actions.contains(.copyJWTHeader))
        XCTAssertFalse(actions.contains(.copyJWTPayload))
        XCTAssertEqual(SecretFacts.facts(for: bad, kind: .jwt, now: now), [])
    }

    func test_privateKeyWithoutPublicKey() {
        let encrypted = "-----" + "BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----" + "END ENCRYPTED PRIVATE KEY-----"
        let actions = SecretActions.actions(for: encrypted, kind: .privateKey)
        XCTAssertFalse(actions.contains(.copyPublicKey))
        XCTAssertFalse(actions.contains(.copyFingerprint))
        XCTAssertTrue(actions.contains(.saveKeyFile))
    }

    func test_copyTexts() {
        func copy(_ action: SecretAction, _ text: String, _ kind: SecretKind) -> String? {
            SecretActions.copyText(for: action, text: text, kind: kind)
        }
        XCTAssertEqual(copy(.copyLinkWithoutPassword, link, .linkPassword), "postgres://admin@db.local:5432/app")
        XCTAssertEqual(copy(.copyPasswordOnly, link, .linkPassword), "hunter22")
        XCTAssertEqual(copy(.copyUser, link, .linkPassword), "admin")
        XCTAssertEqual(copy(.copyKeyOnly, env, .keyValue), "DB_PASSWORD")
        XCTAssertEqual(copy(.copyValueOnly, env, .keyValue), "s3cr3t-Pa55w0rd")
        XCTAssertEqual(copy(.copyMasked, token, .githubToken), "ghp_\u{2022}\u{2022}\u{2022}\u{2022}a1b2")
        XCTAssertEqual(copy(.copyFormat(.shellExport), token, .githubToken), "export GITHUB_TOKEN=" + token)
        XCTAssertEqual(copy(.copyJWTHeader, jwt(), .jwt), "{\n  \"alg\" : \"HS256\",\n  \"typ\" : \"JWT\"\n}")
        XCTAssertTrue(copy(.copyFingerprint, ed25519Key(), .privateKey)?.hasPrefix("SHA256:") == true)
        XCTAssertTrue(copy(.copyPublicKey, ed25519Key(), .privateKey)?.hasPrefix("ssh-ed25519 AAAA") == true)
        XCTAssertNil(copy(.decodeJWT, jwt(), .jwt))
        XCTAssertNil(copy(.saveKeyFile, ed25519Key(), .privateKey))
    }
}
