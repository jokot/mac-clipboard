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

    private struct Keys {
        static let hotkeyKeyCode = "settings.hotkey.keycode"
        static let hotkeyModifiers = "settings.hotkey.modifiers"
        static let theme = "settings.theme"
        static let maxItems = "settings.maxItems"
        static let autoCleanEnabled = "settings.autoClean"
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

        self.hotkeyKeyCode = initialKeyCode
        self.hotkeyModifiers = initialModifiers
        self.theme = initialTheme
        self.maxItems = initialMax
        self.autoCleanEnabled = initialAutoClean
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

extension UInt32 {
    var containsCmd: Bool { (self & UInt32(cmdKey)) != 0 }
    var containsCtrl: Bool { (self & UInt32(controlKey)) != 0 }
    var containsAlt: Bool { (self & UInt32(optionKey)) != 0 }
    var containsShift: Bool { (self & UInt32(shiftKey)) != 0 }
}

