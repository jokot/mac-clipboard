import Foundation

/// The 10 recommended accent colors. The values are the dark mode system colors of macOS.
enum AccentPreset: String, CaseIterable {
    case indigo, blue, purple, pink, red, orange, yellow, green, teal, graphite

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var hex: String {
        switch self {
        case .indigo: return "#5E5CE6"
        case .blue: return "#0A84FF"
        case .purple: return "#BF5AF2"
        case .pink: return "#FF375F"
        case .red: return "#FF453A"
        case .orange: return "#FF9F0A"
        case .yellow: return "#FFD60A"
        case .green: return "#30D158"
        case .teal: return "#40C8E0"
        case .graphite: return "#98989D"
        }
    }
}

/// The accent color in Settings: a preset or a custom color.
enum AccentChoice: Equatable {
    case preset(AccentPreset)
    /// "#RRGGBB" in upper case.
    case custom(String)

    static let `default` = AccentChoice.preset(.indigo)

    /// A preset name, or a hex value. A value that is neither gives Indigo.
    init(stored: String) {
        if let preset = AccentPreset(rawValue: stored.lowercased()) {
            self = .preset(preset)
        } else if let hex = AccentColor.normalizedHex(stored) {
            self = .custom(hex)
        } else {
            self = .default
        }
    }

    var stored: String {
        switch self {
        case .preset(let preset): return preset.rawValue
        case .custom(let hex): return hex
        }
    }

    var hex: String {
        switch self {
        case .preset(let preset): return preset.hex
        case .custom(let hex): return hex
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// The caption under "Accent color".
    var caption: String {
        switch self {
        case .preset(.indigo): return "Indigo (default)"
        case .preset(let preset): return preset.title
        case .custom(let hex): return "Custom \u{00B7} \(hex)"
        }
    }

    /// ← and → in Settings: the presets in order, then Custom. It stops at both ends.
    func stepped(by step: Int, lastCustom: String) -> AccentChoice {
        let all = AccentPreset.allCases.map { AccentChoice.preset($0) } + [.custom(lastCustom)]
        let index: Int
        switch self {
        case .preset(let preset): index = AccentPreset.allCases.firstIndex(of: preset) ?? 0
        case .custom: index = all.count - 1
        }
        return all[min(max(0, index + step), all.count - 1)]
    }
}

/// Color math for the accent: contrast, readable text, and the values of the color picker.
enum AccentColor {
    /// "#RRGGBB" in upper case, from six hex digits with or without "#". Nil for other text.
    static func normalizedHex(_ text: String) -> String? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits
    }

    /// Red, green and blue from 0 to 1.
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        guard let normalized = normalizedHex(hex), let value = UInt32(normalized.dropFirst(), radix: 16) else {
            return (0, 0, 0)
        }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    static func hex(r: Double, g: Double, b: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// `amount` 0 gives `a`, 1 gives `b`.
    static func mix(_ a: String, _ b: String, _ amount: Double) -> String {
        let x = rgb(a), y = rgb(b)
        return hex(r: x.r + (y.r - x.r) * amount, g: x.g + (y.g - x.g) * amount, b: x.b + (y.b - x.b) * amount)
    }

    /// The relative luminance of WCAG 2.
    static func luminance(_ hex: String) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let c = rgb(hex)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    static func contrast(_ a: String, _ b: String) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Button text on the accent: white when white has 3:1 contrast or more, else near black.
    static func usesWhiteText(on hex: String) -> Bool {
        contrast(hex, "#FFFFFF") >= 3
    }

    /// Colored text, for example a link: the accent, lighter in dark mode or darker in light mode,
    /// until it has 4.5:1 contrast with the background.
    static func textTint(_ hex: String, background: String, isDark: Bool) -> String {
        let target = isDark ? "#FFFFFF" : "#000000"
        for step in 0...20 {
            let candidate = mix(hex, target, Double(step) / 20)
            if contrast(candidate, background) >= 4.5 { return candidate }
        }
        return target
    }

    /// Hue from 0 to 360, saturation and brightness from 0 to 1.
    static func hsv(_ hex: String) -> (hue: Double, saturation: Double, brightness: Double) {
        let c = rgb(hex)
        let high = max(c.r, c.g, c.b), low = min(c.r, c.g, c.b), delta = high - low
        var hue = 0.0
        if delta > 0 {
            switch high {
            case c.r: hue = ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6)
            case c.g: hue = (c.b - c.r) / delta + 2
            default: hue = (c.r - c.g) / delta + 4
            }
            hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        return (hue, high == 0 ? 0 : delta / high, high)
    }

    static func hex(hue: Double, saturation: Double, brightness: Double) -> String {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let s = min(max(saturation, 0), 1), v = min(max(brightness, 0), 1)
        let chroma = v * s
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<1: (r, g, b) = (chroma, x, 0)
        case ..<2: (r, g, b) = (x, chroma, 0)
        case ..<3: (r, g, b) = (0, chroma, x)
        case ..<4: (r, g, b) = (0, x, chroma)
        case ..<5: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        let m = v - chroma
        return hex(r: r + m, g: g + m, b: b + m)
    }

    /// The newest custom colors, at most 4, without repeats.
    static func addRecent(_ hex: String, to recent: [String]) -> [String] {
        Array(([hex] + recent.filter { $0 != hex }).prefix(4))
    }
}
