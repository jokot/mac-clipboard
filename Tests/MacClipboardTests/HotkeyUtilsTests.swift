import XCTest
@testable import MaClip
import Carbon.HIToolbox

final class HotkeyUtilsTests: XCTestCase {
    func testDescriptionIncludesModifierSymbols() {
        let cmdCtrl: UInt32 = UInt32(cmdKey | controlKey) // Carbon flags
        let desc = HotkeyUtils.description(keyCode: 0x08, modifiers: cmdCtrl) // keycode 0x08 -> C
        XCTAssertTrue(desc.contains("⌘"))
        XCTAssertTrue(desc.contains("⌃"))
        XCTAssertTrue(desc.hasSuffix("C"))
    }

    // macOS menus show modifiers in this order: Control, Option, Shift, Command.
    func testDescriptionUsesTheMacOSModifierOrder() {
        let all = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        XCTAssertEqual(HotkeyUtils.description(keyCode: 0x11, modifiers: all), "\u{2303}\u{2325}\u{21E7}\u{2318}T")
    }
}