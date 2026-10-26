import SwiftUI

/// The window or side that shows the shortcuts panel.
enum ShortcutScope: Equatable {
    case clipList, preview, imageEditor, settings, about, accessibility
}

/// Which window shows its shortcuts panel now. Only the key window takes ⌘/, so one panel at a time is open.
@MainActor
final class ShortcutsPanelState: ObservableObject {
    static let shared = ShortcutsPanelState()

    @Published private(set) var visible: ShortcutScope?

    func isVisible(_ scope: ShortcutScope) -> Bool { visible == scope }

    func toggle(_ scope: ShortcutScope) {
        visible = visible == scope ? nil : scope
    }

    func hide(_ scope: ShortcutScope) {
        if visible == scope { visible = nil }
    }
}

/// The shortcuts card: a title, the groups in columns, and a note.
struct ShortcutsCard: View {
    @ObservedObject private var accentStore = AccentStore.shared
    let title: String
    let columns: [[ShortcutGroup]]
    var note: String? = nil
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.selectedFill)
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "keyboard").font(.system(size: 13)).foregroundColor(Theme.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keyboard Shortcuts").font(.system(size: 13, weight: .semibold))
                    Text(title).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close (esc)")
                .accessibilityLabel("Close keyboard shortcuts")
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 10)

            Rectangle().fill(Theme.line).frame(height: 1)

            ShortcutColumnsView(columns: columns)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Rectangle().fill(Theme.line).frame(height: 1)

            HStack(spacing: 10) {
                if let note {
                    Text(note).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    KeyLabel(key: "\u{2318}/")
                    Text("or")
                    KeyLabel(key: "esc")
                    Text("closes")
                }
                .fixedSize()
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        // At most this wide. In a narrow window, such as About, the card fits the window.
        .frame(maxWidth: columns.count > 1 ? 496 : 340)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
    }
}

/// Groups of shortcut lines in columns. Settings shows it on the Shortcuts tab too.
struct ShortcutColumnsView: View {
    @ObservedObject private var accentStore = AccentStore.shared
    let columns: [[ShortcutGroup]]

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, groups in
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.title.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.6)
                                .foregroundColor(group.highlight ? Theme.accentText : .secondary)
                                .frame(height: 20)
                            ForEach(group.rows, id: \.label) { row in
                                HStack(spacing: 8) {
                                    Text(row.label)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    HStack(spacing: 3) {
                                        ForEach(row.keys, id: \.self) { KeyLabel(key: $0) }
                                    }
                                }
                                .frame(height: 22)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Puts the shortcuts card on top of the view while `scope` is the visible panel.
/// A click outside the card closes it.
struct ShortcutsOverlay: ViewModifier {
    let scope: ShortcutScope
    let title: String
    var note: String? = nil
    let columns: () -> [[ShortcutGroup]]
    @ObservedObject private var state = ShortcutsPanelState.shared

    func body(content: Content) -> some View {
        content.overlay {
            if state.isVisible(scope) {
                ZStack {
                    Color.black.opacity(0.35)
                        .contentShape(Rectangle())
                        .onTapGesture { state.hide(scope) }
                    ShortcutsCard(title: title, columns: columns(), note: note) { state.hide(scope) }
                        .padding(12)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
    }
}

extension View {
    func shortcutsPanel(_ scope: ShortcutScope, title: String, note: String? = nil,
                        columns: @escaping () -> [[ShortcutGroup]]) -> some View {
        modifier(ShortcutsOverlay(scope: scope, title: title, note: note, columns: columns))
    }
}

/// A small keyboard button that opens the shortcuts panel of a window.
struct ShortcutsButton: View {
    let scope: ShortcutScope

    var body: some View {
        Button { ShortcutsPanelState.shared.toggle(scope) } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Keyboard Shortcuts (\u{2318}/)")
        .accessibilityLabel("Keyboard shortcuts")
    }
}
