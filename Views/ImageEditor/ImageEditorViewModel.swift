import SwiftUI
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

    // MARK: - Text draft

    struct TextDraft: Equatable {
        var origin: CGPoint
        var string: String
    }

    /// Text being typed with the text tool, not yet a layer. Lives here (not in
    /// CanvasView) so Save can commit it and the sheet can turn off Return/Esc.
    @Published var textDraft: TextDraft?

    var hasPendingText: Bool { !(textDraft?.string.isEmpty ?? true) }

    func beginText(at origin: CGPoint, color: Color, fontSize: CGFloat) {
        commitText(color: color, fontSize: fontSize)
        textDraft = TextDraft(origin: origin, string: "")
    }

    func commitText(color: Color, fontSize: CGFloat) {
        guard let draft = textDraft else { return }
        textDraft = nil
        guard !draft.string.isEmpty else { return }
        mutate { $0.layers.append(.text(origin: draft.origin, string: draft.string, color: color, fontSize: fontSize)) }
    }

    func cancelText() {
        textDraft = nil
    }
}
