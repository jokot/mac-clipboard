# Automated Release Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a PR merges to `main`, CI opens or updates a release PR that bumps the version and the changelog. When the release PR merges, CI tags the commit, publishes a GitHub release with the changelog, and attaches `MacClip-<version>.dmg` and its `.sha256`.

**Architecture:** One workflow, `.github/workflows/release.yml`, with three jobs. `release-please` ([googleapis/release-please-action](https://github.com/googleapis/release-please-action)) reads conventional commits, maintains the release PR, and creates the tag and release. `sync-build` adds the build number and the Xcode project sync to the release PR branch. `build` runs on a macOS runner, builds and packages the app with `scripts/release/build-dmg.sh`, and uploads the files. The same `build` job also runs on every PR to `main` and uploads the DMG as a workflow artifact, so the packaging is tested before a release.

**Tech Stack:** GitHub Actions, release-please v4 (`release-type: simple`), bash, `xcodebuild`, `create-dmg`, `gh`.

**Spec:** No separate spec file. The design was agreed in chat on 2026-10-22. It is copied in "Design" below.

## Design (agreed in chat)

1. A PR merges to `main`. CI opens a release PR, or updates the open one. The release PR changes the app version and adds entries to `CHANGELOG.md`. *(User.)*
2. When the release PR merges, CI creates the tag and publishes the GitHub release. *(User.)*
3. The release page shows the changelog and the build files, like the current releases: `MacClip-<version>.dmg` and `MacClip-<version>.dmg.sha256`. *(User.)*
4. The "What's new" sections are removed from `README.md`. *(User.)*
5. The next version comes from conventional commit types: `feat` → minor, `fix` → patch, `!` or `BREAKING CHANGE` → major. The open release PR collects all merges until it merges. *(Claude's call. User did not object.)*
6. The build stays unsigned (ad-hoc signature), as today. No Apple Developer secrets. *(Claude's call.)*
7. The first release after PR #13 merges is 1.11.0, not 1.12.0. *(Claude's call.)*
8. The old "What's new" text moves into `CHANGELOG.md` as history for 1.10.0 and 1.10.1. The hand-written 1.11.0 section is deleted. release-please writes 1.11.0 from the commits. *(Claude's call.)*

## Global Constraints

- Tag format: `v<version>`, for example `v1.11.0`. Same as the existing tags.
- Asset names: `MacClip-<version>.dmg` and `MacClip-<version>.dmg.sha256`. Same as v1.10.1.
- Version source of truth: `project.yml` `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. `MacClipboard.xcodeproj/project.pbxproj` must always hold the same two values (2 occurrences each, Debug and Release).
- Build number rule: build number at the last release tag + 1. It does not grow when the release PR is regenerated.
- Last released version at bootstrap: `1.10.1` (tag `v1.10.1`, build 14).
- Runner: `macos-15`. Action versions: `googleapis/release-please-action@v4`, `actions/checkout@v4`, `actions/upload-artifact@v4`.
- Workflow permissions: `contents: write` and `pull-requests: write` for the release jobs only. The PR build job is read-only.
- No secrets other than `GITHUB_TOKEN`.
- All work goes on branch `feature/1.11.0-image-edit` (PR #13).

## Review Focus

1. **A second merge while the release PR is open.** release-please force-pushes its branch. The build number must still be last-release + 1, not + 2. Owner: Task 2, test `test_idempotent`.
2. **A merge with only `docs`, `chore` or `test` commits.** release-please opens no PR. `sync-build` and `build` must be skipped, not fail. Owner: Task 4, `if:` conditions, checked in Step 4 with `actionlint`.
3. **The tag version and the built app disagree** (for example, `project.pbxproj` was not synced). The build must fail before upload. Owner: Task 3, test `test_version_mismatch_fails`.
4. **`create-dmg` fails on the runner** (Finder AppleScript has no GUI session or times out). The script must retry without the Finder layout step (`--skip-jenkins`) and still produce a DMG. Owner: Task 3, Step 3.
5. **Two merges to `main` close together.** Two runs must not race on the release PR branch. Owner: Task 4, `concurrency` group.

---

### Task 1: release-please configuration and changelog seed

**Files:**
- Create: `release-please-config.json`
- Create: `.release-please-manifest.json`
- Create: `CHANGELOG.md`
- Modify: `project.yml:30` (annotate `MARKETING_VERSION`)

**Interfaces:**
- Produces: release-please updates `project.yml` `MARKETING_VERSION` and `CHANGELOG.md` on its branch `release-please--branches--main`. Task 4 reads the action outputs `release_created`, `tag_name`, `version`, `pr`.

- [ ] **Step 1: Write `release-please-config.json`**

Values: `"release-type": "simple"`, one package `"."`, `"include-component-in-tag": false`, `"include-v-in-tag": true`, `"changelog-path": "CHANGELOG.md"`, `"pull-request-title-pattern": "chore${scope}: release ${version}"`. `"extra-files": [{"type": "generic", "path": "project.yml"}]`. `"changelog-sections"`: Features (`feat`), Bug Fixes (`fix`), Reverts (`revert`), Performance (`perf`). `docs`, `chore`, `test`, `refactor`, `plan` are hidden.

- [ ] **Step 2: Write `.release-please-manifest.json`**

Content: `{ ".": "1.10.1" }`.

- [ ] **Step 3: Annotate the version line in `project.yml`**

`MARKETING_VERSION: 1.11.0 # x-release-please-version`. Run `xcodegen generate` and check that `project.pbxproj` still has `MARKETING_VERSION = 1.11.0;`. Restore the scheme afterward with `git checkout -- MacClipboard.xcodeproj/xcshareddata/xcschemes/MacClipboard.xcscheme`.

- [ ] **Step 4: Write `CHANGELOG.md`**

Start with `# Changelog`. Below it, add `## 1.10.1` and `## 1.10.0`, with the bullet text moved from the README "What's new" sections (Task 5 deletes them there). release-please inserts new versions under the `# Changelog` line.

- [ ] **Step 5: Verify the next version with a dry run**

Push the branch, then run:

```bash
GH_TOKEN="$(gh auth token --user jokot)" npx --yes release-please@16 release-pr \
  --repo-url=jokot/mac-clipboard --target-branch=feature/1.11.0-image-edit \
  --token="$GH_TOKEN" --dry-run
```

Expected: the output proposes version `1.11.0`. It lists `CHANGELOG.md` and `project.yml` in the changes. The changelog shows "Features" and "Bug Fixes" entries from the 1.11.0 commits. If it also lists `version.txt`, accept it. The `simple` type keeps that file, and it does no harm.

- [ ] **Step 6: Commit**

```bash
git add release-please-config.json .release-please-manifest.json CHANGELOG.md project.yml MacClipboard.xcodeproj/project.pbxproj
git commit -m "ci(release): add release-please config and changelog"
```

---

### Task 2: Build number and Xcode project sync script

**Files:**
- Create: `scripts/release/sync-version.sh`
- Test: `scripts/release/test-sync-version.sh`

**Interfaces:**
- Produces: `scripts/release/sync-version.sh <last-tag>`, run from the repo root. It reads `MARKETING_VERSION` from `project.yml`. It sets `CURRENT_PROJECT_VERSION` in `project.yml` to (the value in `git show <last-tag>:project.yml`) + 1. It writes both values to every occurrence in `MacClipboard.xcodeproj/project.pbxproj`. It prints `version=<v> build=<n>` and exits 0. If the tag is missing, it exits 1 with `error: tag <last-tag> not found`.

- [ ] **Step 1: Write the failing tests in `scripts/release/test-sync-version.sh`**

Each test makes a temp git repo with a fixture `project.yml` (`MARKETING_VERSION: 1.10.1`, `CURRENT_PROJECT_VERSION: 14`). It also has a `project.pbxproj` with 2 occurrences of each key. The fixture is committed and tagged `v1.10.1`. Then the test sets `MARKETING_VERSION: 1.11.0` and runs the script with `v1.10.1`.

- `test_sets_build_to_tag_plus_one`: `project.yml` has `CURRENT_PROJECT_VERSION: 15`. The output is `version=1.11.0 build=15`.
- `test_syncs_pbxproj`: `grep -c 'MARKETING_VERSION = 1.11.0;'` is 2, and `grep -c 'CURRENT_PROJECT_VERSION = 15;'` is 2.
- `test_idempotent`: a second run gives the same files (`git diff --quiet` after commit of run 1).
- `test_keeps_annotation`: the line `MARKETING_VERSION: 1.11.0 # x-release-please-version` keeps its comment.
- `test_missing_tag_fails`: `v9.9.9` gives exit 1 and the message `error: tag v9.9.9 not found`.

- [ ] **Step 2: Run the tests and verify they fail**

Run: `bash scripts/release/test-sync-version.sh`
Expected: FAIL, because `sync-version.sh` does not exist.

- [ ] **Step 3: Implement `scripts/release/sync-version.sh`**

`set -euo pipefail`. Use `sed -E -i.bak` with `.bak` cleanup, so the script works with BSD sed (macOS runner) and GNU sed.

- [ ] **Step 4: Run the tests and verify they pass**

Run: `bash scripts/release/test-sync-version.sh`
Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Run the script on the real repo**

Run: `scripts/release/sync-version.sh v1.10.1`
Expected: `version=1.11.0 build=15`. `git status --short` shows no change, because PR #13 already has these values.

- [ ] **Step 6: Commit**

```bash
git add scripts/release/sync-version.sh scripts/release/test-sync-version.sh
git commit -m "ci(release): add build number and Xcode project sync script"
```

---

### Task 3: DMG build script

**Files:**
- Create: `scripts/release/build-dmg.sh`
- Test: `scripts/release/test-build-dmg.sh`

**Interfaces:**
- Produces: `scripts/release/build-dmg.sh <version>`, run from the repo root. It builds the Release configuration into `build/` with an ad-hoc signature (`CODE_SIGN_IDENTITY=-`). It checks that `CFBundleShortVersionString` in `build/Release/MaClip.app` equals `<version>`, or exits 1 with `error: app version <x> does not match <version>`. It writes `dist/MacClip-<version>.dmg` and `dist/MacClip-<version>.dmg.sha256`. The `.sha256` file holds the base name only (`<hash>  MacClip-<version>.dmg`), so `shasum -a 256 -c` works in the download folder.

- [ ] **Step 1: Write the failing tests in `scripts/release/test-build-dmg.sh`**

- `test_version_mismatch_fails`: `build-dmg.sh 0.0.1` exits 1 and prints `error: app version 1.11.0 does not match 0.0.1`. No file is written to `dist/`.
- `test_builds_dmg`: `build-dmg.sh 1.11.0` exits 0. `(cd dist && shasum -a 256 -c MacClip-1.11.0.dmg.sha256)` prints `OK`. `hdiutil attach -nobrowse -readonly` on the DMG shows `MaClip.app` and an `Applications` link. `codesign -v` on the mounted app exits 0.

- [ ] **Step 2: Run the tests and verify they fail**

Run: `bash scripts/release/test-build-dmg.sh`
Expected: FAIL, because `build-dmg.sh` does not exist.

- [ ] **Step 3: Implement `scripts/release/build-dmg.sh`**

Use the `xcodebuild` and `create-dmg` commands from the README "Packaging" section. Install `create-dmg` with `brew` when it is missing. If `create-dmg` fails, delete any partial DMG and run it again with `--skip-jenkins` (Review Focus 4). Check the version before `create-dmg`, so a mismatch writes nothing.

- [ ] **Step 4: Run the tests and verify they pass**

Run: `bash scripts/release/test-build-dmg.sh`
Expected: `2 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/release/build-dmg.sh scripts/release/test-build-dmg.sh
git commit -m "ci(release): add DMG build script"
```

---

### Task 4: Release workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `.gitignore` (add `dist/`)

**Interfaces:**
- Consumes: Task 1 config files. `scripts/release/sync-version.sh <last-tag>` (Task 2). `scripts/release/build-dmg.sh <version>` (Task 3).

- [ ] **Step 1: Write `.github/workflows/release.yml`**

- Triggers: `push` to `main`, and `pull_request` to `main`.
- `concurrency: { group: release-${{ github.ref }}, cancel-in-progress: false }`.
- Job `release-please` (`ubuntu-latest`, push only, `contents: write`, `pull-requests: write`): runs `googleapis/release-please-action@v4` with `config-file` and `manifest-file`. It exposes `release_created`, `tag_name`, `version`, and `pr`.
- Job `sync-build` (`ubuntu-latest`, `contents: write`, needs `release-please`, `if: needs.release-please.outputs.pr != ''`): checks out `fromJSON(needs.release-please.outputs.pr).headBranchName` with full history and tags. It reads the last tag as `v` + the version in `git show origin/main:.release-please-manifest.json`. Do not read the manifest on the release branch, because release-please already changed it there to the new version. It runs `sync-version.sh`. When the files change, it commits as `github-actions[bot]` with the message `chore(release): set build number` and pushes.
- Job `build` (`macos-15`):
  - On `pull_request`, it runs `build-dmg.sh <version>`, with the version read from `project.yml`. It uploads `dist/*` with `actions/upload-artifact@v4`, name `MacClip-dmg`, retention 7 days.
  - On push, it needs `release-please` and runs only when `release_created == 'true'`. It checks out `tag_name`, runs `build-dmg.sh <version>`, then `gh release upload <tag_name> dist/MacClip-<version>.dmg dist/MacClip-<version>.dmg.sha256 --clobber`.
- Every `run:` step that uses `${{ }}` values passes them through `env:`, not inline. This prevents script injection.

- [ ] **Step 2: Add `dist/` to `.gitignore`**

- [ ] **Step 3: Lint the workflow**

Run: `brew list actionlint >/dev/null 2>&1 || brew install actionlint; actionlint .github/workflows/release.yml`
Expected: no output, exit 0.

- [ ] **Step 4: Check the job conditions against Review Focus 2**

Read the `if:` lines. `sync-build` must be skipped when `pr` is empty. The push-side `build` must be skipped when `release_created` is not `'true'`. `actionlint` must not report an unknown output name.

- [ ] **Step 5: Commit and push, then check the PR run**

```bash
git add .github/workflows/release.yml .gitignore
git commit -m "ci(release): add release workflow"
git push
```

Expected: PR #13 shows a check `release / build`. It passes, and the run has an artifact `MacClip-dmg` with `MacClip-1.11.0.dmg` and its `.sha256`. Download it with `gh run download` and run `shasum -a 256 -c` on it (`OK`). This is the first test of `build-dmg.sh` on the GitHub runner, including Review Focus 4.

---

### Task 5: Repository setting, README and contributor docs

**Files:**
- Modify: `README.md` (remove the "What's new" sections, link to the latest release, update "Packaging")
- Modify: `CONTRIBUTING.md` (add "Releases")
- Modify: `docs/superpowers/todo-1.11.0.md` (add release workflow status)

- [ ] **Step 1: Ask the user before changing the repository setting**

release-please needs "Allow GitHub Actions to create and approve pull requests". The repo has it off now (`can_approve_pull_request_reviews: false`). After the user agrees, run:

```bash
GH_TOKEN="$(gh auth token --user jokot)" gh api -X PUT repos/jokot/mac-clipboard/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```

Expected: `gh api repos/jokot/mac-clipboard/actions/permissions/workflow` returns `"can_approve_pull_request_reviews":true`.

- [ ] **Step 2: Edit `README.md`**

- Delete the "What's new in 1.11.0", "1.10.1" and "1.10.0" sections.
- Change the download line to `[Download the latest release](https://github.com/jokot/mac-clipboard/releases/latest)`, and add a link to `CHANGELOG.md`.
- In "Packaging", say that CI builds the release DMG. Replace the manual commands with `scripts/release/build-dmg.sh <version>`. Change the checksum commands to `cd dist && shasum -a 256 -c MacClip-*.dmg.sha256`.

- [ ] **Step 3: Add a "Releases" section to `CONTRIBUTING.md`**

Cover these points:
- Commit types decide the next version (`feat` → minor, `fix` → patch, `!` → major).
- PRs to `main` must use merge commits, so that each commit reaches `main` with its type. A squash merge would use the PR title.
- Merging the release PR publishes the release.
- Do not edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` by hand.

- [ ] **Step 4: Check the docs**

Run: `grep -n "What's new" README.md`
Expected: no output.

- [ ] **Step 5: Commit and push**

```bash
git add README.md CONTRIBUTING.md docs/superpowers/todo-1.11.0.md
git commit -m "docs: document the automated release flow"
git push
```

---

### After PR #13 merges (user action, then check)

1. The `release` workflow runs on `main`. Expected: a PR `chore(main): release 1.11.0`. `CHANGELOG.md` has a `1.11.0` section above `1.10.1`, and `CURRENT_PROJECT_VERSION` stays `15`.
2. Merge that PR. Expected: tag `v1.11.0`, and a release with the changelog text, `MacClip-1.11.0.dmg` and `MacClip-1.11.0.dmg.sha256`.
3. If step 1 opens no PR, check the run log of the `release-please` job. The most likely causes are the repository setting (Task 5, Step 1) and a missing `v1.10.1` release match (check the manifest).
