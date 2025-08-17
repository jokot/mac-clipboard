import Foundation
import Cocoa

protocol ClipboardRepositoryProtocol {
    func loadFromDisk() -> [ClipboardItem]
    func saveToDisk(items: [ClipboardItem])
    func saveToDiskAsync(items: [ClipboardItem])
    func clearAllFiles()
}

final class ClipboardRepository: ClipboardRepositoryProtocol {
    private struct PersistRecord: Codable {
        let id: UUID
        let date: Date
        let type: String // "text", "image", or "url"
        let text: String?
        let imageFilename: String?
        let url: String?
        let cachedText: String?
        let cachedBarcode: String?
    }

    // Serialize all disk operations to avoid race conditions and out-of-order writes
    private let saveQueue = DispatchQueue(label: "com.macclip.repository.save", qos: .utility)
    
    func loadFromDisk() -> [ClipboardItem] {
        guard let url = dataFileURL(), let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        guard let records = try? decoder.decode([PersistRecord].self, from: data) else { return [] }
        
        var loaded: [ClipboardItem] = []
        let imagesDir = imagesDirectory()
        
        for rec in records {
            switch rec.type {
            case "text":
                if let text = rec.text {
                    loaded.append(ClipboardItem(id: rec.id, date: rec.date, content: .text(text)))
                }
            case "image":
                if let name = rec.imageFilename, let imagesDir {
                    let imgURL = imagesDir.appendingPathComponent(name)
                    if let data = try? Data(contentsOf: imgURL), let image = NSImage(data: data) {
                        let imgContent = ImageContent(image: image, cachedText: rec.cachedText, cachedBarcode: rec.cachedBarcode)
                        loaded.append(ClipboardItem(id: rec.id, date: rec.date, content: .image(imgContent)))
                    }
                }
            case "url":
                if let s = rec.url, let u = URL(string: s) {
                    loaded.append(ClipboardItem(id: rec.id, date: rec.date, content: .url(u)))
                }
            default:
                continue
            }
        }
        return loaded
    }
    
    func saveToDiskAsync(items: [ClipboardItem]) {
        let snapshot = items
        saveQueue.async { [weak self] in
            self?.performSave(items: snapshot)
        }
    }

    func saveToDisk(items: [ClipboardItem]) {
        let snapshot = items
        saveQueue.sync {
            self.performSave(items: snapshot)
        }
    }

    // Actual save implementation executed on saveQueue only
    private func performSave(items: [ClipboardItem]) {
        guard let dataURL = dataFileURL() else { return }
        var records: [PersistRecord] = []
        let imagesDir = imagesDirectory()
        let fm = FileManager.default
        var savedImageHashes: [Data: String] = [:]  // Track saved images by their data hash
        
        for item in items {
            switch item.content {
            case .text(let text):
                records.append(PersistRecord(id: item.id, date: item.date, type: "text", text: text, imageFilename: nil, url: nil, cachedText: nil, cachedBarcode: nil))
            case .image(let imgContent):
                guard let imagesDir else { continue }
                let filename = item.id.uuidString + ".png"
                let fileURL = imagesDir.appendingPathComponent(filename)
                
                // Get PNG data for comparison
                guard let pngData = imgContent.image.pngData() else { continue }
                
                // Check if we already saved this exact image data
                if let existingFilename = savedImageHashes[pngData] {
                    // Reuse existing file
                    records.append(PersistRecord(id: item.id, date: item.date, type: "image", text: nil, imageFilename: existingFilename, url: nil, cachedText: imgContent.cachedText, cachedBarcode: imgContent.cachedBarcode))
                } else {
                    // Write new PNG file
                    if !fm.fileExists(atPath: fileURL.path) {
                        try? pngData.write(to: fileURL, options: .atomic)
                    }
                    savedImageHashes[pngData] = filename
                    records.append(PersistRecord(id: item.id, date: item.date, type: "image", text: nil, imageFilename: filename, url: nil, cachedText: imgContent.cachedText, cachedBarcode: imgContent.cachedBarcode))
                }
            case .url(let u):
                records.append(PersistRecord(id: item.id, date: item.date, type: "url", text: nil, imageFilename: nil, url: u.absoluteString, cachedText: nil, cachedBarcode: nil))
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(records) {
            try? data.write(to: dataURL, options: .atomic)
        }
        
        // Cleanup: remove any image files not referenced by current records
        if let imagesDir,
           let contents = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil, options: []) {
            let referenced = Set(records.compactMap { $0.imageFilename })
            for url in contents {
                if !referenced.contains(url.lastPathComponent) {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }

    func clearAllFiles() {
        // Ensure no save is running while we clear files
        saveQueue.sync {
            let fm = FileManager.default
            // Remove history.json
            if let dataURL = dataFileURL(), fm.fileExists(atPath: dataURL.path) {
                try? fm.removeItem(at: dataURL)
            }
            // Remove all images in Images directory
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
        if let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = url.appendingPathComponent("MaClip", isDirectory: true)
            if !fm.fileExists(atPath: appDir.path) {
                try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
            }
            return appDir
        }
        return nil
    }

    func dataFileURL() -> URL? {
        appSupportDirectory()?.appendingPathComponent("history.json")
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