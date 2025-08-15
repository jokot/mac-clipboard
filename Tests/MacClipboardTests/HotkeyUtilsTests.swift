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
}