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

    // MARK: - Text draft (QA #11)

    func test_commitTextAppendsLayer() {
        let vm = ImageEditorViewModel(base: makeBase())
        vm.beginText(at: CGPoint(x: 2, y: 3), color: .red, fontSize: 24)
        vm.textDraft?.string = "hi 123"
        XCTAssertTrue(vm.hasPendingText)
        vm.commitText(color: .red, fontSize: 24)
        XCTAssertNil(vm.textDraft)
        XCTAssertEqual(vm.state.layers, [.text(origin: CGPoint(x: 2, y: 3), string: "hi 123", color: .red, fontSize: 24)])
        vm.undo()
        XCTAssertTrue(vm.state.layers.isEmpty)
    }

    func test_commitEmptyTextAddsNothing() {
        let vm = ImageEditorViewModel(base: makeBase())
        vm.beginText(at: .zero, color: .red, fontSize: 24)
        XCTAssertFalse(vm.hasPendingText)
        vm.commitText(color: .red, fontSize: 24)
        XCTAssertNil(vm.textDraft)
        XCTAssertFalse(vm.canUndo)
    }

    func test_beginTextCommitsPreviousDraft() {
        let vm = ImageEditorViewModel(base: makeBase())
        vm.beginText(at: .zero, color: .red, fontSize: 24)
        vm.textDraft?.string = "first"
        vm.beginText(at: CGPoint(x: 5, y: 5), color: .red, fontSize: 24)
        XCTAssertEqual(vm.state.layers.count, 1)
        XCTAssertEqual(vm.textDraft?.origin, CGPoint(x: 5, y: 5))
        XCTAssertEqual(vm.textDraft?.string, "")
    }

    func test_cancelTextDiscardsDraft() {
        let vm = ImageEditorViewModel(base: makeBase())
        vm.beginText(at: .zero, color: .red, fontSize: 24)
        vm.textDraft?.string = "gone"
        vm.cancelText()
        XCTAssertNil(vm.textDraft)
        XCTAssertTrue(vm.state.layers.isEmpty)
    }

    // QA #19: undoing a rotation keeps the layers drawn before it.
    func test_undoRotationKeepsEarlierLayer() {
        let vm = ImageEditorViewModel(base: makeBase())
        vm.mutate { $0.layers.append(.rectangle(frame: CGRect(x: 1, y: 1, width: 4, height: 4),
                                                style: StrokeStyle(color: .red, width: 2))) }
        vm.mutate { $0.rotationQuarterTurns = 1 }
        vm.undo()
        XCTAssertEqual(vm.state.rotationQuarterTurns, 0)
        XCTAssertEqual(vm.state.layers.count, 1)
    }

    // QA #20: Save stays disabled until something changes.
    func test_isDirtyTracksEveryKindOfChange() {
        let vm = ImageEditorViewModel(base: makeBase())
        XCTAssertFalse(vm.state.isDirty)

        vm.mutate { $0.layers.append(.redact(frame: CGRect(x: 1, y: 1, width: 2, height: 2))) }
        XCTAssertTrue(vm.state.isDirty)
        vm.undo()
        XCTAssertFalse(vm.state.isDirty)

        vm.mutate { $0.cropRect = CGRect(x: 0, y: 0, width: 5, height: 5) }
        XCTAssertTrue(vm.state.isDirty)
        vm.undo()

        vm.mutate { $0.rotationQuarterTurns = 1 }
        XCTAssertTrue(vm.state.isDirty)
    }
}
