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
            if let image = toast.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if toast.isProgress {
                ProgressView().controlSize(.small)
            }
            Text(toast.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.78))
        )
        .environment(\.colorScheme, .dark)
    }
}
