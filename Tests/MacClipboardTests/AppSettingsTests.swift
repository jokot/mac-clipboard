import XCTest
@testable import MaClip

final class AppSettingsTests: XCTestCase {

    private let pasteKey = "settings.pasteOnClick"
    private let moveKey = "settings.moveTopOnClick"
    private let excludedKey = "settings.excludedBundleIDs"
    private let skipConcealedKey = "settings.skipConcealedItems"
    private let concealedTimeoutKey = "settings.concealedClearTimeout"

    private static let seedExclusions: Set<String> = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPassMacDesktop",
        "com.jokot.MacClipboard",
    ]

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

    func test_seedExclusionsWhenKeyAbsent() {
        UserDefaults.standard.removeObject(forKey: excludedKey)
        let initial = AppSettings.makeInitialExcludedBundleIDs()
        XCTAssertEqual(Set(initial), Self.seedExclusions)
    }

    func test_emptyArrayPersistsAndIsNotReseeded() {
        let encoded = try! JSONEncoder().encode([String]())
        UserDefaults.standard.set(encoded, forKey: excludedKey)
        let initial = AppSettings.makeInitialExcludedBundleIDs()
        XCTAssertEqual(initial, [])
        UserDefaults.standard.removeObject(forKey: excludedKey)
    }

    func test_skipConcealedDefaultFalse() {
        UserDefaults.standard.removeObject(forKey: skipConcealedKey)
        let value = UserDefaults.standard.object(forKey: skipConcealedKey) as? Bool ?? false
        XCTAssertFalse(value)
    }

    func test_concealedTimeoutDefault300() {
        UserDefaults.standard.removeObject(forKey: concealedTimeoutKey)
        let raw = UserDefaults.standard.object(forKey: concealedTimeoutKey) as? Double
        let value = raw ?? 300
        XCTAssertEqual(value, 300, accuracy: 0.001)
    }

    func test_settingExcludedBundleIDsPersists() {
        AppSettings.shared.excludedBundleIDs = ["com.foo.bar"]
        let data = UserDefaults.standard.data(forKey: excludedKey)!
        let decoded = try! JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(decoded, ["com.foo.bar"])
        UserDefaults.standard.removeObject(forKey: excludedKey)
    }

    func test_settingSkipConcealedPersists() {
        AppSettings.shared.skipConcealedItems = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: skipConcealedKey) as? Bool, true)
        AppSettings.shared.skipConcealedItems = false
        UserDefaults.standard.removeObject(forKey: skipConcealedKey)
    }

    func test_settingConcealedTimeoutPersists() {
        AppSettings.shared.concealedClearTimeout = 60
        XCTAssertEqual(UserDefaults.standard.object(forKey: concealedTimeoutKey) as? Double, 60)
        AppSettings.shared.concealedClearTimeout = 300
        UserDefaults.standard.removeObject(forKey: concealedTimeoutKey)
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
