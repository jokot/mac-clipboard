import XCTest
@testable import MaClip

final class SecretExportTests: XCTestCase {
    private var token: String { "ghp_" + String(repeating: "a", count: 36) }

    private func name(_ text: String, _ kind: SecretKind) -> String? {
        SecretDetector.mainMatch(in: text, kind: kind).flatMap(SecretExport.variableName(for:))
    }

    func test_variableNames() {
        XCTAssertEqual(name("AKIAIOSFODNN7EXAMPLE", .awsAccessKey), "AWS_ACCESS_KEY_ID")
        XCTAssertEqual(name(token, .githubToken), "GITHUB_TOKEN")
        XCTAssertEqual(name("glpat-" + String(repeating: "x1", count: 10), .gitlabToken), "GITLAB_TOKEN")
        XCTAssertEqual(name("xoxb-" + String(repeating: "1", count: 12), .slackToken), "SLACK_TOKEN")
        XCTAssertEqual(name("https://hooks.slack.com/services/T0/B0/" + String(repeating: "X", count: 24), .slackWebhook),
                       "SLACK_WEBHOOK_URL")
        XCTAssertEqual(name("https://discord.com/api/webhooks/1/" + String(repeating: "a", count: 30), .discordWebhook),
                       "DISCORD_WEBHOOK_URL")
        XCTAssertEqual(name("sk_" + "live_" + String(repeating: "a", count: 24), .stripeKey), "STRIPE_SECRET_KEY")
        XCTAssertEqual(name("rk_" + "test_" + String(repeating: "a", count: 24), .stripeKey), "STRIPE_RESTRICTED_KEY")
        XCTAssertEqual(name("sk-" + "ant-" + String(repeating: "a", count: 30), .anthropicKey), "ANTHROPIC_API_KEY")
        XCTAssertEqual(name("sk-" + "proj-" + String(repeating: "a", count: 30), .openAIKey), "OPENAI_API_KEY")
        XCTAssertEqual(name("AIza" + String(repeating: "a", count: 35), .googleAPIKey), "GOOGLE_API_KEY")
        XCTAssertEqual(name("npm_" + String(repeating: "a", count: 36), .npmToken), "NPM_TOKEN")
        XCTAssertEqual(name("redis://u:" + "hunter22" + "@cache:6379", .linkPassword), "REDIS_URL")
        XCTAssertEqual(name("amqps://u:" + "hunter22" + "@mq", .linkPassword), "AMQP_URL")
        XCTAssertEqual(name("postgres://u:" + "hunter22" + "@db/app", .linkPassword), "DATABASE_URL")
        let jwt = "eyJ" + "hbGciOiJIUzI1NiJ9" + ".eyJ" + "zdWIiOiIxMjM0In0" + "." + String(repeating: "s", count: 20)
        XCTAssertNil(name(jwt, .jwt))
    }

    func test_envQuotesOnlyWhenNeeded() {
        XCTAssertEqual(SecretExport.render([("K", "abc-123_x.y/z:@%+=,")], as: .env), "K=abc-123_x.y/z:@%+=,")
        XCTAssertEqual(SecretExport.render([("K", "a b\"c\\d")], as: .env), "K=\"a b\\\"c\\\\d\"")
    }

    func test_shellExportUsesSingleQuotes() {
        XCTAssertEqual(SecretExport.render([("K", "it's")], as: .shellExport), "export K='it'\\''s'")
        XCTAssertEqual(SecretExport.render([("K", "plain")], as: .shellExport), "export K=plain")
    }

    func test_jsonIsSortedAndFormatted() {
        XCTAssertEqual(SecretExport.render([("B", "2"), ("A", "a/b")], as: .json), "{\n  \"A\" : \"a/b\",\n  \"B\" : \"2\"\n}")
    }

    func test_yamlUsesAJSONStringWhenNeeded() {
        XCTAssertEqual(SecretExport.render([("K", "a: b")], as: .yaml), "K: \"a: b\"")
        XCTAssertEqual(SecretExport.render([("K", "plain-value")], as: .yaml), "K: plain-value")
    }

    func test_pairsReadsEachForm() {
        let text = """
        # database
        DB_PASSWORD=s3cr3t-Pa55w0rd
        export API_KEY="abc"
        LOG_LEVEL: debug
          "client_secret": "abcd1234efgh",
        """
        let pairs = SecretExport.pairs(in: text)
        XCTAssertEqual(pairs.map(\.key), ["DB_PASSWORD", "API_KEY", "LOG_LEVEL", "client_secret"])
        XCTAssertEqual(pairs.map(\.value), ["s3cr3t-Pa55w0rd", "abc", "debug", "abcd1234efgh"])
    }

    func test_aTokenBecomesOneLine() {
        XCTAssertEqual(SecretExport.text(for: "token " + token, kind: .githubToken, format: .shellExport),
                       "export GITHUB_TOKEN=" + token)
        XCTAssertEqual(SecretExport.text(for: "DB_PASSWORD=s3cr3t-Pa55w0rd\nDB_USER=app", kind: .keyValue, format: .env),
                       "DB_PASSWORD=s3cr3t-Pa55w0rd\nDB_USER=app")
    }

    func test_titles() {
        XCTAssertEqual(SecretFormat.allCases.map(\.title),
                       ["Copy as .env", "Copy as Shell Export", "Copy as JSON", "Copy as YAML"])
    }
}
