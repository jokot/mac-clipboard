import XCTest
@testable import MaClip

final class ClipboardItemRepositoryTests: XCTestCase {

    func test_textItemRoundTripPreservesNewFields() throws {
        let bundleID = "com.apple.TextEdit"
        let expiry = Date(timeIntervalSinceNow: 60)
        let item = ClipboardItem(
            id: UUID(),
            date: Date(),
            content: .text("hello"),
            sourceBundleID: bundleID,
            isConcealed: true,
            concealedExpiresAt: expiry
        )

        let repo = ClipboardRepository()
        repo.saveToDisk(items: [item])
        let loaded = repo.loadFromDisk()
        defer { repo.clearAllFiles() }

        XCTAssertEqual(loaded.count, 1)
        let r = loaded[0]
        XCTAssertEqual(r.sourceBundleID, bundleID)
        XCTAssertTrue(r.isConcealed)
        let loadedExpiry = try XCTUnwrap(r.concealedExpiresAt)
        XCTAssertEqual(loadedExpiry.timeIntervalSince1970,
                       expiry.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func test_legacyJSONDecodesWithDefaults() throws {
        let legacyJSON = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "date": 770000000,
            "type": "text",
            "text": "old item",
            "imageFilename": null,
            "url": null,
            "cachedText": null,
            "cachedId": null,
            "cachedBarcode": null
          }
        ]
        """.data(using: .utf8)!

        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("MaClip", isDirectory: true)
            .appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try legacyJSON.write(to: url, options: .atomic)

        let repo = ClipboardRepository()
        let loaded = repo.loadFromDisk()
        defer { repo.clearAllFiles() }

        XCTAssertEqual(loaded.count, 1)
        let r = loaded[0]
        XCTAssertNil(r.sourceBundleID)
        XCTAssertFalse(r.isConcealed)
        XCTAssertNil(r.concealedExpiresAt)
        if case .text(let t) = r.content {
            XCTAssertEqual(t, "old item")
        } else {
            XCTFail("expected text content")
        }
    }
}
