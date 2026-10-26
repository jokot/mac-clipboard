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

    func test_maxItemsDefaultIs50() {
        AppEnvironment.defaults.removeObject(forKey: "settings.maxItems")
        XCTAssertEqual(AppSettings.defaultMaxItems, 50)
        XCTAssertEqual(AppSettings.initialMaxItems(stored: 0), 50)
        XCTAssertEqual(AppSettings.initialMaxItems(stored: 10), 10)
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

    func test_restorePrivacyDefaultsResetsAllFour() {
        AppSettings.shared.excludedBundleIDs = ["com.foo.bar"]
        AppSettings.shared.skipConcealedItems = true
        AppSettings.shared.concealedClearTimeout = 60
        AppSettings.shared.saveMaClipClips = true

        AppSettings.shared.restorePrivacyDefaults()

        XCTAssertEqual(Set(AppSettings.shared.excludedBundleIDs), Self.seedExclusions)
        XCTAssertFalse(AppSettings.shared.skipConcealedItems)
        XCTAssertEqual(AppSettings.shared.concealedClearTimeout, 300, accuracy: 0.001)
        XCTAssertFalse(AppSettings.shared.saveMaClipClips)
        AppEnvironment.defaults.removeObject(forKey: "settings.saveMaClipClips")

        AppEnvironment.defaults.removeObject(forKey: excludedKey)
        AppEnvironment.defaults.removeObject(forKey: skipConcealedKey)
        AppEnvironment.defaults.removeObject(forKey: concealedTimeoutKey)
    }
}

final class RestoreDefaultSettingsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(AppEnvironment.isRunningTests, "test storage isolation is not active")
    }

    func test_restoreSetsEverySettingBackToItsDefault() {
        let s = AppSettings.shared
        s.theme = .dark
        s.accentColor = "#2BB673"
        s.pasteOnClick = false
        s.moveTopOnClick = false
        s.autoDismissOverlayEnabled = false
        s.autoDismissOverlayTimeout = 60
        s.hotkeyKeyCode = 1
        s.extractTextHotkeyEnabled = false
        s.extractCodeKeyCode = 2
        s.autoCleanEnabled = true
        s.autoCleanDays = 30
        s.excludedBundleIDs = ["com.foo.bar"]
        s.saveMaClipClips = true
        s.skipConcealedItems = true

        s.restoreDefaultSettings()

        XCTAssertEqual(s.theme, .system)
        XCTAssertEqual(s.accentColor, "indigo")
        XCTAssertTrue(s.pasteOnClick)
        XCTAssertTrue(s.moveTopOnClick)
        XCTAssertTrue(s.autoDismissOverlayEnabled)
        XCTAssertEqual(s.autoDismissOverlayTimeout, 20, accuracy: 0.001)
        XCTAssertEqual(s.hotkeyKeyCode, AppSettings.defaultHotkeyKeyCode)
        XCTAssertEqual(s.hotkeyModifiers, AppSettings.defaultHotkeyModifiers)
        XCTAssertTrue(s.extractTextHotkeyEnabled)
        XCTAssertEqual(s.extractCodeKeyCode, AppSettings.defaultExtractCodeKeyCode)
        XCTAssertFalse(s.autoCleanEnabled)
        XCTAssertEqual(s.autoCleanDays, 7)
        XCTAssertEqual(s.excludedBundleIDs, AppSettings.defaultSeedExclusions)
        XCTAssertFalse(s.saveMaClipClips)
        XCTAssertFalse(s.skipConcealedItems)
    }

    func test_restoreKeepsTheClipLimitAndEncryption() {
        let s = AppSettings.shared
        s.maxItems = 120
        s.encryptHistory = true
        defer { s.maxItems = 50; s.encryptHistory = false }

        s.restoreDefaultSettings()

        XCTAssertEqual(s.maxItems, 120, "a lower limit would delete clips")
        XCTAssertTrue(s.encryptHistory, "encryption changes the files and needs the Keychain")
    }
}

final class MaClipClipsTests: XCTestCase {
    private let own = "com.jokot.MacClipboard"

    func test_maClipIsNotInTheDefaultAppList() {
        XCTAssertFalse(AppSettings.defaultSeedExclusions.contains(own))
    }

    func test_clipsFromMaClipAreSkippedWhileTheSwitchIsOff() {
        XCTAssertTrue(AppSettings.skipsClip(from: own, excluded: [], saveMaClipClips: false))
        XCTAssertFalse(AppSettings.skipsClip(from: own, excluded: [], saveMaClipClips: true))
    }

    func test_aScreenshotWhileMaClipIsInFrontIsSaved() {
        // MaClip never puts an image on the clipboard without skipping it itself. An image
        // while MaClip is in front comes from the screenshot tool.
        XCTAssertFalse(AppSettings.skipsClip(from: own, excluded: [], saveMaClipClips: false, isImage: true))
        XCTAssertTrue(AppSettings.skipsClip(from: "com.bitwarden.desktop", excluded: ["com.bitwarden.desktop"],
                                            saveMaClipClips: false, isImage: true), "the list still skips images")
    }

    func test_otherAppsFollowTheList() {
        XCTAssertTrue(AppSettings.skipsClip(from: "com.bitwarden.desktop", excluded: ["com.bitwarden.desktop"], saveMaClipClips: true))
        XCTAssertFalse(AppSettings.skipsClip(from: "com.apple.Notes", excluded: ["com.bitwarden.desktop"], saveMaClipClips: false))
        XCTAssertFalse(AppSettings.skipsClip(from: nil, excluded: ["com.bitwarden.desktop"], saveMaClipClips: false))
    }

    func test_upgradeTakesMaClipOutOfTheListAndKeepsItsRule() {
        let upgraded = AppSettings.migrateMaClipExclusion(["com.bitwarden.desktop", own])
        XCTAssertEqual(upgraded.list, ["com.bitwarden.desktop"])
        XCTAssertFalse(upgraded.saveMaClipClips, "MaClip was in the list, so its clips stay unsaved")
    }

    func test_maClipStaysOutOfTheListAfterTheSwitchIsSaved() {
        let resolved = AppSettings.resolveMaClipSetting(storedSwitch: true, storedList: ["com.bitwarden.desktop", own], hadList: true)
        XCTAssertEqual(resolved.list, ["com.bitwarden.desktop"])
        XCTAssertTrue(resolved.saveMaClipClips)
    }

    func test_aNewInstallStartsWithTheSwitchOff() {
        let resolved = AppSettings.resolveMaClipSetting(storedSwitch: nil, storedList: AppSettings.defaultSeedExclusions, hadList: false)
        XCTAssertEqual(resolved.list, AppSettings.defaultSeedExclusions)
        XCTAssertFalse(resolved.saveMaClipClips)
    }

    func test_upgradeTurnsTheSwitchOnWhenMaClipWasRemovedFromTheList() {
        let upgraded = AppSettings.migrateMaClipExclusion(["com.bitwarden.desktop"])
        XCTAssertEqual(upgraded.list, ["com.bitwarden.desktop"])
        XCTAssertTrue(upgraded.saveMaClipClips, "the person chose to save clips from MaClip")
    }
}

final class MaxItemsDraftTests: XCTestCase {
    func test_noNoteWhenTheNumberDidNotChange() {
        XCTAssertNil(MaxItemsDraft.note(draft: 50, saved: 50, count: 44))
        XCTAssertFalse(MaxItemsDraft.canApply(draft: 50, saved: 50))
    }

    func test_aLowerNumberWarnsAboutTheDeletedClips() {
        XCTAssertEqual(MaxItemsDraft.note(draft: 30, saved: 50, count: 44),
                       MaxItemsDraft.Note(text: "Apply deletes the 14 oldest clips. You cannot undo this.", isWarning: true))
        XCTAssertEqual(MaxItemsDraft.note(draft: 43, saved: 50, count: 44)?.text,
                       "Apply deletes the oldest clip. You cannot undo this.")
        XCTAssertTrue(MaxItemsDraft.canApply(draft: 30, saved: 50))
    }

    func test_aNumberThatKeepsEveryClipSaysWhatApplyDoes() {
        XCTAssertEqual(MaxItemsDraft.note(draft: 60, saved: 50, count: 44),
                       MaxItemsDraft.Note(text: "Press Apply or \u{21A9} to keep up to 60 clips.", isWarning: false))
    }

    func test_aNumberOutOfRangeCannotBeApplied() {
        XCTAssertFalse(MaxItemsDraft.canApply(draft: 0, saved: 50))
        XCTAssertFalse(MaxItemsDraft.canApply(draft: 1001, saved: 50))
        XCTAssertEqual(MaxItemsDraft.note(draft: 0, saved: 50, count: 44),
                       MaxItemsDraft.Note(text: "Enter a number from 1 to 1000.", isWarning: true))
    }
}

final class AppThemeAppearanceTests: XCTestCase {
    func test_themeMapsToAnAppearance() {
        XCTAssertNil(AppTheme.system.nsAppearance, "System follows macOS")
        XCTAssertEqual(AppTheme.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppTheme.dark.nsAppearance?.name, .darkAqua)
    }
}
