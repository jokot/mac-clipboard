import Foundation

extension EditTool {
    var title: String {
        switch self {
        case .crop: return "Crop"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .oval: return "Oval"
        case .text: return "Text"
        case .pen: return "Pen"
        case .redact: return "Redact"
        }
    }

    /// The key that selects the tool in the image editor.
    var key: String {
        switch self {
        case .crop: return "c"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .oval: return "o"
        case .text: return "t"
        case .pen: return "p"
        case .redact: return "x"
        }
    }
}

enum EditorCommand: Hashable {
    case tool(EditTool)
    /// A color preset, 1 to 8.
    case color(Int)
    case thinner, thicker, rotateLeft, rotateRight, undo, redo
    case save, saveAsNew, cancel, showShortcuts
}

enum EditorKeyMap {
    static let table = ShortcutTable<EditorCommand>(
        groupOrder: ["Tools", "Style", "Image", "Finish"],
        bindings: EditTool.allCases.map { tool in
            KeyBinding(command: .tool(tool), label: tool.title, group: "Tools", keys: [KeyCombo(.character(tool.key))])
        } + [
            KeyBinding(command: nil, label: "Color 1 to 8", group: "Style", keys: [], display: ["1\u{2013}8"]),
        ] + (1...8).map { n in
            KeyBinding(command: .color(n), label: "Color \(n)", group: "Style", keys: [KeyCombo(.character("\(n)"))], listed: false)
        } + [
            KeyBinding(command: nil, label: "Thinner or thicker line", group: "Style", keys: [], display: ["[", "]"]),
            KeyBinding(command: .thinner, label: "Thinner line", group: "Style", keys: [KeyCombo(.character("["))], listed: false),
            KeyBinding(command: .thicker, label: "Thicker line", group: "Style", keys: [KeyCombo(.character("]"))], listed: false),

            KeyBinding(command: .rotateLeft, label: "Rotate left", group: "Image", keys: [.command("l")]),
            KeyBinding(command: .rotateRight, label: "Rotate right", group: "Image", keys: [.command("r")]),
            KeyBinding(command: .undo, label: "Undo", group: "Image", keys: [.command("z")]),
            KeyBinding(command: .redo, label: "Redo", group: "Image", keys: [KeyCombo(.character("z"), [.shift, .command])]),
            KeyBinding(command: nil, label: "Cancel the shape you draw", group: "Image", keys: [], display: ["esc"]),

            KeyBinding(command: .save, label: "Save", group: "Finish", keys: [KeyCombo(.returnKey), .command("s")]),
            KeyBinding(command: .saveAsNew, label: "Save as new clip", group: "Finish",
                       keys: [KeyCombo(.character("s"), [.shift, .command])]),
            KeyBinding(command: .cancel, label: "Cancel", group: "Finish", keys: [KeyCombo(.escape), .command("w")]),
            KeyBinding(command: .showShortcuts, label: "This list", group: "Finish", keys: [.command("/")], listed: false),
        ])

    static func columns() -> [[ShortcutGroup]] {
        [[table.group("Tools"), table.group("Style")].compactMap { $0 },
         [table.group("Image"), table.group("Finish")].compactMap { $0 }]
    }
}

enum SettingsCommand: Hashable {
    case tab(SettingsTab)
    /// MaClip moves the focus between the controls itself, so the keys work without
    /// Keyboard navigation in System Settings.
    case nextControl, previousControl
    /// Turn on or off a switch, press a button, or record a shortcut.
    case activate
    /// The previous or next value of a choice.
    case stepBack, stepForward
    case removeSelectedApp, close, showShortcuts
}

enum SettingsKeyMap {
    static let table = ShortcutTable<SettingsCommand>(
        groupOrder: ["Tabs", "Controls", "Window"],
        bindings: SettingsTab.allCases.enumerated().map { index, tab in
            KeyBinding(command: .tab(tab), label: tab.title, group: "Tabs", keys: [.command("\(index + 1)")])
        } + [
            KeyBinding(command: .nextControl, label: "Next control", group: "Controls",
                       keys: [KeyCombo(.tab), KeyCombo(.down)], display: ["\u{21E5}", "\u{2193}"]),
            KeyBinding(command: .previousControl, label: "Previous control", group: "Controls",
                       keys: [KeyCombo(.tab, .shift), KeyCombo(.up)], display: ["\u{21E7}\u{21E5}", "\u{2191}"]),
            KeyBinding(command: .activate, label: "Turn on or off, or press", group: "Controls",
                       keys: [KeyCombo(.space), KeyCombo(.returnKey)], display: ["space"]),
            KeyBinding(command: nil, label: "Change a choice", group: "Controls", keys: [], display: ["\u{2190}", "\u{2192}"]),
            KeyBinding(command: .stepBack, label: "Previous choice", group: "Controls", keys: [KeyCombo(.left)], listed: false),
            KeyBinding(command: .stepForward, label: "Next choice", group: "Controls", keys: [KeyCombo(.right)], listed: false),
            KeyBinding(command: .removeSelectedApp, label: "Remove the focused app", group: "Controls", keys: [KeyCombo(.delete)]),
            KeyBinding(command: .close, label: "Close Settings", group: "Window",
                       keys: [KeyCombo(.escape), .command("w"), .command(",")]),
            KeyBinding(command: .showShortcuts, label: "This list", group: "Window", keys: [.command("/")], listed: false),
        ])

    /// While the number field has the cursor, the field takes every key except ⇥, ⇧⇥, ↑, ↓ and ⌘ keys.
    /// ↑ and ↓ move the focus, because a one-line field does nothing with them.
    static func worksInTextField(_ combo: KeyCombo) -> Bool {
        switch combo.key {
        case .tab, .up, .down: return true
        default: return combo.modifiers.contains(.command)
        }
    }
}

/// The order of the focus in Settings, and the values of a choice.
enum SettingsFocus {
    /// The next (`by` 1) or previous (`by` -1) control. It wraps at both ends, like ⇥ in macOS.
    static func move(in ids: [String], from current: String?, by step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else {
            return step >= 0 || current != nil ? ids.first : ids.last
        }
        return ids[((index + step) % ids.count + ids.count) % ids.count]
    }

    /// The next or previous value. It stops at the first and the last value.
    static func step<Value: Equatable>(_ values: [Value], from current: Value, by step: Int) -> Value {
        guard let index = values.firstIndex(of: current) else { return values.first ?? current }
        return values[min(max(0, index + step), values.count - 1)]
    }

    /// The focus after the focused control goes away. An app of the list goes to the next app,
    /// else to the app before it, so the focus stays in the list. Else the next control.
    static func afterRemoving(_ id: String, from ids: [String]) -> String? {
        guard let index = ids.firstIndex(of: id) else { return ids.first }
        let kind = id.split(separator: ":").first.map(String.init) ?? id
        let sameKind = { (other: String) in other != id && other.hasPrefix(kind + ":") }
        if let next = ids[(index + 1)...].first(where: sameKind) { return next }
        if let previous = ids[..<index].last(where: sameKind) { return previous }
        if index + 1 < ids.count { return ids[index + 1] }
        return index > 0 ? ids[index - 1] : nil
    }
}

enum AboutCommand: Hashable {
    case close, showShortcuts
}

enum AboutKeyMap {
    static let table = ShortcutTable<AboutCommand>(
        groupOrder: ["Window"],
        bindings: [
            KeyBinding(command: nil, label: "Check for updates", group: "Window", keys: [], display: ["\u{21A9}"]),
            KeyBinding(command: .close, label: "Close", group: "Window",
                       keys: [KeyCombo(.escape), .command("w"), .command("i")]),
            KeyBinding(command: .showShortcuts, label: "This list", group: "Window", keys: [.command("/")], listed: false),
        ])
}

enum PromptCommand: Hashable {
    case notNow, showShortcuts
}

enum PromptKeyMap {
    static let table = ShortcutTable<PromptCommand>(
        groupOrder: ["This step"],
        bindings: [
            KeyBinding(command: nil, label: "Main button", group: "This step", keys: [], display: ["\u{21A9}"]),
            KeyBinding(command: .notNow, label: "Not Now", group: "This step", keys: [KeyCombo(.escape), .command("w")]),
            KeyBinding(command: .showShortcuts, label: "This list", group: "This step", keys: [.command("/")], listed: false),
        ])
}
