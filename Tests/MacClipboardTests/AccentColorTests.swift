import XCTest
@testable import MaClip

final class AccentColorTests: XCTestCase {
    // MARK: - The saved choice

    func test_presetsAreSavedByName() {
        XCTAssertEqual(AccentChoice.preset(.orange).stored, "orange")
        XCTAssertEqual(AccentChoice(stored: "orange"), .preset(.orange))
        XCTAssertEqual(AccentChoice(stored: "Teal"), .preset(.teal), "names are not case sensitive")
    }

    func test_customColorsAreSavedAsHex() {
        XCTAssertEqual(AccentChoice.custom("#2BB673").stored, "#2BB673")
        XCTAssertEqual(AccentChoice(stored: "#2bb673"), .custom("#2BB673"))
    }

    func test_aBadSavedValueFallsBackToIndigo() {
        XCTAssertEqual(AccentChoice(stored: "plaid"), .preset(.indigo))
        XCTAssertEqual(AccentChoice(stored: "#12"), .preset(.indigo))
        XCTAssertEqual(AccentChoice(stored: ""), .preset(.indigo))
        XCTAssertEqual(AccentChoice.default, .preset(.indigo))
    }

    func test_theTenPresetsInOrder() {
        XCTAssertEqual(AccentPreset.allCases.map(\.title),
                       ["Indigo", "Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Teal", "Graphite"])
        XCTAssertEqual(AccentPreset.indigo.hex, "#5E5CE6")
        XCTAssertEqual(AccentPreset.graphite.hex, "#98989D")
    }

    func test_captionNamesTheChoice() {
        XCTAssertEqual(AccentChoice.preset(.indigo).caption, "Indigo (default)")
        XCTAssertEqual(AccentChoice.preset(.green).caption, "Green")
        XCTAssertEqual(AccentChoice.custom("#2BB673").caption, "Custom \u{00B7} #2BB673")
    }

    // MARK: - Hex

    func test_hexParsingAcceptsSixDigitsWithOrWithoutTheHash() {
        XCTAssertEqual(AccentColor.normalizedHex(" 2bb673 "), "#2BB673")
        XCTAssertEqual(AccentColor.normalizedHex("#2BB673"), "#2BB673")
        XCTAssertNil(AccentColor.normalizedHex("#2BB67"))
        XCTAssertNil(AccentColor.normalizedHex("#GGGGGG"))
    }

    // MARK: - Readable text

    func test_buttonTextIsWhiteOnDarkColorsAndDarkOnLightColors() {
        for preset: AccentPreset in [.indigo, .blue, .purple, .pink, .red] {
            XCTAssertTrue(AccentColor.usesWhiteText(on: preset.hex), preset.title)
        }
        for preset: AccentPreset in [.orange, .yellow, .green, .teal, .graphite] {
            XCTAssertFalse(AccentColor.usesWhiteText(on: preset.hex), preset.title)
        }
        XCTAssertFalse(AccentColor.usesWhiteText(on: "#F8E1F4"), "a custom pastel gets dark text")
    }

    func test_textTintReaches4_5To1OnBothBackgrounds() {
        let dark = "#1C1C1E", light = "#FFFFFF"
        for hex in AccentPreset.allCases.map(\.hex) + ["#FFFF00", "#101010"] {
            let onDark = AccentColor.textTint(hex, background: dark, isDark: true)
            let onLight = AccentColor.textTint(hex, background: light, isDark: false)
            XCTAssertGreaterThanOrEqual(AccentColor.contrast(onDark, dark), 4.5, "\(hex) on dark")
            XCTAssertGreaterThanOrEqual(AccentColor.contrast(onLight, light), 4.5, "\(hex) on light")
        }
    }

    func test_aReadableColorKeepsItsOwnTint() {
        // Indigo on white has 5:1 contrast, so it needs no change. Blue on white has 3.7:1, so it gets darker.
        XCTAssertEqual(AccentColor.textTint("#5E5CE6", background: "#FFFFFF", isDark: false), "#5E5CE6")
        XCTAssertNotEqual(AccentColor.textTint("#0A84FF", background: "#FFFFFF", isDark: false), "#0A84FF")
    }

    // MARK: - HSV for the picker

    func test_hsvRoundTrip() {
        for hex in ["#2BB673", "#5E5CE6", "#FF9F0A", "#000000", "#FFFFFF"] {
            let hsv = AccentColor.hsv(hex)
            XCTAssertEqual(AccentColor.hex(hue: hsv.hue, saturation: hsv.saturation, brightness: hsv.brightness), hex)
        }
        let green = AccentColor.hsv("#2BB673")
        // r 43, g 182, b 115: hue = ((115 - 43) / 139 + 2) × 60 = 151°.
        XCTAssertEqual(green.hue, 151, accuracy: 1)
        XCTAssertEqual(green.saturation, 0.76, accuracy: 0.01)
        XCTAssertEqual(green.brightness, 0.71, accuracy: 0.01)
    }

    func test_recentCustomColorsKeepTheNewestFour() {
        XCTAssertEqual(AccentColor.addRecent("#111111", to: ["#222222", "#333333"]), ["#111111", "#222222", "#333333"])
        XCTAssertEqual(AccentColor.addRecent("#333333", to: ["#111111", "#222222", "#333333"]),
                       ["#333333", "#111111", "#222222"], "a color moves to the front, once")
        XCTAssertEqual(AccentColor.addRecent("#555555", to: ["#111111", "#222222", "#333333", "#444444"]),
                       ["#555555", "#111111", "#222222", "#333333"])
    }

    // MARK: - Keyboard order

    func test_arrowKeysStepThroughThePresetsAndCustom() {
        XCTAssertEqual(AccentChoice.preset(.indigo).stepped(by: 1, lastCustom: "#2BB673"), .preset(.blue))
        XCTAssertEqual(AccentChoice.preset(.graphite).stepped(by: 1, lastCustom: "#2BB673"), .custom("#2BB673"))
        XCTAssertEqual(AccentChoice.custom("#2BB673").stepped(by: 1, lastCustom: "#2BB673"), .custom("#2BB673"),
                       "Custom is the last choice")
        XCTAssertEqual(AccentChoice.custom("#2BB673").stepped(by: -1, lastCustom: "#2BB673"), .preset(.graphite))
        XCTAssertEqual(AccentChoice.preset(.indigo).stepped(by: -1, lastCustom: "#2BB673"), .preset(.indigo))
    }
}
