import Foundation
import Combine
import Cocoa

@MainActor
final class ClipboardListViewModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var searchText: String = ""

    private let repository: ClipboardRepositoryProtocol
    private let monitor: ClipboardMonitorProtocol
    private var cancellables = Set<AnyCancellable>()

    init(repository: ClipboardRepositoryProtocol = ClipboardRepository(), monitor: ClipboardMonitorProtocol = ClipboardMonitor()) {
        self.repository = repository
        self.monitor = monitor

        // Load initial once
        let loadedItems = repository.loadFromDisk()
        self.items = loadedItems
        
        // Apply current settings limits immediately after loading
        applyMaxItems(AppSettings.shared.maxItems)
        if AppSettings.shared.autoCleanEnabled { 
            autoClean() 
        }
        
        // Save the trimmed list back to disk if it was modified
        if items.count != loadedItems.count {
            repository.saveToDisk(items: items)
        }

        // Start monitoring
        monitor.itemPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.append(item)
            }
            .store(in: &cancellables)
        monitor.start()

        // Save on termination via Combine
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.repository.saveToDisk(items: self.items)
            }
            .store(in: &cancellables)
    }

    deinit {
        monitor.stop()
    }

    // Intents
    func clearHistory() {
        items.removeAll()
        repository.clearAllFiles()
        // Use synchronous save for critical operations to avoid race conditions
        repository.saveToDisk(items: items)
    }

    func remove(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: idx)
        repository.saveToDiskAsync(items: items)
    }

    func promote(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let moved = items.remove(at: idx)
        items.insert(moved, at: 0)
        repository.saveToDiskAsync(items: items)
    }

    func setPasteboard(to item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let imgContent):
            guard let tiffData = imgContent.image.tiffRepresentation else { return }
            pasteboard.setData(tiffData, forType: .tiff)
        case .url(let url):
            // Write both URL object and plain string for broad compatibility
            _ = pasteboard.writeObjects([url as NSURL])
            pasteboard.setString(url.absoluteString, forType: .string)
        }
    }

    func applyMaxItems(_ limit: Int) {
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        // Remove the save here - let caller handle saving
    }

    // Derived data
    var filteredItems: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        let loweredQuery = query.lowercased()
        return items.filter { item in
            switch item.content {
            case .text(let text):
                return text.lowercased().contains(loweredQuery)
            case .image:
                return false
            case .url(let url):
                return url.absoluteString.lowercased().contains(loweredQuery)
            }
        }
    }

    // Private
    private func append(_ item: ClipboardItem) {
        if let last = items.first, last == item {
            return
        }
        items.insert(item, at: 0)
        applyMaxItems(AppSettings.shared.maxItems)
        if AppSettings.shared.autoCleanEnabled { autoClean() }
        // Only save once after all modifications
        repository.saveToDiskAsync(items: items)
    }

    func insertNewItemAtTop(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        applyMaxItems(AppSettings.shared.maxItems)
        if AppSettings.shared.autoCleanEnabled { autoClean() }
        repository.saveToDiskAsync(items: items)
    }

    // Helper: update cached extraction values on an image item
    func updateImageItemCache(_ item: ClipboardItem, cachedText: String?, cachedId: String?, cachedBarcode: String?) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .image(let imgContent) = items[idx].content {
            var newContent = imgContent
            if let cachedText = cachedText {
                newContent.cachedText = cachedText
            }
            if let cachedId = cachedId {
                newContent.cachedId = cachedId
            }
            if let cachedBarcode = cachedBarcode {
                newContent.cachedBarcode = cachedBarcode
            }
            items[idx] = ClipboardItem(id: items[idx].id, date: items[idx].date, content: .image(newContent))
            repository.saveToDiskAsync(items: items)
        }
    }

    // Helper: find an existing item matching a result id/text (text or URL types)
    func findExistingResult(matchingId id: String, text: String) -> ClipboardItem? {
        return items.first { item in
            switch item.content {
            case .text(let t):
                return t == id || t == text
            case .url(let u):
                return u.absoluteString == id || u.absoluteString == text
            case .image:
                return false
            }
        }
    }

    // Promote existing result or insert a new one; returns the item put on top
    func promoteOrInsertResult(text: String) -> ClipboardItem {
        if let url = URLUtils.linkURL(from: text) {
            if let existing = items.first(where: { if case .url(let u) = $0.content { return u == url } else { return false } }) {
                promote(existing)
                return existing
            } else {
                let newItem = ClipboardItem(date: Date(), content: .url(url))
                insertNewItemAtTop(newItem)
                return newItem
            }
        } else {
            if let existing = items.first(where: { if case .text(let t) = $0.content { return t == text } else { return false } }) {
                promote(existing)
                return existing
            } else {
                let newItem = ClipboardItem(date: Date(), content: .text(text))
                insertNewItemAtTop(newItem)
                return newItem
            }
        }
    }

    private func autoClean() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        items.removeAll { $0.date < sevenDaysAgo }
    }
    // Helper methods for cached OCR results
    func findItemByCachedId(_ cachedId: String) -> ClipboardItem? {
        return items.first { item in
            if case .text(let text) = item.content {
                return text == cachedId
            }
            return false
        }
    }
    
    func promoteOrAddItem(text: String, cachedId: String) {
        // First check if an item with this exact text already exists
        if let existingItem = items.first(where: { item in
            if case .text(let itemText) = item.content {
                return itemText == text
            }
            return false
        }) {
            // Move existing item to top
            promote(existingItem)
        } else {
            // Create new item if not found
            let newItem = ClipboardItem(date: Date(), content: .text(text))
            insertNewItemAtTop(newItem)
        }
    }
}