import XCTest
import AppKit
@testable import MaClip

@MainActor
final class ImageEditorViewModelTests: XCTestCase {

    private func makeBase() -> NSImage {
        let img = NSImage(size: NSSize(width: 10, height: 10))
        img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 10, height: 10).fill(); img.unlockFocus()
        return img
    }

    func test_mutatePushesUndoState() {
        let vm = ImageEditorViewModel(base: makeBase())
        vm.mutate { $0.layers.append(.redact(frame: CGRect(x: 1, y: 1, width: 2, height: 2))) }
        XCTAssertEqual(vm.state.layers.count, 1)
        XCTAssertTrue(vm.canUndo)
    }

    func test_undoRestoresPreviousState() {
        let vm = ImageEditorViewModel(base: makeBase())
        vm.mutate { $0.layers.append(.redact(frame: CGRect(x: 1, y: 1, width: 2, height: 2))) }
        vm.undo()
        XCTAssertEqual(vm.state.layers.count, 0)
        XCTAssertTrue(vm.canRedo)
    }

    func test_redoRestoresForwardState() {
        let vm = ImageEditorViewModel(base: makeBase())
        vm.mutate { $0.layers.append(.redact(frame: CGRect(x: 1, y: 1, width: 2, height: 2))) }
        vm.undo()
        vm.redo()
        XCTAssertEqual(vm.state.layers.count, 1)
    }

    func test_mutateClearsRedoStack() {
        let vm = ImageEditorViewModel(base: makeBase())
        vm.mutate { $0.layers.append(.redact(frame: CGRect(x: 1, y: 1, width: 2, height: 2))) }
        vm.undo()
        XCTAssertTrue(vm.canRedo)
        vm.mutate { $0.rotationQuarterTurns = 1 }
        XCTAssertFalse(vm.canRedo)
    }

    func test_undoCapAt20() {
        let vm = ImageEditorViewModel(base: makeBase())
        for i in 0..<25 {
            vm.mutate { $0.layers.append(.redact(frame: CGRect(x: CGFloat(i), y: 0, width: 1, height: 1))) }
        }
        var undos = 0
        while vm.canUndo { vm.undo(); undos += 1 }
        XCTAssertEqual(undos, 20)
    }
}
