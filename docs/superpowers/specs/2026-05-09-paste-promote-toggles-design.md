# Paste & Promote Selection Toggles — Design

**Date:** 2026-05-09
**Status:** Approved (pending implementation plan)
**Branch:** feature/optimize

## Summary

Add two user-toggleable settings that control behavior when an item is selected (clicked or Enter) from the MaClip overlay:

- `pasteOnClick` (default ON) — auto-paste the selected item into the previously focused app via synthesized ⌘V keystroke. When OFF, the item is written to the system pasteboard, the overlay closes, focus returns to the previous app, and the user pastes manually with ⌘V.
- `moveTopOnClick` (default ON) — promote the selected item to the top of the clipboard history list. When OFF, the item stays at its original index.

Both defaults match the current shipping behavior (1.5.0), so existing users see no change after upgrade. The feature mimics Windows clipboard behavior (Win+V) where these knobs are user-controlled.

## Motivation

- Users want the option to paste directly into the focused window on selection (Windows clipboard parity).
- Users want a stable, chronological history that does not reorder when older items are reused.
- Both behaviors are already wired in code but are unconditional today; this design exposes them as user preferences.

## Scope

**In scope:**
- Two persisted Bool settings in `AppSettings`
- Settings UI in `SettingsView` ("Behavior" GroupBox)
- Conditional branching in `OverlayWindow.onSelect`
- Monitor self-write dedupe via `ClipboardMonitor.ignoreCurrentChangeCount()` to prevent re-selecting an item from creating a duplicate history entry

**Out of scope:**
- Paste-keystroke reliability tweaks (event source, inter-key delays, fallback timeouts)
- Per-item override of either toggle
- Keyboard shortcut to toggle paste-on-click at runtime

## Architecture

No new types, services, or modules. The change is additive across existing files:

| File | Change |
|------|--------|
| `Models/AppSettings.swift` | Add 2 `@Published` Bool properties + Keys + init defaults |
| `Views/SettingsView.swift` | New "Behavior" GroupBox with 2 toggles + caption text |
| `App/OverlayWindow.swift` | `onSelect` closure branches on `AppSettings.shared` flags |
| `Services/ClipboardMonitor.swift` | Add protocol method + impl: `ignoreCurrentChangeCount()` |
| `ViewModels/ClipboardListViewModel.swift` | Call `monitor.ignoreCurrentChangeCount()` at end of `setPasteboard(to:)` |

`OverlayWindowController` already has both `hideImmediatelyAndPaste()` and `hideImmediatelyRefocusOnly()`. `AppFocusService` already has both `switchToAppAndPaste(_:)` and `switchToAppOnly(_:)`. No extraction required.

## Data Flow

Select event (click or Enter):

```
User selects item
  └─► OverlayWindow.onSelect(item)
        ├─► viewModel.setPasteboard(to: item)
        │     ├─► writes to NSPasteboard
        │     └─► monitor.ignoreCurrentChangeCount()    ← prevents dup capture
        │
        ├─► if AppSettings.shared.moveTopOnClick:
        │     viewModel.promote(item)
        │
        └─► if AppSettings.shared.pasteOnClick:
              autoPastePending = true
              hideImmediatelyAndPaste()       ← existing path
            else:
              autoPastePending = false
              hideImmediatelyRefocusOnly()    ← existing path
```

## Components

### `Models/AppSettings.swift`

```swift
@Published var pasteOnClick: Bool {
    didSet { UserDefaults.standard.set(pasteOnClick, forKey: Keys.pasteOnClick) }
}
@Published var moveTopOnClick: Bool {
    didSet { UserDefaults.standard.set(moveTopOnClick, forKey: Keys.moveTopOnClick) }
}

private struct Keys {
    // ...existing keys
    static let pasteOnClick = "settings.pasteOnClick"
    static let moveTopOnClick = "settings.moveTopOnClick"
}

// In init():
let initialPasteOnClick = defaults.object(forKey: Keys.pasteOnClick) as? Bool ?? true
let initialMoveTopOnClick = defaults.object(forKey: Keys.moveTopOnClick) as? Bool ?? true
self.pasteOnClick = initialPasteOnClick
self.moveTopOnClick = initialMoveTopOnClick
```

Defaults via `defaults.object(forKey:) as? Bool ?? true` so an absent key yields `true`. Required: `defaults.bool(forKey:)` returns `false` for absent keys, which would silently flip behavior on first launch.

### `Services/ClipboardMonitor.swift`

```swift
protocol ClipboardMonitorProtocol {
    // ...existing
    func ignoreCurrentChangeCount()
}

// in ClipboardMonitor:
func ignoreCurrentChangeCount() {
    lastChangeCount = NSPasteboard.general.changeCount
}
```

### `ViewModels/ClipboardListViewModel.swift`

At the end of `setPasteboard(to:)` — after writing the item to `NSPasteboard.general`:

```swift
monitor.ignoreCurrentChangeCount()
```

### `App/OverlayWindow.swift`

`onSelect` closure replaced:

```swift
let content = ContentView(viewModel: viewModel, onSelect: { [weak self] item in
    guard let self else { return }
    self.viewModel.setPasteboard(to: item)
    if AppSettings.shared.moveTopOnClick {
        self.viewModel.promote(item)
    }
    if AppSettings.shared.pasteOnClick {
        self.autoPastePending = true
        self.hideImmediatelyAndPaste()
    } else {
        self.autoPastePending = false
        self.hideImmediatelyRefocusOnly()
    }
}, onOpenSettings: { [weak self] in
    self?.openSettings()
})
```

### `Views/SettingsView.swift`

New "Behavior" GroupBox added near existing groups (placement matches existing visual style):

```swift
GroupBox("Behavior") {
    VStack(alignment: .leading, spacing: 12) {
        Toggle("Paste on selection", isOn: $settings.pasteOnClick)
        Text("Automatically paste to the previous app when selecting an item.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading, 24)

        Toggle("Move item to top on selection", isOn: $settings.moveTopOnClick)
        Text("When selecting an item, move it to the top of the history list.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading, 24)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

## Edge Cases

1. **Both toggles OFF** — item written to pasteboard, overlay closes, prev app refocused, history unchanged. User has clipboard ready, manually pastes. Valid state.
2. **First-launch defaults** — both default ON; behavior identical to current shipping app. No regression.
3. **Self-write dedupe** — `monitor.ignoreCurrentChangeCount()` called synchronously after pasteboard write. Polling timer's next tick reads `lastChangeCount == NSPasteboard.general.changeCount`, skips emission. Safe.
4. **Image items + paste OFF** — image written to pasteboard same as text; ⌘V manually works in apps that accept image paste. No code-path difference.
5. **No previous app to refocus** — `switchToAppOnly` already handles via `cleanup()` + `app.activate`; if no app tracked, the existing no-op path applies.
6. **Toggle changed while overlay open** — `AppSettings.shared` read at the moment of select; latest value wins. No stale capture.

## Error Handling

No new failure modes. UserDefaults read/write for Bool is infallible. No new I/O, no new async work. Existing paste/refocus error handling unchanged.

## Testing

### Unit tests

1. **`AppSettingsTests`** (new file)
   - Default values: with cleared UserDefaults, `pasteOnClick == true` and `moveTopOnClick == true`
   - Persistence: setting each property writes the correct UserDefaults key
   - Round-trip: write key → re-init `AppSettings` → reads back same value

2. **`ClipboardListViewModelTests`** (extend)
   - `setPasteboard(to:)` calls `monitor.ignoreCurrentChangeCount()` exactly once
   - Use mock `ClipboardMonitorProtocol` with a call counter

3. **`ClipboardMonitorTests`** (extend, if file exists; otherwise add)
   - `ignoreCurrentChangeCount()` updates internal `lastChangeCount` to `NSPasteboard.general.changeCount`
   - After `ignoreCurrentChangeCount()`, the next `pollPasteboard` (with no external change) emits no item

### Manual QA checklist

| Scenario | Expected |
|---|---|
| Both toggles ON, click item | Pastes into prev app, item moves to top |
| Both toggles ON, Enter key | Same as click |
| pasteOnClick OFF, move ON, click | Overlay closes, item at top, prev app focused, ⌘V pastes |
| pasteOnClick ON, move OFF, click | Pastes into prev app, item stays at original index |
| Both OFF, click | Overlay closes, prev app focused, item at original index, ⌘V pastes |
| Re-select older item | History contains no duplicate |
| Toggle settings, restart app | Toggles persist |
| Toggle while overlay open, then select | Latest value applied |

UI/window/focus behavior is exercised through manual QA; `OverlayWindow.onSelect` branching is not unit-tested directly because it depends on AppKit window state.

## Migration / Rollout

- Existing users: keys absent on first launch after upgrade → defaults applied (both true) → identical behavior to 1.5.0.
- No data migration required.
- No version bump required by the design itself; coordinate with release process.

## Open Questions

None.
