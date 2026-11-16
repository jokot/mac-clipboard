import XCTest
@testable import MaClip

final class SecretViewTextTests: XCTestCase {
    private func item(kind: SecretKind?, concealed: Bool = true) -> ClipboardItem {
        ClipboardItem(date: Date(), content: .text("x"), sourceBundleID: "com.apple.Safari",
                      isConcealed: concealed, concealedExpiresAt: concealed ? .distantFuture : nil, secretKind: kind)
    }

    func test_concealedTitle() {
        XCTAssertEqual(ClipPreviewInfo.concealedTitle(for: item(kind: .githubToken)), "This clip is a GitHub token")
        XCTAssertEqual(ClipPreviewInfo.concealedTitle(for: item(kind: .keyValue)), "This clip is a secret value")
        XCTAssertEqual(ClipPreviewInfo.concealedTitle(for: item(kind: .awsAccessKey)), "This clip is an AWS access key")
        XCTAssertEqual(ClipPreviewInfo.concealedTitle(for: item(kind: .openAIKey)), "This clip is an OpenAI API key")
        XCTAssertEqual(ClipPreviewInfo.concealedTitle(for: item(kind: .npmToken)), "This clip is an npm token")
        XCTAssertEqual(ClipPreviewInfo.concealedTitle(for: item(kind: .jwt)), "This clip is a JWT")
        XCTAssertEqual(ClipPreviewInfo.concealedTitle(for: item(kind: .linkPassword)), "This clip is a password in a link")
        XCTAssertEqual(ClipPreviewInfo.concealedTitle(for: item(kind: nil)), "This clip is concealed")
    }

    func test_countdownLine() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(ClipPreviewInfo.countdownLine(until: now.addingTimeInterval(272), now: now), "MaClip deletes it in 4:32.")
        XCTAssertNil(ClipPreviewInfo.countdownLine(until: .distantFuture, now: now))
        XCTAssertNil(ClipPreviewInfo.countdownLine(until: nil, now: now))
    }

    func test_headerShowsTheKindAfterTheDate() {
        XCTAssertEqual(ClipPreviewInfo.header(time: "Today at 10:42", kind: .githubToken, detail: "1 word", hidden: true),
                       "Today at 10:42 · GitHub token")
        XCTAssertEqual(ClipPreviewInfo.header(time: "Today at 10:42", kind: .githubToken, detail: "1 word", hidden: false),
                       "Today at 10:42 · GitHub token · 1 word")
        XCTAssertEqual(ClipPreviewInfo.header(time: "Today", kind: nil, detail: "1 word", hidden: false), "Today · 1 word")
        XCTAssertEqual(ClipPreviewInfo.header(time: "Today", kind: nil, detail: "1 word", hidden: true), "Today")
    }

    func test_rowAccessibilityLabelNeverHasTheValue() {
        XCTAssertEqual(ClipPreviewInfo.hiddenRowLabel(for: item(kind: .githubToken)), "Concealed clip, GitHub token")
        XCTAssertEqual(ClipPreviewInfo.hiddenRowLabel(for: item(kind: nil)), "Concealed clip")
    }

    func test_menuHasNotASecretAfterShowForFiveSeconds() {
        let entries = ClipMenuLayout.entries(for: item(kind: .githubToken))
        let show = entries.firstIndex(of: .showForFiveSeconds)
        XCTAssertNotNil(show)
        XCTAssertEqual(entries[show! + 1], .notASecret)
        XCTAssertNil(ClipMenuEntry.notASecret.key)
        XCTAssertEqual(ClipMenuEntry.notASecret.title, "Not a Secret")
    }

    func test_aConcealedClipWithoutAKindHasNoNotASecret() {
        XCTAssertFalse(ClipMenuLayout.entries(for: item(kind: nil)).contains(.notASecret))
        XCTAssertFalse(ClipMenuLayout.entries(for: item(kind: nil, concealed: false)).contains(.notASecret))
    }

    func test_menuOfANormalTextClipIsUnchanged() {
        let normal = ClipboardItem(date: Date(), content: .text("x"), sourceBundleID: "com.apple.Safari")
        XCTAssertEqual(ClipMenuLayout.entries(for: normal),
                       [.paste, .copyOnly, .preview, .edit, .separator, .excludeApp("com.apple.Safari"), .separator, .delete])
    }

    func test_previewButtonOfASecretIsNotASecret() {
        XCTAssertTrue(ClipPreviewInfo.showsNotASecretButton(for: item(kind: .jwt)))
        XCTAssertFalse(ClipPreviewInfo.showsNotASecretButton(for: item(kind: nil)))
    }
}
