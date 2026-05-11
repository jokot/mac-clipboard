# Privacy & Provenance (1.7.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship MaClip 1.7.0 "Privacy & Provenance": capture each clip's source app (icon shown in row, `from:` search syntax), block ingestion from a user-managed exclusion list seeded with common password managers (with retroactive purge), and detect concealed-pasteboard types (default behavior: ingest with redacted preview + auto-clear after configurable timeout; opt-in to skip entirely).

**Architecture:** All three features share `ClipboardMonitor.pollPasteboard()` — capture frontmost-app bundle ID, check exclusion list, sniff pasteboard for concealed UTIs, then either skip or emit with new metadata fields. `ClipboardItem` gains `sourceBundleID`, `isConcealed`, `concealedExpiresAt` (persisted via existing `PersistRecord` JSON layer with optional fields so legacy histories load cleanly). New `AppMetadata` utility caches bundle-ID → icon/display-name lookups. New "Privacy" GroupBox in `SettingsView` manages the list and concealed-handling toggles. Background timer in `ClipboardListViewModel` purges expired concealed items every 30s.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSWorkspace`, `NSPasteboard`, `Bundle`, `NSOpenPanel`), Combine, XCTest. Build: `xcodebuild -scheme MacClipboard -destination 'platform=macOS' test`. Module name: `MaClip`.

**Reference spec:** `docs/superpowers/specs/2026-05-10-privacy-provenance-design.md`

**File map:**

| File | Responsibility |
|---|---|
| `Models/ClipboardItem.swift` | Add `sourceBundleID`, `isConcealed`, `concealedExpiresAt` to struct |
| `Services/ClipboardRepository.swift` | Extend `PersistRecord` w/ optional fields; load+save round-trip preserves them; legacy entries decode w/ defaults |
| `Models/AppSettings.swift` | Add `excludedBundleIDs`, `skipConcealedItems`, `concealedClearTimeout` w/ seed defaults |
| `Utilities/AppMetadata.swift` (new) | Bundle-ID → icon + display-name lookup w/ in-memory cache |
| `Services/ClipboardMonitor.swift` | Capture frontmost in `pollPasteboard`, exclusion + concealed-UTI gates, populate new item fields |
| `ViewModels/ClipboardListViewModel.swift` | Concealed-expiry timer; `purgeItems(matchingBundleID:)` helper; `filteredItems` parses `from:` syntax |
| `Views/Components/ClipboardItemRow.swift` | 16×16 source icon w/ tooltip; concealed redaction + lock + countdown |
| `Views/SettingsView.swift` | New "Privacy" GroupBox (excluded apps list + concealed toggle/timeout); window height 400→520 |
| `Views/ContentView.swift` | Search placeholder hint; right-click "Exclude [App]" w/ confirm dialog |
| `Tests/MacClipboardTests/ClipboardItemRepositoryTests.swift` (new) | Persist round-trip incl. new fields, legacy-decode tolerance |
| `Tests/MacClipboardTests/AppSettingsTests.swift` (extend) | Defaults + persistence for new keys |
| `Tests/MacClipboardTests/AppMetadataTests.swift` (new) | Display-name resolution + cache hit |
| `Tests/MacClipboardTests/ClipboardListViewModelTests.swift` (extend) | `purgeItems(matchingBundleID:)`, expiry sweep, `from:` filter |
| `project.yml` | Bump `MARKETING_VERSION` 1.6.0→1.7.0, `CURRENT_PROJECT_VERSION` 7→8 |

---

### Task 1: Extend `ClipboardItem` with provenance + concealed fields, plumb through `PersistRecord`

**Files:**
- Modify: `Models/ClipboardItem.swift`
- Modify: `Services/ClipboardRepository.swift`
- Create: `Tests/MacClipboardTests/ClipboardItemRepositoryTests.swift`

This task does the data-model spine: add the three new fields, ensure load + save preserves them, ensure legacy histories decode cleanly with defaults.

- [ ] **Step 1: Write the failing repository round-trip test**

Create `Tests/MacClipboardTests/ClipboardItemRepositoryTests.swift`:

```swift
import XCTest
@testable import MaClip

final class ClipboardItemRepositoryTests: XCTestCase {

    func test_textItemRoundTripPreservesNewFields() throws {
        let bundleID = "com.apple.TextEdit"
        let expiry = Date(timeIntervalSinceNow: 60)
        let item = ClipboardItem(
            id: UUID(),
            date: Date(),
            content: .text("hello"),
            sourceBundleID: bundleID,
            isConcealed: true,
            concealedExpiresAt: expiry
        )

        let repo = ClipboardRepository()
        repo.saveToDisk(items: [item])
        let loaded = repo.loadFromDisk()
        defer { repo.clearAllFiles() }

        XCTAssertEqual(loaded.count, 1)
        let r = loaded[0]
        XCTAssertEqual(r.sourceBundleID, bundleID)
        XCTAssertTrue(r.isConcealed)
        XCTAssertEqual(r.concealedExpiresAt?.timeIntervalSince1970,
                       expiry.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func test_legacyJSONDecodesWithDefaults() throws {
        // Legacy PersistRecord layout has no new keys.
        let legacyJSON = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "date": 770000000,
            "type": "text",
            "text": "old item",
            "imageFilename": null,
            "url": null,
            "cachedText": null,
            "cachedId": null,
            "cachedBarcode": null
          }
        ]
        """.data(using: .utf8)!

        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("MaClip", isDirectory: true)
            .appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try legacyJSON.write(to: url, options: .atomic)

        let repo = ClipboardRepository()
        let loaded = repo.loadFromDisk()
        defer { repo.clearAllFiles() }

        XCTAssertEqual(loaded.count, 1)
        let r = loaded[0]
        XCTAssertNil(r.sourceBundleID)
        XCTAssertFalse(r.isConcealed)
        XCTAssertNil(r.concealedExpiresAt)
        if case .text(let t) = r.content {
            XCTAssertEqual(t, "old item")
        } else {
            XCTFail("expected text content")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/ClipboardItemRepositoryTests test
```
Expected: FAIL — compile error (`Extra arguments at positions ... in call`) because `ClipboardItem.init` doesn't yet accept the new params.

- [ ] **Step 3: Add fields to `ClipboardItem`**

Edit `Models/ClipboardItem.swift`. Replace the `struct ClipboardItem` block (lines 29–39) with:

```swift
struct ClipboardItem: Identifiable {
    let id: UUID
    let date: Date
    let content: ClipboardItemContent
    let sourceBundleID: String?
    let isConcealed: Bool
    let concealedExpiresAt: Date?

    init(id: UUID = UUID(),
         date: Date,
         content: ClipboardItemContent,
         sourceBundleID: String? = nil,
         isConcealed: Bool = false,
         concealedExpiresAt: Date? = nil) {
        self.id = id
        self.date = date
        self.content = content
        self.sourceBundleID = sourceBundleID
        self.isConcealed = isConcealed
        self.concealedExpiresAt = concealedExpiresAt
    }
}
```

The default values keep all existing call sites compiling unchanged.

- [ ] **Step 4: Extend `PersistRecord` and load/save logic**

Edit `Services/ClipboardRepository.swift`. Replace the `private struct PersistRecord` (lines 13–23) with:

```swift
private struct PersistRecord: Codable {
    let id: UUID
    let date: Date
    let type: String // "text", "image", or "url"
    let text: String?
    let imageFilename: String?
    let url: String?
    let cachedText: String?
    let cachedId: String?
    let cachedBarcode: String?
    // Added in 1.7.0; optional so legacy JSON without these keys still decodes.
    let sourceBundleID: String?
    let isConcealed: Bool?
    let concealedExpiresAt: Date?
}
```

In `loadFromDisk()`, replace the entire `for rec in records { … }` block with:

```swift
for rec in records {
    let isConcealed = rec.isConcealed ?? false
    switch rec.type {
    case "text":
        if let text = rec.text {
            loaded.append(ClipboardItem(
                id: rec.id, date: rec.date, content: .text(text),
                sourceBundleID: rec.sourceBundleID,
                isConcealed: isConcealed,
                concealedExpiresAt: rec.concealedExpiresAt
            ))
        }
    case "image":
        if let name = rec.imageFilename, let imagesDir {
            let imgURL = imagesDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: imgURL.path) {
                let imgContent = ImageContent(source: .file(imgURL),
                                              cachedText: rec.cachedText,
                                              cachedId: rec.cachedId,
                                              cachedBarcode: rec.cachedBarcode)
                loaded.append(ClipboardItem(
                    id: rec.id, date: rec.date, content: .image(imgContent),
                    sourceBundleID: rec.sourceBundleID,
                    isConcealed: isConcealed,
                    concealedExpiresAt: rec.concealedExpiresAt
                ))
            }
        }
    case "url":
        if let s = rec.url, let u = URL(string: s) {
            loaded.append(ClipboardItem(
                id: rec.id, date: rec.date, content: .url(u),
                sourceBundleID: rec.sourceBundleID,
                isConcealed: isConcealed,
                concealedExpiresAt: rec.concealedExpiresAt
            ))
        }
    default:
        continue
    }
}
```

In `performSave(items:)`, replace the inner `for item in items { … }` block (and every `PersistRecord(...)` call inside it) with:

```swift
for item in items {
    switch item.content {
    case .text(let text):
        records.append(PersistRecord(
            id: item.id, date: item.date, type: "text",
            text: text, imageFilename: nil, url: nil,
            cachedText: nil, cachedId: nil, cachedBarcode: nil,
            sourceBundleID: item.sourceBundleID,
            isConcealed: item.isConcealed,
            concealedExpiresAt: item.concealedExpiresAt
        ))
    case .image(let imgContent):
        guard let imagesDir else { continue }
        var filename: String?
        switch imgContent.source {
        case .file(let url):
            filename = url.lastPathComponent
            records.append(PersistRecord(
                id: item.id, date: item.date, type: "image",
                text: nil, imageFilename: filename, url: nil,
                cachedText: imgContent.cachedText, cachedId: imgContent.cachedId, cachedBarcode: imgContent.cachedBarcode,
                sourceBundleID: item.sourceBundleID,
                isConcealed: item.isConcealed,
                concealedExpiresAt: item.concealedExpiresAt
            ))
        case .memory(let image):
            let name = item.id.uuidString + ".png"
            let fileURL = imagesDir.appendingPathComponent(name)
            if let pngData = image.pngData() {
                if let existing = savedImageHashes[pngData] {
                    filename = existing
                } else {
                    if !fm.fileExists(atPath: fileURL.path) {
                        try? pngData.write(to: fileURL, options: .atomic)
                    }
                    savedImageHashes[pngData] = name
                    filename = name
                }
                records.append(PersistRecord(
                    id: item.id, date: item.date, type: "image",
                    text: nil, imageFilename: filename, url: nil,
                    cachedText: imgContent.cachedText, cachedId: imgContent.cachedId, cachedBarcode: imgContent.cachedBarcode,
                    sourceBundleID: item.sourceBundleID,
                    isConcealed: item.isConcealed,
                    concealedExpiresAt: item.concealedExpiresAt
                ))
            }
        }
    case .url(let u):
        records.append(PersistRecord(
            id: item.id, date: item.date, type: "url",
            text: nil, imageFilename: nil, url: u.absoluteString,
            cachedText: nil, cachedId: nil, cachedBarcode: nil,
            sourceBundleID: item.sourceBundleID,
            isConcealed: item.isConcealed,
            concealedExpiresAt: item.concealedExpiresAt
        ))
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/ClipboardItemRepositoryTests test
```
Expected: PASS — both tests succeed.

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests test
```
Expected: PASS for our suites; pre-existing `URLUtilsTests` failures unchanged.

- [ ] **Step 6: Run xcodegen if test file isn't auto-registered**

If Step 5 reports the new test class as missing, run `xcodegen generate` and re-run.

- [ ] **Step 7: Commit**

```bash
git add Models/ClipboardItem.swift Services/ClipboardRepository.swift \
        Tests/MacClipboardTests/ClipboardItemRepositoryTests.swift \
        MacClipboard.xcodeproj/project.pbxproj
git commit -m "feat(model): add provenance + concealed fields to ClipboardItem"
```

---

### Task 2: Add `excludedBundleIDs`, `skipConcealedItems`, `concealedClearTimeout` to `AppSettings`

**Files:**
- Modify: `Models/AppSettings.swift`
- Modify: `Tests/MacClipboardTests/AppSettingsTests.swift`

`excludedBundleIDs` is an array, persisted as JSON-encoded data under one UserDefaults key. Two scalars use the existing `?? default` pattern.

- [ ] **Step 1: Add failing tests**

Edit `Tests/MacClipboardTests/AppSettingsTests.swift`. Inside the existing `final class AppSettingsTests: XCTestCase { … }`, add these properties and tests:

```swift
private let excludedKey = "settings.excludedBundleIDs"
private let skipConcealedKey = "settings.skipConcealedItems"
private let concealedTimeoutKey = "settings.concealedClearTimeout"

private static let seedExclusions: Set<String> = [
    "com.agilebits.onepassword7",
    "com.1password.1password",
    "com.bitwarden.desktop",
    "com.apple.keychainaccess",
    "com.dashlane.dashlanephonefinal",
    "com.lastpass.LastPassMacDesktop",
    "com.jokot.MacClipboard",
]

func test_seedExclusionsWhenKeyAbsent() {
    UserDefaults.standard.removeObject(forKey: excludedKey)
    let initial = AppSettings.makeInitialExcludedBundleIDs()
    XCTAssertEqual(Set(initial), Self.seedExclusions)
}

func test_emptyArrayPersistsAndIsNotReseeded() {
    let encoded = try! JSONEncoder().encode([String]())
    UserDefaults.standard.set(encoded, forKey: excludedKey)
    let initial = AppSettings.makeInitialExcludedBundleIDs()
    XCTAssertEqual(initial, [])
    UserDefaults.standard.removeObject(forKey: excludedKey)
}

func test_skipConcealedDefaultFalse() {
    UserDefaults.standard.removeObject(forKey: skipConcealedKey)
    let value = UserDefaults.standard.object(forKey: skipConcealedKey) as? Bool ?? false
    XCTAssertFalse(value)
}

func test_concealedTimeoutDefault300() {
    UserDefaults.standard.removeObject(forKey: concealedTimeoutKey)
    let raw = UserDefaults.standard.object(forKey: concealedTimeoutKey) as? Double
    let value = raw ?? 300
    XCTAssertEqual(value, 300, accuracy: 0.001)
}

func test_settingExcludedBundleIDsPersists() {
    AppSettings.shared.excludedBundleIDs = ["com.foo.bar"]
    let data = UserDefaults.standard.data(forKey: excludedKey)!
    let decoded = try! JSONDecoder().decode([String].self, from: data)
    XCTAssertEqual(decoded, ["com.foo.bar"])
    UserDefaults.standard.removeObject(forKey: excludedKey)
}

func test_settingSkipConcealedPersists() {
    AppSettings.shared.skipConcealedItems = true
    XCTAssertEqual(UserDefaults.standard.object(forKey: skipConcealedKey) as? Bool, true)
    AppSettings.shared.skipConcealedItems = false
    UserDefaults.standard.removeObject(forKey: skipConcealedKey)
}

func test_settingConcealedTimeoutPersists() {
    AppSettings.shared.concealedClearTimeout = 60
    XCTAssertEqual(UserDefaults.standard.object(forKey: concealedTimeoutKey) as? Double, 60)
    AppSettings.shared.concealedClearTimeout = 300
    UserDefaults.standard.removeObject(forKey: concealedTimeoutKey)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/AppSettingsTests test
```
Expected: FAIL — `Type 'AppSettings' has no member 'makeInitialExcludedBundleIDs' / 'excludedBundleIDs' / 'skipConcealedItems' / 'concealedClearTimeout'`.

- [ ] **Step 3: Add properties to `AppSettings`**

Edit `Models/AppSettings.swift`. After the `autoCleanEnabled` property block (~line 30), add:

```swift
@Published var excludedBundleIDs: [String] {
    didSet {
        if let data = try? JSONEncoder().encode(excludedBundleIDs) {
            UserDefaults.standard.set(data, forKey: Keys.excludedBundleIDs)
        }
    }
}
@Published var skipConcealedItems: Bool {
    didSet { UserDefaults.standard.set(skipConcealedItems, forKey: Keys.skipConcealedItems) }
}
@Published var concealedClearTimeout: TimeInterval {
    didSet { UserDefaults.standard.set(concealedClearTimeout, forKey: Keys.concealedClearTimeout) }
}
```

In the `private struct Keys { … }` block, add:

```swift
static let excludedBundleIDs = "settings.excludedBundleIDs"
static let skipConcealedItems = "settings.skipConcealedItems"
static let concealedClearTimeout = "settings.concealedClearTimeout"
```

Add the static seed factory at the file scope of `AppSettings` (above `private init()`):

```swift
static let defaultSeedExclusions: [String] = [
    "com.agilebits.onepassword7",
    "com.1password.1password",
    "com.bitwarden.desktop",
    "com.apple.keychainaccess",
    "com.dashlane.dashlanephonefinal",
    "com.lastpass.LastPassMacDesktop",
    "com.jokot.MacClipboard",
]

static func makeInitialExcludedBundleIDs() -> [String] {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: Keys.excludedBundleIDs),
       let decoded = try? JSONDecoder().decode([String].self, from: data) {
        return decoded   // user has explicit value (possibly empty); never re-seed
    }
    return defaultSeedExclusions
}
```

In `private init()`, after `let initialAutoClean = …`, add:

```swift
let initialExcluded = AppSettings.makeInitialExcludedBundleIDs()
let initialSkipConcealed = defaults.object(forKey: Keys.skipConcealedItems) as? Bool ?? false
let initialConcealedTimeout = (defaults.object(forKey: Keys.concealedClearTimeout) as? Double) ?? 300
```

After `self.autoCleanEnabled = initialAutoClean`, add:

```swift
self.excludedBundleIDs = initialExcluded
self.skipConcealedItems = initialSkipConcealed
self.concealedClearTimeout = initialConcealedTimeout
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/AppSettingsTests test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Models/AppSettings.swift Tests/MacClipboardTests/AppSettingsTests.swift
git commit -m "feat(settings): add excluded apps + concealed-item handling settings"
```

---

### Task 3: Create `Utilities/AppMetadata.swift` for bundle-ID → icon/name resolution

**Files:**
- Create: `Utilities/AppMetadata.swift`
- Create: `Tests/MacClipboardTests/AppMetadataTests.swift`

In-memory cache to avoid repeated `NSWorkspace` calls during overlay rendering.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MacClipboardTests/AppMetadataTests.swift`:

```swift
import XCTest
@testable import MaClip

final class AppMetadataTests: XCTestCase {

    @MainActor
    override func setUp() {
        super.setUp()
        AppMetadata.shared.clearCache()
    }

    @MainActor
    func test_displayNameForKnownAppReturnsNonNil() {
        let name = AppMetadata.shared.displayName(for: "com.apple.TextEdit")
        XCTAssertNotNil(name)
    }

    @MainActor
    func test_displayNameForUnknownAppReturnsNil() {
        let name = AppMetadata.shared.displayName(for: "com.example.does-not-exist-xyz")
        XCTAssertNil(name)
    }

    @MainActor
    func test_iconForKnownAppReturnsNonNil() {
        let icon = AppMetadata.shared.icon(for: "com.apple.TextEdit")
        XCTAssertNotNil(icon)
    }

    @MainActor
    func test_displayNameCachedOnSecondCall() {
        let bundleID = "com.apple.TextEdit"
        let first = AppMetadata.shared.displayName(for: bundleID)
        let second = AppMetadata.shared.displayName(for: bundleID)
        XCTAssertEqual(first, second)
        XCTAssertTrue(AppMetadata.shared.isCached(bundleID: bundleID))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/AppMetadataTests test
```
Expected: FAIL — compile error (no such type `AppMetadata`).

- [ ] **Step 3: Create `Utilities/AppMetadata.swift`**

```swift
import Cocoa

/// Resolves bundle IDs to display names and icons, caching results.
@MainActor
final class AppMetadata {
    static let shared = AppMetadata()

    private struct Entry {
        let displayName: String?
        let icon: NSImage?
    }

    private var cache: [String: Entry] = [:]

    private init() {}

    func displayName(for bundleID: String) -> String? {
        return entry(for: bundleID).displayName
    }

    func icon(for bundleID: String) -> NSImage? {
        return entry(for: bundleID).icon
    }

    func isCached(bundleID: String) -> Bool {
        return cache[bundleID] != nil
    }

    func clearCache() {
        cache.removeAll()
    }

    private func entry(for bundleID: String) -> Entry {
        if let cached = cache[bundleID] { return cached }
        let resolved = resolve(bundleID: bundleID)
        cache[bundleID] = resolved
        return resolved
    }

    private func resolve(bundleID: String) -> Entry {
        let workspace = NSWorkspace.shared
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            return Entry(displayName: nil, icon: nil)
        }
        let bundle = Bundle(url: appURL)
        let displayName = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let icon = workspace.icon(forFile: appURL.path)
        return Entry(displayName: displayName, icon: icon)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/AppMetadataTests test
```
Expected: PASS. If new test file isn't auto-registered, run `xcodegen generate` and re-run.

- [ ] **Step 5: Commit**

```bash
git add Utilities/AppMetadata.swift \
        Tests/MacClipboardTests/AppMetadataTests.swift \
        MacClipboard.xcodeproj/project.pbxproj
git commit -m "feat(utility): add AppMetadata bundle-id resolver with cache"
```

---

### Task 4: Capture frontmost app + apply exclusion + concealed gates in `ClipboardMonitor`

**Files:**
- Modify: `Services/ClipboardMonitor.swift`

This task has no automated test — `ClipboardMonitor.pollPasteboard` reads `NSWorkspace.shared.frontmostApplication` and `NSPasteboard.general` directly, both global singletons hard to stub without invasive refactor. Manual QA in Task 10 covers these paths.

- [ ] **Step 1: Replace `pollPasteboard()`**

Edit `Services/ClipboardMonitor.swift`. Replace the entire `private func pollPasteboard()` body with:

```swift
private func pollPasteboard() {
    let pb = NSPasteboard.general
    guard pb.changeCount != lastChangeCount else { return }
    lastChangeCount = pb.changeCount

    let frontmost = NSWorkspace.shared.frontmostApplication
    let sourceBundleID = frontmost?.bundleIdentifier

    // Self-capture guard. Belt-and-suspenders against any race in
    // ClipboardListViewModel.setPasteboard's ignoreCurrentChangeCount() (1.6.0).
    if sourceBundleID == "com.jokot.MacClipboard" { return }

    // Exclusion list — never ingest from these apps.
    if let id = sourceBundleID,
       AppSettings.shared.excludedBundleIDs.contains(id) {
        return
    }

    // Concealed UTI detection. Inspect types BEFORE reading data.
    let concealedUTIs: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.AutoGeneratedType",
        "com.apple.is-sensitive",
    ]
    let isConcealed: Bool = {
        guard let types = pb.types else { return false }
        return types.contains { concealedUTIs.contains($0.rawValue) }
    }()

    if isConcealed && AppSettings.shared.skipConcealedItems {
        return
    }

    let expiry: Date? = isConcealed
        ? Date().addingTimeInterval(AppSettings.shared.concealedClearTimeout)
        : nil

    // Read content (image > URL > text) — same priority as before.
    if let image = readImage(from: pb) {
        let imgContent = ImageContent(source: .memory(image),
                                      cachedText: nil, cachedId: nil, cachedBarcode: nil)
        subject.send(ClipboardItem(
            date: Date(), content: .image(imgContent),
            sourceBundleID: sourceBundleID,
            isConcealed: isConcealed,
            concealedExpiresAt: expiry
        ))
        return
    }

    if let url = readURL(from: pb) {
        subject.send(ClipboardItem(
            date: Date(), content: .url(url),
            sourceBundleID: sourceBundleID,
            isConcealed: isConcealed,
            concealedExpiresAt: expiry
        ))
        return
    }

    if let text = readText(from: pb) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detected = URLUtils.linkURL(from: trimmed) {
            subject.send(ClipboardItem(
                date: Date(), content: .url(detected),
                sourceBundleID: sourceBundleID,
                isConcealed: isConcealed,
                concealedExpiresAt: expiry
            ))
        } else {
            subject.send(ClipboardItem(
                date: Date(), content: .text(text),
                sourceBundleID: sourceBundleID,
                isConcealed: isConcealed,
                concealedExpiresAt: expiry
            ))
        }
    }
}
```

- [ ] **Step 2: Build to confirm**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run full test suite to confirm no regressions**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests test
```
Expected: PASS for our suites.

- [ ] **Step 4: Commit**

```bash
git add Services/ClipboardMonitor.swift
git commit -m "feat(monitor): capture source app + apply exclusion and concealed gates"
```

---

### Task 5: Concealed-expiry sweep + `purgeItems(matchingBundleID:)` in `ClipboardListViewModel`

**Files:**
- Modify: `ViewModels/ClipboardListViewModel.swift`
- Modify: `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Edit `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`. Add inside the test class:

```swift
@MainActor
func test_purgeItemsRemovesAllMatchingBundleID() {
    let repo = MockRepo()
    let monitor = MockMonitor()
    let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

    let safari = ClipboardItem(date: Date(), content: .text("a"), sourceBundleID: "com.apple.Safari")
    let textEdit = ClipboardItem(date: Date(), content: .text("b"), sourceBundleID: "com.apple.TextEdit")
    let safari2 = ClipboardItem(date: Date(), content: .text("c"), sourceBundleID: "com.apple.Safari")
    monitor.emit(safari)
    monitor.emit(textEdit)
    monitor.emit(safari2)

    let removed = vm.purgeItems(matchingBundleID: "com.apple.Safari")

    XCTAssertEqual(removed, 2)
    XCTAssertEqual(vm.items.count, 1)
    XCTAssertEqual(vm.items.first?.sourceBundleID, "com.apple.TextEdit")
}

@MainActor
func test_concealedExpirySweepRemovesPastItems() {
    let repo = MockRepo()
    let monitor = MockMonitor()
    let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

    let alive = ClipboardItem(date: Date(), content: .text("alive"),
                              isConcealed: true,
                              concealedExpiresAt: Date(timeIntervalSinceNow: 60))
    let expired = ClipboardItem(date: Date(), content: .text("expired"),
                                isConcealed: true,
                                concealedExpiresAt: Date(timeIntervalSinceNow: -1))
    monitor.emit(alive)
    monitor.emit(expired)

    vm.runConcealedExpirySweep(now: Date())

    XCTAssertEqual(vm.items.count, 1)
    XCTAssertEqual(vm.items.first?.id, alive.id)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/ClipboardListViewModelTests test
```
Expected: FAIL — `Value of type 'ClipboardListViewModel' has no member 'purgeItems' / 'runConcealedExpirySweep'`.

- [ ] **Step 3: Add helpers + timer**

Edit `ViewModels/ClipboardListViewModel.swift`. Add a property near the top of the class (after `private var cancellables = Set<AnyCancellable>()`):

```swift
private var concealedTimer: Timer?
```

In `init`, after the existing `monitor.start()` call, add:

```swift
// Sweep concealed items every 30 s.
self.concealedTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
    Task { @MainActor in
        self?.runConcealedExpirySweep(now: Date())
    }
}
```

In `deinit`, after `monitor.stop()`, add:

```swift
concealedTimer?.invalidate()
```

Then add two new methods to the class:

```swift
@discardableResult
func purgeItems(matchingBundleID bundleID: String) -> Int {
    let before = items.count
    items.removeAll { $0.sourceBundleID == bundleID }
    let removed = before - items.count
    if removed > 0 {
        repository.saveToDiskAsync(items: items)
    }
    return removed
}

func runConcealedExpirySweep(now: Date) {
    let before = items.count
    items.removeAll { item in
        item.isConcealed && (item.concealedExpiresAt.map { $0 <= now } ?? false)
    }
    if items.count != before {
        repository.saveToDiskAsync(items: items)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/ClipboardListViewModelTests test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ViewModels/ClipboardListViewModel.swift \
        Tests/MacClipboardTests/ClipboardListViewModelTests.swift
git commit -m "feat(viewmodel): concealed expiry sweep + bundle-id purge helper"
```

---

### Task 6: `from:` search syntax in `ClipboardListViewModel.filteredItems`

**Files:**
- Modify: `ViewModels/ClipboardListViewModel.swift`
- Modify: `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`

`from:com.apple.Safari` → exact bundle-ID match. `from:Safari` → display-name substring (case-insensitive). Plain tokens AND'd with text contains.

- [ ] **Step 1: Write the failing tests**

Edit `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`. Add to the test class:

```swift
@MainActor
func test_filterFromExactBundleIDMatches() {
    let repo = MockRepo()
    let monitor = MockMonitor()
    let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

    monitor.emit(ClipboardItem(date: Date(), content: .text("a"), sourceBundleID: "com.apple.Safari"))
    monitor.emit(ClipboardItem(date: Date(), content: .text("b"), sourceBundleID: "com.apple.TextEdit"))

    vm.searchText = "from:com.apple.Safari"
    XCTAssertEqual(vm.filteredItems.count, 1)
    XCTAssertEqual(vm.filteredItems.first?.sourceBundleID, "com.apple.Safari")
}

@MainActor
func test_filterFromBundleIDAndTextCombined() {
    let repo = MockRepo()
    let monitor = MockMonitor()
    let vm = ClipboardListViewModel(repository: repo, monitor: monitor)

    monitor.emit(ClipboardItem(date: Date(), content: .text("hello world"),
                               sourceBundleID: "com.apple.Safari"))
    monitor.emit(ClipboardItem(date: Date(), content: .text("goodbye"),
                               sourceBundleID: "com.apple.Safari"))
    monitor.emit(ClipboardItem(date: Date(), content: .text("hello world"),
                               sourceBundleID: "com.apple.TextEdit"))

    vm.searchText = "from:com.apple.Safari hello"
    XCTAssertEqual(vm.filteredItems.count, 1)
    if case .text(let t) = vm.filteredItems.first?.content {
        XCTAssertEqual(t, "hello world")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/ClipboardListViewModelTests test
```
Expected: FAIL — current `filteredItems` treats `from:…` as a literal text substring.

- [ ] **Step 3: Update `filteredItems`**

Edit `ViewModels/ClipboardListViewModel.swift`. Replace the entire `var filteredItems: [ClipboardItem]` computed property with:

```swift
var filteredItems: [ClipboardItem] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return items }

    var sourceFilters: [String] = []
    var textFilters: [String] = []

    for token in trimmed.split(separator: " ", omittingEmptySubsequences: true) {
        let s = String(token)
        if s.lowercased().hasPrefix("from:") {
            let value = String(s.dropFirst(5))
            if !value.isEmpty { sourceFilters.append(value) }
        } else {
            textFilters.append(s.lowercased())
        }
    }

    return items.filter { item in
        if !sourceFilters.isEmpty {
            let bundleID = item.sourceBundleID
            let displayName = bundleID.flatMap { AppMetadata.shared.displayName(for: $0) }
            let matchesSource = sourceFilters.contains { token in
                if token.contains(".") {
                    return bundleID == token
                } else {
                    return displayName?.localizedCaseInsensitiveContains(token) ?? false
                }
            }
            if !matchesSource { return false }
        }

        if !textFilters.isEmpty {
            let haystack: String
            switch item.content {
            case .text(let t): haystack = t.lowercased()
            case .url(let u):  haystack = u.absoluteString.lowercased()
            case .image:       haystack = ""
            }
            for token in textFilters where !haystack.contains(token) {
                return false
            }
        }

        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests/ClipboardListViewModelTests test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ViewModels/ClipboardListViewModel.swift \
        Tests/MacClipboardTests/ClipboardListViewModelTests.swift
git commit -m "feat(filter): support 'from:' search syntax for source app filtering"
```

---

### Task 7: Source-app icon + concealed redaction in `ClipboardItemRow`

**Files:**
- Modify: `Views/Components/ClipboardItemRow.swift`

UI-only; covered by manual QA in Task 10.

- [ ] **Step 1: Add `SourceIconBadge` and `ConcealedBadge` helpers**

Edit `Views/Components/ClipboardItemRow.swift`. Append at end of file (after the existing private subviews):

```swift
private struct SourceIconBadge: View {
    let bundleID: String?

    var body: some View {
        Group {
            if let bundleID,
               let icon = AppMetadata.shared.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .help(AppMetadata.shared.displayName(for: bundleID) ?? bundleID)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .help("Unknown source")
            }
        }
    }
}

private struct ConcealedBadge: View {
    let expiresAt: Date?
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            if let expiresAt {
                let remaining = max(0, Int(expiresAt.timeIntervalSince(now)))
                Text(formatRemaining(seconds: remaining))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .onReceive(timer) { now = $0 }
    }

    private func formatRemaining(seconds: Int) -> String {
        if seconds >= 60 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }
}
```

- [ ] **Step 2: Add new properties to `TextItemContent`, `URLItemContent`, `ImageItemContent`**

For each of the three private structs, add three properties:

```swift
let bundleID: String?
let isConcealed: Bool
let concealedExpiresAt: Date?
```

Place them next to the existing properties (e.g. after `let isHovered: Bool`).

- [ ] **Step 3: Update each subview's body**

In `TextItemContent.body`, change the leading `Text(...)` and trailing area:

```swift
HStack(alignment: .top, spacing: 10) {
    Image(systemName: "doc.on.clipboard")
        .font(.title3)
        .foregroundColor(.accentColor)
        .frame(width: 28)
    VStack(alignment: .leading, spacing: 6) {
        let displayString = isConcealed
            ? String(repeating: "•", count: min(8, max(1, string.count)))
            : TextPreview.preview(for: string)
        Text(displayString)
            .font(.body)
            .lineLimit(4)
        HStack(spacing: 8) {
            Text(date, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
            if isConcealed {
                ConcealedBadge(expiresAt: concealedExpiresAt)
            }
        }
    }
    Spacer()
    SourceIconBadge(bundleID: bundleID)
    if isHovered {
        pillButton(label: "Delete", systemImage: "trash", color: .red,
                   outlineOpacity: 0.35, fillsWidth: false, action: onRemove)
    }
}
.padding(.trailing, 10)
```

For `URLItemContent.body`, apply the same pattern: redact the URL preview to `••••••` when `isConcealed`, append `ConcealedBadge` next to the date, place `SourceIconBadge(bundleID: bundleID)` before the hover delete button.

For `ImageItemContent.body`, place `SourceIconBadge(bundleID: bundleID)` next to the existing trailing controls. When `isConcealed` is true, overlay a lock SF Symbol on top of the image thumbnail (use `.overlay { Image(systemName: "lock.fill") … }` on the thumbnail container).

- [ ] **Step 4: Update the `content` switch in `ClipboardItemRow`**

Replace the entire `@ViewBuilder private var content: some View` block:

```swift
@ViewBuilder
private var content: some View {
    switch item.content {
    case .text(let string):
        TextItemContent(string: string,
                        date: item.date,
                        bundleID: item.sourceBundleID,
                        isConcealed: item.isConcealed,
                        concealedExpiresAt: item.concealedExpiresAt,
                        isHovered: isHovered,
                        onRemove: onRemove)
    case .image(let imgContent):
        ImageItemContent(imgContent: imgContent,
                         item: item,
                         bundleID: item.sourceBundleID,
                         isConcealed: item.isConcealed,
                         concealedExpiresAt: item.concealedExpiresAt,
                         isHovered: isHovered,
                         onRemove: onRemove,
                         onExtractText: onExtractText,
                         onExtractBarcode: onExtractBarcode)
    case .url(let url):
        URLItemContent(url: url,
                       date: item.date,
                       bundleID: item.sourceBundleID,
                       isConcealed: item.isConcealed,
                       concealedExpiresAt: item.concealedExpiresAt,
                       isHovered: isHovered,
                       onRemove: onRemove)
    }
}
```

- [ ] **Step 5: Build to confirm**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Views/Components/ClipboardItemRow.swift
git commit -m "feat(row): show source-app icon and concealed-item redaction"
```

---

### Task 8: New "Privacy" GroupBox in `SettingsView`; bump window height to 520pt

**Files:**
- Modify: `Views/SettingsView.swift`

UI-only; covered by manual QA in Task 10.

- [ ] **Step 1: Insert the Privacy GroupBox**

Edit `Views/SettingsView.swift`. Inside `body`, between the existing "Storage" GroupBox closing brace (~line 81) and the existing Behavior GroupBox, insert:

```swift
// Privacy Settings
GroupBox("Privacy") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Excluded Apps")
            .font(.subheadline.bold())
        VStack(alignment: .leading, spacing: 4) {
            ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                HStack(spacing: 8) {
                    if let icon = AppMetadata.shared.icon(for: bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "questionmark.app.dashed").frame(width: 18, height: 18)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(AppMetadata.shared.displayName(for: bundleID) ?? bundleID)
                            .font(.body)
                        Text(bundleID).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        settings.excludedBundleIDs.removeAll { $0 == bundleID }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            if settings.excludedBundleIDs.isEmpty {
                Text("No apps excluded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        Button("+ Add Application…") {
            addApplicationViaPicker()
        }
        Text("Clips copied from these apps will never be saved to your history.")
            .font(.caption)
            .foregroundColor(.secondary)

        Divider().padding(.vertical, 4)

        Toggle("Skip concealed clipboard items", isOn: $settings.skipConcealedItems)
        HStack {
            Text("Auto-clear concealed items after")
            Spacer()
            Picker("", selection: $settings.concealedClearTimeout) {
                Text("30 sec").tag(TimeInterval(30))
                Text("1 min").tag(TimeInterval(60))
                Text("2 min").tag(TimeInterval(120))
                Text("5 min").tag(TimeInterval(300))
                Text("10 min").tag(TimeInterval(600))
                Text("15 min").tag(TimeInterval(900))
                Text("30 min").tag(TimeInterval(1800))
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            .disabled(settings.skipConcealedItems)
        }
        Text("Items marked secret by apps like 1Password are kept with redacted preview, then removed automatically. Turn the toggle on to skip them entirely.")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

Add this private method to `SettingsView`:

```swift
private func addApplicationViaPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    if panel.runModal() == .OK, let url = panel.url {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            let alert = NSAlert()
            alert.messageText = "Couldn't read bundle identifier"
            alert.informativeText = "The selected file does not look like a valid macOS app."
            alert.runModal()
            return
        }
        if !settings.excludedBundleIDs.contains(bundleID) {
            settings.excludedBundleIDs.append(bundleID)
            let count = viewModel.items.filter { $0.sourceBundleID == bundleID }.count
            if count > 0 {
                let alert = NSAlert()
                let name = AppMetadata.shared.displayName(for: bundleID) ?? bundleID
                alert.messageText = "Remove \(count) existing clip\(count == 1 ? "" : "s") from \(name)?"
                alert.informativeText = "These clips were captured before this app was excluded."
                alert.addButton(withTitle: "Remove")
                alert.addButton(withTitle: "Keep")
                if alert.runModal() == .alertFirstButtonReturn {
                    viewModel.purgeItems(matchingBundleID: bundleID)
                }
            }
        }
    }
}
```

Add `import UniformTypeIdentifiers` at the top if not already present (needed for `.application`).

- [ ] **Step 2: Bump Settings window height**

In the same file, in `SettingsWindowController.init()` (~line 156), change:

```swift
contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
```

to:

```swift
contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
```

- [ ] **Step 3: Build to confirm**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Views/SettingsView.swift
git commit -m "feat(settings-ui): add Privacy section and bump window height to 520pt"
```

---

### Task 9: Right-click "Exclude [App]" + retroactive purge dialog + search placeholder

**Files:**
- Modify: `Views/ContentView.swift`
- Modify: `Views/Components/ClipboardItemRow.swift`

UI-only; covered by manual QA in Task 10.

- [ ] **Step 1: Add `onExcludeApp` callback to `ClipboardItemRow`**

Edit `Views/Components/ClipboardItemRow.swift`. Add to the struct's properties (after `var onExtractBarcode`):

```swift
var onExcludeApp: ((String) -> Void)? = nil
```

In `body`, append a `.contextMenu` modifier after the existing `.overlay(...)` modifier:

```swift
.contextMenu {
    if let bundleID = item.sourceBundleID, let onExcludeApp {
        let name = AppMetadata.shared.displayName(for: bundleID) ?? bundleID
        Button("Exclude \"\(name)\" from history") { onExcludeApp(bundleID) }
    } else {
        Text("Source unknown for this clip")
            .foregroundColor(.secondary)
    }
}
```

- [ ] **Step 2: Wire `onExcludeApp` in `ContentView`**

Edit `Views/ContentView.swift`. At the `ClipboardItemRow(...)` instantiation inside the `list` view, add the new closure parameter:

```swift
onExcludeApp: { bundleID in
    confirmExclude(bundleID: bundleID)
}
```

Add this method to `ContentView`:

```swift
private func confirmExclude(bundleID: String) {
    let displayName = AppMetadata.shared.displayName(for: bundleID) ?? bundleID
    let count = viewModel.items.filter { $0.sourceBundleID == bundleID }.count

    let alert = NSAlert()
    alert.messageText = "Exclude \(displayName) from history?"
    alert.informativeText = "MaClip will no longer save clips copied from \(displayName). You can re-enable this in Settings → Privacy."
    alert.addButton(withTitle: "Exclude")
    alert.addButton(withTitle: "Cancel")

    let checkbox = NSButton(checkboxWithTitle: "Also remove \(count) existing clip\(count == 1 ? "" : "s") from history",
                            target: nil, action: nil)
    checkbox.state = .on
    checkbox.isHidden = (count == 0)
    alert.accessoryView = checkbox

    if alert.runModal() == .alertFirstButtonReturn {
        if !AppSettings.shared.excludedBundleIDs.contains(bundleID) {
            AppSettings.shared.excludedBundleIDs.append(bundleID)
        }
        if checkbox.state == .on && count > 0 {
            viewModel.purgeItems(matchingBundleID: bundleID)
        }
    }
}
```

- [ ] **Step 3: Update search-field placeholder**

Find the `TextField(...)` for the search input (currently `"Search…"`). Change to:

```swift
TextField("Search… (try \"from:Safari\")", text: $viewModel.searchText)
```

- [ ] **Step 4: Build to confirm**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Views/ContentView.swift Views/Components/ClipboardItemRow.swift
git commit -m "feat(overlay): right-click Exclude app + search placeholder hint"
```

---

### Task 10: Manual QA matrix

**Files:** none (verification only)

Validates AppKit window state, NSPasteboard concealed UTIs, NSWorkspace activation, drag-out-of-Settings flows, password-manager integration.

- [ ] **Step 1: Build and launch**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' -configuration Debug build && \
~/Library/Developer/Xcode/DerivedData/MacClipboard-*/Build/Products/Debug/MaClip.app/Contents/MacOS/MaClip
```

Grant Accessibility for the new debug binary path if prompted (1.6.0 added the prompt).

- [ ] **Step 2: Walk the matrix**

| # | Scenario | Expected |
|---|---|---|
| 1 | Copy from TextEdit, open overlay | Row shows TextEdit icon at right; tooltip "TextEdit" |
| 2 | Add `com.apple.TextEdit` via Settings → Privacy → Add Application; copy fresh text from TextEdit | Item never appears in history |
| 3 | Right-click an existing TextEdit clip → "Exclude TextEdit"; confirm with checkbox checked | Existing TextEdit clips removed; bundle ID added to Settings list |
| 4 | Same as #3 but uncheck the box | Existing TextEdit clips remain; future TextEdit clips blocked |
| 5 | Copy a password from 1Password 8 (sets ConcealedType). Toggle OFF (default): row shows redacted ••••••, lock icon, ~5 min countdown; click pastes real password into prev app. Toggle ON: never appears in history |
| 6 | Concealed item expires (set timeout to 30 s, copy a password, wait) | Row animates out; selection moves to next item |
| 7 | Search `from:Safari` in overlay | Only Safari-sourced clips shown |
| 8 | Search `from:Safari hello` | Safari-sourced clips containing "hello" |
| 9 | Search `from:com.apple.Safari` | Same as #7 (exact bundle match) |
| 10 | Upgrade scenario: keep an existing 1.6.0 history file | All legacy clips render with placeholder icon + "Unknown source" tooltip |
| 11 | Quit and relaunch with no UserDefaults override | Settings list shows seed bundle IDs |
| 12 | Remove all exclusions from Settings, quit, relaunch | List remains empty (no re-seed) |
| 13 | Settings → + Add Application → pick a non-app file | Error alert "Couldn't read bundle identifier"; list unchanged |
| 14 | Right-click clip with `sourceBundleID == nil` (legacy clip) | Context menu shows "Source unknown for this clip" |
| 15 | Toggle "Skip concealed" ON while a concealed item is in history | Existing concealed item still auto-clears; future concealed items skipped |
| 16 | Open Settings | Window opens at 520pt; all GroupBoxes (Hotkey / Display / Storage / Privacy / Behavior) + Action Buttons fully visible without scroll |

- [ ] **Step 3: If all 16 pass, mark plan complete**

If any fails, return to the implicated task (1–9), fix, and re-run from #1.

---

### Task 11: Bump version to 1.7.0 (build 8)

**Files:**
- Modify: `project.yml`
- Modify: `MacClipboard.xcodeproj/project.pbxproj` (regenerated by xcodegen)

- [ ] **Step 1: Edit `project.yml`**

Change the two version values inside the `MacClipboard` target's `settings:` block:

```yaml
      CURRENT_PROJECT_VERSION: 8
      MARKETING_VERSION: 1.7.0
```

(replace existing values 7 / 1.6.0).

- [ ] **Step 2: Regenerate the project**

```bash
xcodegen generate
```

- [ ] **Step 3: Build + run all tests**

```bash
xcodebuild -scheme MacClipboard -destination 'platform=macOS' \
  -only-testing:MacClipboardTests test 2>&1 | tail -5
```
Expected: PASS for our suites.

- [ ] **Step 4: Commit**

```bash
git add project.yml MacClipboard.xcodeproj/project.pbxproj
git commit -m "chore(version): bump to 1.7.0 (build 8)"
```

---

## Self-Review

**Spec coverage** — every section of `docs/superpowers/specs/2026-05-10-privacy-provenance-design.md` maps to at least one task:

| Spec section | Task |
|---|---|
| Data model fields + decode-with-defaults | 1 |
| `AppSettings` additions + seed | 2 |
| `AppMetadata` helper + cache | 3 |
| Capture flow (self-guard + exclusion + concealed UTIs) | 4 |
| Concealed expiry sweep | 5 |
| Bundle-ID purge helper | 5 |
| `from:` search syntax | 6 |
| Source icon + concealed redaction in row | 7 |
| Settings "Privacy" GroupBox + height bump | 8 |
| Right-click "Exclude [App]" + retroactive dialog | 9 |
| Search placeholder hint | 9 |
| Migration (legacy decode) | 1 (`test_legacyJSONDecodesWithDefaults`) |
| Manual QA matrix (16 scenarios) | 10 |
| Version bump | 11 |

**Placeholder scan:** every code-changing step has a complete code block. No "TBD" / "TODO" / "similar to Task N". Manual QA matrix lists all 16 scenarios verbatim from the spec.

**Type consistency:** `sourceBundleID: String?`, `isConcealed: Bool`, `concealedExpiresAt: Date?` used identically across Tasks 1, 4, 5, 6, 7. `excludedBundleIDs: [String]`, `skipConcealedItems: Bool`, `concealedClearTimeout: TimeInterval` used identically across Tasks 2, 4, 8. `purgeItems(matchingBundleID:)` signature identical in Tasks 5, 8, 9. `runConcealedExpirySweep(now:)` signature identical between Task 5's helper and the timer callsite. `AppMetadata.shared.displayName(for:)` / `.icon(for:)` / `.isCached(bundleID:)` / `.clearCache()` used identically across Tasks 3, 6, 7, 8, 9.
