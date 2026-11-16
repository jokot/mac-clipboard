import XCTest
@testable import MaClip

final class SecretMaskTests: XCTestCase {
    private let dot4 = "\u{2022}\u{2022}\u{2022}\u{2022}"
    private var token: String { "ghp_" + String(repeating: "a", count: 32) + "a1b2" }
    private var webhook: String { "https://hooks.slack.com/services/" + "T000/B000/" + String(repeating: "X", count: 20) + "WXYZ" }
    private var keyBlock: String {
        "-----" + "BEGIN OPENSSH PRIVATE KEY-----\nAAAA\nBBBB\n-----" + "END OPENSSH PRIVATE KEY-----"
    }

    func test_masksATokenWithItsPrefixAndLastFour() {
        XCTAssertEqual(SecretMask.masked(token), "ghp_" + dot4 + "a1b2")
    }

    func test_hidesTheTailOfAShortSecret() {
        XCTAssertEqual(SecretMask.masked("DB_PASSWORD=" + "s3cr3t-Pa55w0rd"), "DB_PASSWORD=" + dot4)
    }

    func test_masksOnlyThePasswordOfALink() {
        XCTAssertEqual(SecretMask.masked("postgres://admin:" + "hunter22" + "@db.local:5432/app"),
                       "postgres://admin:" + dot4 + "@db.local:5432/app")
    }

    func test_masksOnlyTheLastPartOfAWebhook() {
        XCTAssertEqual(SecretMask.masked(webhook), "https://hooks.slack.com/services/T000/B000/" + dot4 + "WXYZ")
    }

    func test_aPrivateKeyBecomesALabel() {
        XCTAssertEqual(SecretMask.masked("before\n" + keyBlock + "\nafter"), "before\n[Private key]\nafter")
    }

    func test_overlapUsesTheEarlierRule() {
        XCTAssertEqual(SecretMask.masked("export GITHUB_TOKEN=\"" + token + "\""),
                       "export GITHUB_TOKEN=\"ghp_" + dot4 + "a1b2\"")
    }

    func test_redactsEachSecretInALog() {
        let stripe = "sk_" + "live_" + String(repeating: "b", count: 24)
        let log = "GET /repos 401\nAuthorization: token " + token + "\nstripe key " + stripe + " rejected"
        XCTAssertEqual(SecretMask.redacted(log),
                       "GET /repos 401\nAuthorization: token [REDACTED GitHub token]\nstripe key [REDACTED Stripe key] rejected")
    }

    func test_masksASecretAfterTheDetectionLimit() {
        let text = String(repeating: " ", count: 70_000) + token
        XCTAssertEqual(SecretMask.masked(text), String(repeating: " ", count: 70_000) + "ghp_" + dot4 + "a1b2")
    }

    func test_normalTextIsUnchanged() {
        for text in ["123e4567-e89b-12d3-a456-426614174000", "#5E5CE6", "https://github.com/jokot/mac-clipboard",
                     "ssh://git@github.com/jokot/mac-clipboard.git", "Copy the token from the dashboard.",
                     "API_KEY=${API_KEY}", "TOKEN_TTL=3600"] {
            XCTAssertEqual(SecretMask.masked(text), text)
            XCTAssertEqual(SecretMask.redacted(text), text)
        }
    }

    func test_hasOtherText() {
        XCTAssertFalse(SecretMask.hasOtherText(token))
        XCTAssertFalse(SecretMask.hasOtherText("  " + token + "\n"))
        XCTAssertTrue(SecretMask.hasOtherText("token: " + token + "\nstatus 401"))
        XCTAssertFalse(SecretMask.hasOtherText("DB_PASSWORD=" + "s3cr3t-Pa55w0rd"))
        XCTAssertFalse(SecretMask.hasOtherText(keyBlock))
    }

    func test_matchValues() {
        let hook = SecretDetector.mainMatch(in: webhook, kind: .slackWebhook)
        XCTAssertEqual(hook?.value, webhook)

        let link = "postgres://admin:" + "hunter22" + "@db.local:5432/app"
        let linkMatch = SecretDetector.mainMatch(in: link, kind: .linkPassword)
        XCTAssertEqual(linkMatch?.value, link)
        XCTAssertEqual(linkMatch.map { String(link[$0.range]) }, "hunter22")

        let env = "DB_PASSWORD=\"" + "s3cr3t-Pa55w0rd" + "\""
        let kv = SecretDetector.mainMatch(in: env, kind: .keyValue)
        XCTAssertEqual(kv?.key, "DB_PASSWORD")
        XCTAssertEqual(kv?.value, "s3cr3t-Pa55w0rd")
        XCTAssertEqual(kv.map { String(env[$0.range]) }, "s3cr3t-Pa55w0rd")

        let gh = SecretDetector.mainMatch(in: "x " + token + " y", kind: .githubToken)
        XCTAssertEqual(gh?.value, token)
        XCTAssertNil(gh?.key)
    }

    func test_matchesAreInTextOrder() {
        let stripe = "sk_" + "test_" + String(repeating: "c", count: 24)
        let text = stripe + "\n" + token
        XCTAssertEqual(SecretDetector.matches(in: text).map(\.kind), [.stripeKey, .githubToken])
    }
}
