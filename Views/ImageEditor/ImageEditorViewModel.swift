import Foundation
import AppKit

@MainActor
final class ImageEditorViewModel: ObservableObject {
    @Published var state: ImageEditState
    private var undoStack: [ImageEditState] = []
    private var redoStack: [ImageEditState] = []
    private let cap = 20

    init(base: NSImage) {
        self.state = ImageEditState(baseImage: base)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func mutate(_ change: (inout ImageEditState) -> Void) {
        undoStack.append(state)
        if undoStack.count > cap { undoStack.removeFirst() }
        redoStack.removeAll()
        change(&state)
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(state)
        state = prev
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
    }
}
