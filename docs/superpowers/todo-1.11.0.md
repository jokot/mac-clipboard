# MaClip 1.11.0: open tasks

Branch: `feature/1.11.0-image-edit`. Last update: 2026-10-21.

QA history: the scripted test run added test clips. History was restored from the 19:37 backup after the run.

Spec: `docs/superpowers/specs/2026-07-16-1.11.0-image-edit-design.md`.
Plan: `docs/superpowers/plans/2026-07-16-1.11.0-image-edit.md`.

## 1. Commits

Committed on 2026-10-21. Each commit builds with its tests.

- [x] `737b087 fix(tests): isolate test storage from real user data`
- [x] `7f6c122 fix(editor): composite edits in top-left image space`
- [x] `3e5b6bb fix(row): reload image preview when the clip file changes`
- [x] `b4d1c6e revert(overlay): make the overlay a fixed 520x600 window again`
- [x] `e2efe93 feat(editor): open the image editor in a separate window`
- [x] `a21fff1 fix(editor): show crop and rotation in the canvas, fix the text tool`
- [x] `0ffd8bc test: cover image edit save paths from the 1.11.0 QA list`
- [x] `4a2d067 chore(settings): set the default history limit to 50`
- [x] `69aa049 docs: add 1.11.0 todo with QA results and open decisions`
- [x] `2436839 fix(editor): handle save failure, Esc mid-drag, concealed copies`

## 2. Manual QA

Use a new screenshot (⌃⇧⌘4). Images edited before the compositor fix keep the flipped edits.

Scripted UI run on 2026-10-21: every row passes, after the fixes in 2.4. Unit tests: 121, with 2 known failures in `URLUtilsTests`.

### 2.1 Retest of issues found on 2026-10-19

| ID | Steps | Expected | Result |
|---|---|---|---|
| A | Right-click an image clip → **Edit…** | Overlay hides. A separate "Edit Image" window opens. | PASS (scripted, 2026-10-21). |
| B | Draw an arrow near the top-left corner → **Save** | Window closes. Focus goes back to the previous app. The clip preview shows the arrow at the top-left immediately. | PASS. Preview updated immediately. Saved PNG: arrow at x 28–121, y 29–91, as drawn. |
| C | Open the same clip in the editor again | Arrow is at the top-left. | PASS. |
| D | Draw a rectangle and a redact box → **Save as new** | New clip at the top shows both layers at the correct position. Original clip does not change. | PASS. New clip has all layers at the drawn position. Original has the arrow only. |
| E | Immediately after B or D, take a screenshot with ⌃⇧⌘4 | The screenshot shows as a new clip. | PASS. Focus returned to the previous app. The next copied image was captured. |

### 2.2 Spec QA matrix

| Spec # | Steps | Expected | Result |
|---|---|---|---|
| 4 | Crop tool → drag a box → Save | Clip is cropped to the box. The crop applies on mouse release. There is no Apply button. | PASS (retest after fix). Crop tool dims the removed area and outlines the crop. Other tools show only the crop. Saved output 193×144. |
| 5 | Rotate clockwise → Save | Image turns clockwise. Width and height swap. | PASS (retest after fix). The editor shows the rotation. Saved output 300×400, correct direction. |
| 19 | Draw a rectangle → rotate clockwise → ⌘Z | Rotation is undone. Rectangle stays. | PASS. ⌘Z undid the rotation. The rectangle stayed in the editor and in the saved PNG. |
| 6, 7 | Draw 3 shapes → ⌘Z → ⌘⇧Z | ⌘Z removes the last shape. ⌘⇧Z restores it. | PASS. ⌘Z removed one box. ⌘⇧Z restored it. |
| 8 | Make 21 changes → press ⌘Z 21 times | 20 undo steps work. Step 21 does nothing. | PASS. After 20 undos, only the first change was left and Undo was disabled. Undo 21 did nothing. |
| 11 | Text tool → click → type "hi 123" → Return | Text layer shows "hi 123". Color does not change. | PASS (retest after fix). "hi 123" typed with digits. Color stayed red. Return added the text and did not save. |
| 15 | With no text field open, press 3 | Color changes to yellow. | PASS. Key 3 made the next rectangle yellow. |
| 20 | Open the editor and make no change | Save and Save as new are disabled. | PASS. Save and Save as new did nothing with no edits. |
| 10 | Make an edit → Esc | Window closes. No change is saved. | PASS. Window closed. No file saved. Focus went back to the previous app. |
| — | Make an edit → red close button | Same result as Esc. | PASS. Same result as Esc. |
| — | With the editor open, open the overlay and choose Edit… on a different image | The open editor comes to the front. Its edits stay. | PASS. The same editor window came to the front. Its arrow was still there. |
| 18 | Redact over text → Save → paste into Preview | The box is opaque black. | PASS. Redact over the blue block saved opaque black. No blue pixels left. |
| 12 | Edit a concealed clip (lock badge) → Save | Clip stays concealed. Badge stays. | PASS. Lock overlay and expiry badge stayed after Save. |
| 13 | Edit an image larger than 4096 px on one side | Alert: "Image too large to edit in v1.11.0 (max 4096 px)." | PASS. 5000×100 image showed the alert. The editor did not open. |
| 17 | Save an edit → quit MaClip → start MaClip | Edited image is still there and opens correctly. | PASS. After quit and start, the edited clip had the redact box at the same position. |
| — | Open the overlay | Size is 520×600. The window cannot be resized. | PASS. A corner drag did not change the 520×600 bounds. |

### 2.3 Changed or removed scenarios

- **#9** (Esc during a pen stroke): Esc cancels only the stroke (`2436839`).
- **#14** (overlay hides during an edit): no longer possible. The overlay hides when the editor opens.
- **#16** (disk full): tested with a read-only Images folder. The alert shows and the editor stays open (`2436839`).
- **#21–24** (overlay resize): removed with the resizable overlay.

### 2.4 Bugs found in the scripted run (2026-10-21)

- [x] **Text field has no focus.** After a click with the text tool, the field shows but does not take keyboard input. Fix: focus the field when it appears.
- [x] **Return saves the image during text entry.** Save has `.keyboardShortcut(.defaultAction)`. When the text field is not focused, Return closes the editor and saves without the text.
- [x] **Crop has no visual feedback.** `CanvasView` draws the full base image after a crop. Only the saved PNG shows the crop.
- [x] **Rotation has no visual feedback.** `CanvasView` ignores `rotationQuarterTurns`. Shapes drawn after a rotation use the unrotated view.

Fixed on 2026-10-21 in `a21fff1`:

- `Views/ImageEditor/CanvasView.swift`: new `CanvasGeometry` maps base-image space to the view in the same order as `ImageCompositor` (crop, rotate, fit). The canvas, hit testing and the text field use it. The crop tool shows the full image with the crop outlined. A crop is limited to the image bounds.
- `Views/ImageEditor/ImageEditorViewModel.swift`: the text draft moves here (`beginText`, `commitText`, `cancelText`). Save commits typed text first.
- `Views/ImageEditor/ImageEditorSheet.swift`: Return and Esc do not trigger Save and Cancel while text is typed. Esc in the text field discards the draft.
- New tests: `CanvasGeometryTests` (7, including one that compares the view with the compositor output) and 4 text draft tests in `ImageEditorViewModelTests`.

### 2.5 Observations, not bugs

- A copy made while MaClip is frontmost is dropped. In the test run this happened when a copy came less than 1 s after a clip was selected. See section 5.
- Selecting a clip moves it to the top (`moveTopOnClick`). Row numbers change after each selection.

## 3. Decisions (closed on 2026-10-21)

- [x] **Save as new on a concealed clip:** the new clip copies `isConcealed` and `concealedExpiresAt`. Test: `test_insertImageCopiesConcealedFlags`.
- [x] **Editor window level:** floating, like Settings. Checked in the app: window layer 3.
- [x] **#9 Esc during a pen stroke:** Esc cancels only the shape in progress. Esc at other times closes the editor. Checked in the app.
- [x] **#16 save failure:** alert "Could not save image". The editor stays open with its edits. Checked in the app with a read-only Images folder. Return closes the alert. A retry after the fix saved the edit.
- [x] **Unused settings:** `settings.overlay.width` and `settings.overlay.height` deleted from the user defaults on the dev machine.

## 4. Doc updates before the PR

- [x] Spec: remove the resizable overlay from scope and from the architecture table.
- [x] Spec: change "sheet over overlay" to "separate window". Update QA rows 1, 4, 9, 14 and 21–24.
- [x] Plan: tick the done tasks. Add a note that Task 1 was reverted.
- [x] README: add the image editor to the feature list.

## 5. Known issues not caused by 1.11.0

- `URLUtilsTests`: 2 tests fail. A bare domain gets `http://`, but the tests expect `https://`. The code did not change on this branch.
- On 2026-10-19 at about 10:35, a full test run deleted the local clipboard history and reset some settings. The cause was missing test isolation. Commit `737b087` fixes this. The lost clips cannot be recovered without a backup from before that time.
- Screenshots taken while the overlay is open are dropped, because MaClip excludes itself (Settings → Privacy). This existed before 1.11.0. To capture them, remove MaClip from the excluded apps.

## 6. Release automation (2026-10-22)

Plan: `docs/superpowers/plans/2026-10-22-release-workflow.md`.

- [x] release-please config, manifest (`1.10.1`) and `CHANGELOG.md`. A dry run proposes 1.11.0.
- [x] `scripts/release/sync-version.sh` (5 tests) and `scripts/release/build-dmg.sh` (2 tests).
- [x] `.github/workflows/release.yml`. The PR build passed on GitHub (run 39695871291). The artifact checksum is OK.
- [x] README "What's new" sections moved to `CHANGELOG.md`. Release steps are in `CONTRIBUTING.md`.
- [ ] Repository setting "Allow GitHub Actions to create and approve pull requests" (needs the owner's OK).
- [ ] After PR #13 merges: check that the release PR `chore(main): release 1.11.0` opens, then merge it and check the release page.
