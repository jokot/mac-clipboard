import AppKit

/// Runs a secret action of ⌘K or of the preview. A copy action keeps the clip window open,
/// as Copy Path does.
@MainActor
enum SecretActionRunner {
    static func run(_ action: SecretAction, on item: ClipboardItem, viewModel: ClipboardListViewModel) {
        guard let kind = item.secretKind, let text = item.secretText else { return }
        switch action {
        case .decodeJWT:
            NotificationCenter.default.post(name: .overlayDecodeJWT, object: item.id)
        case .saveKeyFile:
            saveKeyFile(from: text)
        case .openKeyPage(_, let url):
            NSWorkspace.shared.open(url)
            NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
        default:
            guard let result = SecretActions.copyText(for: action, text: text, kind: kind) else {
                NSSound.beep()
                return
            }
            viewModel.copySecretResult(result, from: item, holdsSecret: action.holdsSecret)
        }
    }

    /// A save panel in `~/.ssh`. The file gets permission 600.
    private static func saveKeyFile(from text: String) {
        guard let info = PrivateKeyInspector.inspect(text) else { return }
        let panel = NSSavePanel()
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.nameFieldStringValue = info.fileName
        panel.showsHiddenFiles = true
        panel.canCreateDirectories = true
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PrivateKeyFile.write(info.keyBlock, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "The key was not saved"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
