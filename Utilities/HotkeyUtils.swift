import Foundation
import Carbon.HIToolbox

/// Utilities for working with hotkeys and key codes
enum HotkeyUtils {
    /// Maps a subset of macOS virtual key codes to readable symbols or letters
    static let letterMap: [UInt32: String] = [
        0x00:"A",0x0B:"B",0x08:"C",0x02:"D",0x0E:"E",0x03:"F",0x05:"G",0x04:"H",0x22:"I",0x26:"J",
        0x28:"K",0x25:"L",0x2E:"M",0x2D:"N",0x1F:"O",0x23:"P",0x0C:"Q",0x0F:"R",0x01:"S",0x11:"T",
        0x20:"U",0x09:"V",0x0D:"W",0x07:"X",0x10:"Y",0x06:"Z"
    ]

    /// Build a user-facing hotkey description from keyCode and carbon modifier flags
    static func description(keyCode: UInt32, modifiers: UInt32) -> String {
        var components: [String] = []
        if modifiers.containsCmd { components.append("⌘") }
        if modifiers.containsCtrl { components.append("⌃") }
        if modifiers.containsAlt { components.append("⌥") }
        if modifiers.containsShift { components.append("⇧") }
        let key = letterMap[keyCode] ?? "V"
        components.append(key)
        return components.joined()
    }
}

extension UInt32 {
    var containsCmd: Bool { (self & UInt32(cmdKey)) != 0 }
    var containsCtrl: Bool { (self & UInt32(controlKey)) != 0 }
    var containsAlt: Bool { (self & UInt32(optionKey)) != 0 }
    var containsShift: Bool { (self & UInt32(shiftKey)) != 0 }
}