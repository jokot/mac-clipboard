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
}
