import SwiftUI
import AppKit

/// Colors and sizes of the 2.0 design. See the "Foundations" artboard of the design canvas.
/// The fills use `Color.primary` with opacity, so they work in light and dark appearance.
enum Theme {
    /// Indigo, #5E5CE6.
    static let accent = Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255)
    static let selectedFill = accent.opacity(0.22)
    static let hoverFill = Color.primary.opacity(0.06)
    static let fieldFill = Color.primary.opacity(0.07)
    static let tileFill = Color.primary.opacity(0.08)
    static let keyFill = Color.primary.opacity(0.08)
    static let line = Color.primary.opacity(0.1)
    static let warning = Color.orange

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

/// A 28 pt icon button for the row actions that show on hover.
struct RowActionButton: View {
    let label: String
    let systemImage: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
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
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}
