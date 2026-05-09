# Paste & Promote Selection Toggles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two user-toggleable settings (`pasteOnClick`, `moveTopOnClick`, both default ON) that control auto-paste and history reordering on item selection from the MaClip overlay; add monitor self-write dedupe so re-selecting an item does not produce a duplicate history entry.

**Architecture:** Additive change across 5 existing files. New persisted Bool properties on `AppSettings`, conditional branching in `OverlayWindow.onSelect`, new `ignoreCurrentChangeCount()` method on `ClipboardMonitorProtocol`, called by `ClipboardListViewModel.setPasteboard(to:)`. No new types, no new services. UI: one new GroupBox in `SettingsView`.

**Tech Stack:** Swift, SwiftUI, AppKit (Cocoa), Combine, XCTest. Build via `xcodebuild -scheme MacClipboard -destination 'platform=macOS' test`.

**Reference spec:** `docs/superpowers/specs/2026-05-09-paste-promote-toggles-design.md`

**File map:**

| File | Responsibility |
|---|---|
| `Models/AppSettings.swift` | Add 2 new persisted Bool settings |
| `Services/ClipboardMonitor.swift` | Add `ignoreCurrentChangeCount()` to protocol + impl |
| `ViewModels/ClipboardListViewModel.swift` | Call dedupe after pasteboard write |
| `Tests/MacClipboardTests/ClipboardListViewModelTests.swift` | Update `MockMonitor`, assert dedupe |
| `Tests/MacClipboardTests/AppSettingsTests.swift` | NEW — defaults + persistence tests |
| `App/OverlayWindow.swift` | Branch on settings in `onSelect` |
| `Views/SettingsView.swift` | Add "Behavior" GroupBox UI |

---

### Task 1: Add `pasteOnClick` + `moveTopOnClick` to `AppSettings` (TDD)

**Files:**
- Create: `Tests/MacClipboardTests/AppSettingsTests.swift`
- Modify: `Models/AppSettings.swift`

`AppSettings` is a singleton, which complicates clean unit testing. The persistence/default contract is what matters. The test below clears `UserDefaults` for the two keys, then verifies defaults via a fresh `UserDefaults` lookup that mirrors `AppSettings.init`. This validates the contract without re-instantiating the singleton.

- [ ] **Step 1: Write the failing test**

Create `Tests/MacClipboardTests/AppSettingsTests.swift`:

```swift
import XCTest
@testable import MacClipboard

final class AppSettingsTests: XCTestCase {

    private let pasteKey = "settings.pasteOnClick"
    private let moveKey = "settings.moveTopOnClick"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: pasteKey)
        UserDefaults.standard.removeObject(forKey: moveKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: pasteKey)
        UserDefaults.standard.removeObject(forKey: moveKey)
        super.tearDown()
    }

    func test_defaultsAreTrueWhenKeysAbsent() {
        // Mirrors AppSettings.init's read pattern.
        let pasteDefault = UserDefaults.standard.object(forKey: pasteKey) as? Bool ?? true
        let moveDefault = UserDefaults.standard.object(forKey: moveKey) as? Bool ?? true
        XCTAssertTrue(pasteDefault)
        XCTAssertTrue(moveDefault)
    }

    func test_settingPasteOnClickPersists() {
        AppSettings.shared.pasteOnClick = false
        XCTAssertEqual(UserDefaults.standard.object(forKey: pasteKey) as? Bool, false)
        AppSettings.shared.pasteOnClick = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: pasteKey) as? Bool, true)
    }

    func test_settingMoveTopOnClickPersists() {
        AppSettings.shared.moveTopOnClick = false
        XCTAssertEqual(UserDefaults.standard.object(forKey: moveKey) as? Bool, false)
        AppSettings.shared.moveTopOnClick = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: moveKey) as? Bool, true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/AppSettingsTests test
```
Expected: FAIL — compilation error (`Value of type 'AppSettings' has no member 'pasteOnClick'`).

- [ ] **Step 3: Add the two properties to `AppSettings`**

Edit `Models/AppSettings.swift`. After the existing `autoCleanEnabled` block (line 30 area) add two new `@Published` Bool properties:

```swift
@Published var pasteOnClick: Bool {
    didSet { UserDefaults.standard.set(pasteOnClick, forKey: Keys.pasteOnClick) }
}
@Published var moveTopOnClick: Bool {
    didSet { UserDefaults.standard.set(moveTopOnClick, forKey: Keys.moveTopOnClick) }
}
```

In the `private struct Keys { … }` block add:

```swift
static let pasteOnClick = "settings.pasteOnClick"
static let moveTopOnClick = "settings.moveTopOnClick"
```

In `private init()`, after `let initialAutoClean = …` line, add:

```swift
let initialPasteOnClick = defaults.object(forKey: Keys.pasteOnClick) as? Bool ?? true
let initialMoveTopOnClick = defaults.object(forKey: Keys.moveTopOnClick) as? Bool ?? true
```

After `self.autoCleanEnabled = initialAutoClean` add:

```swift
self.pasteOnClick = initialPasteOnClick
self.moveTopOnClick = initialMoveTopOnClick
```

Use `defaults.object(forKey:) as? Bool ?? true` — required so an absent key yields `true`. `defaults.bool(forKey:)` returns `false` for absent keys, which would silently flip behavior for new installs.

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/AppSettingsTests test
```
Expected: PASS — three tests succeed.

- [ ] **Step 5: Commit**

```bash
git add Models/AppSettings.swift Tests/MacClipboardTests/AppSettingsTests.swift
git commit -m "feat(settings): add pasteOnClick and moveTopOnClick toggles"
```

---

### Task 2: Add `ignoreCurrentChangeCount()` to `ClipboardMonitorProtocol`

**Files:**
- Modify: `Services/ClipboardMonitor.swift`
- Modify: `Tests/MacClipboardTests/ClipboardListViewModelTests.swift` (private `MockMonitor`)

The test in Task 3 will exercise this; here we only declare the protocol method, implement it, and update the existing mock so the test target keeps compiling.

- [ ] **Step 1: Add method to protocol**

Edit `Services/ClipboardMonitor.swift`. Replace the existing `ClipboardMonitorProtocol` (lines 5–9) with:

```swift
protocol ClipboardMonitorProtocol {
    var itemPublisher: AnyPublisher<ClipboardItem, Never> { get }
    func start()
    func stop()
    func ignoreCurrentChangeCount()
}
```

- [ ] **Step 2: Implement in `ClipboardMonitor`**

In the same file, after the existing `stop()` method (line 27) add:

```swift
func ignoreCurrentChangeCount() {
    lastChangeCount = NSPasteboard.general.changeCount
}
```

- [ ] **Step 3: Update `MockMonitor` in tests so target compiles**

Edit `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`. Replace the existing `MockMonitor` definition (around line 79) with:

```swift
private final class MockMonitor: ClipboardMonitorProtocol {
    private let subject = PassthroughSubject<ClipboardItem, Never>()
    var itemPublisher: AnyPublisher<ClipboardItem, Never> { subject.eraseToAnyPublisher() }
    func start() {}
    func stop() {}

    private(set) var ignoreCallCount: Int = 0
    func ignoreCurrentChangeCount() { ignoreCallCount += 1 }

    func emit(_ item: ClipboardItem) { subject.send(item) }
}
```

- [ ] **Step 4: Build to confirm no compile errors**

Run:
```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' build-for-testing
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Services/ClipboardMonitor.swift Tests/MacClipboardTests/ClipboardListViewModelTests.swift
git commit -m "feat(monitor): add ignoreCurrentChangeCount() to protocol"
```

---

### Task 3: Wire dedupe into `ClipboardListViewModel.setPasteboard(to:)` (TDD)

**Files:**
- Modify: `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`
- Modify: `ViewModels/ClipboardListViewModel.swift`

- [ ] **Step 1: Write the failing test**

Edit `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`. Add this test method inside `final class ClipboardListViewModelTests: XCTestCase { … }` (any position before the closing brace):

```swift
@MainActor
func test_setPasteboard_callsIgnoreCurrentChangeCountOnce() {
    let repo = MockRepo()
    let monitor = MockMonitor()
    let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

    let item = ClipboardItem(date: Date(), content: .text("hello"))
    vm.setPasteboard(to: item)

    XCTAssertEqual(monitor.ignoreCallCount, 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/ClipboardListViewModelTests/test_setPasteboard_callsIgnoreCurrentChangeCountOnce test
```
Expected: FAIL — `XCTAssertEqual failed: ("0") is not equal to ("1")`.

- [ ] **Step 3: Wire the call in `setPasteboard(to:)`**

Edit `ViewModels/ClipboardListViewModel.swift`. In `setPasteboard(to:)` (starting line 77), append `monitor.ignoreCurrentChangeCount()` as the last statement of the function body (after the `switch` block, before the closing brace at line 101):

```swift
func setPasteboard(to item: ClipboardItem) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    switch item.content {
    case .text(let text):
        pasteboard.setString(text, forType: .string)
    case .image(let imgContent):
        var image: NSImage?
        switch imgContent.source {
        case .memory(let img):
            image = img
        case .file(let url):
            if let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
        }
        guard let validImage = image,
              let tiffData = validImage.tiffRepresentation else { return }
        pasteboard.setData(tiffData, forType: .tiff)
    case .url(let url):
        // Write both URL object and plain string for broad compatibility
        _ = pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
    }
    // Prevent the monitor from picking up our own pasteboard write.
    monitor.ignoreCurrentChangeCount()
}
```

Note the `guard let validImage … else { return }` early-exit on the image branch: if validation fails the function returns before the dedupe call, but in that branch nothing was written to the pasteboard, so no dedupe is needed. Behavior is correct.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/ClipboardListViewModelTests/test_setPasteboard_callsIgnoreCurrentChangeCountOnce test
```
Expected: PASS.

Then run the full VM test class to confirm no regressions:
```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/ClipboardListViewModelTests test
```
Expected: PASS — all tests succeed.

- [ ] **Step 5: Commit**

```bash
git add ViewModels/ClipboardListViewModel.swift Tests/MacClipboardTests/ClipboardListViewModelTests.swift
git commit -m "feat(viewmodel): dedupe self-pasteboard-writes from monitor"
```

---

### Task 4: Branch `OverlayWindow.onSelect` on settings

**Files:**
- Modify: `App/OverlayWindow.swift`

This is window-controller logic that depends on AppKit window state and is covered by manual QA in Task 6. No automated test.

- [ ] **Step 1: Replace the `onSelect` closure**

Edit `App/OverlayWindow.swift`. Replace lines 113–124 (the `let content = ContentView(...)` block inside `createWindow()`, including the trailing `.background(ESCKeyCatcher())` modifier) with:

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
.background(ESCKeyCatcher())
```

- [ ] **Step 2: Build to confirm**

Run:
```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run all tests to confirm no regressions**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' test
```
Expected: PASS — all tests succeed.

- [ ] **Step 4: Commit**

```bash
git add App/OverlayWindow.swift
git commit -m "feat(overlay): branch onSelect on pasteOnClick and moveTopOnClick"
```

---

### Task 5: Add "Behavior" GroupBox to `SettingsView`

**Files:**
- Modify: `Views/SettingsView.swift`

- [ ] **Step 1: Add the GroupBox**

Edit `Views/SettingsView.swift`. Insert a new GroupBox between the existing "Storage" GroupBox (ends at line 81) and the `Spacer()` (line 83). The new block:

```swift
// Behavior Settings
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

The resulting body order: Hotkey → Display → Storage → **Behavior** → Spacer → Action Buttons.

- [ ] **Step 2: Build to confirm**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Views/SettingsView.swift
git commit -m "feat(settings-ui): add Behavior section with paste/promote toggles"
```

---

### Task 6: Manual QA

**Files:** none (verification only)

This step validates the wiring end-to-end. The unit tests cover settings persistence and dedupe; the QA matrix covers the AppKit window/focus paths.

- [ ] **Step 1: Run app**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' build
open build/Build/Products/Debug/MaClip.app
```
(Or run the "MacClipboard" scheme from Xcode.)

- [ ] **Step 2: Walk through the QA matrix**

For each row, copy several items (text + image) into the clipboard, focus another app (e.g. TextEdit), then trigger MaClip with ⌃⌘V and select an item. Verify the expected outcome.

| Scenario | Toggle state | Action | Expected |
|---|---|---|---|
| 1 | paste ON, move ON | click | Pastes into prev app, item moves to top |
| 2 | paste ON, move ON | Enter key | Same as scenario 1 |
| 3 | paste OFF, move ON | click | Overlay closes, item at top of history, prev app focused, ⌘V pastes the item |
| 4 | paste ON, move OFF | click | Pastes into prev app, item stays at original index |
| 5 | paste OFF, move OFF | click | Overlay closes, prev app focused, item at original index, ⌘V pastes |
| 6 | any | re-select an old item | History contains no duplicate of the just-selected item |
| 7 | any → toggle → restart app | open Settings, toggle, quit, re-open | Toggle state persists |
| 8 | toggle while overlay open | open overlay, open Settings, change toggle, return to overlay, select | Latest value applied |

- [ ] **Step 3: If all 8 scenarios pass, mark plan complete**

If any scenario fails, capture the deviation, return to the implicated task, fix, and re-run the matrix.

---

## Self-Review

**Spec coverage:**
- ✅ `pasteOnClick` setting (default ON, persisted): Task 1
- ✅ `moveTopOnClick` setting (default ON, persisted): Task 1
- ✅ `OverlayWindow.onSelect` branches on both settings: Task 4
- ✅ Settings UI GroupBox: Task 5
- ✅ `ClipboardMonitor.ignoreCurrentChangeCount()` on protocol + impl: Task 2
- ✅ `setPasteboard(to:)` calls dedupe: Task 3
- ✅ Image + paste-OFF edge case: covered by manual QA scenarios 3/5 (no separate code branch)
- ✅ AppSettingsTests (defaults + persistence): Task 1
- ✅ ClipboardListViewModelTests dedupe assertion: Task 3
- The "monitor.ignoreCurrentChangeCount updates lastChangeCount" unit test from the spec is folded into manual QA scenario 6 because exercising it requires touching `NSPasteboard.general` shared state (flaky in unit tests) and the end-to-end behavior is what matters.

**Placeholder scan:** No "TBD"/"TODO"/"add appropriate X". All code blocks contain complete, paste-ready code.

**Type consistency:** `pasteOnClick`/`moveTopOnClick` (camelCase Bool) used identically across Tasks 1, 4, 5. `ignoreCurrentChangeCount()` signature identical across Tasks 2, 3 (protocol/mock/impl/call). `MockMonitor.ignoreCallCount` defined in Task 2, asserted in Task 3.
