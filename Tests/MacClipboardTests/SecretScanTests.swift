import XCTest
@testable import MaClip

final class SecretScanTests: XCTestCase {
    private func scan(_ kinds: [SecretKind], checked: Int = 4) -> SecretScan {
        SecretScan(checked: checked, found: kinds.map { (id: UUID(), kind: $0) })
    }

    func test_noSecrets() {
        let s = scan([])
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.title, "No secrets found")
        XCTAssertEqual(s.message, "MaClip checked 4 clips.")
        XCTAssertEqual(scan([], checked: 1).message, "MaClip checked 1 clip.")
    }

    func test_oneSecret() {
        let s = scan([.githubToken])
        XCTAssertFalse(s.isEmpty)
        XCTAssertEqual(s.title, "1 secret found")
        XCTAssertEqual(s.message, "1 GitHub token. Hide it, or delete it now.")
    }

    func test_kindsFollowTheTableOrder() {
        let s = scan([.githubToken, .privateKey, .githubToken])
        XCTAssertEqual(s.title, "3 secrets found")
        XCTAssertEqual(s.message, "1 private key and 2 GitHub tokens. Hide them, or delete them now.")
    }

    func test_threeKinds() {
        let s = scan([.githubToken, .awsAccessKey, .privateKey])
        XCTAssertEqual(s.message, "1 private key, 1 AWS access key and 1 GitHub token. Hide them, or delete them now.")
    }

    func test_moreThanThreeKinds() {
        let s = scan([.privateKey, .awsAccessKey, .awsAccessKey, .githubToken, .githubToken, .githubToken, .slackToken, .jwt])
        XCTAssertEqual(s.title, "8 secrets found")
        XCTAssertEqual(s.message,
                       "1 private key, 2 AWS access keys, 3 GitHub tokens and 2 other secrets. Hide them, or delete them now.")
        XCTAssertEqual(scan([.privateKey, .awsAccessKey, .githubToken, .jwt]).message,
                       "1 private key, 1 AWS access key, 1 GitHub token and 1 other secret. Hide them, or delete them now.")
    }
}
