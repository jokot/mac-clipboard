# Secret Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MaClip finds API keys, tokens and private keys in copied text and handles them as concealed clips, with the kind on the row, "Not a Secret", `tag:secret`, and "Find Secrets in History…".

**Architecture:** A pure detector (`SecretDetector`) and a pure capture decision (`SecretCapture`) hold all the rules, so tests cover them without a pasteboard. `ClipboardItem` gets `secretKind` and `secretDismissed`. The repository saves them as optional fields. The view model owns the "same text again" rule, "Not a Secret" and the history scan. The views only show the result.

**Tech Stack:** Swift 5, SwiftUI and AppKit, macOS 13+, XCTest. No new packages.

**Spec:** `docs/superpowers/specs/2026-10-30-secret-detection-design.md`. Design canvas: https://claude.ai/artifact/REhTjHvSy9VkLAUrrGrAgS (artboards "Clip window — secrets", "Clip window — secret preview", "Settings — Privacy", "Secrets in history — messages").

## Global Constraints

- Test command: `xcodebuild -scheme MacClipboard -destination 'platform=macOS' test`. Redirect output to a file in the scratchpad and read the tail.
- After a new Swift file: `xcodegen generate`, then `git checkout -- MacClipboard.xcodeproj/xcshareddata/xcschemes/MacClipboard.xcscheme`.
- **No literal token in any file.** GitHub push protection blocks a push with a real-format token. Tests build tokens at run time, for example `"ghp_" + String(repeating: "a", count: 36)`. The only literal key allowed is `AKIAIOSFODNN7EXAMPLE`.
- Older history files must load: every new saved field is optional.
- A hidden secret never shows its value in a row, the preview, a menu, a help tag or an accessibility label.
- Detection reads at most the first 65,536 characters of a clip.
- Copy: sentence case for row titles, title case for buttons and menu items. Exact strings come from the spec.
- Branch `feat/secret-detection`. One PR, title `feat: find secrets in copied text and hide them`, squash merge.

## Review Focus

1. **False matches on normal developer text.** A UUID, a commit hash, a SHA-256 hash, a CSS color, a plain link, `ssh://git@host` and code with `token` in it stay normal clips. Task 1 tests each one.
2. **A copy site that drops the new fields.** About 10 places build a new `ClipboardItem` from an old one. If one drops `secretKind` or `secretDismissed`, an edit makes a secret visible or brings back a dismissed secret. Task 2 moves all of them to one helper and tests an edit.
3. **A text clip that becomes a link clip.** `ClipboardMonitor` turns text such as `https://user:pass@host` into a URL clip. Detection must check the text before that change. Task 4 tests the decision for both paths.
4. **A token already in the history.** The user copies a token that is in the history as a normal clip. The earlier clip must become hidden. Task 5 tests it.
5. **Old history files.** A `history.json` without the new keys loads, and an unknown `secretKind` value loads as no kind. Task 2 tests both.

---

### Task 1: The detector

**Files:**
- Create: `Utilities/SecretDetector.swift`
- Test: `Tests/MacClipboardTests/SecretDetectorTests.swift`

**Interfaces:**
- Produces:
  - `enum SecretKind: String, CaseIterable, Codable` with the cases of the spec table in table order: `privateKey, awsAccessKey, githubToken, gitlabToken, slackToken, slackWebhook, discordWebhook, stripeKey, anthropicKey, openAIKey, googleAPIKey, npmToken, jwt, linkPassword, keyValue`.
  - `SecretKind.title: String`: the "Name on the row" column ("GitHub token").
  - `SecretKind.count(_ n: Int) -> String`: the number and the name in lower case except for brand names and acronyms, with an `s` for more than one: "1 GitHub token", "2 GitHub tokens", "1 private key", "3 secret values", "2 JWTs". The one exception: `linkPassword` gives "1 password in a link" and "2 passwords in links".
  - `enum SecretDetector { static func kind(in text: String) -> SecretKind? }`

- [ ] **Step 1: Write the failing tests**

A helper `tokens` builds every positive sample at run time. Cases:

```swift
func test_findsEachKind() {
    let a36 = String(repeating: "a", count: 36)
    let cases: [(String, SecretKind)] = [
        ("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----", .privateKey),
        ("-----BEGIN PRIVATE KEY-----", .privateKey),
        ("AKIAIOSFODNN7EXAMPLE", .awsAccessKey),
        ("ghp_" + a36, .githubToken),
        ("github_pat_" + String(repeating: "A1_", count: 10), .githubToken),
        ("glpat-" + String(repeating: "x1", count: 10), .gitlabToken),
        ("xoxb-" + String(repeating: "1", count: 12) + "-abc", .slackToken),
        ("https://hooks.slack.com/services/" + "T000/B000/" + String(repeating: "X", count: 24), .slackWebhook),
        ("https://discord.com/api/webhooks/123456/" + String(repeating: "a", count: 30), .discordWebhook),
        ("sk_" + "live_" + String(repeating: "a", count: 24), .stripeKey),
        ("sk-" + "ant-" + String(repeating: "a", count: 30), .anthropicKey),
        ("sk-" + "proj-" + String(repeating: "a", count: 30), .openAIKey),
        ("AIza" + String(repeating: "a", count: 35), .googleAPIKey),
        ("npm_" + a36, .npmToken),
        ("eyJ" + "hbGciOiJIUzI1NiJ9" + ".eyJ" + "zdWIiOiIxMjM0In0" + "." + String(repeating: "s", count: 20), .jwt),
        ("postgres://admin:" + "hunter22" + "@db.local:5432/app", .linkPassword),
        ("DB_PASSWORD=" + "s3cr3t-Pa55w0rd", .keyValue),
        ("export API_KEY=\"" + String(repeating: "k", count: 7) + "9\"", .keyValue),
        ("client_secret: " + "abcd1234efgh", .keyValue),
        ("  \"client_secret\": \"" + "abcd1234efgh" + "\",", .keyValue),
    ]
    for (text, kind) in cases { XCTAssertEqual(SecretDetector.kind(in: text), kind, text.prefix(20).description) }
}

func test_aKnownFormatWinsOverKeyValue() {
    XCTAssertEqual(SecretDetector.kind(in: "export GITHUB_TOKEN=\"ghp_" + String(repeating: "a", count: 36) + "\""), .githubToken)
}

func test_anthropicIsCheckedBeforeOpenAI() {
    XCTAssertEqual(SecretDetector.kind(in: "sk-" + "ant-" + String(repeating: "b", count: 30)), .anthropicKey)
}

func test_normalDeveloperTextIsNotASecret() {
    for text in [
        "123e4567-e89b-12d3-a456-426614174000",
        "a0036a7f3c9d1e2b4f5a6c7d8e9f0a1b2c3d4e5f",
        String(repeating: "ab12", count: 16),            // SHA-256 shape
        "#5E5CE6",
        "https://github.com/jokot/mac-clipboard",
        "ssh://git@github.com/jokot/mac-clipboard.git",
        "let total = items.reduce(0) { $0 + $1.price }",
        "const token = req.headers.authorization",
        "Copy the token from the dashboard.",
        "password = getPassword()",
        "API_KEY=${API_KEY}",
        "TOKEN_TTL=3600",
        "SECRET_KEY=<your-key>",
        "PASSWORD=changeme",
        "API_TOKEN=your_token_here",
        "DB_PASSWORD=xxxxxxxxxx",
        "AUTH_TOKEN=null",
    ] {
        XCTAssertNil(SecretDetector.kind(in: text), text)
    }
}

func test_readsOnlyTheFirst65536Characters() {
    let late = String(repeating: " ", count: 65_536) + "ghp_" + String(repeating: "a", count: 36)
    XCTAssertNil(SecretDetector.kind(in: late))
}

func test_isFastOnALongText() {
    let text = String(repeating: "let value = compute(index) // no secret here\n", count: 1_500)  // ~66k chars
    let start = Date()
    _ = SecretDetector.kind(in: text)
    XCTAssertLessThan(Date().timeIntervalSince(start), 0.05, "Debug build limit. The Release target is 5 ms.")
}

func test_countTextUsesSingularAndPlural() {
    XCTAssertEqual(SecretKind.githubToken.count(1), "1 GitHub token")
    XCTAssertEqual(SecretKind.githubToken.count(2), "2 GitHub tokens")
    XCTAssertEqual(SecretKind.jwt.count(3), "3 JWTs")
    XCTAssertEqual(SecretKind.privateKey.count(1), "1 private key")
    XCTAssertEqual(SecretKind.linkPassword.count(2), "2 passwords in links")
}
```

- [ ] **Step 2: Run the tests.** Expected: build FAIL, "cannot find 'SecretDetector' in scope".
- [ ] **Step 3: Implement `Utilities/SecretDetector.swift`.** One `NSRegularExpression` per kind, compiled once in a `static let` array in table order. `kind(in:)` takes `text.prefix(65_536)`, then returns the first kind whose regex matches. `keyValue` and `linkPassword` use a regex for the outline and a Swift check for the placeholder rules of the spec. Run `xcodegen generate` and restore the scheme file.
- [ ] **Step 4: Run the tests.** Expected: all `SecretDetectorTests` PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): detect API keys, tokens and private keys in text`.

### Task 2: Save the kind with the clip

**Files:**
- Modify: `Models/ClipboardItem.swift`, `Services/ClipboardRepository.swift` (Record, load, save), `ViewModels/ClipboardListViewModel.swift` (copy sites)
- Test: `Tests/MacClipboardTests/ClipboardItemRepositoryTests.swift`, `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`

**Interfaces:**
- Consumes: `SecretKind` (Task 1).
- Produces:
  - `ClipboardItem.secretKind: SecretKind?` and `ClipboardItem.secretDismissed: Bool`, both with default values in `init` (`nil`, `false`), after `isOCRResult`.
  - `ClipboardItem.replacing(content: ClipboardItemContent) -> ClipboardItem`: same id, date and all flags, new content.
  - `ClipboardItem.marked(concealed: Bool, expiresAt: Date?, secretKind: SecretKind?, secretDismissed: Bool) -> ClipboardItem`: same id, date, content and source, new flags.
  - Record fields `secretKind: String?` and `secretDismissed: Bool?`.

- [ ] **Step 1: Write the failing tests.**
  - `test_secretFieldsRoundTrip`: save a text clip with `secretKind: .githubToken`, `secretDismissed: false`, and a second clip with `secretKind: nil`, `secretDismissed: true`. Load. Both values match. Run it once with encryption off and once on, as the other round-trip tests do.
  - `test_historyWithoutSecretKeysLoads`: write a `history.json` with the 1.10 record shape (no new keys). It loads with `secretKind == nil` and `secretDismissed == false`.
  - `test_unknownSecretKindLoadsAsNoKind`: a record with `"secretKind": "futureKind"` and `"isConcealed": true` loads with `secretKind == nil` and `isConcealed == true`.
  - `test_editKeepsTheSecretFlags` (view model): a clip with `isConcealed: true`, an expiry and `secretKind: .keyValue`. `replaceContent(of:with: .text("new"))`. The result keeps all three values.
- [ ] **Step 2: Run the tests.** Expected: build FAIL on the unknown init arguments.
- [ ] **Step 3: Implement.** Add the fields and the two helpers. Replace every `ClipboardItem(id: existing.id, …)` copy in `ClipboardListViewModel.swift` and `ClipboardRepository.swift` with `replacing(content:)` or with an init that passes the new fields. Find them with `grep -n "isOCRResult: existing\|isOCRResult: item\|isOCRResult: source\|isOCRResult: rec" -r ViewModels Services`. `insertImage(pngData:from:)` keeps `secretKind` and `secretDismissed` of `source`. Save `secretKind?.rawValue`. On load, `SecretKind(rawValue:)` gives nil for an unknown value.
- [ ] **Step 4: Run the tests.** Expected: the new tests PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): save the secret kind with each clip`.

### Task 3: The setting

**Files:**
- Modify: `Models/AppSettings.swift`
- Test: `Tests/MacClipboardTests/AppSettingsTests.swift`

**Interfaces:**
- Produces: `AppSettings.findSecrets: Bool` (`@Published`, key `"settings.findSecrets"`, default `true`).

- [ ] **Step 1: Write the failing tests.** `test_findSecretsIsOnByDefault` (empty defaults → `true`). `test_findSecretsIsSaved` (set `false`, read the defaults key → `false`). Add to the existing `RestoreDefaultSettingsTests`: after `restoreDefaultSettings()` and after `restorePrivacyDefaults()`, `findSecrets == true`.
- [ ] **Step 2: Run the tests.** Expected: build FAIL, no member `findSecrets`.
- [ ] **Step 3: Implement.** Follow `saveMaClipClips`: a `Keys` entry, `didSet` that writes the key, an initial value in `init`, and `findSecrets = true` in `restorePrivacyDefaults()`.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): add the Find secrets in copied text setting`.

### Task 4: Hide secrets when they are copied

**Files:**
- Create: `Services/SecretCapture.swift`
- Modify: `Services/ClipboardMonitor.swift`
- Test: `Tests/MacClipboardTests/SecretCaptureTests.swift`

**Interfaces:**
- Consumes: `SecretDetector.kind(in:)`, `AppSettings.findSecrets`, `skipConcealedItems`, `concealedClearTimeout`.
- Produces:
  - `enum SecretCapture.Decision: Equatable { case skip; case save(isConcealed: Bool, expiresAt: Date?, secretKind: SecretKind?) }`
  - `static func decide(text: String?, hasConcealedMark: Bool, findSecrets: Bool, skipConcealed: Bool, timeout: TimeInterval, now: Date) -> Decision`. `text` is nil for an image clip or a file clip.

- [ ] **Step 1: Write the failing tests.** With `now = Date(timeIntervalSince1970: 1_000)`:
  - A GitHub token, no mark, `findSecrets` on, `skipConcealed` off, timeout 300 → `.save(true, now + 300, .githubToken)`.
  - The same with timeout `-1` → `.save(true, .distantFuture, .githubToken)`.
  - The same with `skipConcealed` on → `.skip`.
  - The same with `findSecrets` off → `.save(false, nil, nil)`.
  - Normal text, no mark → `.save(false, nil, nil)`.
  - Normal text with the mark → `.save(true, now + 300, nil)`. With the mark and `skipConcealed` on → `.skip`.
  - A token with the mark → `.save(true, now + 300, .githubToken)`.
  - `text: nil` with the mark → `.save(true, now + 300, nil)`. Without the mark → `.save(false, nil, nil)`.
  - `"https://admin:" + "hunter22" + "@db.local"` → kind `.linkPassword`. This is the text that the monitor later turns into a URL clip.
- [ ] **Step 2: Run the tests.** Expected: build FAIL, no `SecretCapture`.
- [ ] **Step 3: Implement.** `decide` holds the rules of the spec section "New clips". In `ClipboardMonitor.pollPasteboard()`, replace the concealed block with one `decide` call. Read the text first: for a file or image clip pass `nil`. For a pasteboard URL pass `url.absoluteString`. For text pass the raw text, before `URLUtils.linkURL`. Pass the decision values into each `ClipboardItem` that the monitor sends. Run `xcodegen generate` and restore the scheme file.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): hide a secret when it is copied`.

### Task 5: The view model

**Files:**
- Create: `Utilities/SecretScan.swift`
- Modify: `ViewModels/ClipboardListViewModel.swift`
- Test: `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`, `Tests/MacClipboardTests/SecretScanTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `struct SecretScan { let checked: Int; let found: [(id: UUID, kind: SecretKind)] }` with `title: String`, `message: String` and `isEmpty: Bool`. `title` and `message` use the exact strings of the spec section "Find Secrets in History".
  - `ClipboardListViewModel.dismissSecret(_ item: ClipboardItem)`
  - `ClipboardListViewModel.scanHistoryForSecrets() -> SecretScan`
  - `ClipboardListViewModel.hideSecrets(_ scan: SecretScan)` and `deleteSecrets(_ scan: SecretScan)`
  - `tag:secret` in `filteredItems`.

- [ ] **Step 1: Write the failing tests.**
  - `test_copyingASecretAgainHidesTheEarlierClip`: history has a normal text clip with a token. The monitor emits the same text with `isConcealed: true`, an expiry and `.githubToken`. The top clip has the same id as before, `isConcealed == true`, the new expiry and `.githubToken`.
  - `test_aDismissedSecretStaysVisibleWhenCopiedAgain`: the same, but the earlier clip has `secretDismissed: true`. The top clip stays `isConcealed == false`.
  - `test_notASecretShowsTheClip`: `dismissSecret` on a hidden secret gives `isConcealed == false`, `concealedExpiresAt == nil`, `secretKind == nil`, `secretDismissed == true`, and the repository saves.
  - `test_scanFindsSecretsAndSkipsConcealedAndDismissedClips`: history with 1 token, 1 private key, 1 normal text, 1 concealed clip with a token, 1 dismissed clip with a token, 1 image. `checked == 4` (text and link clips that are not concealed or dismissed), `found` has 2 entries.
  - `test_hideSecretsHasNoCountdown`: after `hideSecrets`, the found clips have `isConcealed == true`, `concealedExpiresAt == nil` and their kinds.
  - `test_deleteSecretsRemovesTheClips`.
  - `test_tagSecretFindsClipsWithAKind`: `searchText = "tag:secret"` returns only the clips with a kind.
  - `SecretScanTests`: 0 found → "No secrets found" / "MaClip checked 4 clips." 1 found → "1 secret found" / "1 GitHub token. Hide it, or delete it now." 3 found → "3 secrets found" / "1 private key and 2 GitHub tokens. Hide them, or delete them now." 5 kinds → the first 3 kinds in table order, then "and N other secrets".
- [ ] **Step 2: Run the tests.** Expected: build FAIL on the missing members.
- [ ] **Step 3: Implement.**
  - In `append(_:)`, before "already on top": if the new item has a `secretKind`, and the earlier clip is not concealed and not dismissed, replace the earlier clip with `existing.marked(concealed: true, expiresAt: item.concealedExpiresAt, secretKind: item.secretKind, secretDismissed: false)`. Then move it to the top. Save.
  - In `filteredItems`, treat `tag:secret` as its own filter, before the `ContentTag(rawValue:)` lookup. It keeps clips with `secretKind != nil`.
  - "Hide it" for one secret, "Hide them" for more than one. Run `xcodegen generate` and restore the scheme file.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): add Not a Secret, tag:secret and the history scan`.

### Task 6: The views

**Files:**
- Modify: `Views/Components/ClipboardItemRow.swift`, `Views/ClipPreview.swift`, `Views/ContentView.swift` (⌘K menu), `Views/SettingsView.swift` (Privacy tab and alert)
- Test: `Tests/MacClipboardTests/ClipboardListViewModelTests.swift` or a new `SecretViewTextTests.swift` for the strings that the views read

**Interfaces:**
- Consumes: Tasks 2, 3, 5.
- Produces: no new API for later tasks.

- [ ] **Step 1: Write the failing tests.** Move the view strings into small pure functions next to the existing helpers, and test them:
  - `ClipPreviewInfo.concealedTitle(for:)`: "This clip is a GitHub token" for a kind, "This clip is concealed" without.
  - `ClipPreviewInfo.countdownLine(until:now:)`: "MaClip deletes it in 4:32." for a date, nil for `.distantFuture` or nil.
  - The ⌘K actions: extract `ContentView.menuTitles(for:)`, or test the existing builder if it is reachable. A detected secret has "Not a Secret" directly after "Show for 5 Seconds", without a key. A concealed clip without a kind does not have it.
  - The settings focus IDs: `findSecrets` and `findSecretsInHistory` follow `concealedTimeout`, if the focus order has a test.
- [ ] **Step 2: Run the tests.** Expected: FAIL on the missing functions.
- [ ] **Step 3: Implement**, as in the canvas:
  - Row: after the masked dots, the kind title in secondary text. The accessibility label says "Concealed clip, GitHub token", never the value.
  - Preview: the title and the countdown line. In the header, the kind after the date. "Not a Secret" in place of "Edit…" for a detected secret.
  - ⌘K: "Not a Secret" calls `dismissSecret`.
  - Privacy tab: the Secrets section after "Concealed clips", with `SettingsSwitch` and `.settingsFocus("findSecrets", toggle:)`, and the button with `.settingsFocus("findSecretsInHistory", press:)`. The button runs `scanHistoryForSecrets()` and shows an `NSAlert`: for no secrets, one OK button. Else "Delete N Clips" (`hasDestructiveAction`), "Hide", and "Cancel" (Esc).
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS. Then make a Release build and install it:
  ```bash
  S=<scratchpad>
  xcodebuild -scheme MacClipboard -configuration Release BUILD_DIR="$S/relbuild" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= clean build > "$S/rel.log" 2>&1; tail -3 "$S/rel.log"
  osascript -e 'quit app "MaClip"'; rm -rf /Applications/MaClip.app && ditto "$S/relbuild/Release/MaClip.app" /Applications/MaClip.app && open /Applications/MaClip.app
  ``` Check by hand: copy a built token from Terminal (`printf 'ghp_%s' $(printf 'a%.0s' {1..36}) | pbcopy`), open the clip window, see the hidden row with "GitHub token"; ⌘K → Not a Secret shows the text; Settings → Privacy → Find Secrets in History… shows the alert.
- [ ] **Step 5: Commit** `feat(secrets): show the kind of secret and add the Secrets settings`.

### Task 7: Docs and PR

**Files:**
- Modify: `README.md` (Features list), `docs/superpowers/todo.md` (section 6: mark secret detection done when merged)

- [ ] **Step 1:** Add to README Features, after the concealed line: "Find API keys, tokens and private keys in copied text. MaClip hides them as concealed clips. Search with `tag:secret`."
- [ ] **Step 2:** Run the full suite. Expected: PASS.
- [ ] **Step 3: Commit** `docs: describe secret detection in the README`, push `feat/secret-detection`, open the PR.
