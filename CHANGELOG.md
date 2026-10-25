# Changelog

All notable changes to MaClip. Versions 1.11.0 and later are written by
release-please from the commit messages.

## [2.0.0](https://github.com/jokot/mac-clipboard/compare/v1.13.1...v2.0.0) (2026-10-25)


### ⚠ BREAKING CHANGES

* redesign MaClip for 2.0 with a new app icon ([#31](https://github.com/jokot/mac-clipboard/issues/31))

### Features

* **clips:** preview a clip in full with the space bar ([#33](https://github.com/jokot/mac-clipboard/issues/33)) ([08e22f8](https://github.com/jokot/mac-clipboard/commit/08e22f8198d52004bd284270d78e337cbb200237))
* **clips:** redesign the clip window for 2.0 ([#32](https://github.com/jokot/mac-clipboard/issues/32)) ([dcfb19e](https://github.com/jokot/mac-clipboard/commit/dcfb19e7eb2d6457012ce14fdcfd9875c13c54e7))
* **editor:** redesign the image editor toolbar for 2.0 ([#35](https://github.com/jokot/mac-clipboard/issues/35)) ([a0181f0](https://github.com/jokot/mac-clipboard/commit/a0181f078f40fd37ba8a5b20b34ce70616bd562f))
* redesign MaClip for 2.0 with a new app icon ([#31](https://github.com/jokot/mac-clipboard/issues/31)) ([51125fc](https://github.com/jokot/mac-clipboard/commit/51125fc566da98f77838076b194a505f976d6d65))
* redesign the Accessibility prompt, the extract messages and About for 2.0 ([#36](https://github.com/jokot/mac-clipboard/issues/36)) ([8ebc06b](https://github.com/jokot/mac-clipboard/commit/8ebc06b25280f3ee8705e4dcc18a3958e8a49e14))
* **settings:** redesign the Settings window for 2.0 ([#34](https://github.com/jokot/mac-clipboard/issues/34)) ([004bccd](https://github.com/jokot/mac-clipboard/commit/004bccd86a09a08775bdd8927aae5bf80d4e6de0))

## [1.13.1](https://github.com/jokot/mac-clipboard/compare/v1.13.0...v1.13.1) (2026-10-25)


### Bug Fixes

* **links:** use https for a copied bare domain ([#28](https://github.com/jokot/mac-clipboard/issues/28)) ([1729fc1](https://github.com/jokot/mac-clipboard/commit/1729fc1b66fb969f81a3d782e6d0baba017f9d63))

## [1.13.0](https://github.com/jokot/mac-clipboard/compare/v1.12.1...v1.13.0) (2026-10-25)


### Features

* **extract:** paste the text or QR code of the last image with a shortcut ([#24](https://github.com/jokot/mac-clipboard/issues/24)) ([c7b089c](https://github.com/jokot/mac-clipboard/commit/c7b089c3311de09b7e318177c7f3f0f18b78638f))
* **paste:** ask for Accessibility access only when MaClip pastes ([#23](https://github.com/jokot/mac-clipboard/issues/23)) ([d275166](https://github.com/jokot/mac-clipboard/commit/d275166d8f087d1f3eb3310b7d46190e8f88385c))

## [1.12.1](https://github.com/jokot/mac-clipboard/compare/v1.12.0...v1.12.1) (2026-10-25)


### Bug Fixes

* **installer:** keep hidden DMG files away from the install steps ([4766ce2](https://github.com/jokot/mac-clipboard/commit/4766ce2576f207607bcd604e9d5b7c373d3e4c70))

## [1.12.0](https://github.com/jokot/mac-clipboard/compare/v1.11.0...v1.12.0) (2026-10-25)


### Features

* **privacy:** make history encryption optional and off by default ([9d1481a](https://github.com/jokot/mac-clipboard/commit/9d1481ac60495c4e2633a2ca747eb502de4b1e6c))


### Bug Fixes

* **installer:** show the install steps in the DMG window ([2ad0f3e](https://github.com/jokot/mac-clipboard/commit/2ad0f3e07a9635235476cd206a1389f4e94a7b67))

## [1.11.0](https://github.com/jokot/mac-clipboard/compare/v1.10.1...v1.11.0) (2026-10-22)

### Features

* **editor:** edit image clips. Right-click an image clip and choose **Edit…**. The editor opens in its own window.
* **editor:** crop, rotate 90° left or right, arrow, rectangle, oval, single-line text, freehand pen, and redact (opaque black box).
* **editor:** 8 color presets (toolbar or keys 1–8) and a stroke width from 1 to 12 pt.
* **editor:** undo with ⌘Z and redo with ⌘⇧Z, up to 20 steps. Esc during a drag cancels only that shape.
* **editor:** **Save** replaces the image and keeps the clip id and date. **Save as new** adds a new clip at the top. Both keep the concealed setting.
* **editor:** the overlay hides while the editor is open. On close, focus goes back to the previous app.
* **settings:** the default history limit is now 50 clips. A limit that you set before does not change.

### Bug Fixes

* **editor:** a failed save shows "Could not save image" and keeps the editor open with your edits.
* **row:** the clip preview updates immediately after an edit.

### Known limits

* Images larger than 4096 px on one side cannot be edited in this version.
* The app has an ad-hoc signature only. Gatekeeper can block it on first open. See the install steps in the [README](https://github.com/jokot/mac-clipboard#install).

## [1.10.1](https://github.com/jokot/mac-clipboard/compare/v1.10.0...v1.10.1) (2026-07-14)

- Edit a clip in place: right-click any text, URL, or file clip → **Edit…** to open an inline editor. Cancel (Esc) discards, Save (⌘↩) commits. The clip keeps its id, date, source app, concealed/OCR flags — only the content changes, and the leading tag icon re-detects (e.g. plain text → JSON swaps to `curlybraces`).
- Image clips are intentionally not editable in v1.10.1.
- Validation: URL edits require a scheme + host; file edits reject an empty list. Errors show inline in red without leaving edit mode.
- Smart quotes / dashes / auto-replacement are disabled inside the editor so JSON and code edits round-trip unchanged.
- Internals: version 1.10.1, build 14. `ClipboardItem` equality is now strict (id + content) so SwiftUI view diffing reflects edits; content-only dedup for new captures uses a separate `matchesContent(_:)` helper.

## [1.10.0](https://github.com/jokot/mac-clipboard/releases/tag/v1.10.0) (2026-05-18)

- File and folder clips: ⌘C on files or folders in Finder (or anywhere that writes file URLs to the pasteboard) is now captured as a new clip kind. The clip stores URLs only — no file contents are copied. Multi-selection becomes one clip showing `FirstFile +N more`.
- Row UI for file clips shows the file's actual icon (via `NSWorkspace.icon(forFile:)`) plus its name and parent directory. Stale clips (file deleted after capture) automatically swap to a `?` ghost icon.
- Right-click a file clip → unified menu with `Open`, `Reveal in Finder`, `Copy Path`, then the existing `Exclude "<App>"`. Same menu shape on all clip types now.
- Copy Path writes the file paths as text to the pasteboard and adds a new text clip with the original file clip's source attribution (typically Finder), instead of attributing it to whichever app happens to be frontmost.
- New `tag:file` search filter; free-text search also matches file paths.
- Internals: version 1.10.0, build 13.
