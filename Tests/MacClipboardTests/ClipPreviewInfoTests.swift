import XCTest
import AppKit
@testable import MaClip

final class ClipPreviewInfoTests: XCTestCase {
    private func item(_ content: ClipboardItemContent) -> ClipboardItem {
        ClipboardItem(date: Date(), content: content)
    }

    func test_textDetailCountsWordsAndLines() {
        let text = "Release checklist\n\nInstall the DMG.\nOpen MaClip."
        XCTAssertEqual(ClipPreviewInfo.detail(for: item(.text(text))), "7 words \u{00B7} 4 lines")
    }

    func test_oneWordAndOneLine() {
        XCTAssertEqual(ClipPreviewInfo.detail(for: item(.text("hello"))), "1 word \u{00B7} 1 line")
    }

    func test_linkDetailIsTheHost() {
        XCTAssertEqual(ClipPreviewInfo.detail(for: item(.url(URL(string: "https://github.com/jokot")!))), "github.com")
    }

    func test_fileDetailCountsFiles() {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        XCTAssertEqual(ClipPreviewInfo.detail(for: item(.file(urls))), "2 files")
        XCTAssertEqual(ClipPreviewInfo.detail(for: item(.file([urls[0]]))), "1 file")
    }

    func test_imageDetailIsThePixelSize() {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 32)!
        let image = NSImage(size: NSSize(width: 20, height: 15))
        image.addRepresentation(rep)
        XCTAssertEqual(ClipPreviewInfo.detail(for: image), "40 \u{00D7} 30 px")
    }

    // MARK: - Edit in the preview

    private func saved(_ outcome: ClipEdit.Outcome, file: StaticString = #filePath, line: UInt = #line) -> ClipboardItemContent? {
        guard case .save(let content) = outcome else {
            XCTFail("expected save, got \(outcome)", file: file, line: line)
            return nil
        }
        return content
    }

    private func problem(_ outcome: ClipEdit.Outcome) -> String? {
        guard case .invalid(let message) = outcome else { return nil }
        return message
    }

    func test_editorTextOfEachKind() {
        XCTAssertEqual(ClipEdit.text(for: .text("Meeting at 2")), "Meeting at 2")
        XCTAssertEqual(ClipEdit.text(for: .url(URL(string: "https://github.com/jokot")!)), "https://github.com/jokot")
        let files = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        XCTAssertEqual(ClipEdit.text(for: .file(files)), "/tmp/a.txt\n/tmp/b.txt")
    }

    func test_editedTextIsSavedAsTyped() {
        guard case .text(let text)? = saved(ClipEdit.outcome(of: "  two\nlines \n", editing: .text("old"))) else {
            return XCTFail("expected a text clip")
        }
        XCTAssertEqual(text, "  two\nlines \n")
    }

    func test_editedLinkIsTrimmed() {
        guard case .url(let url)? = saved(ClipEdit.outcome(of: " https://maclip.jokot.dev/ \n",
                                                           editing: .url(URL(string: "https://a.dev")!))) else {
            return XCTFail("expected a link clip")
        }
        XCTAssertEqual(url.absoluteString, "https://maclip.jokot.dev/")
    }

    func test_linkWithoutSchemeOrHostIsInvalid() {
        let old = ClipboardItemContent.url(URL(string: "https://a.dev")!)
        XCTAssertEqual(problem(ClipEdit.outcome(of: "not a link", editing: old)), "Not a valid URL")
        XCTAssertEqual(problem(ClipEdit.outcome(of: "https://", editing: old)), "Not a valid URL")
    }

    func test_editedFilesSkipEmptyLines() {
        let old = ClipboardItemContent.file([URL(fileURLWithPath: "/tmp/a.txt")])
        guard case .file(let urls)? = saved(ClipEdit.outcome(of: "/tmp/x.txt\n\n  /tmp/y.txt  \n", editing: old)) else {
            return XCTFail("expected a file clip")
        }
        XCTAssertEqual(urls.map(\.path), ["/tmp/x.txt", "/tmp/y.txt"])
    }

    func test_filesWithoutAPathAreInvalid() {
        let old = ClipboardItemContent.file([URL(fileURLWithPath: "/tmp/a.txt")])
        XCTAssertEqual(problem(ClipEdit.outcome(of: " \n\n", editing: old)), "Need at least one path")
    }
}
