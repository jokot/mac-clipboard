import SwiftUI
import AppKit

/// A dark message near the bottom of the screen, like the macOS volume display.
/// It does not take focus and does not catch clicks, so the frontmost app keeps
/// the keyboard.
@MainActor
final class ExtractToastWindow: ExtractToastPresenting {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ toast: ExtractToast) {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: ExtractToastView(toast: toast))
        panel.contentView = hosting
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 120,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        // A progress message stays until the result replaces it.
        guard !toast.isProgress else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}

private struct ExtractToastView: View {
    let toast: ExtractToast

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = toast.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.65))
                }
            }
            .fixedSize()
            Spacer(minLength: 4)
            statusIcon
        }
        .foregroundColor(.white)
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.11).opacity(0.95))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = toast.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "photo").foregroundColor(.white.opacity(0.65)))
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toast.style {
        case .progress:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle").foregroundColor(Theme.warning)
        case .error:
            Image(systemName: "exclamationmark.circle").foregroundColor(Color(red: 1, green: 0.41, blue: 0.38))
        }
    }
}
