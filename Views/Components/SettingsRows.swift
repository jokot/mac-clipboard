import SwiftUI

/// A Settings section: a title, then its rows in one rounded box. Rows are split by thin lines.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) {
                _VariadicView.Tree(DividedRows()) { content }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.hoverFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1))
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Puts a thin line between the rows of a section.
private struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
            if child.id != last {
                Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 14)
            }
        }
    }
}

/// One Settings row: the label (and a caption below it) at the left, the control at the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, caption == nil ? 10 : 9)
        .frame(minHeight: 44)
    }
}

/// A switch in the accent color, for a Settings row.
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.accent)
    }
}

/// A small status word: "On" in green, or "Off" in orange.
struct StatusBadge: View {
    let isOn: Bool

    var body: some View {
        Text(isOn ? "On" : "Off")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(isOn ? .green : Theme.warning)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill((isOn ? Color.green : Theme.warning).opacity(0.18)))
    }
}

/// A field that shows a shortcut. A click starts to record new keys.
struct ShortcutField: View {
    let shortcut: String
    let isRecording: Bool
    var isEnabled: Bool = true
    let onRecord: () -> Void

    var body: some View {
        Button(action: onRecord) {
            Text(isRecording ? "Press keys\u{2026}" : shortcut)
                .font(.system(size: 13))
                .tracking(isRecording ? 0 : 1)
                .foregroundColor(isRecording || !isEnabled ? .secondary : .primary)
                .frame(minWidth: 112)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isRecording ? Theme.accent : Theme.line, lineWidth: 1)
                )
                .shadow(color: isRecording ? Theme.accent.opacity(0.35) : .clear, radius: 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isRecording ? "Press the new shortcut. Esc cancels." : "Click to record a new shortcut")
        .accessibilityLabel(isRecording ? "Recording a new shortcut" : "Shortcut \(shortcut). Click to record a new shortcut.")
    }
}

// MARK: - Keyboard focus

/// The Settings control with the keyboard focus. MaClip moves the focus and draws the ring itself,
/// so ⇥, space and the arrow keys work without Keyboard navigation in System Settings.
@MainActor
final class SettingsFocusState: ObservableObject {
    static let shared = SettingsFocusState()
    @Published var focused: String?
}

enum SettingsControlAction: Equatable {
    case activate
    /// The previous (-1) or next (1) value of a choice.
    case step(Int)
    /// ⌫ on an app of the Privacy list.
    case remove
}

/// A key for the control with this id.
struct SettingsControlEvent {
    let id: String
    let action: SettingsControlAction
}

/// The ids of the focusable controls of the visible tab, in the order of the view.
struct SettingsFocusIDsKey: PreferenceKey {
    static var defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

private struct SettingsFocusable: ViewModifier {
    let id: String
    let enabled: Bool
    let handle: (SettingsControlAction) -> Void
    @ObservedObject private var focus = SettingsFocusState.shared

    init(id: String, enabled: Bool, handle: @escaping (SettingsControlAction) -> Void) {
        self.id = id
        self.enabled = enabled
        self.handle = handle
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled && focus.focused == id {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }
            .id(id)
            .preference(key: SettingsFocusIDsKey.self, value: enabled ? [id] : [])
            .onReceive(NotificationCenter.default.publisher(for: .settingsControlAction)) { note in
                guard enabled, let event = note.object as? SettingsControlEvent, event.id == id else { return }
                handle(event.action)
            }
    }
}

extension View {
    /// Adds the control to the ⇥ order of Settings. `handle` runs space, ↩, ← → and ⌫.
    func settingsFocus(_ id: String, enabled: Bool = true,
                       handle: @escaping (SettingsControlAction) -> Void) -> some View {
        modifier(SettingsFocusable(id: id, enabled: enabled, handle: handle))
    }

    /// A switch: space and ↩ turn it on or off.
    func settingsFocus(_ id: String, enabled: Bool = true, toggle isOn: Binding<Bool>) -> some View {
        settingsFocus(id, enabled: enabled) { action in
            if action == .activate { isOn.wrappedValue.toggle() }
        }
    }

    /// A choice: ← → select the previous or next value, and space selects the next value.
    func settingsFocus<Value: Equatable>(_ id: String, enabled: Bool = true,
                                         choice selection: Binding<Value>, values: [Value]) -> some View {
        settingsFocus(id, enabled: enabled) { action in
            switch action {
            case .step(let step):
                selection.wrappedValue = SettingsFocus.step(values, from: selection.wrappedValue, by: step)
            case .activate:
                guard let index = values.firstIndex(of: selection.wrappedValue) else { return }
                selection.wrappedValue = values[(index + 1) % values.count]
            case .remove:
                break
            }
        }
    }

    /// A button: space and ↩ press it.
    func settingsFocus(_ id: String, enabled: Bool = true, press: @escaping () -> Void) -> some View {
        settingsFocus(id, enabled: enabled) { action in
            if action == .activate { press() }
        }
    }
}
