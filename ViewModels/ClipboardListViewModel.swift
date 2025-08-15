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
        case .image(let image):
            guard let tiffData = image.tiffRepresentation else { return }
            pasteboard.setData(tiffData, forType: .tiff)
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

    private func autoClean() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        items.removeAll { $0.date < sevenDaysAgo }
    }
}