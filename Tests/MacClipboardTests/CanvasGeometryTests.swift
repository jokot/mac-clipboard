import XCTest
import AppKit
@testable import MaClip

final class CanvasGeometryTests: XCTestCase {

    private func assertPoint(_ a: CGPoint, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.001, file: file, line: line)
    }

    func test_noCropNoRotationFitsAndCenters() {
        let g = CanvasGeometry(imageSize: CGSize(width: 200, height: 100), cropRect: nil,
                               quarterTurns: 0, container: CGSize(width: 400, height: 400))
        XCTAssertEqual(g.scale, 2, accuracy: 0.001)
        XCTAssertEqual(g.display, CGRect(x: 0, y: 100, width: 400, height: 200))
        assertPoint(g.toView(.zero), CGPoint(x: 0, y: 100))
        assertPoint(g.toView(CGPoint(x: 200, y: 100)), CGPoint(x: 400, y: 300))
    }

    func test_rotationCWMovesTopLeftToTopRight() {
        let g = CanvasGeometry(imageSize: CGSize(width: 200, height: 100), cropRect: nil,
                               quarterTurns: 1, container: CGSize(width: 100, height: 200))
        XCTAssertEqual(g.display, CGRect(x: 0, y: 0, width: 100, height: 200))
        assertPoint(g.toView(.zero), CGPoint(x: 100, y: 0))
        assertPoint(g.toView(CGPoint(x: 200, y: 0)), CGPoint(x: 100, y: 200))
        assertPoint(g.toView(CGPoint(x: 0, y: 100)), CGPoint(x: 0, y: 0))
    }

    func test_negativeQuarterTurnsNormalize() {
        let ccw = CanvasGeometry(imageSize: CGSize(width: 200, height: 100), cropRect: nil,
                                 quarterTurns: -1, container: CGSize(width: 100, height: 200))
        let three = CanvasGeometry(imageSize: CGSize(width: 200, height: 100), cropRect: nil,
                                   quarterTurns: 3, container: CGSize(width: 100, height: 200))
        assertPoint(ccw.toView(.zero), three.toView(.zero))
        assertPoint(ccw.toView(.zero), CGPoint(x: 0, y: 200))
    }

    func test_cropShowsOnlyCropArea() {
        let g = CanvasGeometry(imageSize: CGSize(width: 100, height: 100),
                               cropRect: CGRect(x: 20, y: 30, width: 40, height: 25),
                               quarterTurns: 0, container: CGSize(width: 40, height: 25))
        XCTAssertEqual(g.display, CGRect(x: 0, y: 0, width: 40, height: 25))
        assertPoint(g.toView(CGPoint(x: 20, y: 30)), .zero)
        assertPoint(g.toView(CGPoint(x: 60, y: 55)), CGPoint(x: 40, y: 25))
    }

    func test_toBaseInvertsToView() {
        let g = CanvasGeometry(imageSize: CGSize(width: 300, height: 200),
                               cropRect: CGRect(x: 10, y: 20, width: 150, height: 90),
                               quarterTurns: 3, container: CGSize(width: 640, height: 480))
        for p in [CGPoint(x: 10, y: 20), CGPoint(x: 77, y: 51), CGPoint(x: 160, y: 110)] {
            assertPoint(g.toBase(g.toView(p)), p)
        }
    }

    func test_zeroContainerDoesNotProduceNaN() {
        let g = CanvasGeometry(imageSize: CGSize(width: 100, height: 100), cropRect: nil,
                               quarterTurns: 0, container: .zero)
        XCTAssertFalse(g.toBase(CGPoint(x: 5, y: 5)).x.isNaN)
    }

    /// What the canvas shows must match the saved PNG, pixel for pixel at scale 1.
    func test_viewMatchesCompositorOutput() throws {
        let size = NSSize(width: 120, height: 90)
        let base = NSImage(size: size)
        base.lockFocus(); NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill(); base.unlockFocus()

        var state = ImageEditState(baseImage: base)
        state.cropRect = CGRect(x: 10, y: 10, width: 80, height: 60)
        state.rotationQuarterTurns = 1
        state.layers = [.redact(frame: CGRect(x: 20, y: 20, width: 10, height: 10))]

        let g = CanvasGeometry(imageSize: size, cropRect: state.cropRect,
                               quarterTurns: state.rotationQuarterTurns,
                               container: CGSize(width: 60, height: 80))
        XCTAssertEqual(g.scale, 1, accuracy: 0.001)

        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(ImageCompositor.compose(state))))
        let v = g.toView(CGPoint(x: 25, y: 25))
        let c = try XCTUnwrap(rep.colorAt(x: Int(v.x), y: Int(v.y))?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(c.redComponent, 0.1, "redact centre should be black at \(v)")

        let outside = g.toView(CGPoint(x: 60, y: 50))
        let w = try XCTUnwrap(rep.colorAt(x: Int(outside.x), y: Int(outside.y))?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(w.redComponent, 0.9)
    }
}
