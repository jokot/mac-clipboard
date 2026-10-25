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
