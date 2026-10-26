import Foundation

/// The state of the clip window that the list, the preview and the key handling share.
@MainActor
final class ClipWindowState: ObservableObject {
    /// The side with focus. Keys go to this side.
    @Published var pane: ClipPane = .list
    @Published var previewOpen = false
    @Published var editing = false
}

/// One item of the ⌘K action menu. An item without `run` is a separator.
struct ClipMenuAction {
    let title: String
    var key: KeyCombo? = nil
    let run: (() -> Void)?

    static let separator = ClipMenuAction(title: "", run: nil)
}
