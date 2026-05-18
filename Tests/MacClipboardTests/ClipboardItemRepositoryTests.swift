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

    func test_isOCRResultRoundTrips() throws {
        let item = ClipboardItem(
            id: UUID(),
            date: Date(),
            content: .text("hello"),
            sourceBundleID: "com.apple.Preview",
            isConcealed: false,
            concealedExpiresAt: nil,
            isOCRResult: true
        )

        let repo = ClipboardRepository()
        repo.saveToDisk(items: [item])
        let loaded = repo.loadFromDisk()
        defer { repo.clearAllFiles() }

        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(loaded[0].isOCRResult)
    }

    func test_encryptedRoundTrip() throws {
        let item = ClipboardItem(
            id: UUID(),
            date: Date(),
            content: .text("encrypted hello"),
            sourceBundleID: "com.apple.TextEdit",
            isConcealed: false,
            concealedExpiresAt: nil,
            isOCRResult: false
        )

        let repo = ClipboardRepository()
        repo.saveToDisk(items: [item])
        let loaded = repo.loadFromDisk()
        defer { repo.clearAllFiles() }

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].sourceBundleID, "com.apple.TextEdit")
        if case .text(let t) = loaded[0].content {
            XCTAssertEqual(t, "encrypted hello")
        } else { XCTFail("expected text") }

        // On-disk file should be history.bin, NOT history.json, and inspecting it must NOT
        // reveal plaintext.
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("MaClip", isDirectory: true)
        let binURL = appSupport.appendingPathComponent("history.bin")
        let jsonURL = appSupport.appendingPathComponent("history.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: binURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        let raw = try Data(contentsOf: binURL)
        XCTAssertFalse(String(data: raw, encoding: .utf8)?.contains("encrypted hello") ?? false,
                       "plaintext should not be readable in the on-disk binary")
    }

    func test_legacyJSONMigratesToEncryptedAtFirstLoad() throws {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("MaClip", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        try? FileManager.default.removeItem(at: appSupport.appendingPathComponent("history.bin"))
        try? FileManager.default.removeItem(at: appSupport.appendingPathComponent("history.json"))
        try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(".encrypted"))

        let legacyJSON = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "date": 770000000,
            "type": "text",
            "text": "legacy item",
            "imageFilename": null,
            "url": null,
            "cachedText": null,
            "cachedId": null,
            "cachedBarcode": null
          }
        ]
        """.data(using: .utf8)!
        try legacyJSON.write(to: appSupport.appendingPathComponent("history.json"), options: .atomic)

        let repo = ClipboardRepository()
        let loaded = repo.loadFromDisk()
        defer { repo.clearAllFiles() }

        XCTAssertEqual(loaded.count, 1)
        if case .text(let t) = loaded[0].content {
            XCTAssertEqual(t, "legacy item")
        } else { XCTFail("expected text") }

        XCTAssertFalse(FileManager.default.fileExists(atPath: appSupport.appendingPathComponent("history.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appSupport.appendingPathComponent("history.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appSupport.appendingPathComponent(".encrypted").path))
    }

    func test_fileClipRoundTrips() throws {
        let url1 = URL(fileURLWithPath: "/tmp/maclip-test-1.txt")
        let url2 = URL(fileURLWithPath: "/tmp/maclip-test-2.txt")
        try Data().write(to: url1)
        try Data().write(to: url2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let item = ClipboardItem(
            id: UUID(),
            date: Date(),
            content: .file([url1, url2]),
            sourceBundleID: "com.apple.finder",
            isConcealed: false,
            concealedExpiresAt: nil,
            isOCRResult: false
        )

        let repo = ClipboardRepository()
        repo.saveToDisk(items: [item])
        let loaded = repo.loadFromDisk()
        defer { repo.clearAllFiles() }

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].sourceBundleID, "com.apple.finder")
        if case .file(let urls) = loaded[0].content {
            XCTAssertEqual(urls.map(\.path), [url1.path, url2.path])
        } else {
            XCTFail("expected .file content, got \(loaded[0].content)")
        }
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
