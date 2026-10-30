# MaClip: open tasks

Last update: 2026-10-30. Latest release: v2.2.1.

Older lists: `docs/superpowers/todo-1.11.0.md` (archived).

## 1. Test v1.13.0 by hand

These steps need a person. They show macOS dialogs or need System Settings.

- [ ] Install `MacClip-1.13.0.dmg` from the release page. Follow the install steps in the DMG window.
- [ ] Pick a clip with "Paste on selection" on. In the MaClip window, click **Continue**. Turn on MaClip in System Settings. The window shows "MaClip can paste now" and closes.
- [ ] Take a screenshot with text (⌃⇧⌘4). In an app with a text field, press ⌃⌥⌘T. The text pastes. Then press ⌘V. The screenshot pastes.
- [ ] Do the same with a QR code and ⌃⌥⌘B.
- [ ] Settings → Storage → **Restore Earlier Clips**. Click Allow in the macOS dialog. The clips from 1.11 and earlier come back.

## 2. Landing page at maclip.jokot.dev

The page is live at `https://maclip.jokot.dev` on Cloudflare Pages. The Download button downloads `MaClip.dmg` from the latest release.

- [ ] Add `https://maclip.jokot.dev` to the GitHub repository "Website" field.

## 3. Code

- [ ] With history encryption on, if the user clicks **Deny** in the Keychain dialog at launch, MaClip shows an empty history. The next save then writes over `history.bin`, and the earlier clips are lost. Keep the encrypted files when the key cannot be read, and show a message. (Not new. This behavior is from 1.9.0.)

## 4. Signing (needs an Apple Developer account, $99 per year)

- [ ] Sign the app with a Developer ID certificate and notarize the DMG in the release workflow. This change removes:
  - the "MaClip.app Not Opened" dialog on the first open,
  - the Keychain dialog after each update, when encryption is on,
  - the step to add MaClip again to Accessibility after each update.
- The workflow then needs these secrets: the certificate (`.p12`, base64), its password, the Apple ID, an app-specific password, and the team ID.

## 5. Later

- [ ] GitHub shows that `googleapis/release-please-action@v4` uses Node 20, which is deprecated. The action still works. Update the action when a version for Node 24 is available.

## 6. Features for IT people

Goal: make MaClip the clipboard app for developers and IT people. Make a design before each feature, and send each feature as a separate PR.

### First: in this order

- [ ] **Secret detection.** Find secrets in text clips: AWS keys (`AKIA…`), GitHub tokens (`ghp_…`, `github_pat_…`), Slack tokens (`xox…`), JWTs, private key blocks (`-----BEGIN … PRIVATE KEY-----`) and `.env` lines such as `API_KEY=…`. Hide these clips in the list and delete them automatically after some minutes, as MaClip does for concealed clips. Add a switch in Settings → Privacy.
- [ ] **Transform actions in ⌘K.** Format or minify JSON. Encode or decode Base64 and URL text. Decode a JWT and show the header, the payload and the expiry date. Convert a Unix time to an ISO date and back. Change the case. Sort lines and remove repeated lines. Remove spaces at the start and end. Paste the result, or save it as a new clip.
- [ ] **Pinned clips and snippets.** Pin a clip, for example an SSH command, an IP address, a kubectl command or an SQL query. Pinned clips stay at the top, and the "Keep up to" limit does not delete them. Give a pinned clip a short keyword to find it.
- [ ] **Safe paste into a terminal.** When the target app is Terminal, iTerm or another terminal, remove a `$ ` prompt at the start of a command. Remove the last newline, so that the command does not run before you press Return. Show a warning before MaClip pastes more than 1 line.

### Second

- [ ] **More content tags:** `tag:ip`, `tag:uuid`, `tag:hash`, `tag:timestamp`, `tag:sql`, `tag:shell`, `tag:path` and `tag:log` (stack traces and log lines).
- [ ] **Better previews.** Code with syntax colors and the name of the language. JSON as a tree. A diff with colors. A timestamp as a date. An IP or CIDR clip with its range. A cron expression with its next run times.
- [ ] **Compare two clips.** Select two clips and show the diff of the two texts, for example two config files or two API responses.
- [ ] **Paste queue.** Copy some values, then paste them in order with one key, for example to fill a form.
- [ ] **`maclip` command-line tool.** `cat log.txt | maclip` adds a clip. `maclip get 3` prints clip 3. `maclip search "kubectl"` finds clips.

### Later

- [ ] **Snippet templates.** A snippet such as `ssh {{user}}@{{host}}`. MaClip asks for each value when you paste it.
- [ ] **Open in an editor.** Open a clip in VS Code or Xcode, or save it as a file, from ⌘K.
- [ ] **Sync between Macs.** Not now: the history can contain secrets, so this feature needs a careful design.

## Done on 2026-10-25

- v1.12.0: history encryption is optional and off by default. The DMG window shows the install steps.
- v1.12.1: the DMG window keeps hidden files away from the install steps.
- v1.13.0: MaClip asks for Accessibility access only when it pastes. ⌃⌥⌘T and ⌃⌥⌘B paste the text or the QR code of the last image.
- Release workflow: `sync-build` runs on each merge, and the release PR builds its DMG one time without an approval. Merges are squash merges, so each PR gives one changelog line.
- The release notes of v1.11.0, v1.12.0 and v1.12.1 are correct.
- The test Keychain item `com.jokot.maclip-acl-experiment` is deleted.
- Merged branches are deleted on GitHub and on this computer.
- PR #28 (open): a copied bare domain such as `example.com` becomes an `https://` link. After this PR, all 156 tests pass.
