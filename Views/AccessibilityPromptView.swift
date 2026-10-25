import SwiftUI
import AppKit
import Combine

/// Explains why MaClip needs Accessibility access before macOS asks.
struct AccessibilityPromptView: View {
    @ObservedObject var access: AccessibilityAccess
    @ObservedObject private var settings = AppSettings.shared
    /// True when the user picked a clip. MaClip copied it but could not paste it.
    let afterCopy: Bool
    let onClose: () -> Void

    @State private var askedSystem = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: access.isGranted ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                    .font(.system(size: 30))
                    .foregroundColor(access.isGranted ? .green : .accentColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    ForEach(lines, id: \.self) { line in
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !access.isGranted {
                HStack {
                    if settings.pasteOnClick {
                        Button("Turn Off Paste on Selection") {
                            settings.pasteOnClick = false
                            onClose()
                        }
                        .buttonStyle(.link)
                    }
                    Spacer()
                    Button("Not Now") { onClose() }
                        .keyboardShortcut(.cancelAction)
                    Button(primaryTitle) { primaryAction() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .onReceive(poll) { _ in
            let wasGranted = access.isGranted
            access.refresh()
            if access.isGranted && !wasGranted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onClose() }
            }
        }
    }

    private var title: String {
        if access.isGranted { return "MaClip can paste now" }
        return access.needsRepair ? "Allow MaClip again" : "Allow MaClip to paste for you"
    }

    private var lines: [String] {
        if access.isGranted {
            return ["Pick a clip, and MaClip pastes it into the app that you used before."]
        }
        var lines: [String] = []
        if afterCopy {
            lines.append("MaClip copied the clip. Press \u{2318}V to paste it.")
        }
        if access.needsRepair {
            lines.append("MaClip was updated, so macOS needs you to allow it again.")
            lines.append("In the list, select MaClip and click \u{2212} to remove it. Then click +, choose MaClip in Applications, and turn it on.")
        } else if askedSystem {
            lines.append("In the macOS dialog, click Open System Settings. Then turn on MaClip in the list.")
            lines.append("If MaClip is already on, select it and click \u{2212} to remove it. Then click Continue again.")
        } else {
            lines.append("To paste a clip into the app that you used before, MaClip needs Accessibility access. MaClip uses it only to press \u{2318}V for you.")
            lines.append("Click Continue. macOS then asks you to allow MaClip.")
        }
        return lines
    }

    private var primaryTitle: String {
        access.needsRepair ? "Open Accessibility Settings" : "Continue"
    }

    private func primaryAction() {
        if access.needsRepair {
            access.openSettings()
        } else {
            access.requestSystemPrompt()
            askedSystem = true
        }
    }
}

@MainActor
final class AccessibilityPromptWindowController: NSObject, NSWindowDelegate {
    static let shared = AccessibilityPromptWindowController()

    private var window: NSWindow?
    private var onDismiss: (() -> Void)?

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
        let dismiss = onDismiss
        onDismiss = nil
        dismiss?()
    }
}
