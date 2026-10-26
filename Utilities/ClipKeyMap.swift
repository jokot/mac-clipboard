import Foundation

/// The two sides of the clip window. Only one side has focus.
enum ClipPane: Equatable {
    case list, preview
}

enum ClipCommand: Hashable {
    case moveUp, moveDown, moveFirst, moveLast, pageUp, pageDown
    case focusSearch, focusPreview, focusList
    /// ⌫ in the list: delete the last letter of the search.
    case deleteSearchLetter
    /// Esc: end the edit, else close the preview, else clear the search, else close the window.
    case back
    case paste, pasteClip(Int), copyOnly, togglePreview, edit, showActions
    case delete, excludeApp, revealConcealed
    case open, revealInFinder, copyPath, extractText, extractCode
    case settings, about, clearHistory, closeWindow, quit, showShortcuts
    case scrollUp, scrollDown, scrollPageUp, scrollPageDown, scrollTop, scrollBottom
    case saveEdit, cancelEdit
    /// The shortcuts panel is open, so the window behind it does nothing with the key.
    case ignore
}

/// What the clip window does now. The same key can do different things in each state.
struct ClipKeyState: Equatable {
    var pane: ClipPane = .list
    var previewOpen = false
    var editing = false
    /// The search field has the text cursor.
    var searchFocused = false
    var searchText = ""
    /// The text field or the preview text with the cursor has a selection.
    var textSelected = false
    var shortcutsVisible = false
}

/// The keys of the clip window and of the preview beside it.
enum ClipKeyMap {
    static let list = ShortcutTable<ClipCommand>(
        groupOrder: ["Move", "Window", "Clip", "Links and files", "Images"],
        bindings: [
            KeyBinding(command: nil, label: "Select a clip", group: "Move", keys: [], display: ["\u{2191}", "\u{2193}"]),
            KeyBinding(command: .moveUp, label: "Up", group: "Move", keys: [KeyCombo(.up)], listed: false),
            KeyBinding(command: .moveDown, label: "Down", group: "Move", keys: [KeyCombo(.down)], listed: false),
            KeyBinding(command: nil, label: "First or last clip", group: "Move", keys: [],
                       display: ["\u{2318}\u{2191}", "\u{2318}\u{2193}"]),
            KeyBinding(command: .moveFirst, label: "First clip", group: "Move",
                       keys: [KeyCombo(.up, .command), KeyCombo(.home)], listed: false),
            KeyBinding(command: .moveLast, label: "Last clip", group: "Move",
                       keys: [KeyCombo(.down, .command), KeyCombo(.end)], listed: false),
            KeyBinding(command: nil, label: "Page up or down", group: "Move", keys: [], display: ["fn\u{2191}", "fn\u{2193}"]),
            KeyBinding(command: .pageUp, label: "Page up", group: "Move", keys: [KeyCombo(.pageUp)], listed: false),
            KeyBinding(command: .pageDown, label: "Page down", group: "Move", keys: [KeyCombo(.pageDown)], listed: false),
            KeyBinding(command: .focusSearch, label: "Search", group: "Move", keys: [.command("f")]),
            KeyBinding(command: nil, label: "Filter by typing", group: "Move", keys: [], display: ["a\u{2013}z"]),
            KeyBinding(command: .deleteSearchLetter, label: "Delete a search letter", group: "Move",
                       keys: [KeyCombo(.delete)], listed: false),
            KeyBinding(command: nil, label: "List or preview", group: "Move", keys: [], display: ["\u{2190}", "\u{2192}"]),
            KeyBinding(command: .focusPreview, label: "Preview side", group: "Move", keys: [KeyCombo(.right)], listed: false),
            KeyBinding(command: .back, label: "Back, then close", group: "Move", keys: [KeyCombo(.escape)]),

            KeyBinding(command: .paste, label: "Paste", group: "Clip", keys: [KeyCombo(.returnKey)]),
            KeyBinding(command: .pasteClip(1), label: "Paste clip 1 to 9", group: "Clip", keys: [.command("1")],
                       display: ["\u{2318}1\u{2013}9"]),
        ] + (2...9).map { n in
            KeyBinding(command: .pasteClip(n), label: "Paste clip \(n)", group: "Clip", keys: [.command("\(n)")], listed: false)
        } + [
            KeyBinding(command: .copyOnly, label: "Copy only", group: "Clip", keys: [.command("c")]),
            KeyBinding(command: .togglePreview, label: "Preview", group: "Clip", keys: [KeyCombo(.space)]),
            KeyBinding(command: .edit, label: "Edit", group: "Clip", keys: [.command("e")]),
            KeyBinding(command: .showActions, label: "All actions", group: "Clip", keys: [.command("k")]),
            KeyBinding(command: .delete, label: "Delete", group: "Clip",
                       keys: [KeyCombo(.delete, .command), KeyCombo(.forwardDelete, .command)],
                       display: [KeyCombo(.delete, .command).display]),
            KeyBinding(command: .excludeApp, label: "Don\u{2019}t save from app\u{2026}", group: "Clip",
                       keys: [KeyCombo(.delete, [.option, .command])]),
            KeyBinding(command: .revealConcealed, label: "Show concealed clip", group: "Clip", keys: [.command("u")]),

            KeyBinding(command: .open, label: "Open", group: "Links and files", keys: [.command("o")]),
            KeyBinding(command: .revealInFinder, label: "Reveal in Finder", group: "Links and files", keys: [.command("r")]),
            KeyBinding(command: .copyPath, label: "Copy path", group: "Links and files",
                       keys: [KeyCombo(.character("c"), [.option, .command])]),

            KeyBinding(command: .extractText, label: "Extract text", group: "Images", keys: [.command("t")]),
            KeyBinding(command: .extractCode, label: "Extract code", group: "Images", keys: [.command("b")]),

            KeyBinding(command: .settings, label: "Settings", group: "Window", keys: [.command(",")]),
            KeyBinding(command: .about, label: "About MaClip", group: "Window", keys: [.command("i")]),
            KeyBinding(command: .clearHistory, label: "Clear history\u{2026}", group: "Window",
                       keys: [KeyCombo(.delete, [.shift, .command])]),
            KeyBinding(command: .closeWindow, label: "Close window", group: "Window", keys: [.command("w")]),
            KeyBinding(command: .quit, label: "Quit MaClip", group: "Window", keys: [.command("q")]),
            KeyBinding(command: .showShortcuts, label: "This list", group: "Window", keys: [.command("/")]),
        ])

    /// Keys that work only while the preview has focus. All other keys come from `list`.
    static let preview = ShortcutTable<ClipCommand>(
        groupOrder: ["Preview"],
        bindings: [
            KeyBinding(command: nil, label: "Scroll", group: "Preview", keys: [], display: ["\u{2191}", "\u{2193}"]),
            KeyBinding(command: .scrollUp, label: "Scroll up", group: "Preview", keys: [KeyCombo(.up)], listed: false),
            KeyBinding(command: .scrollDown, label: "Scroll down", group: "Preview", keys: [KeyCombo(.down)], listed: false),
            KeyBinding(command: nil, label: "Page up or down", group: "Preview", keys: [], display: ["fn\u{2191}", "fn\u{2193}"]),
            KeyBinding(command: .scrollPageUp, label: "Page up", group: "Preview", keys: [KeyCombo(.pageUp)], listed: false),
            KeyBinding(command: .scrollPageDown, label: "Page down", group: "Preview", keys: [KeyCombo(.pageDown)], listed: false),
            KeyBinding(command: nil, label: "Top or bottom", group: "Preview", keys: [],
                       display: ["\u{2318}\u{2191}", "\u{2318}\u{2193}"]),
            KeyBinding(command: .scrollTop, label: "Top", group: "Preview",
                       keys: [KeyCombo(.up, .command), KeyCombo(.home)], listed: false),
            KeyBinding(command: .scrollBottom, label: "Bottom", group: "Preview",
                       keys: [KeyCombo(.down, .command), KeyCombo(.end)], listed: false),
            KeyBinding(command: .focusList, label: "Back to the list", group: "Preview", keys: [KeyCombo(.left)]),
            KeyBinding(command: .togglePreview, label: "Close preview", group: "Preview", keys: [KeyCombo(.space)],
                       display: ["space", "esc"]),
        ])

    /// Keys of the edit mode in the preview. Every other key goes to the text editor.
    static let editing = ShortcutTable<ClipCommand>(
        groupOrder: ["Edit"],
        bindings: [
            KeyBinding(command: .saveEdit, label: "Save", group: "Edit",
                       keys: [KeyCombo(.returnKey, .command), .command("s")]),
            KeyBinding(command: .cancelEdit, label: "Cancel", group: "Edit", keys: [KeyCombo(.escape)]),
        ])

    /// List keys that mean nothing while the preview has focus.
    private static let listOnly: Set<ClipCommand> = [.moveUp, .moveDown, .moveFirst, .moveLast, .pageUp, .pageDown, .focusPreview]

    static func command(for combo: KeyCombo, state: ClipKeyState) -> ClipCommand? {
        if state.shortcutsVisible {
            if combo == KeyCombo(.escape) || combo == .command("/") { return .showShortcuts }
            if combo == .command("q") { return .quit }
            return .ignore
        }
        if state.editing {
            if combo == .command("/") { return .showShortcuts }
            return editing.command(for: combo)
        }
        if state.previewOpen && state.pane == .preview {
            if combo == .command("c") && state.textSelected { return nil }
            if let command = preview.command(for: combo) { return command }
            guard let command = list.command(for: combo), !listOnly.contains(command) else { return nil }
            return command
        }
        if state.searchFocused {
            let hasText = !state.searchText.isEmpty
            switch combo {
            // ⌫ deletes the letter in the field itself.
            case KeyCombo(.delete):
                return nil
            // A space between two words is text. A space in an empty field opens the preview.
            case KeyCombo(.space):
                if hasText { return nil }
            case KeyCombo(.left), KeyCombo(.right),
                 KeyCombo(.delete, .command), KeyCombo(.forwardDelete, .command):
                if hasText { return nil }
            case .command("c"):
                if state.textSelected { return nil }
            default:
                break
            }
        }
        guard let command = list.command(for: combo) else { return nil }
        if command == .focusPreview && !state.previewOpen { return nil }
        if command == .deleteSearchLetter && state.searchText.isEmpty { return nil }
        return command
    }

    /// Commands that take the cursor out of the search field. The search text stays, and the
    /// list takes the keys, so Space opens the preview. A typed letter goes back to the search.
    static func leavesSearchField(_ command: ClipCommand) -> Bool {
        switch command {
        case .moveUp, .moveDown, .moveFirst, .moveLast, .pageUp, .pageDown: return true
        default: return false
        }
    }

    // MARK: - Panels

    /// The clip window panel. `globalKeys` are the keys from Settings that work in any app.
    static func listColumns(globalKeys: [ShortcutRow]) -> [[ShortcutGroup]] {
        var left = [list.group("Move"), list.group("Window")].compactMap { $0 }
        if !globalKeys.isEmpty {
            left.append(ShortcutGroup(title: "In any app", rows: globalKeys))
        }
        let right = [list.group("Clip"), list.group("Links and files"), list.group("Images")].compactMap { $0 }
        return [left, right]
    }

    static func previewColumns() -> [[ShortcutGroup]] {
        let clip = ShortcutGroup(title: "Clip", rows: list.rows(for: [.paste, .copyOnly, .edit, .delete]))
        return [[preview.group("Preview", highlight: true), clip].compactMap { $0 }]
    }

    static func editingColumns() -> [[ShortcutGroup]] {
        let text = ShortcutGroup(title: "Text", rows: [
            ShortcutRow(label: "Undo", keys: ["\u{2318}Z"]),
            ShortcutRow(label: "Redo", keys: ["\u{21E7}\u{2318}Z"]),
            ShortcutRow(label: "Select all", keys: ["\u{2318}A"]),
            ShortcutRow(label: "Move by word", keys: ["\u{2325}\u{2190}", "\u{2325}\u{2192}"]),
            ShortcutRow(label: "Start or end of line", keys: ["\u{2318}\u{2190}", "\u{2318}\u{2192}"]),
            ShortcutRow(label: "Start or end of text", keys: ["\u{2318}\u{2191}", "\u{2318}\u{2193}"]),
            ShortcutRow(label: "Delete a word", keys: ["\u{2325}\u{232B}"]),
        ])
        return [[editing.group("Edit", highlight: true), text].compactMap { $0 }]
    }
}
