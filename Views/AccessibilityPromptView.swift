import SwiftUI
import AppKit
import Combine

/// Explains why MaClip needs Accessibility access before macOS asks. It has three steps:
/// the reason, the steps in System Settings while MaClip waits, and the success message.
struct AccessibilityPromptView: View {
    @ObservedObject var access: AccessibilityAccess
    @ObservedObject private var settings = AppSettings.shared
    /// True when the user picked a clip. MaClip copied it but could not paste it.
    let afterCopy: Bool
    let onClose: () -> Void

    @State private var askedSystem = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if access.isGranted {
                granted
            } else if askedSystem || access.needsRepair {
                waiting
            } else {
                intro
            }
        }
        .padding(20)
        .frame(width: 400)
        .shortcutsPanel(.accessibility, title: "Accessibility access") { [PromptKeyMap.table.groups()] }
        .onReceive(poll) { _ in
            let wasGranted = access.isGranted
            access.refresh()
            if access.isGranted && !wasGranted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { onClose() }
            }
        }
    }

    // MARK: Step 1

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppIconView().frame(width: 44, height: 44)
            Text("Allow MaClip to paste for you")
                .font(.system(size: 15, weight: .semibold))
            if afterCopy {
                Text("The clip is copied. Press \u{2318}V to paste it now.")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.green.opacity(0.14)))
            }
            Text("To paste for you, MaClip needs Accessibility access. MaClip uses it only to press \u{2318}V in the app that you used before.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ShortcutsButton(scope: .accessibility)
                if settings.pasteOnClick {
                    Button("Turn Off Paste on Selection") {
                        settings.pasteOnClick = false
                        onClose()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
                Spacer()
                Button("Not Now") { onClose() }
                    .keyboardShortcut(.cancelAction)
                    .help("Not Now (esc)")
                Button("Continue") {
                    access.requestSystemPrompt()
                    askedSystem = true
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
    }

    // MARK: Step 2

    private var waiting: some View {
        let repair = access.needsRepair
        let steps = repair
            ? ["Click Open System Settings.",
               "Select MaClip in the Accessibility list, and click \u{2212} to remove it.",
               "Click +, choose MaClip in Applications, and turn it on."]
            : ["In the macOS dialog, click Open System Settings.",
               "Turn on MaClip in the Accessibility list.",
               "MaClip already on? Select it, click \u{2212}, then add it again with +."]
        return VStack(alignment: .leading, spacing: 12) {
            Text(repair ? "Allow MaClip again" : "Turn on MaClip in System Settings")
                .font(.system(size: 15, weight: .semibold))
            if repair {
                Text("MaClip was updated, so macOS needs you to allow it again.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.tileFill))
                        Text(step).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for access\u{2026}")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                ShortcutsButton(scope: .accessibility)
                Spacer()
                Button("Not Now") { onClose() }
                    .keyboardShortcut(.cancelAction)
                    .help("Not Now (esc)")
                Button("Open System Settings") { access.openSettings() }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Step 3

    private var granted: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Color.green.opacity(0.18))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundColor(.green))
            Text("MaClip can paste now")
                .font(.system(size: 15, weight: .semibold))
            Text("Pick a clip, and MaClip pastes it into the app that you used before.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("This window closes in 2 seconds.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

@MainActor
final class AccessibilityPromptWindowController: NSObject, NSWindowDelegate {
    static let shared = AccessibilityPromptWindowController()

    private var window: NSWindow?
    private var onDismiss: (() -> Void)?
    private var keyMonitor: Any?

    /// `onDismiss` runs when the window closes, for example to give focus back to
    /// the app that the user worked in.
    func show(afterCopy: Bool, onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        let view = AccessibilityPromptView(access: .shared, afterCopy: afterCopy) { [weak self] in
            self?.window?.close()
        }
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable]
            window.title = "MaClip"
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.delegate = self
            self.window = window
            // The keys of the prompt, from `PromptKeyMap`. The buttons take ↩ and esc themselves.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let window = self?.window, window.isKeyWindow,
                      let combo = KeyCombo(event: event) else { return event }
                let panel = ShortcutsPanelState.shared
                if panel.isVisible(.accessibility) {
                    if combo == KeyCombo(.escape) || combo == .command("/") { panel.hide(.accessibility) }
                    return nil
                }
                switch PromptKeyMap.table.command(for: combo) {
                case .notNow where combo == .command("w"):
                    window.close()
                case .showShortcuts:
                    panel.toggle(.accessibility)
                default:
                    return event
                }
                return nil
            }
        }
        guard let window else { return }
        // Size the window to the view before center(), or the window can open
        // partly above the top of the screen.
        if let content = window.contentViewController?.view {
            window.setContentSize(content.fittingSize)
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        ShortcutsPanelState.shared.hide(.accessibility)
        let dismiss = onDismiss
        onDismiss = nil
        dismiss?()
    }
}
