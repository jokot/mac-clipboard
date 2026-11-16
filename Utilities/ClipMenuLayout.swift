import Foundation

/// One item of the ⌘K menu of a clip. The clip window maps each entry to its action.
enum ClipMenuEntry: Equatable {
    case paste, copyOnly, preview
    case openLink, open, revealInFinder, copyPath
    case extractText, extractCode
    case showForFiveSeconds, notASecret
    case secret(SecretAction)
    case edit
    case excludeApp(String)
    case delete
    case separator

    /// The menu title. The title of `excludeApp` needs the app name, so the view makes it.
    var title: String {
        switch self {
        case .paste: return "Paste"
        case .copyOnly: return "Copy Only"
        case .preview: return "Preview"
        case .openLink: return "Open Link"
        case .open: return "Open"
        case .revealInFinder: return "Reveal in Finder"
        case .copyPath: return "Copy Path"
        case .extractText: return "Extract Text"
        case .extractCode: return "Extract Code"
        case .showForFiveSeconds: return "Show for 5 Seconds"
        case .notASecret: return "Not a Secret"
        case .secret(let action): return action.title
        case .edit: return "Edit\u{2026}"
        case .excludeApp: return "Don\u{2019}t Save Clips from App\u{2026}"
        case .delete: return "Delete"
        case .separator: return ""
        }
    }

    var key: KeyCombo? {
        switch self {
        case .paste: return KeyCombo(.returnKey)
        case .copyOnly: return .command("c")
        case .preview: return KeyCombo(.space)
        case .openLink, .open: return .command("o")
        case .revealInFinder: return .command("r")
        case .copyPath: return KeyCombo(.character("c"), [.option, .command])
        case .extractText: return .command("t")
        case .extractCode: return .command("b")
        case .showForFiveSeconds: return .command("u")
        case .edit: return .command("e")
        case .excludeApp: return KeyCombo(.delete, [.option, .command])
        case .delete: return KeyCombo(.delete, .command)
        case .notASecret, .secret, .separator: return nil
        }
    }
}

enum ClipMenuLayout {
    /// The ⌘K menu of a clip, in order.
    static func entries(for item: ClipboardItem) -> [ClipMenuEntry] {
        var entries: [ClipMenuEntry] = [.paste, .copyOnly, .preview]
        switch item.content {
        case .url: entries.append(.openLink)
        case .file: entries += [.open, .revealInFinder, .copyPath]
        case .image: entries += [.extractText, .extractCode]
        case .text: break
        }
        if item.isConcealed { entries.append(.showForFiveSeconds) }
        if let kind = item.secretKind {
            entries.append(.notASecret)
            if let text = item.secretText {
                let actions = SecretActions.actions(for: text, kind: kind)
                if !actions.isEmpty { entries += [.separator] + actions.map { .secret($0) } }
                entries.append(.separator)
            }
        }
        entries.append(.edit)
        entries.append(.separator)
        if let bundleID = item.sourceBundleID { entries += [.excludeApp(bundleID), .separator] }
        entries.append(.delete)
        return entries
    }
}

/// The buttons of the preview, left of Paste.
enum PreviewButton: Equatable {
    case edit, copyOnly, notASecret
    case secret(SecretAction)
}

enum PreviewButtons {
    static func buttons(for item: ClipboardItem, decodedJWT: Bool) -> [PreviewButton] {
        guard let kind = item.secretKind else { return [.edit, .copyOnly] }
        if kind == .jwt, decodedJWT { return [.secret(.copyJWTHeader), .secret(.copyJWTPayload)] }
        if kind == .privateKey, let text = item.secretText, PrivateKeyInspector.inspect(text)?.publicKeyLine != nil {
            return [.notASecret, .secret(.copyPublicKey)]
        }
        return [.notASecret, .copyOnly]
    }
}

extension ClipboardItem {
    /// The text that secret detection reads: the text of a text clip, or the link of a link clip.
    var secretText: String? {
        switch content {
        case .text(let text): return text
        case .url(let url): return url.absoluteString
        case .image, .file: return nil
        }
    }
}
