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
    func test_setPasteboardForFileWritesURLs() {
        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let url = URL(fileURLWithPath: "/tmp/maclip-paste-test.txt")
        try? Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let item = ClipboardItem(date: Date(), content: .file([url]))
        vm.setPasteboard(to: item)

        let pasted = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                                      options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(pasted?.first?.path, url.path)
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

    @MainActor
    func test_concealedSweepSkipsNeverTimeoutItems() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let neverItem = ClipboardItem(
            date: Date(),
            content: .text("never expires"),
            isConcealed: true,
            concealedExpiresAt: Date.distantFuture
        )
        let expiredItem = ClipboardItem(
            date: Date(),
            content: .text("already expired"),
            isConcealed: true,
            concealedExpiresAt: Date(timeIntervalSinceNow: -1)
        )
        monitor.emit(neverItem)
        monitor.emit(expiredItem)

        await MainActor.run {
            vm.runConcealedExpirySweep(now: Date())
            XCTAssertEqual(vm.items.count, 1)
            XCTAssertEqual(vm.items.first?.id, neverItem.id)
        }
    }

    @MainActor
    func test_initDropsExpiredConcealedItemsFromLoadedHistory() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        // Repo returns one fresh + one expired concealed item.
        let alive = ClipboardItem(date: Date(), content: .text("alive"),
                                  isConcealed: true,
                                  concealedExpiresAt: Date(timeIntervalSinceNow: 60))
        let expired = ClipboardItem(date: Date(), content: .text("expired"),
                                    isConcealed: true,
                                    concealedExpiresAt: Date(timeIntervalSinceNow: -10))
        let repo = MockRepo()
        repo.savedItems = [alive, expired]
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        await MainActor.run {
            XCTAssertEqual(vm.items.count, 1)
            XCTAssertEqual(vm.items.first?.id, alive.id)
        }
    }

    @MainActor
    func test_imageAppendPreservesProvenanceAndConcealedFields() async throws {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let bundleID = "com.apple.Safari"
        let expiry = Date(timeIntervalSinceNow: 60)
        let img = NSImage(size: NSSize(width: 1, height: 1))
        let imgContent = ImageContent(source: .memory(img), cachedText: nil, cachedId: nil, cachedBarcode: nil)
        let item = ClipboardItem(
            date: Date(),
            content: .image(imgContent),
            sourceBundleID: bundleID,
            isConcealed: true,
            concealedExpiresAt: expiry
        )

        monitor.emit(item)
        // Drain main queue so Combine sink delivers append.
        await MainActor.run { }

        XCTAssertEqual(vm.items.count, 1)
        let stored = vm.items[0]
        XCTAssertEqual(stored.sourceBundleID, bundleID)
        XCTAssertTrue(stored.isConcealed)
        let storedExpiry = try XCTUnwrap(stored.concealedExpiresAt)
        XCTAssertEqual(storedExpiry.timeIntervalSince1970,
                       expiry.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    @MainActor
    func test_imageAppendPreservesIsOCRResult() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let img = NSImage(size: NSSize(width: 1, height: 1))
        let imgContent = ImageContent(source: .memory(img), cachedText: nil, cachedId: nil, cachedBarcode: nil)
        let item = ClipboardItem(
            date: Date(),
            content: .image(imgContent),
            sourceBundleID: "com.apple.Preview",
            isOCRResult: true
        )

        monitor.emit(item)
        await MainActor.run {
            XCTAssertEqual(vm.items.count, 1)
            XCTAssertEqual(vm.items[0].sourceBundleID, "com.apple.Preview")
            XCTAssertTrue(vm.items[0].isOCRResult)
        }
    }

    @MainActor
    func test_promoteOrInsertResultMarksOCRAndForwardsSource() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let result = vm.promoteOrInsertResult(text: "extracted text",
                                              sourceBundleID: "com.apple.Preview",
                                              isOCRResult: true)
        XCTAssertEqual(result.sourceBundleID, "com.apple.Preview")
        XCTAssertTrue(result.isOCRResult)
        XCTAssertEqual(vm.items.first?.id, result.id)
    }

    @MainActor
    func test_filterTagJSON() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        monitor.emit(ClipboardItem(date: Date(), content: .text("{\"a\":1}")))
        monitor.emit(ClipboardItem(date: Date(), content: .text("hello world")))

        // Drain main queue so Combine sink delivers appends before filter read.
        await MainActor.run { }

        vm.searchText = "tag:json"
        await MainActor.run {
            XCTAssertEqual(vm.filteredItems.count, 1)
            if case .text(let t) = vm.filteredItems.first?.content {
                XCTAssertEqual(t, "{\"a\":1}")
            }
        }
    }

    @MainActor
    func test_filterTagCodeAndText() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let codeWithHello = """
        func hello() {
            return "hi"
        }
        """
        let plainHello = "hello world"
        monitor.emit(ClipboardItem(date: Date(), content: .text(codeWithHello)))
        monitor.emit(ClipboardItem(date: Date(), content: .text(plainHello)))

        // Drain main queue so Combine sink delivers appends before filter read.
        await MainActor.run { }

        vm.searchText = "tag:code hello"
        await MainActor.run {
            XCTAssertEqual(vm.filteredItems.count, 1)
            if case .text(let t) = vm.filteredItems.first?.content {
                XCTAssertEqual(t, codeWithHello)
            }
        }
    }

    @MainActor
    func test_filterUnknownTagReturnsEmpty() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        monitor.emit(ClipboardItem(date: Date(), content: .text("{\"a\":1}")))

        // Drain main queue so Combine sink delivers appends before filter read.
        await MainActor.run { }

        vm.searchText = "tag:nonsense"
        await MainActor.run {
            XCTAssertTrue(vm.filteredItems.isEmpty)
        }
    }

    @MainActor
    func test_filterTagFile() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        monitor.emit(ClipboardItem(date: Date(), content: .file([URL(fileURLWithPath: "/tmp/a.txt")])))
        monitor.emit(ClipboardItem(date: Date(), content: .text("hello world")))

        vm.searchText = "tag:file"
        await MainActor.run {
            XCTAssertEqual(vm.filteredItems.count, 1)
            if case .file = vm.filteredItems.first?.content {
                // OK
            } else {
                XCTFail("expected file content")
            }
        }
    }

    @MainActor
    func test_filterTagWithFromCombined() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let urlSafari = ClipboardItem(date: Date(),
                                      content: .url(URL(string: "https://example.com")!),
                                      sourceBundleID: "com.apple.Safari")
        let urlTextEdit = ClipboardItem(date: Date(),
                                        content: .url(URL(string: "https://other.com")!),
                                        sourceBundleID: "com.apple.TextEdit")
        monitor.emit(urlSafari)
        monitor.emit(urlTextEdit)

        // Drain main queue so Combine sink delivers appends before filter read.
        await MainActor.run { }

        vm.searchText = "tag:url from:com.apple.Safari"
        await MainActor.run {
            XCTAssertEqual(vm.filteredItems.count, 1)
            XCTAssertEqual(vm.filteredItems.first?.sourceBundleID, "com.apple.Safari")
        }
    }

    @MainActor
    func test_appendSameTextPromotesExistingItem() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        monitor.emit(ClipboardItem(date: Date(), content: .text("first")))
        monitor.emit(ClipboardItem(date: Date(), content: .text("second")))
        monitor.emit(ClipboardItem(date: Date(), content: .text("first")))   // re-copy of "first"

        await MainActor.run {
            XCTAssertEqual(vm.items.count, 2)   // no duplicate
            // "first" promoted to top
            if case .text(let t) = vm.items[0].content {
                XCTAssertEqual(t, "first")
            } else { XCTFail("expected text") }
            if case .text(let t) = vm.items[1].content {
                XCTAssertEqual(t, "second")
            } else { XCTFail("expected text") }
        }
    }

    @MainActor
    func test_updateImageItemCachePreservesProvenance() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let img = NSImage(size: NSSize(width: 1, height: 1))
        let imgContent = ImageContent(source: .memory(img), cachedText: nil, cachedId: nil, cachedBarcode: nil)
        let item = ClipboardItem(
            date: Date(),
            content: .image(imgContent),
            sourceBundleID: "com.apple.Preview",
            isConcealed: false,
            concealedExpiresAt: nil,
            isOCRResult: false
        )
        monitor.emit(item)

        await MainActor.run {
            let inserted = vm.items[0]
            vm.updateImageItemCache(inserted, cachedText: "hello", cachedId: nil, cachedBarcode: nil)
            let updated = vm.items[0]
            XCTAssertEqual(updated.sourceBundleID, "com.apple.Preview")
            XCTAssertFalse(updated.isOCRResult)
            if case .image(let c) = updated.content {
                XCTAssertEqual(c.cachedText, "hello")
            } else {
                XCTFail("expected image content")
            }
        }
    }

    @MainActor
    func test_replaceContentPreservesIdentity() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let original = ClipboardItem(
            date: Date(),
            content: .text("original"),
            sourceBundleID: "com.apple.TextEdit",
            isConcealed: false,
            concealedExpiresAt: nil,
            isOCRResult: false
        )
        monitor.emit(original)

        await MainActor.run {
            let inserted = vm.items[0]
            let updated = vm.replaceContent(of: inserted, with: .text("edited"))
            XCTAssertNotNil(updated)
            XCTAssertEqual(updated?.id, inserted.id)
            XCTAssertEqual(updated?.date, inserted.date)
            XCTAssertEqual(updated?.sourceBundleID, "com.apple.TextEdit")
            if case .text(let t) = updated?.content {
                XCTAssertEqual(t, "edited")
            } else { XCTFail("expected text content") }
        }
    }

    @MainActor
    func test_replaceContentSavesToRepository() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        monitor.emit(ClipboardItem(date: Date(), content: .text("a")))

        await MainActor.run {
            repo.saveAsyncCount = 0
            let inserted = vm.items[0]
            vm.replaceContent(of: inserted, with: .text("b"))
            XCTAssertGreaterThan(repo.saveAsyncCount, 0)
        }
    }

    @MainActor
    func test_insertImageAddsAtTop() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        monitor.emit(ClipboardItem(date: Date(), content: .text("existing")))

        await MainActor.run {
            let png = Data([0x89, 0x50, 0x4E, 0x47])
            let source = ClipboardItem(date: Date(), content: .text("src"), sourceBundleID: "com.apple.Preview")
            XCTAssertTrue(vm.insertImage(pngData: png, from: source))
            XCTAssertEqual(vm.items.count, 2)
            if case .image = vm.items[0].content {} else { XCTFail("first item should be image") }
            XCTAssertEqual(vm.items[0].sourceBundleID, "com.apple.Preview")
            XCTAssertGreaterThan(repo.imageSaveCount, 0)
        }
    }

    @MainActor
    func test_saveEditedImagePreservesIdentity() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let img = NSImage(size: NSSize(width: 4, height: 4))
        let original = ClipboardItem(
            date: Date(),
            content: .image(ImageContent(source: .memory(img), cachedText: nil, cachedId: nil, cachedBarcode: nil)),
            sourceBundleID: "com.apple.Preview"
        )
        monitor.emit(original)

        await MainActor.run {
            let existing = vm.items[0]
            vm.saveEditedImage(replacing: existing, pngData: Data([0x89, 0x50]))
            XCTAssertEqual(vm.items.count, 1)
            XCTAssertEqual(vm.items[0].id, existing.id)
            if case .image = vm.items[0].content {} else { XCTFail("should still be image") }
        }
    }

    // Save as new from a concealed clip makes a concealed clip with the same expiry.
    @MainActor
    func test_insertImageCopiesConcealedFlags() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false
        let vm = ClipboardListViewModel(repository: MockRepo(), monitor: MockMonitor())
        let expiry = Date(timeIntervalSinceNow: 300)
        let source = ClipboardItem(date: Date(), content: .text("secret"), sourceBundleID: "com.apple.Preview",
                                   isConcealed: true, concealedExpiresAt: expiry)

        await MainActor.run {
            XCTAssertTrue(vm.insertImage(pngData: Data([0x89, 0x50]), from: source))
            XCTAssertTrue(vm.items[0].isConcealed)
            XCTAssertEqual(vm.items[0].concealedExpiresAt, expiry)
            XCTAssertEqual(vm.items[0].sourceBundleID, "com.apple.Preview")
            XCTAssertNotEqual(vm.items[0].id, source.id)
        }
    }

    // QA #16: a failed write reports failure and changes nothing.
    @MainActor
    func test_insertImageReportsWriteFailure() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false
        let repo = MockRepo()
        repo.failImageSaves = true
        let vm = ClipboardListViewModel(repository: repo, monitor: MockMonitor())

        await MainActor.run {
            let source = ClipboardItem(date: Date(), content: .text("src"))
            XCTAssertFalse(vm.insertImage(pngData: Data([0x89, 0x50]), from: source))
            XCTAssertTrue(vm.items.isEmpty)
        }
    }

    @MainActor
    func test_saveEditedImageReportsWriteFailure() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false
        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)
        monitor.emit(ClipboardItem(
            date: Date(),
            content: .image(ImageContent(source: .memory(NSImage(size: NSSize(width: 4, height: 4))),
                                         cachedText: nil, cachedId: nil, cachedBarcode: nil))
        ))

        await MainActor.run {
            let before = vm.items[0]
            repo.failImageSaves = true
            XCTAssertFalse(vm.saveEditedImage(replacing: before, pngData: Data([0x89, 0x50])))
            XCTAssertTrue(vm.items[0].matchesContent(before), "clip must keep its old image")
            XCTAssertTrue(repo.deletedImageURLs.isEmpty)
        }
    }

    // The clip can leave the list while the editor is open (deleted, or pushed out by the limit).
    @MainActor
    func test_saveEditedImageForMissingClipFailsAndDeletesNewFile() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false
        let repo = MockRepo()
        let vm = ClipboardListViewModel(repository: repo, monitor: MockMonitor())
        let gone = ClipboardItem(date: Date(), content: .text("removed"))

        await MainActor.run {
            XCTAssertFalse(vm.saveEditedImage(replacing: gone, pngData: Data([0x89, 0x50])))
            XCTAssertEqual(repo.deletedImageURLs.count, 1, "the new file must not be left behind")
            XCTAssertTrue(vm.items.isEmpty)
        }
    }

    // QA #12: Save keeps a concealed clip concealed, with the same expiry.
    @MainActor
    func test_saveEditedImageKeepsConcealedFlags() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

        let expiry = Date(timeIntervalSinceNow: 300)
        monitor.emit(ClipboardItem(
            date: Date(),
            content: .image(ImageContent(source: .memory(NSImage(size: NSSize(width: 4, height: 4))),
                                         cachedText: nil, cachedId: nil, cachedBarcode: nil)),
            isConcealed: true,
            concealedExpiresAt: expiry
        ))

        await MainActor.run {
            vm.saveEditedImage(replacing: vm.items[0], pngData: Data([0x89, 0x50]))
            XCTAssertTrue(vm.items[0].isConcealed)
            XCTAssertEqual(vm.items[0].concealedExpiresAt, expiry)
        }
    }

    // Save in place points the clip at a new file and deletes the old one.
    @MainActor
    func test_saveEditedImageReplacesAndDeletesOldFile() async {
        AppSettings.shared.maxItems = 10
        AppSettings.shared.autoCleanEnabled = false

        let repo = MockRepo()
        let monitor = MockMonitor()
        let vm = ClipboardListViewModel(repository: repo, monitor: monitor)
        monitor.emit(ClipboardItem(
            date: Date(),
            content: .image(ImageContent(source: .memory(NSImage(size: NSSize(width: 4, height: 4))),
                                         cachedText: nil, cachedId: nil, cachedBarcode: nil))
        ))

        await MainActor.run {
            guard case .image(let before) = vm.items[0].content,
                  case .file(let oldURL) = before.source else {
                return XCTFail("capture should store the image as a file")
            }
            let edited = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
            vm.saveEditedImage(replacing: vm.items[0], pngData: edited)

            guard case .image(let after) = vm.items[0].content,
                  case .file(let newURL) = after.source else {
                return XCTFail("edited clip should be file-backed")
            }
            XCTAssertNotEqual(newURL, oldURL)
            XCTAssertEqual(repo.readImageData(at: newURL), edited)
            XCTAssertEqual(repo.deletedImageURLs, [oldURL])
            XCTAssertEqual(repo.savedItems.first?.id, vm.items[0].id, "edit must be persisted")
        }
    }
}

// MARK: - Mocks
private final class MockRepo: ClipboardRepositoryProtocol {
    var savedItems: [ClipboardItem] = []
    var saveAsyncCount = 0
    var imageSaveCount = 0
    var deletedImageURLs: [URL] = []
    var failImageSaves = false

    func loadFromDisk() -> [ClipboardItem] { savedItems }
    func saveToDisk(items: [ClipboardItem]) { savedItems = items }
    func saveToDiskAsync(items: [ClipboardItem]) { savedItems = items; saveAsyncCount += 1 }
    func clearAllFiles() { savedItems.removeAll() }
    func saveImage(_ image: NSImage) -> URL? {
        imageSaveCount += 1
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MockRepo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(UUID().uuidString + ".png")
        try? Data().write(to: fileURL)
        return fileURL
    }
    func saveImage(pngData: Data) -> URL? {
        if failImageSaves { return nil }
        imageSaveCount += 1
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MockRepo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(UUID().uuidString + ".png")
        try? pngData.write(to: fileURL)
        return fileURL
    }
    func readImageData(at encURL: URL) -> Data? {
        return try? Data(contentsOf: encURL)
    }
    func deleteImage(at encURL: URL) {
        deletedImageURLs.append(encURL)
        try? FileManager.default.removeItem(at: encURL)
    }
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