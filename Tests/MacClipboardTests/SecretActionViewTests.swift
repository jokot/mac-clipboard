import XCTest
@testable import MaClip

final class SecretActionViewTests: XCTestCase {
    private var token: String { "ghp_" + String(repeating: "a", count: 36) }

    private func secret(_ text: String, _ kind: SecretKind) -> ClipboardItem {
        ClipboardItem(date: Date(), content: .text(text), sourceBundleID: "com.apple.Safari",
                      isConcealed: true, concealedExpiresAt: .distantFuture, secretKind: kind)
    }

    func test_menuHasTheSecretActionsBetweenNotASecretAndEdit() {
        let entries = ClipMenuLayout.entries(for: secret(token, .githubToken))
        let start = entries.firstIndex(of: .notASecret)!
        XCTAssertEqual(Array(entries[start...]), [
            .notASecret, .separator,
            .secret(.copyMasked), .secret(.copyFormat(.env)), .secret(.copyFormat(.shellExport)),
            .secret(.openKeyPage(provider: "GitHub", url: URL(string: "https://github.com/settings/tokens")!)),
            .separator, .edit, .separator, .excludeApp("com.apple.Safari"), .separator, .delete,
        ])
        XCTAssertEqual(ClipMenuEntry.secret(.copyMasked).title, "Copy Masked")
        XCTAssertNil(ClipMenuEntry.secret(.copyMasked).key)
    }

    func test_aDismissedClipHasNoSecretActions() {
        let item = ClipboardItem(date: Date(), content: .text(token), secretDismissed: true)
        XCTAssertFalse(ClipMenuLayout.entries(for: item).contains { if case .secret = $0 { return true } else { return false } })
    }

    func test_previewButtonsOfEachKind() {
        XCTAssertEqual(PreviewButtons.buttons(for: ClipboardItem(date: Date(), content: .text("x")), decodedJWT: false),
                       [.edit, .copyOnly])
        XCTAssertEqual(PreviewButtons.buttons(for: secret(token, .githubToken), decodedJWT: false), [.notASecret, .copyOnly])
        XCTAssertEqual(PreviewButtons.buttons(for: secret("x", .jwt), decodedJWT: true),
                       [.secret(.copyJWTHeader), .secret(.copyJWTPayload)])

        let key = "-----" + "BEGIN PRIVATE KEY-----\n" + Data([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65,
            0x70, 0x04, 0x22, 0x04, 0x20] + [UInt8](repeating: 9, count: 32)).base64EncodedString()
            + "\n-----" + "END PRIVATE KEY-----"
        XCTAssertEqual(PreviewButtons.buttons(for: secret(key, .privateKey), decodedJWT: false),
                       [.notASecret, .secret(.copyPublicKey)])
        let encrypted = "-----" + "BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----" + "END ENCRYPTED PRIVATE KEY-----"
        XCTAssertEqual(PreviewButtons.buttons(for: secret(encrypted, .privateKey), decodedJWT: false), [.notASecret, .copyOnly])
    }

    func test_rowLabelOfALiveStripeKey() {
        let live = secret("sk_" + "live_" + String(repeating: "a", count: 24), .stripeKey)
        XCTAssertEqual(ClipPreviewInfo.hiddenRowLabel(for: live), "Concealed clip, Stripe key, live")
        XCTAssertEqual(ClipPreviewInfo.rowBadge(for: live), "LIVE")
        XCTAssertNil(ClipPreviewInfo.rowBadge(for: secret(token, .githubToken)))
    }

    func test_secretTextOfALinkClip() {
        let link = ClipboardItem(date: Date(), content: .url(URL(string: "https://u:pw12345@example.com")!))
        XCTAssertEqual(link.secretText, "https://u:pw12345@example.com")
        XCTAssertNil(ClipboardItem(date: Date(), content: .file([URL(fileURLWithPath: "/tmp/x")])).secretText)
    }
}
