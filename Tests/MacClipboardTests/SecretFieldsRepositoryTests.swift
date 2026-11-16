import XCTest
@testable import MaClip

/// The secret fields of a clip in the saved history.
final class SecretFieldsRepositoryTests: XCTestCase {
    private var savedKeyStore: HistoryKeyStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // These tests delete history. Never let them reach real user data.
        try XCTSkipUnless(AppEnvironment.isRunningTests, "test storage isolation is not active")
        savedKeyStore = HistoryCrypto.keyStore
        HistoryCrypto.keyStore = SpyKeyStore()
        ClipboardRepository(encryptionEnabled: { false }).clearAllFiles()
    }

    override func tearDown() {
        ClipboardRepository(encryptionEnabled: { false }).clearAllFiles()
        if let savedKeyStore { HistoryCrypto.keyStore = savedKeyStore }
        super.tearDown()
    }

    private func roundTrip(encrypted: Bool) {
        let secret = ClipboardItem(date: Date(), content: .text("hidden"),
                                   isConcealed: true, concealedExpiresAt: Date(timeIntervalSinceNow: 60),
                                   secretKind: .githubToken, secretDismissed: false)
        let dismissed = ClipboardItem(date: Date(), content: .url(URL(string: "https://example.com")!),
                                      secretKind: nil, secretDismissed: true)
        let repo = ClipboardRepository(encryptionEnabled: { encrypted })
        repo.saveToDisk(items: [secret, dismissed])

        let loaded = ClipboardRepository(encryptionEnabled: { encrypted }).loadFromDisk()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].secretKind, .githubToken)
        XCTAssertFalse(loaded[0].secretDismissed)
        XCTAssertNil(loaded[1].secretKind)
        XCTAssertTrue(loaded[1].secretDismissed)
    }

    func test_secretFieldsRoundTrip() {
        roundTrip(encrypted: false)
    }

    func test_secretFieldsRoundTripEncrypted() {
        roundTrip(encrypted: true)
    }

    private func writeHistoryJSON(_ json: String) throws {
        let url = AppEnvironment.appSupportDirectory!.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url, options: .atomic)
    }

    func test_historyWithoutSecretKeysLoads() throws {
        try writeHistoryJSON("""
        [{"id": "11111111-1111-1111-1111-111111111111", "date": 770000000, "type": "text",
          "text": "old item", "sourceBundleID": null, "isConcealed": false, "isOCRResult": false,
          "filePaths": null}]
        """)
        let loaded = ClipboardRepository(encryptionEnabled: { false }).loadFromDisk()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded[0].secretKind)
        XCTAssertFalse(loaded[0].secretDismissed)
    }

    func test_unknownSecretKindLoadsAsNoKind() throws {
        try writeHistoryJSON("""
        [{"id": "22222222-2222-2222-2222-222222222222", "date": 770000000, "type": "text",
          "text": "future item", "isConcealed": true, "secretKind": "futureKind"}]
        """)
        let loaded = ClipboardRepository(encryptionEnabled: { false }).loadFromDisk()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded[0].secretKind)
        XCTAssertTrue(loaded[0].isConcealed)
    }
}

final class ClipboardItemSecretFlagsTests: XCTestCase {
    func test_replacingKeepsAllFlags() {
        let expiry = Date(timeIntervalSinceNow: 90)
        let item = ClipboardItem(date: Date(), content: .text("a"), sourceBundleID: "x",
                                 isConcealed: true, concealedExpiresAt: expiry, isOCRResult: true,
                                 secretKind: .keyValue, secretDismissed: false)
        let copy = item.replacing(content: .text("b"))
        XCTAssertEqual(copy.id, item.id)
        XCTAssertEqual(copy.date, item.date)
        XCTAssertEqual(copy.sourceBundleID, "x")
        XCTAssertTrue(copy.isConcealed)
        XCTAssertEqual(copy.concealedExpiresAt, expiry)
        XCTAssertTrue(copy.isOCRResult)
        XCTAssertEqual(copy.secretKind, .keyValue)
        guard case .text("b") = copy.content else { return XCTFail("content not replaced") }
    }

    func test_markedChangesOnlyTheFlags() {
        let item = ClipboardItem(date: Date(), content: .text("a"), sourceBundleID: "x", isOCRResult: true)
        let marked = item.marked(concealed: true, expiresAt: .distantFuture, secretKind: .jwt, secretDismissed: false)
        XCTAssertEqual(marked.id, item.id)
        XCTAssertEqual(marked.sourceBundleID, "x")
        XCTAssertTrue(marked.isOCRResult)
        XCTAssertTrue(marked.isConcealed)
        XCTAssertEqual(marked.concealedExpiresAt, .distantFuture)
        XCTAssertEqual(marked.secretKind, .jwt)
        XCTAssertTrue(marked.matchesContent(item))
    }

    /// SwiftUI compares rows with ==, so a change of the flags must make the rows differ.
    func test_equalityIncludesTheSecretFlags() {
        let item = ClipboardItem(date: Date(), content: .text("a"))
        XCTAssertEqual(item, item.marked(concealed: false, expiresAt: nil, secretKind: nil, secretDismissed: false))
        XCTAssertNotEqual(item, item.marked(concealed: true, expiresAt: nil, secretKind: .jwt, secretDismissed: false))
        XCTAssertNotEqual(item, item.marked(concealed: false, expiresAt: nil, secretKind: nil, secretDismissed: true))
    }
}
