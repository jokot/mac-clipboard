import XCTest
@testable import MaClip

final class SecretCaptureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let token = "ghp_" + String(repeating: "a", count: 36)

    private func decide(_ text: String?, mark: Bool = false, find: Bool = true,
                        skip: Bool = false, timeout: TimeInterval = 300) -> SecretCapture.Decision {
        SecretCapture.decide(text: text, hasConcealedMark: mark, findSecrets: find,
                             skipConcealed: skip, timeout: timeout, now: now)
    }

    func test_aTokenIsConcealedWithItsKindAndCountdown() {
        XCTAssertEqual(decide(token), .save(isConcealed: true, expiresAt: now.addingTimeInterval(300), secretKind: .githubToken))
    }

    func test_neverDeleteGivesDistantFuture() {
        XCTAssertEqual(decide(token, timeout: -1), .save(isConcealed: true, expiresAt: .distantFuture, secretKind: .githubToken))
    }

    func test_dontSaveConcealedSkipsATokenWithoutAMark() {
        XCTAssertEqual(decide(token, skip: true), .skip)
    }

    func test_switchOffSavesATokenAsANormalClip() {
        XCTAssertEqual(decide(token, find: false), .save(isConcealed: false, expiresAt: nil, secretKind: nil))
    }

    func test_normalTextIsANormalClip() {
        XCTAssertEqual(decide("hello world"), .save(isConcealed: false, expiresAt: nil, secretKind: nil))
    }

    func test_theConcealedMarkStillWorks() {
        XCTAssertEqual(decide("hello", mark: true), .save(isConcealed: true, expiresAt: now.addingTimeInterval(300), secretKind: nil))
        XCTAssertEqual(decide("hello", mark: true, skip: true), .skip)
    }

    func test_aTokenWithTheMarkGetsItsKind() {
        XCTAssertEqual(decide(token, mark: true), .save(isConcealed: true, expiresAt: now.addingTimeInterval(300), secretKind: .githubToken))
    }

    func test_aMarkedTokenKeepsNoKindWhenTheSwitchIsOff() {
        XCTAssertEqual(decide(token, mark: true, find: false), .save(isConcealed: true, expiresAt: now.addingTimeInterval(300), secretKind: nil))
    }

    func test_anImageOrFileClipUsesOnlyTheMark() {
        XCTAssertEqual(decide(nil, mark: true), .save(isConcealed: true, expiresAt: now.addingTimeInterval(300), secretKind: nil))
        XCTAssertEqual(decide(nil), .save(isConcealed: false, expiresAt: nil, secretKind: nil))
    }

    func test_aLinkWithAPasswordIsFoundBeforeItBecomesAURL() {
        XCTAssertEqual(decide("https://admin:" + "hunter22" + "@db.local"),
                       .save(isConcealed: true, expiresAt: now.addingTimeInterval(300), secretKind: .linkPassword))
    }
}
