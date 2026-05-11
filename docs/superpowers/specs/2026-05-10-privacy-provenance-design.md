# Privacy & Provenance (1.7.0) — Design

**Date:** 2026-05-10
**Status:** Approved (pending implementation plan)
**Target version:** 1.7.0 (build 8)
**Branch:** feature/privacy-provenance

## Summary

Three coordinated features united by a single narrative: **MaClip captures and surfaces _where_ clips come from, and refuses to capture clips its user shouldn't see.**

| Feature | Code | Purpose |
|---|---|---|
| **Source provenance** | I3 | Capture frontmost app's bundle ID at copy time; show its icon in each clipboard row; let users filter via `from:` search syntax. |
| **App exclusion list** | P1 | User-managed list of bundle IDs whose copies are never ingested. Seeded with common password managers + MaClip itself. Right-click an existing clip to add its source app, with optional retroactive purge. |
| **Concealed-type handling** | P2 | Detect `org.nspasteboard.ConcealedType` and `com.apple.is-sensitive` UTIs. Default behavior: ingest with redacted preview and auto-clear after a configurable timeout (default 5 min). Opt-in to skip ingestion entirely. |

All three share `ClipboardMonitor.pollPasteboard()` plumbing — they touch the same code path that decides "should this pasteboard event become a history item?" Bundling them as one release keeps the monitor change coherent.

## Wedge / Positioning

This release is the first concrete step in MaClip's competitive positioning: **private + intelligent local clipboard**. Privacy is the non-negotiable foundation; provenance is the first piece of intelligence. Future releases (1.8.0 smart tags, 1.9.0 encryption at rest, eventually on-device LLM transforms) build on this foundation. All processing remains on-device; no cloud, no telemetry, no network egress.

## Scope

**In scope:**
- New persisted fields on `ClipboardItem`: `sourceBundleID`, `isConcealed`, `concealedExpiresAt`
- Frontmost-app capture in `ClipboardMonitor.pollPasteboard()`
- Concealed UTI detection in monitor
- Exclusion list stored in UserDefaults; seeded with default password managers + self
- Settings UI: new "Privacy" GroupBox containing exclusion list manager + concealed-items toggle + auto-clear timeout picker
- Overlay row UI: 16×16 source icon corner; placeholder for nil source; redacted preview + lock + countdown badge for concealed items
- Right-click clipboard row → "Exclude [App]" → confirm dialog with optional retroactive purge
- Search filter syntax: `from:Safari` filters by display name
- Background timer that purges expired concealed items
- Settings window height bump 400 → 520pt

**Out of scope (deferred):**
- Encryption at rest (planned for 1.9.0)
- Smart auto-tagging by content (planned for 1.8.0)
- TouchID / biometric gate on concealed items (revisit during 1.9.0 encryption work)
- Configurable concealed-clear timer per-item (use single global setting in 1.7.0)
- Auto-detect installed password managers ("suggested exclusions" panel) — defer to 1.7.x
- Migrating existing legacy clips to add source data — they remain `sourceBundleID = nil`

## Architecture

Additive across existing files plus one new helper. No new services. No new modules.

| File | Change |
|------|--------|
| `Models/ClipboardItem.swift` | Add 3 optional fields; update `Codable` to default-decode legacy items |
| `Models/AppSettings.swift` | Add `excludedBundleIDs: [String]`, `skipConcealedItems: Bool`, `concealedClearTimeout: TimeInterval` |
| `Services/ClipboardMonitor.swift` | Capture frontmost bundle ID; check exclusion + concealed UTIs before emit |
| `ViewModels/ClipboardListViewModel.swift` | Background timer for concealed expiry; bundle-ID-based purge helper for retroactive removal |
| `Views/Components/ClipboardItemRow.swift` | 16×16 source icon + tooltip; concealed redaction + lock + countdown |
| `Views/SettingsView.swift` | New "Privacy" GroupBox; bump window height |
| `Views/ContentView.swift` | Search field placeholder hint; `from:` syntax parsing in `filteredItems` |
| `Utilities/AppMetadata.swift` (new) | Helpers: resolve bundle ID → `NSImage` icon + display name; cache results |

`AppFocusService` and `PasteUtility` are unchanged.

## Data Model

### `ClipboardItem` additions

```swift
struct ClipboardItem: Codable, Identifiable, Equatable {
    // ...existing fields
    let sourceBundleID: String?         // nil for legacy items, system events, MaClip self-writes
    let isConcealed: Bool               // false for legacy
    let concealedExpiresAt: Date?       // nil unless isConcealed && skipConcealedItems == false
}
```

`Codable` decoding uses default values when keys are absent so existing JSON history loads cleanly:

```swift
init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // ...existing decodes
    self.sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
    self.isConcealed = try c.decodeIfPresent(Bool.self, forKey: .isConcealed) ?? false
    self.concealedExpiresAt = try c.decodeIfPresent(Date.self, forKey: .concealedExpiresAt)
}
```

### `AppSettings` additions

```swift
@Published var excludedBundleIDs: [String]         // persisted as JSON-encoded [String] in UserDefaults
@Published var skipConcealedItems: Bool            // default false; toggle in Privacy section
@Published var concealedClearTimeout: TimeInterval // default 300 (5 min); range 30…1800
```

UserDefaults keys:
- `settings.excludedBundleIDs` — `[String]` via JSONEncoder/Decoder for array persistence
- `settings.skipConcealedItems` — `Bool`, default `false` (uses `?? false` pattern)
- `settings.concealedClearTimeout` — `Double`, default `300`

**Default seed for `excludedBundleIDs`** (applied only on first launch when key absent):
```
com.agilebits.onepassword7
com.1password.1password
com.bitwarden.desktop
com.apple.keychainaccess
com.dashlane.dashlanephonefinal
com.lastpass.LastPassMacDesktop
com.jokot.MacClipboard         // self
```

If the user clears the list to empty, an explicit empty array is persisted; we never re-seed.

## Capture Flow (ClipboardMonitor)

Pseudocode for the new `pollPasteboard()`:

```
let pb = NSPasteboard.general
guard pb.changeCount != lastChangeCount else { return }
lastChangeCount = pb.changeCount

let frontmost = NSWorkspace.shared.frontmostApplication
let sourceBundleID = frontmost?.bundleIdentifier

// 1. Self-capture guard (belt + suspenders against ignoreCurrentChangeCount race)
if sourceBundleID == "com.jokot.MacClipboard" { return }

// 2. Exclusion list
if let id = sourceBundleID,
   AppSettings.shared.excludedBundleIDs.contains(id) {
    return
}

// 3. Concealed UTI detection (before reading any data)
let concealedUTIs: Set<String> = [
    "org.nspasteboard.ConcealedType",
    "org.nspasteboard.AutoGeneratedType",
    "com.apple.is-sensitive",
]
let isConcealed = pb.types?.contains { type in
    concealedUTIs.contains(type.rawValue)
} ?? false

if isConcealed && AppSettings.shared.skipConcealedItems {
    return  // user opted to skip entirely
}

// 4. Read content as today (image / URL / text in priority order)
guard let content = readContent(from: pb) else { return }

let expiry: Date? = isConcealed
    ? Date().addingTimeInterval(AppSettings.shared.concealedClearTimeout)
    : nil

let item = ClipboardItem(
    id: UUID(),
    date: Date(),
    content: content,
    sourceBundleID: sourceBundleID,
    isConcealed: isConcealed,
    concealedExpiresAt: expiry
)

subject.send(item)
```

## Concealed-Item Lifecycle

1. **Ingest** with `isConcealed = true` and `concealedExpiresAt = now + concealedClearTimeout`.
2. **Render** in row with redacted preview (`••••••`, length-preserving up to 8 chars), small lock SF Symbol, and countdown badge showing remaining seconds (updates every 5 s).
3. **Paste** behaves identically to any other clip — click writes real content to pasteboard, runs `setPasteboard(to:)` flow. Redaction is purely visual.
4. **Expire**: a timer in `ClipboardListViewModel` runs every 30 s scanning `items` for `isConcealed == true && concealedExpiresAt <= now`, removes them from the in-memory list, and calls `repository.saveToDiskAsync(items: items)`. The system pasteboard is **not** touched (would break user's current ⌘V intent).
5. **Quit-time persistence**: concealed items past their expiry are dropped from save on quit.

## Exclusion-List UX

### Settings → Privacy → Excluded Apps

```
+- Privacy ----------------------------------------+
|  Excluded Apps                                   |
|  +--------------------------------------------+  |
|  | [icon] 1Password 7         (com.agile...7) - |
|  | [icon] Bitwarden           (com.bitwa...op)- |
|  | [icon] MaClip              (com.jokot...rd)- |
|  | ...                                        |  |
|  +--------------------------------------------+  |
|  + Add Application...                            |
|  Clips copied from these apps will never be saved|
|  to your history.                                |
|                                                  |
|  Skip concealed clipboard items     [ off / on ] |
|  Auto-clear concealed items after   [ 5 min  v ] |
|  Items marked as secret by apps like 1Password   |
|  are kept with redacted preview, then removed    |
|  automatically. Turn on to skip them entirely.   |
+--------------------------------------------------+
```

- "Auto-clear" picker disabled (greyed out) when "Skip concealed" toggle is on.
- Picker options: 30 s, 1 min, 2 min, 5 min, 10 min, 15 min, 30 min.
- `+ Add Application…` opens `NSOpenPanel` scoped to `/Applications` (and `~/Applications`); selected `.app` bundle's `Bundle(url:)?.bundleIdentifier` is appended to the list.

### Right-click on a clip in overlay

Context menu adds: `Exclude "Safari" from history` (using resolved display name).

Selecting it opens a confirm dialog:

```
Exclude Safari from history?

MaClip will no longer save clips copied from Safari.
You can re-enable this later in Settings -> Privacy.

  [x] Also remove 17 existing Safari clips from history
                              [Cancel]  [Exclude]
```

Checkbox defaults checked. On confirm:
1. Append bundle ID to `excludedBundleIDs`.
2. If checkbox checked: filter `items` removing matching `sourceBundleID`, save disk.

The same dialog fires when adding via Settings `+ Add Application…` if the picked app has any matching clips in history (count is computed at dialog-open time).

### Disabled action

If the clipboard row has `sourceBundleID == nil`, the right-click "Exclude" item is disabled (greyed; tooltip "Source unknown for this clip").

## Provenance UI in Overlay Row

Layout (left → right):
```
[ content preview ............................ ] [ icon ]
```

- 16×16 trailing-aligned, 4pt right padding, vertically centered against row content
- Resolved via `AppMetadata.icon(for: bundleID)` (cached per bundle ID; `NSWorkspace.shared.icon(forFile: appURL.path)`)
- Tooltip: display name resolved via `Bundle(url:)?.localizedInfoDictionary?["CFBundleDisplayName"]` with fallbacks
- For nil source: SF Symbol `questionmark.app.dashed` rendered at 16pt; tooltip "Unknown source"
- Concealed item: lock SF Symbol replaces source icon position; source icon moves slightly left **and** redaction overlay sits on text preview

## Search-Syntax Filter

`ClipboardListViewModel.filteredItems` is extended:

```
input: "hello"             -> text contains "hello" (existing)
input: "from:Safari"       -> sourceBundleID resolves to display name containing "Safari"
input: "from:Safari hello" -> AND of both
input: "from:com.apple.Safari" -> exact bundle ID match (if input contains a dot)
```

Parsing:
- Tokenize on whitespace.
- Tokens starting with `from:` produce a source filter; remainder are textual filters.
- Multiple `from:` tokens OR'd together; all-text tokens AND'd.
- Display-name match is case-insensitive substring; bundle-ID-shaped tokens (contain ".") match exact `sourceBundleID`.

Search-field placeholder: `Search… (try "from:Safari")`.

## Migration

Existing JSON history files load through the updated `Codable` init; missing keys default to `nil` / `false`. No migration script needed; first save after upgrade rewrites the file with the new fields populated for legacy items as `null`. Reverting to 1.6.0 is **not** supported (1.6.0 ignores unknown keys via `decodeIfPresent` patterns already, but new fields would be silently lost on save — document in CHANGELOG).

## Edge Cases

1. **`NSWorkspace.frontmostApplication` returns nil** during system events (e.g. login, app launch transitions): `sourceBundleID = nil`, item still ingests with placeholder UI. Acceptable.
2. **Frontmost is MaClip itself** (e.g. user copies from search field inside the overlay): explicit guard skips ingest. Belt + suspenders alongside `ignoreCurrentChangeCount()` from 1.6.0.
3. **App uninstalled after capture**: bundle ID still stored; `Bundle(url:)` lookup returns nil; UI falls back to placeholder icon and "Unknown app (com.foo.bar)" tooltip.
4. **Bundle ID lookup fails for `+ Add Application…`** (e.g. user picks a non-`.app` file): show error alert, do not append. No partial state.
5. **Excluded app's bundle ID changes** (rare; e.g. 1Password 7 → 8 rebrand): user must add new ID. Acceptable.
6. **Concealed item's expiry passes while overlay is open**: timer removes it from the list, SwiftUI animates removal. If the item was selected, selection moves to next.
7. **Concealed item paste (item still in history)**: behaves like any normal paste — `setPasteboard(to:)` writes real content, redaction is preview-only.
8. **Concealed item paste after expiry**: item is gone from history before user can click. No special UI.
9. **Toggle "Skip concealed" ON while concealed items exist**: no retroactive purge; existing concealed items continue their auto-clear lifecycle. Setting only affects future captures.
10. **Concealed UTI on an image**: same flow — image ingests with `isConcealed=true`, preview shows lock placeholder over thumbnail.
11. **User picks the same app twice for exclusion**: dedup on insert (Set-style).

## Error Handling

No new I/O failure modes:
- UserDefaults reads/writes are infallible.
- Bundle / icon lookups return optional; UI falls back to placeholder.
- Concealed-clear timer running while app launches another app does not race with monitor (both on main).
- Self-capture guard runs before any data read so a runaway loop cannot occur.

## Settings Window Height

Adding the Privacy GroupBox + the existing Behavior GroupBox (1.6.0) makes the window cramped at 400pt. Bump `SettingsWindowController` `contentRect.height` from 400 → 520. No layout changes elsewhere; `Spacer()` and Action Buttons still pin to the bottom.

## Testing

### Unit tests

1. **`ClipboardItemTests`** (new)
   - Decode JSON without new keys → defaults applied (`sourceBundleID == nil`, `isConcealed == false`, `concealedExpiresAt == nil`)
   - Encode + decode round-trip with all fields populated
   - Encode + decode round-trip with concealed expiry past → still decodes (purge happens at runtime, not in codec)

2. **`AppSettingsTests`** (extend)
   - Default `excludedBundleIDs` on first launch contains seed list
   - Default `skipConcealedItems == false`
   - Default `concealedClearTimeout == 300`
   - Persistence round-trip for all three new properties

3. **`ClipboardMonitorTests`** (new or extend)
   - Self-capture guard: when frontmost reports MaClip's bundle ID → no emit (use a stub `NSWorkspace` indirection)
   - Excluded bundle ID → no emit
   - Concealed UTI present, `skipConcealedItems == true` → no emit
   - Concealed UTI present, `skipConcealedItems == false` → emit with `isConcealed == true` and expiry ≈ now + timeout
   - Normal capture sets `sourceBundleID` from frontmost

4. **`ClipboardListViewModelTests`** (extend)
   - Background timer removes concealed items past expiry
   - Filter `from:Safari` returns items whose source bundle resolves to a name containing "Safari"
   - Filter `from:com.apple.Safari` matches exact bundle ID
   - Combined `from:Safari hello` AND'd
   - `purgeItems(matchingBundleID:)` helper removes correct rows and saves

5. **`AppMetadataTests`** (new)
   - Bundle ID → display name resolution returns expected value for known system apps (`com.apple.Safari`, `com.apple.TextEdit`)
   - Unknown bundle ID returns nil
   - Cache hits second call (verify via spy on `NSWorkspace`)

### Manual QA matrix

| # | Scenario | Expected |
|---|---|---|
| 1 | Copy from TextEdit, open overlay | Row shows TextEdit icon at right; tooltip "TextEdit" |
| 2 | Copy from a Settings exclusion (e.g. add `com.apple.TextEdit`, copy from TextEdit) | Item never appears in history |
| 3 | Right-click an existing clip → "Exclude TextEdit"; confirm with checkbox checked | Existing TextEdit clips removed; bundle ID added to Settings list |
| 4 | Same as #3 but uncheck the box | Existing TextEdit clips remain; future TextEdit clips blocked |
| 5 | Copy a password from 1Password 8 (it sets ConcealedType) | If toggle OFF (default): row shows redacted ••••••, lock icon, ~5min countdown; click pastes real password into prev app. If toggle ON: never appears in history |
| 6 | Concealed item expires while overlay open | Row animates out; selection moves to next item |
| 7 | Search `from:Safari` | Only Safari-sourced clips shown |
| 8 | Search `from:Safari hello` | Safari-sourced clips containing "hello" |
| 9 | Search `from:com.apple.Safari` | Same as #7 (exact bundle match) |
| 10 | Upgrade from 1.6.0 with existing history | All legacy clips render with placeholder source icon + "Unknown source" tooltip |
| 11 | Quit and relaunch with seeded exclusions | Settings list shows seed bundle IDs |
| 12 | Remove all exclusions, quit, relaunch | List remains empty (no re-seed) |
| 13 | `+ Add Application…` pick non-app file | Error alert, no list change |
| 14 | Right-click clip with nil sourceBundleID | "Exclude" menu item disabled |
| 15 | Toggle "Skip concealed" ON while concealed item is in history | Existing concealed item still auto-clears normally; future concealed items skipped |
| 16 | Settings window opens at 520pt | All Privacy + Behavior + Storage + Display + Hotkey sections + Action Buttons fully visible without scroll |

## Migration / Rollout

- 1.6.0 → 1.7.0: existing JSON loads via `decodeIfPresent`; new fields default; first save rewrites with `null` source for legacy items. No user action.
- 1.7.0 ships seed exclusion list on first launch when the key is absent.
- Document in CHANGELOG: forward-incompatible JSON (downgrades to 1.6.0 lose new fields silently).
- Bump version to `1.7.0` (build `8`).

## Open Questions

None.
