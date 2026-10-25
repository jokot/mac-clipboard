# MaClip: open tasks

Last update: 2026-10-25. Latest release: v1.13.0 (build 18).

Older lists: `docs/superpowers/todo-1.11.0.md` (archived).

## 1. Test v1.13.0 by hand

These steps need a person. They show macOS dialogs or need System Settings.

- [ ] Install `MacClip-1.13.0.dmg` from the release page. Follow the install steps in the DMG window.
- [ ] Pick a clip with "Paste on selection" on. In the MaClip window, click **Continue**. Turn on MaClip in System Settings. The window shows "MaClip can paste now" and closes.
- [ ] Take a screenshot with text (⌃⇧⌘4). In an app with a text field, press ⌃⌥⌘T. The text pastes. Then press ⌘V. The screenshot pastes.
- [ ] Do the same with a QR code and ⌃⌥⌘B.
- [ ] Settings → Storage → **Restore Earlier Clips**. Click Allow in the macOS dialog. The clips from 1.11 and earlier come back.

## 2. Landing page at maclip.jokot.dev

Goal: one public page for MaClip at `https://maclip.jokot.dev`.

- [ ] Write the page: what MaClip does, screenshots or the demo video from the README, the feature list, and a download button.
- [ ] The download button opens the newest DMG. Use `https://github.com/jokot/mac-clipboard/releases/latest`, so the page does not change for each release.
- [ ] Show the install steps ("Open Anyway" and the `xattr` command). MaClip is not notarized, so each new user sees the Gatekeeper dialog.
- [ ] Choose the host. Both are free for a static page:
  - GitHub Pages from this repository, for example from a `site/` folder with a workflow.
  - Cloudflare Pages. The DNS of `jokot.dev` is already on Cloudflare (`kristin.ns.cloudflare.com`, `walt.ns.cloudflare.com`).
- [ ] Add the DNS record for `maclip.jokot.dev` in Cloudflare. GitHub Pages needs a CNAME record to `jokot.github.io`. Cloudflare Pages adds its record when you connect the domain.
- [ ] Turn on HTTPS for the domain, and check `https://maclip.jokot.dev` on a phone and on a Mac.
- [ ] Add the link to the README and to the GitHub repository "Website" field.

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

## Done on 2026-10-25

- v1.12.0: history encryption is optional and off by default. The DMG window shows the install steps.
- v1.12.1: the DMG window keeps hidden files away from the install steps.
- v1.13.0: MaClip asks for Accessibility access only when it pastes. ⌃⌥⌘T and ⌃⌥⌘B paste the text or the QR code of the last image.
- Release workflow: `sync-build` runs on each merge, and the release PR builds its DMG one time without an approval. Merges are squash merges, so each PR gives one changelog line.
- The release notes of v1.11.0, v1.12.0 and v1.12.1 are correct.
- The test Keychain item `com.jokot.maclip-acl-experiment` is deleted.
- Merged branches are deleted on GitHub and on this computer.
- PR #28 (open): a copied bare domain such as `example.com` becomes an `https://` link. After this PR, all 156 tests pass.
