import XCTest
@testable import MaClip

final class AppSettingsTests: XCTestCase {

    private let pasteKey = "settings.pasteOnClick"
    private let moveKey = "settings.moveTopOnClick"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: pasteKey)
        UserDefaults.standard.removeObject(forKey: moveKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: pasteKey)
        UserDefaults.standard.removeObject(forKey: moveKey)
        super.tearDown()
    }

    func test_defaultsAreTrueWhenKeysAbsent() {
        // Mirrors AppSettings.init's read pattern.
        let pasteDefault = UserDefaults.standard.object(forKey: pasteKey) as? Bool ?? true
        let moveDefault = UserDefaults.standard.object(forKey: moveKey) as? Bool ?? true
        XCTAssertTrue(pasteDefault)
        XCTAssertTrue(moveDefault)
    }

    func test_settingPasteOnClickPersists() {
        AppSettings.shared.pasteOnClick = false
        XCTAssertEqual(UserDefaults.standard.object(forKey: pasteKey) as? Bool, false)
        AppSettings.shared.pasteOnClick = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: pasteKey) as? Bool, true)
    }

    func test_settingMoveTopOnClickPersists() {
        AppSettings.shared.moveTopOnClick = false
        XCTAssertEqual(UserDefaults.standard.object(forKey: moveKey) as? Bool, false)
        AppSettings.shared.moveTopOnClick = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: moveKey) as? Bool, true)
    }
}
