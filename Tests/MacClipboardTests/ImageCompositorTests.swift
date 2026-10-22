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

    // MARK: - Coordinate space
    // CanvasView records layer + crop geometry top-left origin, y down (SwiftUI).
    // The composited PNG must land those pixels at the same visual position.

    /// Top half red, bottom half blue, as seen on screen.
    private func makeTopRedBottomBlue(_ size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height / 2).fill()
        NSColor.red.setFill()
        NSRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2).fill()
        image.unlockFocus()
        return image
    }

    /// Left half red, right half blue.
    private func makeLeftRedRightBlue(_ size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: size.width / 2, height: size.height).fill()
        NSColor.blue.setFill()
        NSRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height).fill()
        image.unlockFocus()
        return image
    }

    private func isRed(_ c: NSColor?) -> Bool {
        guard let c = c?.usingColorSpace(.deviceRGB) else { return false }
        return c.redComponent > 0.8 && c.blueComponent < 0.2
    }

    private func isBlue(_ c: NSColor?) -> Bool {
        guard let c = c?.usingColorSpace(.deviceRGB) else { return false }
        return c.blueComponent > 0.8 && c.redComponent < 0.2
    }

    private func isBlack(_ c: NSColor?) -> Bool {
        guard let c = c?.usingColorSpace(.deviceRGB) else { return false }
        return c.redComponent < 0.1 && c.greenComponent < 0.1 && c.blueComponent < 0.1
            && c.alphaComponent > 0.9
    }

    func test_composeEmptyStateKeepsOrientation() throws {
        let base = makeTopRedBottomBlue(NSSize(width: 100, height: 100))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(ImageCompositor.compose(ImageEditState(baseImage: base)))))
        XCTAssertTrue(isRed(rep.colorAt(x: 50, y: 10)))
        XCTAssertTrue(isBlue(rep.colorAt(x: 50, y: 90)))
    }

    func test_composeLayerUsesTopLeftOrigin() throws {
        let base = makeSolidImage(NSSize(width: 100, height: 100), color: .white)
        var state = ImageEditState(baseImage: base)
        state.layers = [.redact(frame: CGRect(x: 0, y: 0, width: 20, height: 20))]
        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(ImageCompositor.compose(state))))
        XCTAssertTrue(isBlack(rep.colorAt(x: 5, y: 5)), "redact should be at top-left")
        XCTAssertFalse(isBlack(rep.colorAt(x: 5, y: 95)), "redact must not be at bottom-left")
    }

    func test_composeCropUsesTopLeftOrigin() throws {
        let base = makeTopRedBottomBlue(NSSize(width: 100, height: 100))
        var state = ImageEditState(baseImage: base)
        state.cropRect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(ImageCompositor.compose(state))))
        XCTAssertTrue(isRed(rep.colorAt(x: 50, y: 20)), "top crop should keep the red top half")
    }

    func test_composeRotationCWMovesLeftEdgeToTop() throws {
        let base = makeLeftRedRightBlue(NSSize(width: 200, height: 100))
        var state = ImageEditState(baseImage: base)
        state.rotationQuarterTurns = 1
        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(ImageCompositor.compose(state))))
        XCTAssertTrue(isRed(rep.colorAt(x: 50, y: 50)))
        XCTAssertTrue(isBlue(rep.colorAt(x: 50, y: 150)))
    }

    func test_composeLayerFollowsRotation() throws {
        let base = makeSolidImage(NSSize(width: 200, height: 100), color: .white)
        var state = ImageEditState(baseImage: base)
        state.layers = [.redact(frame: CGRect(x: 0, y: 0, width: 20, height: 20))]
        state.rotationQuarterTurns = 1
        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(ImageCompositor.compose(state))))
        // Base top-left corner lands at output top-right after a CW turn.
        XCTAssertTrue(isBlack(rep.colorAt(x: 95, y: 5)))
    }
}
