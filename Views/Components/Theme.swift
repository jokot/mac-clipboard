import SwiftUI
import AppKit

/// Colors and sizes of the 2.0 design. See the "Foundations" artboard of the design canvas.
/// The fills use `Color.primary` with opacity, so they work in light and dark appearance.
/// The accent colors come from `AccentStore`. A view that draws them observes the store.
enum Theme {
    /// The accent color of Settings → Appearance. Indigo, #5E5CE6, by default.
    static var accent: Color { Color(nsColor: NSColor(hex: AccentStore.shared.choice.hex)) }
    /// Text on the accent, for example on the Paste button: white or near black.
    static var onAccent: Color {
        AccentColor.usesWhiteText(on: AccentStore.shared.choice.hex)
            ? .white
            : Color(nsColor: NSColor(hex: "#1C1C1E"))
    }
    /// Colored text, for example a link: the accent with 4.5:1 contrast in light and dark appearance.
    static var accentText: Color {
        let hex = AccentStore.shared.choice.hex
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: AccentColor.textTint(hex, background: isDark ? "#1C1C1E" : "#FFFFFF", isDark: isDark))
        })
    }
    /// The selected clip: the accent at 22% in dark appearance, 16% in light appearance.
    static var selectedFill: Color {
        let base = NSColor(hex: AccentStore.shared.choice.hex)
        return Color(nsColor: NSColor(name: nil) { appearance in
            base.withAlphaComponent(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.22 : 0.16)
        })
    }
    /// The selected row while the preview has focus.
    static let inactiveSelectedFill = Color.primary.opacity(0.1)
    static let hoverFill = Color.primary.opacity(0.06)
    static let fieldFill = Color.primary.opacity(0.07)
    static let tileFill = Color.primary.opacity(0.08)
    static let keyFill = Color.primary.opacity(0.08)
    static let line = Color.primary.opacity(0.1)
    static let warning = Color.orange
    /// The fill of a row action tip: #3A3A3F in dark appearance, white in light appearance.
    static let tipFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 58 / 255, green: 58 / 255, blue: 63 / 255, alpha: 1)
            : .white
    })

    static let rowHeight: CGFloat = 48
    static let tileSize: CGFloat = 32
    static let imageHeight: CGFloat = 132
}

/// The 32 pt icon at the left of a clip row: the kind of clip, with the source app icon on its corner.
struct KindTile: View {
    let systemImage: String
    var tint: Color = .secondary
    var bundleID: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.tileFill)
            .frame(width: Theme.tileSize, height: Theme.tileSize)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(tint)
            )
            .overlay(alignment: .bottomTrailing) {
                SourceAppBadge(bundleID: bundleID)
                    .offset(x: 6, y: 6)
            }
    }
}

/// The source app icon. MaClip shows no badge when it does not know the app.
struct SourceAppBadge: View {
    let bundleID: String?

    var body: some View {
        if let bundleID, let icon = AppMetadata.shared.icon(for: bundleID) {
            let name = AppMetadata.shared.displayName(for: bundleID) ?? bundleID
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .help(name)
                .accessibilityLabel("From \(name)")
        }
    }
}

/// A 28 pt icon button for the row actions. On hover, it shows its name and key under it,
/// like the native tooltip, but at once and in the style of the 2.0 design.
struct RowActionButton: View {
    let label: String
    /// The key of the action, for example "⌘E".
    var shortcut: String? = nil
    let systemImage: String
    var tint: Color = .secondary
    let action: () -> Void

    @State private var isHovered = false
    @State private var showsTip = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? Theme.hoverFill : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            guard hovering else {
                showsTip = false
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if isHovered { showsTip = true }
            }
        }
        // The trailing edge of the tip is on the trailing edge of the button, so a tip at the
        // right of the window stays in the window.
        .overlay(alignment: .topTrailing) {
            if showsTip {
                ActionTip(label: label, shortcut: shortcut)
                    .offset(y: 32)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .accessibilityLabel(label)
        .accessibilityHint(shortcut.map { "Keyboard shortcut \($0)" } ?? "")
    }
}

/// The tip of a row action: "Edit  ⌘E".
private struct ActionTip: View {
    let label: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
            if let shortcut {
                Text(shortcut).foregroundColor(.secondary)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.tipFill))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }
}

/// A key label in the hint bar, for example "esc".
struct KeyLabel: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11))
            .foregroundColor(.primary.opacity(0.8))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.keyFill))
    }
}

/// The main button of a window: accent fill, white text. Unlike `.borderedProminent`, it keeps
/// its color in a panel that is not the key window, such as the preview panel.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AccentButtonBody(configuration: configuration)
    }
}

/// A view, so that it can observe the accent color.
private struct AccentButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @ObservedObject private var accentStore = AccentStore.shared

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.onAccent)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

extension NSColor {
    /// An sRGB color from "#RRGGBB".
    convenience init(hex: String) {
        let c = AccentColor.rgb(hex)
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    /// "#RRGGBB" in sRGB.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return AccentColor.hex(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
}
