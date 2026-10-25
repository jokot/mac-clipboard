import XCTest
import AppKit
@testable import MaClip

final class EditorStatusTests: XCTestCase {
    private func state() -> ImageEditState {
        ImageEditState(baseImage: NSImage(size: NSSize(width: 10, height: 10)))
    }

    func test_eachToolHasAHint() {
        for tool in EditTool.allCases {
            XCTAssertFalse(EditorStatus.hint(for: tool).isEmpty, "\(tool) has no hint")
        }
        XCTAssertEqual(EditorStatus.hint(for: .arrow), "Arrow: drag on the image. Esc cancels the shape.")
    }

    func test_editCountCountsLayersCropAndRotation() {
        var s = state()
        XCTAssertEqual(EditorStatus.editsText(for: s), "No edits")
        s.layers = [.redact(frame: .zero)]
        XCTAssertEqual(EditorStatus.editsText(for: s), "1 edit")
        s.cropRect = CGRect(x: 0, y: 0, width: 5, height: 5)
        s.rotationQuarterTurns = 1
        XCTAssertEqual(EditorStatus.editsText(for: s), "3 edits")
    }

    func test_sizeIsInPixels() {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2880, pixelsHigh: 1800, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 32)!
        let image = NSImage(size: NSSize(width: 1440, height: 900))
        image.addRepresentation(rep)
        XCTAssertEqual(EditorStatus.sizeText(for: image), "2880 \u{00D7} 1800 px")
    }
}
