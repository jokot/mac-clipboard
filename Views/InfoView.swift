import SwiftUI
import AppKit

struct InfoView: View {
    @StateObject private var viewModel = InfoViewModel()
    private let repoURL = URL(string: "https://github.com/jokot/mac-clipboard")!

    var body: some View {
        VStack(spacing: 16) {
            AppIconView()
                .frame(width: 128, height: 128)

            Text(viewModel.getAppName())
                .font(.title3).bold()

            Text("Version \(viewModel.getAppVersion())")
                .foregroundColor(.secondary)

            Text("Last checked: \(viewModel.getFormattedLastChecked())")
                .font(.footnote)
                .foregroundColor(.secondary)

            Button {
                NSWorkspace.shared.open(repoURL)
            } label: {
                Label("Open on GitHub", systemImage: "link")
            }
            .buttonStyle(.bordered)

            Button(action: viewModel.checkForUpdates) {
                if viewModel.isCheckingUpdate {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking…")
                    }
                } else {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(viewModel.isCheckingUpdate)
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 8)
            Divider()
            HStack(spacing: 6) {
                Text("Made with")
                Image(systemName: "heart.fill")
                    .foregroundColor(.pink)
                Text("by jokot")
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(minWidth: 360)
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
}

struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .inset(by: 8)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 2)

            Image(systemName: "doc.on.clipboard.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(28)
        }
    }
}

final class InfoWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = InfoView()
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
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