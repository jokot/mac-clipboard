# Changelog

All notable changes to MaClip. Versions 1.11.0 and later are written by
release-please from the commit messages.

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

* **editor:** CanvasView renders image + layers + drag drafts ([da37a68](https://github.com/jokot/mac-clipboard/commit/da37a681dc16553c822414e375953e2cfd73017c))
* **editor:** EditLayer/EditTool/StrokeStyle/ImageEditState types ([ba5bdba](https://github.com/jokot/mac-clipboard/commit/ba5bdba1d2884c4b2842f5d2d1a570898c51a081))
* **editor:** ImageCompositor renders layered PNG (TDD) ([b6f437e](https://github.com/jokot/mac-clipboard/commit/b6f437e7c57dab3c4d3ed1aff00dbe09f4177ed8))
* **editor:** ImageEditorSheet toolbar + canvas integration ([95ffd9d](https://github.com/jokot/mac-clipboard/commit/95ffd9dc2225ce217e2ed566f1711d1cc0437606))
* **editor:** ImageEditorViewModel undo/redo stack (TDD) ([b74652d](https://github.com/jokot/mac-clipboard/commit/b74652dc82211d45209a5fb9807517bb7087cd4d))
* **editor:** open the image editor in a separate window ([e2efe93](https://github.com/jokot/mac-clipboard/commit/e2efe939a02781981ae47b781ac622971f675bd3))
* **overlay:** present ImageEditorSheet + wire save handlers + 4096 guard ([2f872ca](https://github.com/jokot/mac-clipboard/commit/2f872cafee66816a8b5d2485ba5ad42328c18451))
* **overlay:** resizable window with persisted size in AppSettings ([a5db229](https://github.com/jokot/mac-clipboard/commit/a5db229056bb14d92fd6bac982d088499e0a7176))
* **repo:** deleteImage(at:) + saveImage(pngData:) for image edit flow ([2a5c824](https://github.com/jokot/mac-clipboard/commit/2a5c82484af8f085a8ca029671e916d823ad2ead))
* **row:** Edit… menu entry for image clips ([18a9949](https://github.com/jokot/mac-clipboard/commit/18a99494d434dac0ba94688f66f94c1902e8588d))
* **viewmodel:** insertImage + saveEditedImage for image edit flow (TDD) ([3c5357c](https://github.com/jokot/mac-clipboard/commit/3c5357c023c1a674c48516a9141fe76387b8a927))


### Bug Fixes

* **editor:** composite edits in top-left image space ([7f6c122](https://github.com/jokot/mac-clipboard/commit/7f6c122c7a1a7342e60ebb39220b5be2c3523c41))
* **editor:** handle save failure, Esc mid-drag, concealed copies ([2436839](https://github.com/jokot/mac-clipboard/commit/243683947fce68e79036d43f9eb56c8850f2cdcf))
* **editor:** show crop and rotation in the canvas, fix the text tool ([a21fff1](https://github.com/jokot/mac-clipboard/commit/a21fff16ae5e8288165ec650d422bc81065f5f2d))
* **overlay:** also remove resizeObserver on immediate-hide paths ([9f96120](https://github.com/jokot/mac-clipboard/commit/9f96120c37b49a678466952ac3d8d1bc813cc7ad))
* **row:** reload image preview when the clip file changes ([3e5b6bb](https://github.com/jokot/mac-clipboard/commit/3e5b6bbb56f76bcaae72f493ff4e3bd712557961))
* **tests:** isolate test storage from real user data ([737b087](https://github.com/jokot/mac-clipboard/commit/737b0879bb8985953f9e98b273017d866add0e58))


### Reverts

* **overlay:** make the overlay a fixed 520x600 window again ([b4d1c6e](https://github.com/jokot/mac-clipboard/commit/b4d1c6e5018bd61e74580a59accea9c1aa87abaa))

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
