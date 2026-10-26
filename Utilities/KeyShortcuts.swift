import AppKit

/// One key with its modifier keys, for example ⌘⌫. MaClip compares key presses with these
/// and shows them in the shortcuts panel.
struct KeyCombo: Hashable {
    enum Key: Hashable {
        /// A letter, digit or sign, in lower case: "c", "1", "/", "[".
        case character(String)
        case up, down, left, right, pageUp, pageDown, home, end
        case returnKey, space, escape, delete, forwardDelete, tab
    }

    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    let key: Key
    let modifiers: Modifiers

    init(_ key: Key, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    static func command(_ character: String) -> KeyCombo {
        KeyCombo(.character(character), .command)
    }

    /// Nil for a key that has no character, for example a modifier key alone.
    init?(event: NSEvent) {
        var modifiers: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        let key: Key
        switch event.keyCode {
        case 126: key = .up
        case 125: key = .down
        case 123: key = .left
        case 124: key = .right
        case 116: key = .pageUp
        case 121: key = .pageDown
        case 115: key = .home
        case 119: key = .end
        case 36, 76: key = .returnKey
        case 49: key = .space
        case 53: key = .escape
        case 51: key = .delete
        case 117: key = .forwardDelete
        case 48: key = .tab
        default:
            // Shift changes the character ("S"), so compare in lower case.
            guard let characters = event.charactersIgnoringModifiers?.lowercased(),
                  !characters.isEmpty else { return nil }
            key = .character(characters)
        }
        self.init(key, modifiers)
    }

    /// The text of the key cap, in the order of Mac menus: ⌃⌥⇧⌘, then the key.
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "\u{2303}" }
        if modifiers.contains(.option) { text += "\u{2325}" }
        if modifiers.contains(.shift) { text += "\u{21E7}" }
        if modifiers.contains(.command) { text += "\u{2318}" }
        switch key {
        case .character(let c): text += c.uppercased()
        case .up: text += "\u{2191}"
        case .down: text += "\u{2193}"
        case .left: text += "\u{2190}"
        case .right: text += "\u{2192}"
        case .pageUp: text += "fn\u{2191}"
        case .pageDown: text += "fn\u{2193}"
        case .home: text += "fn\u{2190}"
        case .end: text += "fn\u{2192}"
        case .returnKey: text += "\u{21A9}"
        case .space: text += "space"
        case .escape: text += "esc"
        case .delete: text += "\u{232B}"
        case .forwardDelete: text += "\u{2326}"
        case .tab: text += "\u{21E5}"
        }
        return text
    }
}

/// One line of the shortcuts panel: what the keys do, and the key caps.
struct ShortcutRow: Hashable {
    let label: String
    let keys: [String]
}

/// A titled group of lines in the shortcuts panel.
struct ShortcutGroup: Hashable {
    let title: String
    let rows: [ShortcutRow]
    /// The group of the side or mode that has focus. The panel shows its title in the accent color.
    var highlight = false
}

/// Keys that run one command, and the line that the shortcuts panel shows for them.
struct KeyBinding<Command: Hashable> {
    /// Nil for a line that only explains keys, for example "↑ ↓ Select a clip". Other
    /// bindings, with `listed` false, then run the commands.
    let command: Command?
    let label: String
    let group: String
    let keys: [KeyCombo]
    /// The key caps to show, when they are not the keys themselves ("⌘1–9").
    var display: [String]? = nil
    var listed = true

    var shownKeys: [String] { display ?? keys.map(\.display) }
}

/// The keys of one window. The key handling and the shortcuts panel both read this table,
/// so the panel shows only keys that work.
struct ShortcutTable<Command: Hashable> {
    let groupOrder: [String]
    let bindings: [KeyBinding<Command>]

    func command(for combo: KeyCombo) -> Command? {
        bindings.first { $0.command != nil && $0.keys.contains(combo) }?.command
    }

    /// Keys that two bindings use. Must be empty.
    var conflicts: [KeyCombo] {
        var seen = Set<KeyCombo>()
        var repeated: [KeyCombo] = []
        for binding in bindings where binding.command != nil {
            for key in binding.keys where !seen.insert(key).inserted {
                repeated.append(key)
            }
        }
        return repeated
    }

    func group(_ title: String, highlight: Bool = false) -> ShortcutGroup? {
        let rows = bindings
            .filter { $0.listed && $0.group == title }
            .map { ShortcutRow(label: $0.label, keys: $0.shownKeys) }
        return rows.isEmpty ? nil : ShortcutGroup(title: title, rows: rows, highlight: highlight)
    }

    func groups() -> [ShortcutGroup] {
        groupOrder.compactMap { group($0) }
    }

    /// The panel lines of some commands, in the order given.
    func rows(for commands: [Command]) -> [ShortcutRow] {
        commands.compactMap { command in
            bindings.first { $0.command == command && $0.listed }
                .map { ShortcutRow(label: $0.label, keys: $0.shownKeys) }
        }
    }
}

/// Makes the block of a local key monitor that holds its owner weakly.
enum KeyMonitorBlock {
    /// `handle` returns nil when it used the key. The block then returns nil too, so macOS
    /// does not send the key on and play the error sound. A plain `owner?.handle(event) ?? event`
    /// returns the key in that case, because `?.` makes the nil of a used key look like a missing owner.
    static func make<Owner: AnyObject>(_ owner: Owner,
                                       _ handle: @escaping (Owner, NSEvent) -> NSEvent?) -> (NSEvent) -> NSEvent? {
        { [weak owner] event in
            guard let owner else { return event }
            return handle(owner, event)
        }
    }
}
