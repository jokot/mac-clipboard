import SwiftUI
import AppKit

struct InfoView: View {
    private let repoURL = URL(string: "https://github.com/jokot/mac-clipboard")!

    var body: some View {
        VStack(spacing: 16) {
            AppIconView()
                .frame(width: 128, height: 128)

            Text(appName())
                .font(.title3).bold()

            Text("Version \(appVersion())")
                .foregroundColor(.secondary)

            Button {
                NSWorkspace.shared.open(repoURL)
            } label: {
                Label("Open on GitHub", systemImage: "link")
            }
            .buttonStyle(.bordered)

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
    }

    private func appVersion() -> String {
        let dict = Bundle.main.infoDictionary
        let short = dict?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = dict?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func appName() -> String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "MacClipboard"
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
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "About MacClipboard"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.level = .modalPanel
            self.window = window
        }
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

enum InfoWindow {
    private static var controller = InfoWindowController()
    static func show() { controller.show() }
}


