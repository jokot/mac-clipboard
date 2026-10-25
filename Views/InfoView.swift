import SwiftUI
import AppKit

struct InfoView: View {
    @StateObject private var viewModel = InfoViewModel()
    @State private var refreshTrigger = false
    private let repoURL = URL(string: "https://github.com/jokot/mac-clipboard")!

    var body: some View {
        VStack(spacing: 6) {
            AppIconView()
                .frame(width: 96, height: 96)

            Text(viewModel.getAppName())
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 6)

            Text("Version \(viewModel.getAppVersion())")
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updates")
                        Text("Last checked: \(viewModel.getFormattedLastChecked())")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .id(refreshTrigger) // Force refresh when this changes
                    }
                    .layoutPriority(1)
                    Spacer()
                    Button(viewModel.isCheckingUpdate ? "Checking\u{2026}" : "Check Now", action: viewModel.checkForUpdates)
                        .disabled(viewModel.isCheckingUpdate)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 12)
                linkRow("Source code on GitHub", url: repoURL)
                Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 12)
                linkRow("Release notes", url: repoURL.appendingPathComponent("releases"))
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.hoverFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .padding(.top, 18)

            if HistoryDecryptFailure.didFailOnThisLaunch {
                Text("Couldn't decrypt clipboard history on this launch. A new encryption key will be created when you next copy something. Past clips are unrecoverable on this device.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            Spacer(minLength: 12)
            Text("Made by jokot \u{00B7} MIT License")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(width: 340)
        .onAppear {
            startRefreshTimer()
        }
        .alert(item: $viewModel.updateAlert) { alert in
            var message = alert.message
            if let notes = alert.releaseNotes {
                message += "\n\nWhat's new:\n" + notes
            }
            if let url = alert.url {
                return Alert(
                    title: Text(alert.title),
                    message: Text(message),
                    primaryButton: .default(Text("Open Release")) { NSWorkspace.shared.open(url) },
                    secondaryButton: .cancel()
                )
            } else {
                return Alert(
                    title: Text(alert.title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private func linkRow(_ title: String, url: URL) -> some View {
        Button(action: { NSWorkspace.shared.open(url) }) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func startRefreshTimer() {
        // Refresh every 30 seconds to keep the "last checked" text current
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            refreshTrigger.toggle()
        }
        
        // Also refresh immediately on appear
        refreshTrigger.toggle()
    }
}

final class InfoWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = InfoView()
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "About MaClip"
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            // Match Settings window behavior: use floating level so order can change among app windows
            window.level = .floating
            self.window = window

            // Local monitor: catch Escape or Command+I while Info is key and close
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.window?.isKeyWindow == true else { return event }
                if event.keyCode == 53 {   // Escape
                    self.window?.close()
                    return nil
                }
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "i" {
                    self.window?.close()
                    return nil
                }
                return event
            }
        }
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

enum InfoWindow {
    private static var controller = InfoWindowController()
    static func show() { controller.show() }
}