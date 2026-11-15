# Secret Detection and Secret Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MaClip finds API keys, tokens and private keys in copied text and handles them as concealed clips, with the kind on the row, "Not a Secret", `tag:secret`, and "Find Secrets in History…". Each kind of secret also gets its own ⌘K actions, such as Copy Masked, the JWT decoder and Copy Public Key, and a facts list in the preview.

**Architecture:** A pure detector (`SecretDetector`) and a pure capture decision (`SecretCapture`) hold all the detection rules, so tests cover them without a pasteboard. `ClipboardItem` gets `secretKind` and `secretDismissed`. The repository saves them as optional fields. The view model owns the "same text again" rule, "Not a Secret", the history scan and the copy results. The actions come from pure helpers: `SecretMask`, `SecretExport`, `JWTDecoder`, `PrivateKeyInspector`, `SecretFacts` and `SecretActions`. The views only show the results.

**Tech Stack:** Swift 5, SwiftUI and AppKit, macOS 13+, CryptoKit, Security, XCTest. No new packages.

**Spec:** `docs/superpowers/specs/2026-10-30-secret-detection-design.md`. Design canvas: https://claude.ai/artifact/REhTjHvSy9VkLAUrrGrAgS (artboards "Clip window — secrets", "Clip window — secret preview", "Clip window — JWT", "Clip window — private key", "Secret actions — menus by kind", "Settings — Privacy", "Secrets in history — messages").

## Global Constraints

- Test command: `xcodebuild -scheme MacClipboard -destination 'platform=macOS' test`. Redirect output to a file in the scratchpad and read the tail.
- After a new Swift file: `xcodegen generate`, then `git checkout -- MacClipboard.xcodeproj/xcshareddata/xcschemes/MacClipboard.xcscheme`.
- **No literal token in any file.** GitHub push protection blocks a push with a real-format token. Tests build tokens at run time, for example `"ghp_" + String(repeating: "a", count: 36)`. The only literal key allowed is `AKIAIOSFODNN7EXAMPLE`.
- Older history files must load: every new saved field is optional.
- A hidden secret never shows its value in a row, the preview, a menu, a help tag or an accessibility label.
- Detection reads at most the first 65,536 characters of a clip.
- Copy: sentence case for row titles, title case for buttons and menu items. Exact strings come from the spec.
- **Test keys are made at run time.** CryptoKit keys, `SecKeyCreateRandomKey` with `kSecAttrIsPermanent: false` (never the keychain), and `-----BEGIN` lines joined from parts. The one fixed key is the public RFC 8032 test 1 key.
- **No network.** "Open Key Page" opens a fixed URL that does not contain the secret. Nothing else leaves the Mac.
- A copy action that holds the secret makes a concealed clip. All copy actions go through one view model method (Task 12).
- Branch `feat/secret-detection`. One PR, title `feat: find secrets in copied text, hide them, and add actions for each kind`, squash merge.

## Review Focus

1. **False matches on normal developer text.** A UUID, a commit hash, a SHA-256 hash, a CSS color, a plain link, `ssh://git@host` and code with `token` in it stay normal clips. Task 1 tests each one.
2. **A copy site that drops the new fields.** About 10 places build a new `ClipboardItem` from an old one. If one drops `secretKind` or `secretDismissed`, an edit makes a secret visible or brings back a dismissed secret. Task 2 moves all of them to one helper and tests an edit.
3. **A text clip that becomes a link clip.** `ClipboardMonitor` turns text such as `https://user:pass@host` into a URL clip. Detection must check the text before that change. Task 4 tests the decision for both paths.
4. **A token already in the history.** The user copies a token that is in the history as a normal clip. The earlier clip must become hidden. Task 5 tests it.
5. **Old history files.** A `history.json` without the new keys loads, and an unknown `secretKind` value loads as no kind. Task 2 tests both.
6. **A copy action that leaks the secret.** Copy Value Only, Copy Password Only and the format actions must make concealed clips. A mask with a mistake must also not leak: the result goes through the detector again. Task 12 tests each path.
7. **Bad input to the key reader.** The DER and OpenSSH readers check each length before they read. Task 10 sends random bytes in a valid key block and expects no crash.
8. **Overlapping matches.** `export GITHUB_TOKEN="ghp_…"` matches the GitHub rule and the keyValue rule. The mask must hide the token once, with the GitHub prefix. Task 7 tests it.

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

### Task 7: Find each secret and mask it

**Files:**
- Modify: `Utilities/SecretDetector.swift`
- Create: `Utilities/SecretMask.swift`
- Test: `Tests/MacClipboardTests/SecretMaskTests.swift`

**Interfaces:**
- Consumes: `SecretKind`, the rules of Task 1.
- Produces:
  - `struct SecretMatch: Equatable { let kind: SecretKind; let range: Range<String.Index>; let value: String; let key: String? }`. `range` is the secret part of the spec. `value` is the full credential. `key` is set for `keyValue` only.
  - `SecretDetector.matches(in text: String, limit: Int? = 65_536) -> [SecretMatch]`: all matches of all rules, sorted by start. When two matches overlap, the match of the earlier rule stays and the other goes. `nil` checks the whole text.
  - `SecretDetector.mainMatch(in text: String, kind: SecretKind) -> SecretMatch?`: the first match of that kind, in the whole text.
  - `SecretMask.masked(_ text: String) -> String` and `SecretMask.redacted(_ text: String) -> String`. Both check the whole text.
  - `SecretMask.hasOtherText(_ text: String) -> Bool`: true when the text has non-space characters outside its secret parts and keys.

- [ ] **Step 1: Write the failing tests.** Build all tokens at run time.
  - `test_masksATokenWithItsPrefixAndLastFour`: `"ghp_" + 32 × "a" + "a1b2"` → `"ghp_••••a1b2"`.
  - `test_hidesTheTailOfAShortSecret`: `DB_PASSWORD=s3cr3t-Pa55w0rd` → `DB_PASSWORD=••••`.
  - `test_masksOnlyThePasswordOfALink`: `postgres://admin:hunter22@db.local:5432/app` → `postgres://admin:••••@db.local:5432/app`.
  - `test_masksOnlyTheLastPartOfAWebhook`: the Slack webhook of Task 1 → the link up to `B000/`, then `••••` and the last 4.
  - `test_aPrivateKeyBecomesALabel`: a block from `-----BEGIN` to `-----END … PRIVATE KEY-----` inside other text → `[Private key]` in the same place.
  - `test_overlapUsesTheEarlierRule`: `export GITHUB_TOKEN="ghp_…a1b2"` → `export GITHUB_TOKEN="ghp_••••a1b2"`, one mask only.
  - `test_redactsEachSecretInALog`: a 3-line log with a GitHub token and a Stripe key → `[REDACTED GitHub token]` and `[REDACTED Stripe key]`, other text unchanged.
  - `test_masksASecretAfterTheDetectionLimit`: 70,000 spaces, then a token → the token is masked.
  - `test_normalTextIsUnchanged`: each text of `test_normalDeveloperTextIsNotASecret` → the same text.
  - `test_hasOtherText`: a token only → false. `"token: " + token + "\nstatus 401"` → true. `DB_PASSWORD=…` → false.
  - `test_matchValues`: the Slack webhook match has `value` = the whole link. The link password match has `value` = the whole link and `range` = the password. The keyValue match has `key == "DB_PASSWORD"`.
- [ ] **Step 2: Run the tests.** Expected: build FAIL, no `SecretMatch`.
- [ ] **Step 3: Implement.** Give each rule of Task 1 a capture group for the secret part. `kind(in:)` keeps its order and speed: it stops at the first rule that matches. `matches` runs every rule on the text, then drops the overlaps. The mask uses the prefix list of the spec section "Masks" and shows the last 4 characters only when the secret part has 20 or more characters. Run `xcodegen generate` and restore the scheme file.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): find each secret in a text and mask it`.

### Task 8: Formats and variable names

**Files:**
- Create: `Utilities/SecretExport.swift`
- Test: `Tests/MacClipboardTests/SecretExportTests.swift`

**Interfaces:**
- Consumes: `SecretMatch`, `SecretDetector.mainMatch` (Task 7).
- Produces:
  - `enum SecretFormat: CaseIterable { case env, shellExport, json, yaml }` with `title` ("Copy as .env", "Copy as Shell Export", "Copy as JSON", "Copy as YAML").
  - `SecretExport.variableName(for match: SecretMatch) -> String?`: the name table of the spec. `nil` for `privateKey` and `jwt`.
  - `SecretExport.pairs(in text: String) -> [(key: String, value: String)]`: every key-value line of the text, secret or not, in the forms `KEY=value`, `export KEY=value`, `KEY: value` and `"KEY": "value",`. Quotes around the value and a comma at the end are removed.
  - `SecretExport.render(_ pairs: [(key: String, value: String)], as format: SecretFormat) -> String`.
  - `SecretExport.text(for text: String, kind: SecretKind, format: SecretFormat) -> String?`: for `keyValue`, `render(pairs(in: text), …)`. For the other kinds, one pair of `variableName` and the main match `value`. `nil` when there is no name or no pair.

- [ ] **Step 1: Write the failing tests.**
  - `test_variableNames`: each row of the spec table. Stripe `sk_` → `STRIPE_SECRET_KEY`, `rk_` → `STRIPE_RESTRICTED_KEY`. `redis://…` → `REDIS_URL`, `amqps://…` → `AMQP_URL`, `postgres://…` → `DATABASE_URL`. A JWT → nil.
  - `test_envQuotesOnlyWhenNeeded`: `abc-123_x.y/z:@%+=,` stays bare. `a b"c\d` → `"a b\"c\\d"`.
  - `test_shellExportUsesSingleQuotes`: `it's` → `export K='it'\''s'`.
  - `test_jsonIsSortedAndFormatted`: two pairs → the `JSONSerialization` output with `[.prettyPrinted, .sortedKeys]`.
  - `test_yamlUsesAJSONStringWhenNeeded`: `a: b` → `K: "a: b"`.
  - `test_pairsReadsEachForm`: a 4-line text with the four forms and a `# comment` line → 4 pairs, no comment.
  - `test_aTokenBecomesOneLine`: a GitHub token, `.shellExport` → `export GITHUB_TOKEN=ghp_…`.
- [ ] **Step 2: Run the tests.** Expected: build FAIL.
- [ ] **Step 3: Implement.** The safe characters are letters, digits and `_ . / : @ % + = , -`. Run `xcodegen generate` and restore the scheme file.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): copy a secret as .env, shell export, JSON or YAML`.

### Task 9: The JWT decoder

**Files:**
- Create: `Utilities/JWTDecoder.swift`
- Test: `Tests/MacClipboardTests/JWTDecoderTests.swift`

**Interfaces:**
- Produces:
  - `struct DecodedJWT: Equatable { let headerJSON: String; let payloadJSON: String; let algorithm: String?; let type: String?; let issuer: String?; let subject: String?; let audience: [String]; let issuedAt: Date?; let expiresAt: Date?; let notBefore: Date?; var isUnsigned: Bool }`. `headerJSON` and `payloadJSON` use `[.prettyPrinted, .sortedKeys]`.
  - `enum JWTStatus: Equatable { case expired(Date), notYetValid(Date), valid(until: Date), noExpiry }`, from `DecodedJWT.status(now: Date) -> JWTStatus`. `notYetValid` comes before `expired`.
  - `JWTStatus.text(now: Date, locale: Locale = .current) -> String`: "Expired 3 days ago", "Not valid until Nov 16, 2026 at 09:00", "Expires in 2 hours", "No expiry date". `isWarning: Bool` is true for `expired` and `notYetValid`.
  - `JWTDecoder.decode(_ token: String) -> DecodedJWT?`: the first JWT in the text. `nil` when the header or the payload is not base64url JSON.

- [ ] **Step 1: Write the failing tests.** A helper builds a token from two dictionaries: base64url of the JSON without `=`, then `.`, then a fixed 20-character signature.
  - `test_readsTheClaims`: `alg`, `typ`, `iss`, `sub`, `aud` as a string, and `iat`, `exp`, `nbf` as integers → all fields.
  - `test_audienceCanBeAList` and `test_dateClaimsCanBeDecimals`.
  - `test_paddingIsOptional`: the same token with `=` padding decodes the same.
  - `test_algNoneIsUnsigned`: `"alg": "None"` → `isUnsigned`.
  - `test_statusText` with `now` fixed and `Locale(identifier: "en_US")`: exp 3 days back → "Expired 3 days ago". exp 2 hours ahead → "Expires in 2 hours". nbf ahead → "Not valid until …". No exp → "No expiry date".
  - `test_theSignatureIsNeverInTheOutput`: neither JSON string contains the signature.
  - `test_badInputIsNil`: a header that is not JSON, and text without a JWT.
- [ ] **Step 2: Run the tests.** Expected: build FAIL.
- [ ] **Step 3: Implement.** Use `RelativeDateTimeFormatter` with `.full` units for the "ago" and "in" parts, and a `DateFormatter` with `.medium` date and `.short` time for the dates. Run `xcodegen generate` and restore the scheme file.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): decode a JWT on the Mac`.

### Task 10: The private key reader

**Files:**
- Create: `Utilities/DERReader.swift`, `Utilities/PrivateKeyInspector.swift`
- Test: `Tests/MacClipboardTests/PrivateKeyInspectorTests.swift`

**Interfaces:**
- Produces:
  - `struct PrivateKeyInfo: Equatable { enum Algorithm: Equatable { case ed25519, rsa(bits: Int), ecdsa(curve: String), dsa, pgp, unknown }; let algorithm: Algorithm; let isEncrypted: Bool; let publicKeyLine: String?; let fingerprint: String? }`.
  - `PrivateKeyInfo.typeText`: "Ed25519", "RSA 4096", "ECDSA P-256", "DSA key", "PGP key" or "Private key".
  - `PrivateKeyInfo.fileName`: `id_ed25519`, `id_rsa`, `id_ecdsa` or `private_key`.
  - `PrivateKeyInfo.keyBlock: String`: the block from `-----BEGIN` to the `-----END …-----` line.
  - `PrivateKeyInspector.inspect(_ text: String) -> PrivateKeyInfo?`: the first key block of the text. `nil` only when there is no block.
  - `DERReader`: reads a tag, a length and the content, and checks each length against the bytes that are left.

- [ ] **Step 1: Write the failing tests.** Build each `-----BEGIN` line from parts.
  - `test_openSSHEd25519`: build an `openssh-key-v1` body at run time: the magic, cipher `none`, KDF `none`, 1 key, the public blob of the RFC 8032 test 1 key (`d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a`), and a private part of random bytes. Expect `.ed25519`, `isEncrypted == false`, `publicKeyLine == "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdamAGCsQq31Uv+08lkBzoO4XLz2qYjJa8CGmj3B1Ea"` and `fingerprint == "SHA256:bbXpuKG6zhzdmnxq256TlqzFBzRl2f6OOg722cYNbU8"`. Both values come from `ssh-keygen -lf`.
  - `test_openSSHWithAPassphraseStillGivesThePublicKey`: the same body with cipher `aes256-ctr` → `isEncrypted == true`, the same public key and fingerprint.
  - `test_pkcs8Ed25519`: the PKCS#8 prefix `302e020100300506032b657004220420`, then the RFC 8032 test 1 seed `9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60` → the same fingerprint as above.
  - `test_pkcs8P256`: `P256.Signing.PrivateKey().pemRepresentation` → `.ecdsa(curve: "P-256")`, and the public key line starts with `ecdsa-sha2-nistp256 `. Also a SEC1 block of a run-time key → the same result.
  - `test_pkcs1RSA`: `SecKeyCreateRandomKey` RSA 2048, `kSecAttrIsPermanent: false`, then `SecKeyCopyExternalRepresentation` in a `RSA PRIVATE KEY` block → `.rsa(bits: 2048)`. The public key line decodes to `ssh-rsa` with the exponent 65537.
  - `test_encryptedPEMHasNoPublicKey`: an `ENCRYPTED PRIVATE KEY` block, and an `RSA PRIVATE KEY` block with `Proc-Type: 4,ENCRYPTED` → `isEncrypted == true`, `publicKeyLine == nil`, `typeText == "Private key"`.
  - `test_dsaAndPGP`: the block names give `.dsa` and `.pgp`, no public key.
  - `test_randomBytesNeverCrash`: 1,000 random bodies of 0 to 600 bytes in each of the four block types → each result is not nil, and nothing crashes.
- [ ] **Step 2: Run the tests.** Expected: build FAIL.
- [ ] **Step 3: Implement.**
  - OpenSSH: read the public blob from the outer part. Do not read the private part.
  - PKCS#1: `n` and `e` from the DER sequence.
  - SEC1 and PKCS#8 EC: `P256`, `P384` and `P521` `.Signing.PrivateKey(pemRepresentation:)`, then the `x963Representation` of the public key.
  - PKCS#8 Ed25519: the 32-byte seed, then `Curve25519.Signing.PrivateKey(rawRepresentation:)`.
  - The SSH blob uses the SSH string and `mpint` encoding (RFC 4253, section 6.6). The fingerprint is the SHA-256 hash of the blob, in base64 without `=`.
  - Run `xcodegen generate` and restore the scheme file.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): read the type, fingerprint and public key of a private key`.

### Task 11: Facts and the list of actions

**Files:**
- Create: `Utilities/SecretActions.swift`
- Test: `Tests/MacClipboardTests/SecretActionsTests.swift`

**Interfaces:**
- Consumes: Tasks 7–10.
- Produces:
  - `struct SecretFact: Equatable { let label: String; let value: String; let isWarning: Bool }`.
  - `SecretFacts.facts(for text: String, kind: SecretKind, now: Date) -> [SecretFact]`: the table of the spec section "Facts about a secret". Stripe `Live` and an expired JWT are warnings.
  - `SecretFacts.rowBadge(for text: String, kind: SecretKind) -> String?`: `"LIVE"` for a live Stripe key, else nil.
  - `enum SecretAction: Equatable { case copyMasked, copyRedacted, copyFormat(SecretFormat), copyKeyOnly, copyValueOnly, copyLinkWithoutPassword, copyPasswordOnly, copyUser, decodeJWT, copyJWTHeader, copyJWTPayload, copyPublicKey, copyFingerprint, saveKeyFile, openKeyPage(provider: String, url: URL) }` with `title: String` and `holdsSecret: Bool`.
  - `SecretActions.actions(for text: String, kind: SecretKind) -> [SecretAction]`: the actions that apply, in the order of the spec table.
  - `SecretActions.copyText(for action: SecretAction, text: String, kind: SecretKind) -> String?`: the text that a copy action copies. `nil` for `decodeJWT`, `saveKeyFile` and `openKeyPage`.

- [ ] **Step 1: Write the failing tests.**
  - `test_menuOfEachKind`: the action titles of a GitHub token, a password in a link, a secret value, a log with a token, a JWT, and a private key. Each list must equal the menu of the kind on the canvas board "Secret actions — menus by kind".
  - `test_keyPages`: each row of the spec table. npm, Discord and keyValue have no `openKeyPage`.
  - `test_holdsSecret`: true for `copyFormat`, `copyValueOnly` and `copyPasswordOnly`. False for the others.
  - `test_factsOfEachKind`: each GitHub prefix, AKIA and ASIA, Stripe live and test, each Slack prefix, the webhook IDs, Anthropic admin, each OpenAI prefix, a link with all parts and a link without a port, and a secret value with 3 lines.
  - `test_jwtWithoutJSONHasNoJWTActions`: a JWT-shaped text that does not decode → no `decodeJWT`, `copyJWTHeader` or `copyJWTPayload`, and no facts.
  - `test_privateKeyWithoutPublicKey`: an encrypted PEM → no `copyPublicKey` or `copyFingerprint`. `saveKeyFile` stays.
  - `test_copyTexts`: Copy Link Without Password, Copy Password Only, Copy User, Copy Key Only, Copy Value Only, Copy Header and Copy Fingerprint give the strings of the spec.
- [ ] **Step 2: Run the tests.** Expected: build FAIL.
- [ ] **Step 3: Implement.** Use `URLComponents` for the link parts. `facts(for:kind:now:)` and `actions(for:kind:)` parse the text when the view asks. Nothing is saved. Run `xcodegen generate` and restore the scheme file.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): list the facts and the actions of each kind`.

### Task 12: Copy results and the key file

**Files:**
- Modify: `ViewModels/ClipboardListViewModel.swift`
- Create: `Services/PrivateKeyFile.swift`
- Test: `Tests/MacClipboardTests/ClipboardListViewModelTests.swift`, `Tests/MacClipboardTests/PrivateKeyFileTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 4, 11.
- Produces:
  - `ClipboardListViewModel.copySecretResult(_ text: String, from source: ClipboardItem, holdsSecret: Bool, skipConcealed: Bool = AppSettings.shared.skipConcealedItems, timeout: TimeInterval = AppSettings.shared.concealedClearTimeout, now: Date = Date())`.
  - `PrivateKeyFile.write(_ keyBlock: String, to url: URL) throws`.

- [ ] **Step 1: Write the failing tests.** Follow the existing tests of `copyToPasteboardAsText` for the pasteboard.
  - `test_aCopyThatHoldsTheSecretIsConcealed`: Copy Value Only of a secret value → a new top clip with `isConcealed`, kind `.keyValue`, and the expiry `now + timeout`. The pasteboard has the text and `org.nspasteboard.ConcealedType`.
  - `test_theDetectedKindWins`: Copy Value Only of `GITHUB_TOKEN=ghp_…` → kind `.githubToken`.
  - `test_aMaskedCopyIsNormal`: Copy Masked → `isConcealed == false`, no kind, no concealed mark.
  - `test_aNormalCopyThatStillHasASecretIsConcealed`: `holdsSecret: false` with a text that contains a token → concealed with `.githubToken`.
  - `test_dontSaveConcealedClipsAddsNoClip`: `skipConcealed: true`, `holdsSecret: true` → the history does not change, and the pasteboard has the text and the mark.
  - `test_theKeyFileHasPermission600`: write to a temporary folder → the file attributes have `posixPermissions == 0o600`, and the file ends with `\n`.
- [ ] **Step 2: Run the tests.** Expected: build FAIL.
- [ ] **Step 3: Implement.**
  - `copySecretResult`: kind = `SecretDetector.kind(in: text)`, else `source.secretKind` when `holdsSecret`. A result with a kind is concealed. Write the pasteboard as `copyToPasteboardAsText` does, and add the concealed type for a concealed result. Call `monitor.ignoreCurrentChangeCount()`. Then insert or move the clip with the flags. For an existing equal clip, use the "same text again" rule of Task 5.
  - `PrivateKeyFile.write`: an atomic write, then `FileManager.setAttributes([.posixPermissions: 0o600])`.
  - Run `xcodegen generate` and restore the scheme file.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS.
- [ ] **Step 5: Commit** `feat(secrets): make each copy of a secret a concealed clip`.

### Task 13: The views of the actions

**Files:**
- Modify: `Views/ContentView.swift` (⌘K menu), `Views/ClipPreview.swift`, `Views/Components/ClipboardItemRow.swift`, `Utilities/Notifications.swift`
- Test: the pure helpers of Tasks 7–11 already cover the strings. Add a test for any new pure helper that this task makes.

**Interfaces:**
- Consumes: Tasks 6, 11, 12.
- Produces: `Notification.Name.overlayDecodeJWT` (object: the clip id).

- [ ] **Step 1: Write a failing test** for each new pure helper, for example the order of the preview buttons of each kind.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement**, as in the canvas:
  - ⌘K: after "Not a Secret", a separator, then `SecretActions.actions(for:kind:)`. Each copy action calls `copySecretResult` with its `holdsSecret`. `decodeJWT` posts `.overlayDecodeJWT`. `saveKeyFile` opens an `NSSavePanel` at `~/.ssh` with `PrivateKeyInfo.fileName`, then calls `PrivateKeyFile.write`. An error shows an `NSAlert`. `openKeyPage` calls `NSWorkspace.shared.open(url)`.
  - Row: the `rowBadge` pill after the kind, orange text on an orange tint. The accessibility label becomes "Concealed clip, Stripe key, live".
  - Preview: the facts list under the main content, in both states. The private key buttons: Not a Secret, Copy Public Key, Paste.
  - Preview, decoded view: on `.overlayDecodeJWT`, select the clip, open the preview, and show the status line, the alg warning, the claims, the header and payload JSON, and the note. The buttons are Copy Header, Copy Payload and Paste. The view ends when the preview closes or the selection moves.
- [ ] **Step 4: Run the tests.** Expected: PASS, and the full suite PASS. Make a Release build and install it, as in Task 6. Check by hand with test values that you build in Terminal:
  - A JWT: `h=$(printf '{"alg":"HS256","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')`, `p=$(printf '{"sub":"user_1","exp":1700000000}' | base64 | tr '+/' '-_' | tr -d '=')`, then `printf '%s.%s.%s' "$h" "$p" "$(printf 's%.0s' {1..20})" | pbcopy`. ⌘K → Decode JWT shows "Expired …".
  - A token: ⌘K → Copy Masked, Copy as Shell Export (a new hidden clip), Open Key Page on GitHub.
  - A link: `printf 'postgres://admin:%s@db.local:5432/app' hunter22 | pbcopy`. ⌘K → Copy Link Without Password, Copy Password Only (a new hidden clip).
  - A private key: `ssh-keygen -t ed25519 -N '' -f "$S/k" -q && pbcopy < "$S/k"`. The facts show the same fingerprint as `ssh-keygen -lf "$S/k"`. Copy Public Key equals `cut -d' ' -f1,2 "$S/k.pub"`. Save as File… writes a file with `-rw-------`. Delete `$S/k*` and the saved file after the check.
  - Open each key page URL of the spec in a signed-in browser. Remove a row whose page does not open, in the code and in the spec.
- [ ] **Step 5: Commit** `feat(secrets): show the secret actions, the facts and the JWT view`.

### Task 14: Docs and PR

**Files:**
- Modify: `README.md` (Features list), `docs/superpowers/todo.md` (section 6)

- [ ] **Step 1:** Add to README Features, after the concealed line:
  - "Find API keys, tokens and private keys in copied text. MaClip hides them as concealed clips. Search with `tag:secret`."
  - "Actions for each kind of secret in ⌘K: decode a JWT, copy the public key of a private key, copy a log with its secrets masked, and more. Nothing leaves your Mac."
- [ ] **Step 2:** In todo section 6, mark secret detection done, and write that the "Decode a JWT" item of the transform actions is done for detected JWTs.
- [ ] **Step 3:** Run the full suite. Expected: PASS.
- [ ] **Step 4: Commit** `docs: describe secret detection and secret actions in the README`, push `feat/secret-detection`, open the PR.
