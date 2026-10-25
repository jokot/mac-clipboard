import XCTest
@testable import MaClip

final class ClipboardItemRepositoryTests: XCTestCase {
    private var keys: SpyKeyStore!
    private var savedKeyStore: HistoryKeyStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // These tests delete history and images. Never let them reach real user data.
        try XCTSkipUnless(AppEnvironment.isRunningTests, "test storage isolation is not active")
        savedKeyStore = HistoryCrypto.keyStore
        keys = SpyKeyStore()
        HistoryCrypto.keyStore = keys
        ClipboardRepository(encryptionEnabled: { false }).clearAllFiles()
    }

    override func tearDown() {
        if let savedKeyStore { HistoryCrypto.keyStore = savedKeyStore }
        super.tearDown()
    }

    private var appSupport: URL { AppEnvironment.appSupportDirectory! }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: appSupport.appendingPathComponent(name).path)
    }

    private func imageFiles(withExtension ext: String) -> [URL] {
        let dir = appSupport.appendingPathComponent("Images")
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == ext }
    }

    private func makePNG() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// Writes one text clip and one image clip with `repo`, in its current format.
    private func saveTextAndImage(with repo: ClipboardRepository, png: Data) throws -> (text: UUID, image: UUID) {
        let url = try XCTUnwrap(repo.saveImage(pngData: png))
        let text = ClipboardItem(id: UUID(), date: Date(), content: .text("secret note"))
        let image = ClipboardItem(id: UUID(), date: Date(),
                                  content: .image(ImageContent(source: .file(url), cachedText: nil,
                                                               cachedId: nil, cachedBarcode: nil)))
        repo.saveToDisk(items: [text, image])
        return (text.id, image.id)
    }

    private func imageData(of item: ClipboardItem, with repo: ClipboardRepository) -> Data? {
        guard case .image(let img) = item.content, case .file(let url) = img.source else { return nil }
        return repo.readImageData(at: url)
    }

    // MARK: - Encryption off (the default)

    func test_plainModeDoesNotReadTheKey() throws {
        let png = try makePNG()
        let repo = ClipboardRepository(encryptionEnabled: { false })
        let ids = try saveTextAndImage(with: repo, png: png)

        let loaded = ClipboardRepository(encryptionEnabled: { false }).loadFromDisk()

        XCTAssertEqual(loaded.map(\.id), [ids.text, ids.image])
        XCTAssertEqual(imageData(of: loaded[1], with: repo), png)
        XCTAssertTrue(exists("history.json"))
        XCTAssertFalse(exists("history.bin"))
        XCTAssertEqual(imageFiles(withExtension: "png").count, 1)
        XCTAssertEqual(imageFiles(withExtension: "enc").count, 0)
        XCTAssertEqual(keys.readCount, 0, "plain mode must never read the Keychain key")
    }

    // An update from 1.9-1.11: the history is encrypted, but encryption is now off.
    func test_plainModeLaunchKeepsEncryptedHistoryAndDoesNotReadTheKey() throws {
        let png = try makePNG()
        _ = try saveTextAndImage(with: ClipboardRepository(encryptionEnabled: { true }), png: png)
        keys.resetCounts()

        let repo = ClipboardRepository(encryptionEnabled: { false })
        XCTAssertEqual(repo.loadFromDisk().count, 0)
        XCTAssertTrue(repo.hasEncryptedHistoryToRestore)

        // New clips are saved as plain files. The encrypted files stay for a restore.
        repo.saveToDisk(items: [ClipboardItem(date: Date(), content: .text("new"))])

        XCTAssertEqual(keys.readCount, 0, "launch must not read the Keychain key")
        XCTAssertTrue(exists("history.bin"))
        XCTAssertEqual(imageFiles(withExtension: "enc").count, 1)
        XCTAssertTrue(exists("history.json"))
    }

    func test_restoreConvertsEncryptedHistoryToPlainFiles() throws {
        let png = try makePNG()
        let ids = try saveTextAndImage(with: ClipboardRepository(encryptionEnabled: { true }), png: png)

        let repo = ClipboardRepository(encryptionEnabled: { false })
        let current = ClipboardItem(date: Date(), content: .text("new"))
        let restored = try XCTUnwrap(repo.loadEncryptedHistory())
        XCTAssertTrue(repo.switchStorage(items: [current] + restored, toEncrypted: false))

        XCTAssertFalse(repo.hasEncryptedHistoryToRestore)
        XCTAssertFalse(exists("history.bin"))
        XCTAssertEqual(imageFiles(withExtension: "enc").count, 0)
        XCTAssertEqual(keys.deleteCount, 1, "the key is not needed after a restore")
        keys.resetCounts()

        let loaded = ClipboardRepository(encryptionEnabled: { false }).loadFromDisk()
        XCTAssertEqual(loaded.map(\.id), [current.id, ids.text, ids.image])
        XCTAssertEqual(imageData(of: loaded[2], with: repo), png)
        XCTAssertEqual(keys.readCount, 0)
    }

    func test_restoreFailureKeepsEncryptedFiles() throws {
        _ = try saveTextAndImage(with: ClipboardRepository(encryptionEnabled: { true }), png: try makePNG())
        keys.failReads = true

        let repo = ClipboardRepository(encryptionEnabled: { false })
        XCTAssertNil(repo.loadEncryptedHistory())

        XCTAssertTrue(repo.hasEncryptedHistoryToRestore)
        XCTAssertTrue(exists("history.bin"))
        XCTAssertEqual(imageFiles(withExtension: "enc").count, 1)
        XCTAssertEqual(keys.deleteCount, 0)
    }

    func test_switchToPlainFailsWithoutTheKeyAndKeepsEncryptedFiles() throws {
        let png = try makePNG()
        let writer = ClipboardRepository(encryptionEnabled: { true })
        _ = try saveTextAndImage(with: writer, png: png)
        let items = writer.loadFromDisk()
        keys.failReads = true

        XCTAssertFalse(writer.switchStorage(items: items, toEncrypted: false))

        XCTAssertTrue(exists("history.bin"))
        XCTAssertFalse(exists("history.json"))
        XCTAssertEqual(imageFiles(withExtension: "enc").count, 1)
        XCTAssertEqual(keys.deleteCount, 0)
    }

    // MARK: - Encryption on

    func test_switchToEncryptedEncryptsPlainHistory() throws {
        let png = try makePNG()
        let plain = ClipboardRepository(encryptionEnabled: { false })
        let ids = try saveTextAndImage(with: plain, png: png)

        XCTAssertTrue(plain.switchStorage(items: plain.loadFromDisk(), toEncrypted: true))

        XCTAssertTrue(exists("history.bin"))
        XCTAssertFalse(exists("history.json"))
        XCTAssertEqual(imageFiles(withExtension: "png").count, 0)
        XCTAssertEqual(imageFiles(withExtension: "enc").count, 1)
        let raw = try Data(contentsOf: appSupport.appendingPathComponent("history.bin"))
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("secret note"))

        let encrypted = ClipboardRepository(encryptionEnabled: { true })
        let loaded = encrypted.loadFromDisk()
        XCTAssertEqual(loaded.map(\.id), [ids.text, ids.image])
        XCTAssertEqual(imageData(of: loaded[1], with: encrypted), png)
    }

    func test_switchToPlainDecryptsHistoryAndDeletesTheKey() throws {
        let png = try makePNG()
        let encrypted = ClipboardRepository(encryptionEnabled: { true })
        let ids = try saveTextAndImage(with: encrypted, png: png)

        XCTAssertTrue(encrypted.switchStorage(items: encrypted.loadFromDisk(), toEncrypted: false))

        XCTAssertFalse(exists("history.bin"))
        XCTAssertTrue(exists("history.json"))
        XCTAssertEqual(imageFiles(withExtension: "enc").count, 0)
        XCTAssertEqual(keys.deleteCount, 1)
        keys.resetCounts()

        let plain = ClipboardRepository(encryptionEnabled: { false })
        let loaded = plain.loadFromDisk()
        XCTAssertEqual(loaded.map(\.id), [ids.text, ids.image])
        XCTAssertEqual(imageData(of: loaded[1], with: plain), png)
        XCTAssertEqual(keys.readCount, 0)
    }

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

        let repo = ClipboardRepository(encryptionEnabled: { true })
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
        let appSupport = AppEnvironment.appSupportDirectory!
        let binURL = appSupport.appendingPathComponent("history.bin")
        let jsonURL = appSupport.appendingPathComponent("history.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: binURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        let raw = try Data(contentsOf: binURL)
        XCTAssertFalse(String(data: raw, encoding: .utf8)?.contains("encrypted hello") ?? false,
                       "plaintext should not be readable in the on-disk binary")
    }

    // History from before 1.9.0 is plain JSON. With encryption on, the next save encrypts it.
    func test_legacyJSONIsEncryptedOnNextSaveWhenEncryptionIsOn() throws {
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

        let repo = ClipboardRepository(encryptionEnabled: { true })
        let loaded = repo.loadFromDisk()
        defer { repo.clearAllFiles() }

        XCTAssertEqual(loaded.count, 1)
        if case .text(let t) = loaded[0].content {
            XCTAssertEqual(t, "legacy item")
        } else { XCTFail("expected text") }

        repo.saveToDisk(items: loaded)
        XCTAssertFalse(exists("history.json"))
        XCTAssertTrue(exists("history.bin"))
    }

    // QA #17: an edited image survives a quit and relaunch (new repository instance).
    func test_editedImagePersistsAcrossReload() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))

        let writer = ClipboardRepository(encryptionEnabled: { true })
        defer { writer.clearAllFiles() }
        let url = try XCTUnwrap(writer.saveImage(pngData: png))
        let id = UUID()
        writer.saveToDisk(items: [ClipboardItem(
            id: id, date: Date(),
            content: .image(ImageContent(source: .file(url), cachedText: nil, cachedId: nil, cachedBarcode: nil))
        )])

        XCTAssertNotEqual(try Data(contentsOf: url), png, "image must be encrypted on disk")

        let reader = ClipboardRepository(encryptionEnabled: { true })
        let loaded = reader.loadFromDisk()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, id)
        guard case .image(let img) = loaded[0].content, case .file(let loadedURL) = img.source else {
            return XCTFail("expected file-backed image")
        }
        let data = try XCTUnwrap(reader.readImageData(at: loadedURL))
        XCTAssertEqual(data, png)
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(decoded.pixelsWide, 3)
        XCTAssertEqual(decoded.pixelsHigh, 2)
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

        let url = AppEnvironment.appSupportDirectory!
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
