MaClip
================

<p align="center">
  <img src="assets/maclip-icon.svg" alt="MaClip icon" width="160" height="160" />
</p>

A simple macOS clipboard history app built with SwiftUI.

## Download

- [Download the latest release](https://github.com/jokot/mac-clipboard/releases/latest)
- [Changelog](CHANGELOG.md)

## Preview
![macclip-screenshot.png](https://github.com/user-attachments/assets/4044711e-39c0-4d71-9eea-989855fc919c)

### Copy Clipboard Demo
https://github.com/user-attachments/assets/55cb6c86-be5d-4175-98f1-ddbddc5ded3d

## Features
- Captures copied text and images
- Extract text from images (OCR) and detect barcodes/QR codes
- Global hotkey Command+Control+V to toggle a floating window
- Click any entry to copy it back to the pasteboard
- Search clipboard history (text) — use Command+F to focus the search field
- Quit from overlay header or menu bar icon
- Command+, opens Settings when overlay is visible; Settings also available in menu bar
- Theme selection: System / Light / Dark (via Settings)
- Customizable global hotkey (changeable in Settings)
- Keyboard navigation in overlay: ↑/↓ to move, Return to select, Esc to close
- Status bar menu: quick access to Show Clipboard, Settings, and Quit
- About/Info window with version details and GitHub link
- Clear All History action
- Persistent clipboard history on disk (JSON metadata + image files), async saving, and auto-save on changes and on quit
- Empty state view when no items match your filter
- Returns focus to the previously active window when closing the overlay
- In-app update checking (Info screen), shows latest version and last-checked time

## Usage

1. Press <kbd>CONTROL (⌃)</kbd> + <kbd>COMMAND (⌘)</kbd> + <kbd>V</kbd> to show the MaClip overlay, or click the menu bar icon.
2. Type in the Search field to filter your clipboard history.
3. Select an item to copy it back to the clipboard:
   - Press <kbd>ENTER</kbd> to copy the highlighted item and close the overlay.
   - Click an item to copy it and close the overlay.
4. Navigate the list with <kbd>↑</kbd>/<kbd>↓</kbd> arrow keys.
5. Press <kbd>ESC</kbd> to close the overlay.
6. Remove a single item: hover over it and click the trash button.
7. Clear all history: click the trash button in the header and confirm.
8. Open Settings: press <kbd>COMMAND (⌘)</kbd> + <kbd>,</kbd> while the overlay is visible, or choose "Settings…" from the menu bar icon.
9. Customize behavior in Settings: change the global hotkey, switch theme (System/Light/Dark), and adjust storage limits.
10. Open About: click the info button in the overlay header to view version details and a GitHub link.

## Build from source
1. Ensure you have Xcode and Homebrew installed.
2. Install XcodeGen if needed and generate the Xcode project:

   ```bash
   brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
   xcodegen generate
   open MacClipboard.xcodeproj
   ```

3. Select the "MacClipboard" scheme and run. (Display name appears as "MaClip".)

## Running Tests

To run the unit tests from the command line:

```bash
# Run all tests
xcodebuild -scheme MacClipboard -destination 'platform=macOS' test

# Run quietly (less verbose output)
xcodebuild -scheme MacClipboard -destination 'platform=macOS' -quiet test

# Run specific test class
xcodebuild -scheme MacClipboard -destination 'platform=macOS' -only-testing:MacClipboardTests/ClipboardListViewModelTests test
```

You can also run tests directly in Xcode using `Cmd+U` or through the Test Navigator.

The test suite includes:
- **ClipboardListViewModelTests**: MVVM behavior, item management, and persistence
- **InfoViewModelTests**: Update checking logic 
- **HotkeyUtilsTests**: Hotkey description formatting
- **TextPreviewTests**: Text truncation utilities
- **URLUtilsTests**: URL utilities coverage

## Data Persistence

MaClip implements comprehensive persistence for both text and image clipboard entries:

### Storage Location
- **Base directory**: `~/Library/Application Support/MaClip/`
- **Metadata**: `history.json` stores clipboard entry references and metadata
- **Images**: PNG files stored in `Images/` subdirectory, named by UUID (e.g., `{uuid}.png`)

### Data Model
Each clipboard entry (`ClipboardItem`) contains:
- `id`: Unique UUID identifier
- `date`: Timestamp when copied
- `content`: Either `.text(String)` or `.image(NSImage)`

### Persistence Workflow
- **Saving**: Items are converted to JSON records with image references. Images are saved as PNG files separately.
- **Loading**: At startup, metadata is read from JSON and images are reconstructed from PNG files. Missing image files are gracefully skipped.
- **Timing**: Data is saved synchronously on app termination and asynchronously on list changes (new items, promotions, deletions, etc.).

### Data Management
- **Deduplication**: Prevents duplicate entries by comparing text strings or PNG data bytes
- **Retention**: Configurable max items limit with automatic truncation
- **Auto-cleanup**: Removes items older than 7 days during new item insertion
- **Atomic writes**: Reduces risk of corrupted files during save operations

*Implementation files: `ClipboardRepository.swift`, `ClipboardItem.swift`, `ClipboardListViewModel.swift`, `ClipboardMonitor.swift`*

## Notes
- The app uses Carbon's RegisterEventHotKey API, so no special permissions are required for the global hotkey.
- The app is not sandboxed and is intended for personal use/development. For Mac App Store distribution, additional work is required.

## Packaging (DMG + checksum)

CI builds the release DMG. See "Releases" in [CONTRIBUTING.md](CONTRIBUTING.md). Every PR to `main` also builds a DMG and attaches it to the workflow run as the `MacClip-dmg` artifact.

To build the same DMG on your Mac:

```bash
scripts/release/build-dmg.sh 1.11.0
```

The script builds the Release configuration into `build/` with an ad-hoc signature. It stops when the version you give does not match `MARKETING_VERSION` in `project.yml`. It writes `dist/MacClip-<version>.dmg` and `dist/MacClip-<version>.dmg.sha256`. It installs `create-dmg` with Homebrew when it is missing.

### Packaging notes
- The DMG window opens for a short time during the build. This is expected. The `--app-drop-link` option adds the Applications shortcut for drag-to-install.
- The app is not signed with a Developer ID, so Gatekeeper can block it on other Macs. For wide distribution, sign and notarize the app.

### Verify checksum
Put the `.dmg` and the `.sha256` file in the same folder, then run:

```bash
shasum -a 256 -c MacClip-*.dmg.sha256
```

The output ends with `OK` when the file is correct.

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on fixing bugs and proposing new features.

## License
MIT License. See `LICENSE` for details.
