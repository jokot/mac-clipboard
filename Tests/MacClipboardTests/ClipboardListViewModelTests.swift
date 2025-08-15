import XCTest
@testable import MaClip
import Combine
import AppKit

final class ClipboardListViewModelTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    func testAppendInsertsAtTopAndTrimsByMaxItems() async {
        // Given
        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)
        AppSettings.shared.maxItems = 2
        AppSettings.shared.autoCleanEnabled = false

        let item1 = ClipboardItem(date: Date(), content: .text("A"))
        let item2 = ClipboardItem(date: Date(), content: .text("B"))
        let item3 = ClipboardItem(date: Date(), content: .text("C"))

        // When
        monitor.emit(item1)
        monitor.emit(item2)
        monitor.emit(item3)

        // Then
        await MainActor.run {
            XCTAssertEqual(vm.items.count, 2)
            XCTAssertEqual(vm.items[0], item3)
            XCTAssertEqual(vm.items[1], item2)
        }
    }

    @MainActor
    func testRemoveDeletesAndPersists() async {
        // Configure settings BEFORE init to avoid trimming/cleaning side effects
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false
        
        // Seed repository state BEFORE init so VM loads them
        let item1 = ClipboardItem(date: Date(), content: .text("A"))
        let item2 = ClipboardItem(date: Date(), content: .text("B"))
        let repo = MockRepo()
        repo.savedItems = [item1, item2]
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)
        
        // Verify initial state
        await MainActor.run {
            XCTAssertEqual(vm.items.count, 2)
            XCTAssertEqual(vm.items[0], item1)
            XCTAssertEqual(vm.items[1], item2)
        }
        
        // Remove item1
        vm.remove(item1)
        
        // Assert removal and persistence call
        await MainActor.run {
            XCTAssertEqual(vm.items.count, 1)
            XCTAssertEqual(vm.items[0], item2)
        }
        XCTAssertEqual(repo.saveAsyncCount, 1)
    }
}

// MARK: - Mocks
private final class MockRepo: ClipboardRepositoryProtocol {
    var savedItems: [ClipboardItem] = []
    var saveAsyncCount = 0

    func loadFromDisk() -> [ClipboardItem] { savedItems }
    func saveToDisk(items: [ClipboardItem]) { savedItems = items }
    func saveToDiskAsync(items: [ClipboardItem]) { savedItems = items; saveAsyncCount += 1 }
    func clearAllFiles() { savedItems.removeAll() }
}

private final class MockMonitor: ClipboardMonitorProtocol {
    private let subject = PassthroughSubject<ClipboardItem, Never>()
    var itemPublisher: AnyPublisher<ClipboardItem, Never> { subject.eraseToAnyPublisher() }
    func start() {}
    func stop() {}

    func emit(_ item: ClipboardItem) { subject.send(item) }
}