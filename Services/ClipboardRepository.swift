import Foundation
import Cocoa

protocol ClipboardRepositoryProtocol {
    func loadFromDisk() -> [ClipboardItem]
    func saveToDisk(items: [ClipboardItem])
    func saveToDiskAsync(items: [ClipboardItem])
    func clearAllFiles()
    func saveImage(_ image: NSImage) -> URL?
    func saveImage(pngData: Data) -> URL?
    func readImageData(at encURL: URL) -> Data?
    func deleteImage(at encURL: URL)
    /// True when encryption is off and an earlier version left encrypted history on disk.
    var hasEncryptedHistoryToRestore: Bool { get }
    /// Decrypts `history.bin`. Reads the Keychain key. Returns nil when the key cannot be read.
    func loadEncryptedHistory() -> [ClipboardItem]?
    /// Saves `items` in the other format and removes the files of the old one.
    /// Returns false, and keeps the old files, when a file cannot be converted.
    func switchStorage(items: [ClipboardItem], toEncrypted: Bool) -> Bool
}

final class ClipboardRepository: ClipboardRepositoryProtocol {
    private struct PersistRecord: Codable {
        let id: UUID
        let date: Date
        let type: String // "text", "image", "url", or "file"
        let text: String?
        let imageFilename: String?
        let url: String?
        let cachedText: String?
        let cachedId: String?
        let cachedBarcode: String?
        // Added in 1.7.0; optional so legacy JSON without these keys still decodes.
        let sourceBundleID: String?
        let isConcealed: Bool?
        let concealedExpiresAt: Date?
        let isOCRResult: Bool?
        // Added in 1.10.0; optional so legacy JSON without this key still decodes.
        let filePaths: [String]?
    }

    // Serialize all disk operations to avoid race conditions and out-of-order writes
    private let saveQueue = DispatchQueue(label: "com.macclip.repository.save", qos: .utility)

    /// Encrypted: `history.bin` and `Images/*.enc`. Plain: `history.json` and `Images/*.png`.
    private let encryptionEnabled: () -> Bool

    init(encryptionEnabled: @escaping () -> Bool = { AppSettings.shared.encryptHistory }) {
        self.encryptionEnabled = encryptionEnabled
    }

    // With encryption off, this never reads the Keychain key.
    func loadFromDisk() -> [ClipboardItem] {
        if encryptionEnabled(), let url = encryptedDataFileURL(),
           let ciphertext = try? Data(contentsOf: url) {
            do {
                return decodeItems(from: try HistoryCrypto.open(ciphertext))
            } catch {
                NSLog("[MaClip] failed to decrypt history.bin: \(error)")
                HistoryDecryptFailure.flag()
                return []
            }
        }
        // Plain history, or history from before 1.9.0. With encryption on, the next save encrypts it.
        guard let url = plainDataFileURL(), let data = try? Data(contentsOf: url) else { return [] }
        return decodeItems(from: data)
    }

    var hasEncryptedHistoryToRestore: Bool {
        guard !encryptionEnabled(), let url = encryptedDataFileURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func loadEncryptedHistory() -> [ClipboardItem]? {
        guard let url = encryptedDataFileURL(),
              let ciphertext = try? Data(contentsOf: url) else { return nil }
        do {
            return decodeItems(from: try HistoryCrypto.open(ciphertext))
        } catch {
            NSLog("[MaClip] failed to decrypt earlier history: \(error)")
            return nil
        }
    }

    func switchStorage(items: [ClipboardItem], toEncrypted encrypt: Bool) -> Bool {
        let snapshot = items
        return saveQueue.sync {
            guard performSave(items: snapshot, encrypt: encrypt, strict: true) else { return false }
            // No file uses the key now.
            if !encrypt { HistoryCrypto.deleteKey() }
            return true
        }
    }

    private func decodeItems(from data: Data) -> [ClipboardItem] {
        let decoder = JSONDecoder()
        guard let records = try? decoder.decode([PersistRecord].self, from: data) else { return [] }

        var loaded: [ClipboardItem] = []
        let imagesDir = imagesDirectory()

        for rec in records {
            let isConcealed = rec.isConcealed ?? false
            switch rec.type {
            case "text":
                if let text = rec.text {
                    loaded.append(ClipboardItem(
                        id: rec.id, date: rec.date, content: .text(text),
                        sourceBundleID: rec.sourceBundleID,
                        isConcealed: isConcealed,
                        concealedExpiresAt: rec.concealedExpiresAt,
                        isOCRResult: rec.isOCRResult ?? false
                    ))
                }
            case "image":
                if let name = rec.imageFilename, let imagesDir {
                    let encURL = imagesDir.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: encURL.path) {
                        let imgContent = ImageContent(source: .file(encURL),
                                                      cachedText: rec.cachedText,
                                                      cachedId: rec.cachedId,
                                                      cachedBarcode: rec.cachedBarcode)
                        loaded.append(ClipboardItem(
                            id: rec.id, date: rec.date, content: .image(imgContent),
                            sourceBundleID: rec.sourceBundleID,
                            isConcealed: isConcealed,
                            concealedExpiresAt: rec.concealedExpiresAt,
                            isOCRResult: rec.isOCRResult ?? false
                        ))
                    }
                }
            case "url":
                if let s = rec.url, let u = URL(string: s) {
                    loaded.append(ClipboardItem(
                        id: rec.id, date: rec.date, content: .url(u),
                        sourceBundleID: rec.sourceBundleID,
                        isConcealed: isConcealed,
                        concealedExpiresAt: rec.concealedExpiresAt,
                        isOCRResult: rec.isOCRResult ?? false
                    ))
                }
            case "file":
                if let paths = rec.filePaths {
                    let urls = paths.map { URL(fileURLWithPath: $0) }
                    loaded.append(ClipboardItem(
                        id: rec.id, date: rec.date, content: .file(urls),
                        sourceBundleID: rec.sourceBundleID,
                        isConcealed: isConcealed,
                        concealedExpiresAt: rec.concealedExpiresAt,
                        isOCRResult: rec.isOCRResult ?? false
                    ))
                }
            default:
                continue
            }
        }
        return loaded
    }

    // Helper to persist a single image immediately (used by ViewModel to convert memory->file)
    func saveImage(_ image: NSImage) -> URL? {
        guard let pngData = image.pngData() else { return nil }
        return saveImage(pngData: pngData)
    }

    // Overload: persist an already-encoded PNG (e.g. from ImageCompositor after edit).
    func saveImage(pngData: Data) -> URL? {
        writeImage(pngData, baseName: UUID().uuidString, encrypt: encryptionEnabled())
    }

    /// Reads `.enc` files with the key and other files as plain PNG.
    func readImageData(at encURL: URL) -> Data? {
        guard let data = try? Data(contentsOf: encURL) else { return nil }
        guard encURL.pathExtension.lowercased() == "enc" else { return data }
        return try? HistoryCrypto.open(data)
    }

    private func writeImage(_ pngData: Data, baseName: String, encrypt: Bool) -> URL? {
        guard let imagesDir = imagesDirectory() else { return nil }
        let fileURL = imagesDir.appendingPathComponent(baseName + (encrypt ? ".enc" : ".png"))
        do {
            let bytes = encrypt ? try HistoryCrypto.seal(pngData) : pngData
            try bytes.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            NSLog("[MaClip] writeImage failed: \(error)")
            return nil
        }
    }

    func deleteImage(at encURL: URL) {
        try? FileManager.default.removeItem(at: encURL)
    }

    func saveToDiskAsync(items: [ClipboardItem]) {
        let snapshot = items
        let encrypt = encryptionEnabled()
        saveQueue.async { [weak self] in
            self?.performSave(items: snapshot, encrypt: encrypt)
        }
    }

    func saveToDisk(items: [ClipboardItem]) {
        let snapshot = items
        let encrypt = encryptionEnabled()
        saveQueue.sync {
            _ = self.performSave(items: snapshot, encrypt: encrypt)
        }
    }

    // Actual save implementation executed on saveQueue only.
    // `strict` (a format switch) stops at the first file that cannot be converted, before
    // it writes the history file, and then removes the history file of the other format.
    @discardableResult
    private func performSave(items: [ClipboardItem], encrypt: Bool, strict: Bool = false) -> Bool {
        let imageExt = encrypt ? "enc" : "png"
        var records: [PersistRecord] = []
        let imagesDir = imagesDirectory()
        let fm = FileManager.default
        var savedImageHashes: [Data: String] = [:]  // Track saved images by their data hash
        
        for item in items {
            switch item.content {
            case .text(let text):
                records.append(PersistRecord(
                    id: item.id, date: item.date, type: "text",
                    text: text, imageFilename: nil, url: nil,
                    cachedText: nil, cachedId: nil, cachedBarcode: nil,
                    sourceBundleID: item.sourceBundleID,
                    isConcealed: item.isConcealed,
                    concealedExpiresAt: item.concealedExpiresAt,
                    isOCRResult: item.isOCRResult,
                    filePaths: nil
                ))
            case .image(let imgContent):
                guard let imagesDir else { continue }
                var filename: String?
                switch imgContent.source {
                case .file(let url):
                    filename = url.lastPathComponent
                    if url.pathExtension.lowercased() != imageExt {
                        // Saved in the other format. Convert it.
                        if let data = readImageData(at: url),
                           let converted = writeImage(data, baseName: url.deletingPathExtension().lastPathComponent,
                                                      encrypt: encrypt) {
                            filename = converted.lastPathComponent
                        } else if strict {
                            NSLog("[MaClip] could not convert \(url.lastPathComponent)")
                            return false
                        }
                    }
                    records.append(PersistRecord(
                        id: item.id, date: item.date, type: "image",
                        text: nil, imageFilename: filename, url: nil,
                        cachedText: imgContent.cachedText, cachedId: imgContent.cachedId, cachedBarcode: imgContent.cachedBarcode,
                        sourceBundleID: item.sourceBundleID,
                        isConcealed: item.isConcealed,
                        concealedExpiresAt: item.concealedExpiresAt,
                        isOCRResult: item.isOCRResult,
                        filePaths: nil
                    ))
                case .memory(let image):
                    let name = item.id.uuidString + "." + imageExt
                    let fileURL = imagesDir.appendingPathComponent(name)
                    if let pngData = image.pngData() {
                        if let existing = savedImageHashes[pngData] {
                            filename = existing
                        } else {
                            if !fm.fileExists(atPath: fileURL.path),
                               writeImage(pngData, baseName: item.id.uuidString, encrypt: encrypt) == nil,
                               strict {
                                return false
                            }
                            savedImageHashes[pngData] = name
                            filename = name
                        }
                        records.append(PersistRecord(
                            id: item.id, date: item.date, type: "image",
                            text: nil, imageFilename: filename, url: nil,
                            cachedText: imgContent.cachedText, cachedId: imgContent.cachedId, cachedBarcode: imgContent.cachedBarcode,
                            sourceBundleID: item.sourceBundleID,
                            isConcealed: item.isConcealed,
                            concealedExpiresAt: item.concealedExpiresAt,
                            isOCRResult: item.isOCRResult,
                            filePaths: nil
                        ))
                    }
                }
            case .url(let u):
                records.append(PersistRecord(
                    id: item.id, date: item.date, type: "url",
                    text: nil, imageFilename: nil, url: u.absoluteString,
                    cachedText: nil, cachedId: nil, cachedBarcode: nil,
                    sourceBundleID: item.sourceBundleID,
                    isConcealed: item.isConcealed,
                    concealedExpiresAt: item.concealedExpiresAt,
                    isOCRResult: item.isOCRResult,
                    filePaths: nil
                ))
            case .file(let urls):
                records.append(PersistRecord(
                    id: item.id, date: item.date, type: "file",
                    text: nil, imageFilename: nil, url: nil,
                    cachedText: nil, cachedId: nil, cachedBarcode: nil,
                    sourceBundleID: item.sourceBundleID,
                    isConcealed: item.isConcealed,
                    concealedExpiresAt: item.concealedExpiresAt,
                    isOCRResult: item.isOCRResult,
                    filePaths: urls.map(\.path)
                ))
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let plaintext = try? encoder.encode(records) else { return false }
        if encrypt {
            guard let ciphertext = try? HistoryCrypto.seal(plaintext) else {
                NSLog("[MaClip] failed to encrypt history; not writing")
                return false
            }
            guard let binURL = encryptedDataFileURL(),
                  (try? ciphertext.write(to: binURL, options: .atomic)) != nil else { return false }
            removeFile(plainDataFileURL())
        } else {
            guard let jsonURL = plainDataFileURL(),
                  (try? plaintext.write(to: jsonURL, options: .atomic)) != nil else { return false }
            if strict {
                removeFile(encryptedDataFileURL())
                removeFile(encryptedSentinelURL())
            }
        }

        // Cleanup: remove any image files not referenced by current records.
        // With encryption off, keep the encrypted images of an earlier version until a restore.
        let keepEncryptedImages = !encrypt && encryptedDataFileURL().map { fm.fileExists(atPath: $0.path) } == true
        if let imagesDir,
           let contents = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil, options: []) {
            let referenced = Set(records.compactMap { $0.imageFilename })
            for url in contents {
                if keepEncryptedImages && url.pathExtension.lowercased() == "enc" { continue }
                if !referenced.contains(url.lastPathComponent) {
                    try? fm.removeItem(at: url)
                }
            }
        }
        return true
    }

    private func removeFile(_ url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func clearAllFiles() {
        // Ensure no save is running while we clear files
        saveQueue.sync {
            let fm = FileManager.default
            // Remove history.bin
            if let binURL = encryptedDataFileURL(), fm.fileExists(atPath: binURL.path) {
                try? fm.removeItem(at: binURL)
            }
            // Remove history.json
            if let jsonURL = plainDataFileURL(), fm.fileExists(atPath: jsonURL.path) {
                try? fm.removeItem(at: jsonURL)
            }
            // Remove the marker from 1.9.0-1.11.x
            if let sentinel = encryptedSentinelURL(), fm.fileExists(atPath: sentinel.path) {
                try? fm.removeItem(at: sentinel)
            }
            // Remove all images in Images directory (.enc and .png)
            if let imagesDir = imagesDirectory(), fm.fileExists(atPath: imagesDir.path) {
                if let contents = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil, options: []) {
                    for url in contents {
                        try? fm.removeItem(at: url)
                    }
                }
            }
        }
    }
}

// MARK: - File Management
private extension ClipboardRepository {
    func appSupportDirectory() -> URL? {
        let fm = FileManager.default
        if let appDir = AppEnvironment.appSupportDirectory {
            if !fm.fileExists(atPath: appDir.path) {
                try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
            }
            return appDir
        }
        return nil
    }

    func encryptedDataFileURL() -> URL? {
        appSupportDirectory()?.appendingPathComponent("history.bin")
    }

    func plainDataFileURL() -> URL? {
        appSupportDirectory()?.appendingPathComponent("history.json")
    }

    /// Versions 1.9.0-1.11.x wrote this marker after their one-time encryption migration.
    func encryptedSentinelURL() -> URL? {
        appSupportDirectory()?.appendingPathComponent(".encrypted")
    }

    func imagesDirectory() -> URL? {
        guard let base = appSupportDirectory() else { return nil }
        let dir = base.appendingPathComponent("Images", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}