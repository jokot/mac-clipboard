import Cocoa
import Combine
import UniformTypeIdentifiers

final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var isSettingPasteboard = false
    private var maxItems: Int { AppSettings.shared.maxItems }

    init() {
        loadFromDisk()
        startMonitoring()
        observeChangesForAutosave()
    }

    deinit {
        timer?.invalidate()
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        if isSettingPasteboard {
            // Skip the next change triggered by our own write
            isSettingPasteboard = false
            lastChangeCount = currentChangeCount
            return
        }

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if let item = readCurrentPasteboardItem(from: pasteboard) {
            append(item)
        }
    }

    private func readCurrentPasteboardItem(from pasteboard: NSPasteboard) -> ClipboardItem? {
        // Prefer images over text when both are present
        if let image = readImage(from: pasteboard) {
            return ClipboardItem(date: Date(), content: .image(image))
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return ClipboardItem(date: Date(), content: .text(string))
        }

        return nil
    }

    private func readImage(from pasteboard: NSPasteboard) -> NSImage? {
        if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) {
            return image
        }
        if let data = pasteboard.data(forType: .tiff), let image = NSImage(data: data) {
            return image
        }
        if let data = pasteboard.data(forType: .pdf), let image = NSImage(data: data) {
            return image
        }
        return nil
    }

    private func append(_ item: ClipboardItem) {
        if let last = items.first, last == item {
            return
        }
        items.insert(item, at: 0)
        applyMaxItems(maxItems)
        if AppSettings.shared.autoCleanEnabled {
            autoClean()
        }
        saveToDiskAsync()
    }

    func allItems() -> [ClipboardItem] {
        return items
    }

    func setPasteboard(to item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.content {
        case .text(let text):
            isSettingPasteboard = true
            pasteboard.setString(text, forType: .string)
        case .image(let image):
            guard let tiffData = image.tiffRepresentation else { return }
            isSettingPasteboard = true
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }

    func promote(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let moved = items.remove(at: index)
        items.insert(moved, at: 0)
        saveToDiskAsync()
    }

    func remove(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        saveToDiskAsync()
    }

    func applyMaxItems(_ limit: Int) {
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        saveToDiskAsync()
    }

    private func autoClean() {
        // Simple policy: remove items older than 7 days
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        items.removeAll { $0.date < sevenDaysAgo }
    }

    // Manually clear all stored history items
    func clearHistory() {
        items.removeAll()
        saveToDiskAsync()
    }
}

// MARK: - Persistence
private extension ClipboardStore {
    struct PersistRecord: Codable {
        let id: UUID
        let date: Date
        let type: String // "text" or "image"
        let text: String?
        let imageFilename: String?
    }

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

    func loadFromDisk() {
        guard let url = dataFileURL(), let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        if let records = try? decoder.decode([PersistRecord].self, from: data) {
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
            self.items = loaded
        }
    }

    func saveToDiskAsync() {
        let snapshot = self.items
        DispatchQueue.global(qos: .utility).async { [self] in
            self.saveToDisk(items: snapshot)
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

    func observeChangesForAutosave() {
        // When app is terminating, save
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.saveToDisk(items: self.items)
        }
    }
}
