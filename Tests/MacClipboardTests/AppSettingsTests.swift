import XCTest
@testable import MaClip

final class AppSettingsTests: XCTestCase {

    private let pasteKey = "settings.pasteOnClick"
    private let moveKey = "settings.moveTopOnClick"
    private let excludedKey = "settings.excludedBundleIDs"
    private let skipConcealedKey = "settings.skipConcealedItems"
    private let concealedTimeoutKey = "settings.concealedClearTimeout"
    private let autoDismissEnabledKey = "settings.autoDismissOverlay.enabled"
    private let autoDismissTimeoutKey = "settings.autoDismissOverlay.timeout"

    private static let seedExclusions: Set<String> = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPassMacDesktop",
        "com.jokot.MacClipboard",
    ]

    private static func sentinelURL() -> URL? {
        AppEnvironment.appSupportDirectory?.appendingPathComponent(".seeded")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // These tests reset settings. Never let them reach the real defaults domain.
        try XCTSkipUnless(AppEnvironment.isRunningTests, "test storage isolation is not active")
        AppEnvironment.defaults.removeObject(forKey: pasteKey)
        AppEnvironment.defaults.removeObject(forKey: moveKey)
        if let sentinel = Self.sentinelURL() {
            try? FileManager.default.removeItem(at: sentinel)
        }
    }

    override func tearDown() {
        AppEnvironment.defaults.removeObject(forKey: pasteKey)
        AppEnvironment.defaults.removeObject(forKey: moveKey)
        if let sentinel = Self.sentinelURL() {
            try? FileManager.default.removeItem(at: sentinel)
        }
        super.tearDown()
    }

    func test_seedExclusionsWhenKeyAbsent() {
        AppEnvironment.defaults.removeObject(forKey: excludedKey)
        let initial = AppSettings.makeInitialExcludedBundleIDs()
        XCTAssertEqual(Set(initial), Self.seedExclusions)
    }

    func test_sentinelAbsentTriggersSeedAndWritesSentinel() throws {
        let fm = FileManager.default
        let sentinel = try XCTUnwrap(Self.sentinelURL())
        try? fm.removeItem(at: sentinel)
        AppEnvironment.defaults.removeObject(forKey: excludedKey)

        let initial = AppSettings.makeInitialExcludedBundleIDs()
        XCTAssertEqual(Set(initial), Self.seedExclusions)
        XCTAssertTrue(fm.fileExists(atPath: sentinel.path))

        try? fm.removeItem(at: sentinel)
    }

    func test_sentinelPresentRespectsExplicitEmptyArray() throws {
        let fm = FileManager.default
        let sentinel = try XCTUnwrap(Self.sentinelURL())
        try? fm.createDirectory(at: sentinel.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try Data().write(to: sentinel)
        let emptyData = try JSONEncoder().encode([String]())
        AppEnvironment.defaults.set(emptyData, forKey: excludedKey)

        let initial = AppSettings.makeInitialExcludedBundleIDs()
        XCTAssertEqual(initial, [])

        AppEnvironment.defaults.removeObject(forKey: excludedKey)
        try? fm.removeItem(at: sentinel)
    }

    func test_sentinelAbsentButKeyPresentReseedsOnUpgrade() throws {
        let fm = FileManager.default
        let sentinel = try XCTUnwrap(Self.sentinelURL())
        try? fm.removeItem(at: sentinel)
        let emptyData = try JSONEncoder().encode([String]())
        AppEnvironment.defaults.set(emptyData, forKey: excludedKey)

        let initial = AppSettings.makeInitialExcludedBundleIDs()
        XCTAssertEqual(Set(initial), Self.seedExclusions)
        XCTAssertTrue(fm.fileExists(atPath: sentinel.path))

        AppEnvironment.defaults.removeObject(forKey: excludedKey)
        try? fm.removeItem(at: sentinel)
    }

    func test_skipConcealedDefaultFalse() {
        AppEnvironment.defaults.removeObject(forKey: skipConcealedKey)
        let value = AppEnvironment.defaults.object(forKey: skipConcealedKey) as? Bool ?? false
        XCTAssertFalse(value)
    }

    func test_concealedTimeoutDefault300() {
        AppEnvironment.defaults.removeObject(forKey: concealedTimeoutKey)
        let raw = AppEnvironment.defaults.object(forKey: concealedTimeoutKey) as? Double
        let value = raw ?? 300
        XCTAssertEqual(value, 300, accuracy: 0.001)
    }

    func test_settingExcludedBundleIDsPersists() {
        AppSettings.shared.excludedBundleIDs = ["com.foo.bar"]
        let data = AppEnvironment.defaults.data(forKey: excludedKey)!
        let decoded = try! JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(decoded, ["com.foo.bar"])
        AppEnvironment.defaults.removeObject(forKey: excludedKey)
    }

    func test_settingSkipConcealedPersists() {
        AppSettings.shared.skipConcealedItems = true
        XCTAssertEqual(AppEnvironment.defaults.object(forKey: skipConcealedKey) as? Bool, true)
        AppSettings.shared.skipConcealedItems = false
        AppEnvironment.defaults.removeObject(forKey: skipConcealedKey)
    }

    func test_settingConcealedTimeoutPersists() {
        AppSettings.shared.concealedClearTimeout = 60
        XCTAssertEqual(AppEnvironment.defaults.object(forKey: concealedTimeoutKey) as? Double, 60)
        AppSettings.shared.concealedClearTimeout = 300
        AppEnvironment.defaults.removeObject(forKey: concealedTimeoutKey)
    }

    func test_concealedClearTimeoutCanBeNeverSentinel() {
        AppSettings.shared.concealedClearTimeout = -1
        XCTAssertEqual(AppSettings.shared.concealedClearTimeout, -1)
        XCTAssertEqual(AppEnvironment.defaults.object(forKey: concealedTimeoutKey) as? Double, -1)
        AppSettings.shared.concealedClearTimeout = 300
        AppEnvironment.defaults.removeObject(forKey: concealedTimeoutKey)
    }

    func test_defaultsAreTrueWhenKeysAbsent() {
        // Mirrors AppSettings.init's read pattern.
        let pasteDefault = AppEnvironment.defaults.object(forKey: pasteKey) as? Bool ?? true
        let moveDefault = AppEnvironment.defaults.object(forKey: moveKey) as? Bool ?? true
        XCTAssertTrue(pasteDefault)
        XCTAssertTrue(moveDefault)
    }

    func test_settingPasteOnClickPersists() {
        AppSettings.shared.pasteOnClick = false
        XCTAssertEqual(AppEnvironment.defaults.object(forKey: pasteKey) as? Bool, false)
        AppSettings.shared.pasteOnClick = true
        XCTAssertEqual(AppEnvironment.defaults.object(forKey: pasteKey) as? Bool, true)
    }

    func test_settingMoveTopOnClickPersists() {
        AppSettings.shared.moveTopOnClick = false
        XCTAssertEqual(AppEnvironment.defaults.object(forKey: moveKey) as? Bool, false)
        AppSettings.shared.moveTopOnClick = true
        XCTAssertEqual(AppEnvironment.defaults.object(forKey: moveKey) as? Bool, true)
    }

    func test_autoDismissEnabledDefaultTrue() {
        AppEnvironment.defaults.removeObject(forKey: autoDismissEnabledKey)
        let value = AppEnvironment.defaults.object(forKey: autoDismissEnabledKey) as? Bool ?? true
        XCTAssertTrue(value)
    }

    func test_autoDismissTimeoutDefault20() {
        AppEnvironment.defaults.removeObject(forKey: autoDismissTimeoutKey)
        let value = (AppEnvironment.defaults.object(forKey: autoDismissTimeoutKey) as? Double) ?? 20
        XCTAssertEqual(value, 20, accuracy: 0.001)
    }

    func test_autoDismissEnabledPersists() {
        AppSettings.shared.autoDismissOverlayEnabled = false
        XCTAssertEqual(AppEnvironment.defaults.object(forKey: autoDismissEnabledKey) as? Bool, false)
        AppSettings.shared.autoDismissOverlayEnabled = true
        AppEnvironment.defaults.removeObject(forKey: autoDismissEnabledKey)
    }

    func test_autoDismissTimeoutPersists() {
        AppSettings.shared.autoDismissOverlayTimeout = 30
        XCTAssertEqual(AppEnvironment.defaults.object(forKey: autoDismissTimeoutKey) as? Double, 30)
        AppSettings.shared.autoDismissOverlayTimeout = 20
        AppEnvironment.defaults.removeObject(forKey: autoDismissTimeoutKey)
    }

    func test_restorePrivacyDefaultsResetsAllThree() {
        AppSettings.shared.excludedBundleIDs = ["com.foo.bar"]
        AppSettings.shared.skipConcealedItems = true
        AppSettings.shared.concealedClearTimeout = 60

        AppSettings.shared.restorePrivacyDefaults()

        XCTAssertEqual(Set(AppSettings.shared.excludedBundleIDs), Self.seedExclusions)
        XCTAssertFalse(AppSettings.shared.skipConcealedItems)
        XCTAssertEqual(AppSettings.shared.concealedClearTimeout, 300, accuracy: 0.001)

        AppEnvironment.defaults.removeObject(forKey: excludedKey)
        AppEnvironment.defaults.removeObject(forKey: skipConcealedKey)
        AppEnvironment.defaults.removeObject(forKey: concealedTimeoutKey)
    }
}
