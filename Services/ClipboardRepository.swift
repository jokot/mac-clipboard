import Foundation
import Cocoa

protocol ClipboardRepositoryProtocol {
    func loadFromDisk() -> [ClipboardItem]
    func saveToDisk(items: [ClipboardItem])
    func saveToDiskAsync(items: [ClipboardItem])
}

final class ClipboardRepository: ClipboardRepositoryProtocol {
    private struct PersistRecord: Codable {
        let id: UUID
        let date: Date
        let type: String // "text" or "image"
        let text: String?
        let imageFilename: String?
    }
    
    func loadFromDisk() -> [ClipboardItem] {
        guard let url = dataFileURL(), let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        guard let records = try? decoder.decode([PersistRecord].self, from: data) else { return [] }
        
        var loaded: [ClipboardItem] = []
        let fm = FileManager.default
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
                        loaded.append(ClipboardItem(id: rec.id, date: rec.date, content: .image(image)))
                    }
                }
            default:
                continue
            }
        }
        return loaded
    }
    
    func saveToDiskAsync(items: [ClipboardItem]) {
        DispatchQueue.global(qos: .utility).async { [self] in
            self.saveToDisk(items: items)
        }
    }

    func saveToDisk(items: [ClipboardItem]) {
        guard let dataURL = dataFileURL() else { return }
        var records: [PersistRecord] = []
        let imagesDir = imagesDirectory()

        for item in items {
            switch item.content {
            case .text(let text):
                records.append(PersistRecord(id: item.id, date: item.date, type: "text", text: text, imageFilename: nil))
            case .image(let image):
                guard let imagesDir else { continue }
                let filename = item.id.uuidString + ".png"
                let fileURL = imagesDir.appendingPathComponent(filename)
                // Write PNG
                if let data = image.pngData() {
                    try? data.write(to: fileURL, options: .atomic)
                    records.append(PersistRecord(id: item.id, date: item.date, type: "image", text: nil, imageFilename: filename))
                }
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(records) {
            try? data.write(to: dataURL, options: .atomic)
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