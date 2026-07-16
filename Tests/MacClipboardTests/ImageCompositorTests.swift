import XCTest
import AppKit
@testable import MaClip

final class ImageCompositorTests: XCTestCase {

    private func makeSolidImage(_ size: NSSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    func test_composeEmptyStateReturnsPngWithBaseDims() throws {
        let base = makeSolidImage(NSSize(width: 100, height: 50), color: .red)
        let state = ImageEditState(baseImage: base)
        let data = try XCTUnwrap(ImageCompositor.compose(state))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 100)
        XCTAssertEqual(rep.pixelsHigh, 50)
    }

    func test_composeAppliesCrop() throws {
        let base = makeSolidImage(NSSize(width: 100, height: 100), color: .blue)
        var state = ImageEditState(baseImage: base)
        state.cropRect = CGRect(x: 20, y: 30, width: 40, height: 25)
        let data = try XCTUnwrap(ImageCompositor.compose(state))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 40)
        XCTAssertEqual(rep.pixelsHigh, 25)
    }

    func test_composeAppliesRotationCW() throws {
        let base = makeSolidImage(NSSize(width: 200, height: 100), color: .green)
        var state = ImageEditState(baseImage: base)
        state.rotationQuarterTurns = 1
        let data = try XCTUnwrap(ImageCompositor.compose(state))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 100)
        XCTAssertEqual(rep.pixelsHigh, 200)
    }

    func test_composeDrawsRedactLayer() throws {
        let base = makeSolidImage(NSSize(width: 100, height: 100), color: .white)
        var state = ImageEditState(baseImage: base)
        state.layers = [.redact(frame: CGRect(x: 40, y: 40, width: 20, height: 20))]
        let data = try XCTUnwrap(ImageCompositor.compose(state))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        let color = rep.colorAt(x: 50, y: 50)
        XCTAssertEqual(color?.redComponent ?? 1, 0, accuracy: 0.05)
        XCTAssertEqual(color?.greenComponent ?? 1, 0, accuracy: 0.05)
        XCTAssertEqual(color?.blueComponent ?? 1, 0, accuracy: 0.05)
        XCTAssertEqual(color?.alphaComponent ?? 0, 1, accuracy: 0.05)
    }
}
