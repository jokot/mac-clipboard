# Changelog

All notable changes to MaClip. Versions 1.11.0 and later are written by
release-please from the commit messages.

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
