import Cocoa
import Combine

final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var isSettingPasteboard = false
    private let maxItems = 100

    init() {
        startMonitoring()
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
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
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
    }
}

