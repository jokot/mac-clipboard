import Foundation
import SwiftUI
import Carbon.HIToolbox

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hotkeyKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }
    @Published var hotkeyModifiers: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var maxItems: Int {
        didSet { UserDefaults.standard.set(maxItems, forKey: Keys.maxItems) }
    }
    @Published var autoCleanEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCleanEnabled, forKey: Keys.autoCleanEnabled) }
    }
    @Published var excludedBundleIDs: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(excludedBundleIDs) {
                UserDefaults.standard.set(data, forKey: Keys.excludedBundleIDs)
            }
        }
    }
    @Published var skipConcealedItems: Bool {
        didSet { UserDefaults.standard.set(skipConcealedItems, forKey: Keys.skipConcealedItems) }
    }
    @Published var concealedClearTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(concealedClearTimeout, forKey: Keys.concealedClearTimeout) }
    }
    @Published var pasteOnClick: Bool {
        didSet { UserDefaults.standard.set(pasteOnClick, forKey: Keys.pasteOnClick) }
    }
    @Published var moveTopOnClick: Bool {
        didSet { UserDefaults.standard.set(moveTopOnClick, forKey: Keys.moveTopOnClick) }
    }

    private struct Keys {
        static let hotkeyKeyCode = "settings.hotkey.keycode"
        static let hotkeyModifiers = "settings.hotkey.modifiers"
        static let theme = "settings.theme"
        static let maxItems = "settings.maxItems"
        static let autoCleanEnabled = "settings.autoClean"
        static let pasteOnClick = "settings.pasteOnClick"
        static let moveTopOnClick = "settings.moveTopOnClick"
        static let excludedBundleIDs = "settings.excludedBundleIDs"
        static let skipConcealedItems = "settings.skipConcealedItems"
        static let concealedClearTimeout = "settings.concealedClearTimeout"
    }

    static let defaultSeedExclusions: [String] = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPassMacDesktop",
        "com.jokot.MacClipboard",
    ]

    static func makeInitialExcludedBundleIDs() -> [String] {
        let defaults = UserDefaults.standard
        let fm = FileManager.default
        let sentinelURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MaClip", isDirectory: true)
            .appendingPathComponent(".seeded")

        let sentinelExists = sentinelURL.map { fm.fileExists(atPath: $0.path) } ?? false

        if sentinelExists,
           let data = defaults.data(forKey: Keys.excludedBundleIDs),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }

        writeSentinel(at: sentinelURL)
        return defaultSeedExclusions
    }

    private static func writeSentinel(at url: URL?) {
        guard let url else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? Data().write(to: url, options: .atomic)
    }

    private init() {
        let defaults = UserDefaults.standard
        let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_V)
        let defaultModifiers: UInt32 = UInt32(controlKey | cmdKey)

        var initialKeyCode = UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode))
        if initialKeyCode == 0 { initialKeyCode = defaultKeyCode }
        var initialModifiers = UInt32(defaults.integer(forKey: Keys.hotkeyModifiers))
        if initialModifiers == 0 { initialModifiers = defaultModifiers }
        let initialTheme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? AppTheme.system.rawValue) ?? .system
        let storedMax = defaults.integer(forKey: Keys.maxItems)
        let initialMax = storedMax > 0 ? storedMax : 100
        let initialAutoClean = defaults.object(forKey: Keys.autoCleanEnabled) as? Bool ?? false
        let initialExcluded = AppSettings.makeInitialExcludedBundleIDs()
        let initialSkipConcealed = defaults.object(forKey: Keys.skipConcealedItems) as? Bool ?? false
        let initialConcealedTimeout = (defaults.object(forKey: Keys.concealedClearTimeout) as? Double) ?? 300
        let initialPasteOnClick = defaults.object(forKey: Keys.pasteOnClick) as? Bool ?? true
        let initialMoveTopOnClick = defaults.object(forKey: Keys.moveTopOnClick) as? Bool ?? true

        self.hotkeyKeyCode = initialKeyCode
        self.hotkeyModifiers = initialModifiers
        self.theme = initialTheme
        self.maxItems = initialMax
        self.autoCleanEnabled = initialAutoClean
        self.excludedBundleIDs = initialExcluded
        self.skipConcealedItems = initialSkipConcealed
        self.concealedClearTimeout = initialConcealedTimeout
        self.pasteOnClick = initialPasteOnClick
        self.moveTopOnClick = initialMoveTopOnClick
    }
}

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum HotkeyChoice: String, CaseIterable, Identifiable {
    case a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z
    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .a: return UInt32(kVK_ANSI_A)
        case .b: return UInt32(kVK_ANSI_B)
        case .c: return UInt32(kVK_ANSI_C)
        case .d: return UInt32(kVK_ANSI_D)
        case .e: return UInt32(kVK_ANSI_E)
        case .f: return UInt32(kVK_ANSI_F)
        case .g: return UInt32(kVK_ANSI_G)
        case .h: return UInt32(kVK_ANSI_H)
        case .i: return UInt32(kVK_ANSI_I)
        case .j: return UInt32(kVK_ANSI_J)
        case .k: return UInt32(kVK_ANSI_K)
        case .l: return UInt32(kVK_ANSI_L)
        case .m: return UInt32(kVK_ANSI_M)
        case .n: return UInt32(kVK_ANSI_N)
        case .o: return UInt32(kVK_ANSI_O)
        case .p: return UInt32(kVK_ANSI_P)
        case .q: return UInt32(kVK_ANSI_Q)
        case .r: return UInt32(kVK_ANSI_R)
        case .s: return UInt32(kVK_ANSI_S)
        case .t: return UInt32(kVK_ANSI_T)
        case .u: return UInt32(kVK_ANSI_U)
        case .v: return UInt32(kVK_ANSI_V)
        case .w: return UInt32(kVK_ANSI_W)
        case .x: return UInt32(kVK_ANSI_X)
        case .y: return UInt32(kVK_ANSI_Y)
        case .z: return UInt32(kVK_ANSI_Z)
        }
    }
}