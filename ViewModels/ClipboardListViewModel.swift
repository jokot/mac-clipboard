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
    private var concealedTimer: Timer?

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

        // Drop already-expired concealed items before they're ever rendered.
        runConcealedExpirySweep(now: Date())

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

        // Sweep concealed items every 30 s.
        self.concealedTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runConcealedExpirySweep(now: Date())
            }
        }

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
        concealedTimer?.invalidate()
    }

    // Intents
    func clearHistory() {
        ContentTagDetector.clearCache()
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

    @discardableResult
    func purgeItems(matchingBundleID bundleID: String) -> Int {
        let before = items.count
        items.removeAll { $0.sourceBundleID == bundleID }
        let removed = before - items.count
        if removed > 0 {
            repository.saveToDiskAsync(items: items)
        }
        return removed
    }

    func runConcealedExpirySweep(now: Date) {
        let before = items.count
        items.removeAll { item in
            item.isConcealed && (item.concealedExpiresAt.map { $0 <= now } ?? false)
        }
        if items.count != before {
            repository.saveToDiskAsync(items: items)
        }
    }

    func promote(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let moved = items.remove(at: idx)
        items.insert(moved, at: 0)
        repository.saveToDiskAsync(items: items)
    }

    func setPasteboard(to item: ClipboardItem) {
        // Always reset the monitor's change-count baseline so the writes below
        // (or any partial write before an early return) do not bounce back as
        // new clipboard items.
        defer { monitor.ignoreCurrentChangeCount() }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let imgContent):
            var image: NSImage?
            switch imgContent.source {
            case .memory(let img):
                image = img
            case .file(let url):
                if let data = repository.readImageData(at: url) {
                    image = NSImage(data: data)
                }
            }
            guard let validImage = image,
                  let tiffData = validImage.tiffRepresentation else { return }
            pasteboard.setData(tiffData, forType: .tiff)
        case .url(let url):
            // Write both URL object and plain string for broad compatibility
            _ = pasteboard.writeObjects([url as NSURL])
            pasteboard.setString(url.absoluteString, forType: .string)
        case .file(let urls):
            let nsURLs = urls.map { $0 as NSURL }
            pasteboard.declareTypes([.fileURL], owner: nil)
            pasteboard.writeObjects(nsURLs)
        }
    }

    /// Decrypts image bytes stored at `url` (an `Images/*.enc` ciphertext file).
    /// Returns the plaintext PNG `Data` suitable for `NSImage(data:)`, or `nil` on failure.
    func imageData(at url: URL) -> Data? {
        repository.readImageData(at: url)
    }

    func applyMaxItems(_ limit: Int) {
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        // Remove the save here - let caller handle saving
    }

    // Derived data
    var filteredItems: [ClipboardItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        var sourceFilters: [String] = []
        var textFilters: [String] = []
        var tagFilters: [ContentTag] = []
        var hasUnknownTag = false

        for token in trimmed.split(separator: " ", omittingEmptySubsequences: true) {
            let s = String(token)
            let lower = s.lowercased()
            if lower.hasPrefix("from:") {
                let value = String(s.dropFirst(5))
                if !value.isEmpty { sourceFilters.append(value) }
            } else if lower.hasPrefix("tag:") {
                let value = String(s.dropFirst(4)).lowercased()
                if let tag = ContentTag(rawValue: value) {
                    tagFilters.append(tag)
                } else {
                    hasUnknownTag = true
                }
            } else {
                textFilters.append(lower)
            }
        }

        if hasUnknownTag { return [] }

        return items.filter { item in
            if !sourceFilters.isEmpty {
                let bundleID = item.sourceBundleID
                let displayName = bundleID.flatMap { AppMetadata.shared.displayName(for: $0) }
                let matchesSource = sourceFilters.contains { token in
                    if token.contains(".") {
                        return bundleID == token
                    } else {
                        return displayName?.localizedCaseInsensitiveContains(token) ?? false
                    }
                }
                if !matchesSource { return false }
            }

            if !tagFilters.isEmpty {
                let tags = ContentTagDetector.tags(for: item)
                for required in tagFilters where !tags.contains(required) {
                    return false
                }
            }

            if !textFilters.isEmpty {
                let haystack: String
                switch item.content {
                case .text(let t): haystack = t.lowercased()
                case .url(let u):  haystack = u.absoluteString.lowercased()
                case .image:       haystack = ""
                case .file:        haystack = "" // Task 4 replaces with joined paths
                }
                for token in textFilters where !haystack.contains(token) {
                    return false
                }
            }

            return true
        }
    }

    // Private
    private func append(_ item: ClipboardItem) {
        // Promote-if-exists: if the same content already lives in history, move it to top.
        if let existingIdx = items.firstIndex(where: { $0 == item }) {
            if existingIdx == 0 { return }   // already on top
            let existing = items.remove(at: existingIdx)
            items.insert(existing, at: 0)
            repository.saveToDiskAsync(items: items)
            return
        }

        var itemToInsert = item
        
        // Optimize image storage:
        // If we receive an image in memory, save it to disk immediately and use the file reference.
        // This keeps the items array lightweight.
        if case .image(let imgContent) = item.content,
           case .memory(let image) = imgContent.source {
            if let savedURL = repository.saveImage(image) {
                let newContent = ImageContent(source: .file(savedURL), cachedText: imgContent.cachedText, cachedId: imgContent.cachedId, cachedBarcode: imgContent.cachedBarcode)
                itemToInsert = ClipboardItem(
                    id: item.id,
                    date: item.date,
                    content: .image(newContent),
                    sourceBundleID: item.sourceBundleID,
                    isConcealed: item.isConcealed,
                    concealedExpiresAt: item.concealedExpiresAt,
                    isOCRResult: item.isOCRResult
                )
            }
        }
        
        items.insert(itemToInsert, at: 0)
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
            let existing = items[idx]
            items[idx] = ClipboardItem(
                id: existing.id,
                date: existing.date,
                content: .image(newContent),
                sourceBundleID: existing.sourceBundleID,
                isConcealed: existing.isConcealed,
                concealedExpiresAt: existing.concealedExpiresAt,
                isOCRResult: existing.isOCRResult
            )
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
            case .file:
                return false
            }
        }
    }

    // Promote existing result or insert a new one; returns the item put on top
    func promoteOrInsertResult(text: String) -> ClipboardItem {
        return promoteOrInsertResult(text: text, sourceBundleID: nil, isOCRResult: false)
    }

    func promoteOrInsertResult(text: String,
                               sourceBundleID: String?,
                               isOCRResult: Bool) -> ClipboardItem {
        if let url = URLUtils.linkURL(from: text) {
            if let existing = items.first(where: { if case .url(let u) = $0.content { return u == url } else { return false } }) {
                promote(existing)
                return existing
            } else {
                let newItem = ClipboardItem(
                    date: Date(),
                    content: .url(url),
                    sourceBundleID: sourceBundleID,
                    isOCRResult: isOCRResult
                )
                insertNewItemAtTop(newItem)
                return newItem
            }
        } else {
            if let existing = items.first(where: { if case .text(let t) = $0.content { return t == text } else { return false } }) {
                promote(existing)
                return existing
            } else {
                let newItem = ClipboardItem(
                    date: Date(),
                    content: .text(text),
                    sourceBundleID: sourceBundleID,
                    isOCRResult: isOCRResult
                )
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