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

    @MainActor
    func test_setPasteboard_callsIgnoreCurrentChangeCountOnce() {
        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let item = ClipboardItem(date: Date(), content: .text("hello"))
        vm.setPasteboard(to: item)

        XCTAssertEqual(monitor.ignoreCallCount, 1)
    }

    @MainActor
    func test_purgeItemsRemovesAllMatchingBundleID() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false
        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let safari = ClipboardItem(date: Date(), content: .text("a"), sourceBundleID: "com.apple.Safari")
        let textEdit = ClipboardItem(date: Date(), content: .text("b"), sourceBundleID: "com.apple.TextEdit")
        let safari2 = ClipboardItem(date: Date(), content: .text("c"), sourceBundleID: "com.apple.Safari")
        monitor.emit(safari)
        monitor.emit(textEdit)
        monitor.emit(safari2)

        // Drain main queue so Combine sink delivers appends before purge.
        await MainActor.run { }

        let removed = vm.purgeItems(matchingBundleID: "com.apple.Safari")

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.sourceBundleID, "com.apple.TextEdit")
    }

    @MainActor
    func test_filterFromExactBundleIDMatches() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false
        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        monitor.emit(ClipboardItem(date: Date(), content: .text("a"), sourceBundleID: "com.apple.Safari"))
        monitor.emit(ClipboardItem(date: Date(), content: .text("b"), sourceBundleID: "com.apple.TextEdit"))

        // Drain main queue so Combine sink delivers appends before filter read.
        await MainActor.run { }

        vm.searchText = "from:com.apple.Safari"
        await MainActor.run {
            XCTAssertEqual(vm.filteredItems.count, 1)
            XCTAssertEqual(vm.filteredItems.first?.sourceBundleID, "com.apple.Safari")
        }
    }

    @MainActor
    func test_filterFromBundleIDAndTextCombined() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false
        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        monitor.emit(ClipboardItem(date: Date(), content: .text("hello world"),
                                   sourceBundleID: "com.apple.Safari"))
        monitor.emit(ClipboardItem(date: Date(), content: .text("goodbye"),
                                   sourceBundleID: "com.apple.Safari"))
        monitor.emit(ClipboardItem(date: Date(), content: .text("hello world"),
                                   sourceBundleID: "com.apple.TextEdit"))

        // Drain main queue so Combine sink delivers appends before filter read.
        await MainActor.run { }

        vm.searchText = "from:com.apple.Safari hello"
        await MainActor.run {
            XCTAssertEqual(vm.filteredItems.count, 1)
            if case .text(let t) = vm.filteredItems.first?.content {
                XCTAssertEqual(t, "hello world")
            } else {
                XCTFail("Expected .text content")
            }
        }
    }

    @MainActor
    func test_concealedExpirySweepRemovesPastItems() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false
        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let alive = ClipboardItem(date: Date(), content: .text("alive"),
                                  isConcealed: true,
                                  concealedExpiresAt: Date(timeIntervalSinceNow: 60))
        let expired = ClipboardItem(date: Date(), content: .text("expired"),
                                    isConcealed: true,
                                    concealedExpiresAt: Date(timeIntervalSinceNow: -1))
        monitor.emit(alive)
        monitor.emit(expired)

        // Drain main queue so Combine sink delivers appends before sweep.
        await MainActor.run { }

        vm.runConcealedExpirySweep(now: Date())

        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.id, alive.id)
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
    func saveImage(_ image: NSImage) -> URL? { nil }
}

private final class MockMonitor: ClipboardMonitorProtocol {
    private let subject = PassthroughSubject<ClipboardItem, Never>()
    var itemPublisher: AnyPublisher<ClipboardItem, Never> { subject.eraseToAnyPublisher() }
    func start() {}
    func stop() {}

    private(set) var ignoreCallCount: Int = 0
    func ignoreCurrentChangeCount() { ignoreCallCount += 1 }

    func emit(_ item: ClipboardItem) { subject.send(item) }
}