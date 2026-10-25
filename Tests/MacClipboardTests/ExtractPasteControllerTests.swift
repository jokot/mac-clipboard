import XCTest
import Combine
import AppKit
@testable import MaClip

@MainActor
final class ExtractPasteControllerTests: XCTestCase {
    private var repo: ExtractTestRepo!
    private var vm: ClipboardListViewModel!
    private var ocr: FakeOCR!
    private var toast: FakeToast!
    private var access: FakeAccess!
    private var pasteboard: FakePasteboard!
    private var pasteCount = 0

    override func setUp() async throws {
        try await super.setUp()
        AppSettings.shared.maxItems = 50
        AppSettings.shared.autoCleanEnabled = false
        repo = ExtractTestRepo()
        ocr = FakeOCR()
        toast = FakeToast()
        access = FakeAccess()
        pasteboard = FakePasteboard()
        pasteCount = 0
    }

    private func makeController(items: [ClipboardItem]) -> ExtractPasteController {
        repo.items = items
        vm = ClipboardListViewModel(repository: repo, monitor: ExtractTestMonitor())
        return ExtractPasteController(
            viewModel: vm, ocr: ocr, toast: toast, accessibility: access, pasteboard: pasteboard,
            sendPaste: { [unowned self] in self.pasteCount += 1 },
            restoreDelay: 0, progressDelay: 0.05)
    }

    private func image(_ text: String? = nil, barcode: String? = nil, age: TimeInterval = 0) -> ClipboardItem {
        ClipboardItem(date: Date(timeIntervalSinceNow: -age),
                      content: .image(ImageContent(source: .memory(NSImage(size: NSSize(width: 4, height: 4))),
                                                   cachedText: text, cachedId: nil, cachedBarcode: barcode)),
                      sourceBundleID: "com.apple.screencaptureui")
    }

    func test_noImageShowsHintAndChangesNothing() async {
        let controller = makeController(items: [ClipboardItem(date: Date(), content: .text("hi"))])

        let outcome = await controller.run(.text)

        XCTAssertEqual(outcome, .noImage)
        XCTAssertEqual(toast.messages, ["No image to read"])
        XCTAssertEqual(toast.last?.detail, "Take a screenshot first with \u{2303}\u{21E7}\u{2318}4.")
        XCTAssertEqual(toast.last?.style, .warning)
        XCTAssertTrue(pasteboard.written.isEmpty)
        XCTAssertEqual(pasteCount, 0)
    }

    func test_cachedTextIsPastedThenTheImageIsPutBack() async {
        let controller = makeController(items: [image("hello")])

        let outcome = await controller.run(.text)

        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(ocr.textCalls, 0, "a cached result needs no scan")
        XCTAssertEqual(pasteboard.written, ["hello"])
        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(pasteboard.restoreCount, 1, "the image goes back on the clipboard")
        XCTAssertTrue(toast.messages.isEmpty, "a paste needs no message")
        guard case .text(let top) = vm.items[0].content else { return XCTFail("expected the text on top") }
        XCTAssertEqual(top, "hello")
        XCTAssertTrue(vm.items[0].isOCRResult)
    }

    func test_cachedEmptyResultShowsNotFoundWithoutAScan() async {
        let controller = makeController(items: [image("")])

        let outcome = await controller.run(.text)

        XCTAssertEqual(outcome, .notFound)
        XCTAssertEqual(ocr.textCalls, 0)
        XCTAssertEqual(toast.messages, ["No text found"])
        XCTAssertEqual(toast.last?.detail, "in the last image. Nothing was pasted.")
        XCTAssertTrue(pasteboard.written.isEmpty)
        XCTAssertEqual(pasteCount, 0)
    }

    func test_scannedCodeIsCachedAndPasted() async {
        ocr.barcodeResult = .success("https://example.com/qr")
        let controller = makeController(items: [image()])

        let outcome = await controller.run(.code)

        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(ocr.barcodeCalls, 1)
        XCTAssertEqual(pasteboard.written, ["https://example.com/qr"])
        let cached = vm.items.compactMap { item -> String? in
            if case .image(let img) = item.content { return img.cachedBarcode }
            return nil
        }
        XCTAssertEqual(cached, ["https://example.com/qr"])
    }

    func test_noCodeFoundIsCachedAndShown() async {
        ocr.barcodeResult = .failure(OCRService.OCRError.noBarcodeFound)
        let controller = makeController(items: [image()])

        let outcome = await controller.run(.code)

        XCTAssertEqual(outcome, .notFound)
        XCTAssertEqual(toast.messages, ["No QR code or barcode found"])
        XCTAssertTrue(pasteboard.written.isEmpty)
        guard case .image(let img) = vm.items[0].content else { return XCTFail("expected the image") }
        XCTAssertEqual(img.cachedBarcode, "", "remember that the image has no code")
    }

    func test_withoutAccessibilityTheTextIsCopiedOnly() async {
        access.granted = false
        let controller = makeController(items: [image("hello")])

        let outcome = await controller.run(.text)

        XCTAssertEqual(outcome, .copiedOnly)
        XCTAssertEqual(pasteboard.written, ["hello"])
        XCTAssertEqual(pasteCount, 0)
        XCTAssertEqual(pasteboard.restoreCount, 0, "keep the text, so the user can press Command-V")
        XCTAssertEqual(toast.messages, ["Text copied"])
        XCTAssertEqual(toast.last?.detail, "Press \u{2318}V to paste it.")
        XCTAssertEqual(toast.last?.style, .success)
        XCTAssertEqual(access.promptCount, 1)
    }

    func test_readsTheNewestImageEvenWhenTextIsNewer() async {
        let controller = makeController(items: [
            ClipboardItem(date: Date(), content: .text("newer text")),
            image("new image", age: 10),
            image("old image", age: 20),
        ])

        _ = await controller.run(.text)

        XCTAssertEqual(pasteboard.written, ["new image"])
    }

    func test_slowScanShowsProgress() async {
        ocr.textResult = .success("slow text")
        ocr.delay = 0.3
        let controller = makeController(items: [image()])

        let outcome = await controller.run(.text)

        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(toast.messages.first, "Reading text\u{2026}")
        XCTAssertEqual(toast.first?.style, .progress)
        XCTAssertEqual(toast.hideCount, 1)
    }
}

// MARK: - Fakes

private final class FakeOCR: OCRServiceProtocol {
    var textResult: Result<String, Error> = .failure(OCRService.OCRError.noTextFound)
    var barcodeResult: Result<String, Error> = .failure(OCRService.OCRError.noBarcodeFound)
    var delay: TimeInterval = 0
    private(set) var textCalls = 0
    private(set) var barcodeCalls = 0

    func extractText(from image: NSImage) async throws -> String {
        textCalls += 1
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return try textResult.get()
    }

    func extractBarcode(from image: NSImage) async throws -> String {
        barcodeCalls += 1
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return try barcodeResult.get()
    }
}

@MainActor
private final class FakeToast: ExtractToastPresenting {
    private(set) var shown: [ExtractToast] = []
    private(set) var hideCount = 0
    var messages: [String] { shown.map(\.title) }
    var first: ExtractToast? { shown.first }
    var last: ExtractToast? { shown.last }
    func show(_ toast: ExtractToast) { shown.append(toast) }
    func hide() { hideCount += 1 }
}

@MainActor
private final class FakeAccess: AccessibilityChecking {
    var granted = true
    private(set) var promptCount = 0
    func isGrantedNow() -> Bool { granted }
    func shouldAskBeforePaste() -> Bool { !granted }
    func showPrompt() { promptCount += 1 }
}

@MainActor
private final class FakePasteboard: PasteboardSwapping {
    private(set) var written: [String] = []
    private(set) var restoreCount = 0
    func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(items: [], changeCount: 0) }
    func write(_ item: ClipboardItem) -> Int {
        switch item.content {
        case .text(let t): written.append(t)
        case .url(let u): written.append(u.absoluteString)
        default: break
        }
        return written.count
    }
    func restore(_ snapshot: PasteboardSnapshot, ifChangeCountIs changeCount: Int) { restoreCount += 1 }
}

private final class ExtractTestRepo: ClipboardRepositoryProtocol {
    var items: [ClipboardItem] = []
    func loadFromDisk() -> [ClipboardItem] { items }
    func saveToDisk(items: [ClipboardItem]) { self.items = items }
    func saveToDiskAsync(items: [ClipboardItem]) { self.items = items }
    func clearAllFiles() { items.removeAll() }
    func saveImage(_ image: NSImage) -> URL? { nil }
    func saveImage(pngData: Data) -> URL? { nil }
    func readImageData(at encURL: URL) -> Data? { nil }
    func deleteImage(at encURL: URL) {}
    var hasEncryptedHistoryToRestore: Bool { false }
    func loadEncryptedHistory() -> [ClipboardItem]? { nil }
    func switchStorage(items: [ClipboardItem], toEncrypted: Bool) -> Bool { true }
}

private final class ExtractTestMonitor: ClipboardMonitorProtocol {
    var itemPublisher: AnyPublisher<ClipboardItem, Never> { Empty().eraseToAnyPublisher() }
    func start() {}
    func stop() {}
    func ignoreCurrentChangeCount() {}
}
