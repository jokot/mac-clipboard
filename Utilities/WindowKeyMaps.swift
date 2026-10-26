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
    case removeSelectedApp, close, showShortcuts
}

enum SettingsKeyMap {
    static let table = ShortcutTable<SettingsCommand>(
        groupOrder: ["Tabs", "Controls", "Window"],
        bindings: SettingsTab.allCases.enumerated().map { index, tab in
            KeyBinding(command: .tab(tab), label: tab.title, group: "Tabs", keys: [.command("\(index + 1)")])
        } + [
            KeyBinding(command: nil, label: "Next or previous control", group: "Controls", keys: [],
                       display: ["\u{21E5}", "\u{21E7}\u{21E5}"]),
            KeyBinding(command: nil, label: "Turn on or off, or click", group: "Controls", keys: [], display: ["space"]),
            KeyBinding(command: nil, label: "Choose in a menu", group: "Controls", keys: [], display: ["\u{2191}", "\u{2193}"]),
            KeyBinding(command: .removeSelectedApp, label: "Remove the selected app", group: "Controls", keys: [KeyCombo(.delete)]),
            KeyBinding(command: .close, label: "Close Settings", group: "Window",
                       keys: [KeyCombo(.escape), .command("w"), .command(",")]),
            KeyBinding(command: .showShortcuts, label: "This list", group: "Window", keys: [.command("/")], listed: false),
        ])
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
