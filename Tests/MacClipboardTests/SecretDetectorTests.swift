import XCTest
@testable import MaClip

/// Test tokens are built at run time, so that GitHub push protection does not block the repo.
/// The only literal key is the AWS documentation example.
final class SecretDetectorTests: XCTestCase {

    func test_findsEachKind() {
        let a36 = String(repeating: "a", count: 36)
        let begin = "-----" + "BEGIN"
        let cases: [(String, SecretKind)] = [
            (begin + " OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----", .privateKey),
            (begin + " PRIVATE KEY-----", .privateKey),
            ("AKIAIOSFODNN7EXAMPLE", .awsAccessKey),
            ("ghp_" + a36, .githubToken),
            ("github_pat_" + String(repeating: "A1_", count: 10), .githubToken),
            ("glpat-" + String(repeating: "x1", count: 10), .gitlabToken),
            ("xoxb-" + String(repeating: "1", count: 12) + "-abc", .slackToken),
            ("https://hooks.slack.com/services/" + "T000/B000/" + String(repeating: "X", count: 24), .slackWebhook),
            ("https://discord.com/api/webhooks/123456/" + String(repeating: "a", count: 30), .discordWebhook),
            ("sk_" + "live_" + String(repeating: "a", count: 24), .stripeKey),
            ("sk-" + "ant-" + String(repeating: "a", count: 30), .anthropicKey),
            ("sk-" + "proj-" + String(repeating: "a", count: 30), .openAIKey),
            ("AIza" + String(repeating: "a", count: 35), .googleAPIKey),
            ("npm_" + a36, .npmToken),
            ("eyJ" + "hbGciOiJIUzI1NiJ9" + ".eyJ" + "zdWIiOiIxMjM0In0" + "." + String(repeating: "s", count: 20), .jwt),
            ("postgres://admin:" + "hunter22" + "@db.local:5432/app", .linkPassword),
            ("DB_PASSWORD=" + "s3cr3t-Pa55w0rd", .keyValue),
            ("export API_KEY=\"" + String(repeating: "k", count: 7) + "9\"", .keyValue),
            ("client_secret: " + "abcd1234efgh", .keyValue),
            ("  \"client_secret\": \"" + "abcd1234efgh" + "\",", .keyValue),
        ]
        for (text, kind) in cases {
            XCTAssertEqual(SecretDetector.kind(in: text), kind, String(text.prefix(24)))
        }
    }

    func test_aKnownFormatWinsOverKeyValue() {
        XCTAssertEqual(SecretDetector.kind(in: "export GITHUB_TOKEN=\"ghp_" + String(repeating: "a", count: 36) + "\""),
                       .githubToken)
    }

    func test_anthropicIsCheckedBeforeOpenAI() {
        XCTAssertEqual(SecretDetector.kind(in: "sk-" + "ant-" + String(repeating: "b", count: 30)), .anthropicKey)
    }

    func test_findsASecretInsideOtherText() {
        let text = "curl -H \"Authorization: Bearer " + "ghp_" + String(repeating: "c", count: 36) + "\" https://api.github.com"
        XCTAssertEqual(SecretDetector.kind(in: text), .githubToken)
    }

    func test_normalDeveloperTextIsNotASecret() {
        for text in [
            "123e4567-e89b-12d3-a456-426614174000",
            "a0036a7f3c9d1e2b4f5a6c7d8e9f0a1b2c3d4e5f",
            String(repeating: "ab12", count: 16),
            "#5E5CE6",
            "https://github.com/jokot/mac-clipboard",
            "ssh://git@github.com/jokot/mac-clipboard.git",
            "let total = items.reduce(0) { $0 + $1.price }",
            "const token = req.headers.authorization",
            "Copy the token from the dashboard.",
            "password = getPassword()",
            "API_KEY=${API_KEY}",
            "TOKEN_TTL=3600",
            "SECRET_KEY=<your-key>",
            "PASSWORD=changeme",
            "API_TOKEN=your_token_here",
            "DB_PASSWORD=xxxxxxxxxx",
            "AUTH_TOKEN=null",
            "ACCESS_TOKEN=example-token-value",
            "SECRET_NAME=%SECRET_NAME%",
            "token: getToken(user)",
        ] {
            XCTAssertNil(SecretDetector.kind(in: text), text)
        }
    }

    func test_readsOnlyTheFirst65536Characters() {
        let late = String(repeating: " ", count: 65_536) + "ghp_" + String(repeating: "a", count: 36)
        XCTAssertNil(SecretDetector.kind(in: late))
    }

    func test_isFastOnALongText() {
        let text = String(repeating: "let value = compute(index) // no secret here\n", count: 1_500)
        let start = Date()
        _ = SecretDetector.kind(in: text)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05, "Debug build limit. The Release target is 5 ms.")
    }

    func test_countTextUsesSingularAndPlural() {
        XCTAssertEqual(SecretKind.githubToken.count(1), "1 GitHub token")
        XCTAssertEqual(SecretKind.githubToken.count(2), "2 GitHub tokens")
        XCTAssertEqual(SecretKind.jwt.count(3), "3 JWTs")
        XCTAssertEqual(SecretKind.privateKey.count(1), "1 private key")
        XCTAssertEqual(SecretKind.keyValue.count(3), "3 secret values")
        XCTAssertEqual(SecretKind.linkPassword.count(1), "1 password in a link")
        XCTAssertEqual(SecretKind.linkPassword.count(2), "2 passwords in links")
    }

    func test_titles() {
        XCTAssertEqual(SecretKind.githubToken.title, "GitHub token")
        XCTAssertEqual(SecretKind.keyValue.title, "Secret value")
        XCTAssertEqual(SecretKind.linkPassword.title, "Password in a link")
        XCTAssertEqual(SecretKind.allCases.first, .privateKey)
        XCTAssertEqual(SecretKind.allCases.last, .keyValue)
    }
}
