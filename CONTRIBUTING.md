# Contributing to MacClipboard

Thanks for your interest in improving MacClipboard! This short guide explains how to contribute bug fixes and propose new features.

## Bug fixes
If you found a bug and want to fix it:

1. Fork this repository to your account.
2. Create a new branch for your fix, for example: `fix/short-description`.
3. Implement the fix.
4. Build and test locally to ensure nothing broke.
5. Open a Pull Request (PR) to the main repository with a clear title and description of the fix.

## New feature requests
If you want to suggest and implement a new feature:

1. First create an Issue describing the feature:
   - What you want to propose and why it’s useful.
   - Any alternatives considered or prior art.
2. After discussion/feedback, fork the repo and create a branch for your work, for example: `feat/short-description`.
3. Implement the feature (and any related documentation updates if applicable).
4. Build and test locally.
5. Open a PR referencing the Issue number and summarizing your changes.

## Pull Request guidelines
To help us review your PR quickly:

- Keep changes focused and as small as practical.
- Follow the existing Swift code style and file organization.
- Do not include secrets, API keys, or credentials in code or config.
- Link related Issues in the PR description (e.g., "Closes #123").
- For UI/visual changes, include screenshots or a short screen recording.
- Ensure the project builds:
  - Open `MacClipboard.xcodeproj` in Xcode and build, or
  - Use `xcodebuild` from the command line.
  - If you add or move files, ensure they are included in `project.yml` and regenerate the Xcode project with `xcodegen generate` before committing.
- Write clear commit messages (e.g., `fix: …`, `feat: …`, `refactor: …`).

## Releases
Releases are automatic. The workflow is `.github/workflows/release.yml`.

1. Use conventional commit types. The commit type sets the next version:
   - `feat:` increases the minor version (1.11.0 to 1.12.0).
   - `fix:` increases the patch version (1.11.0 to 1.11.1).
   - `feat!:` or a `BREAKING CHANGE:` footer increases the major version.
   - `docs:`, `chore:`, `test:`, `refactor:` and `ci:` do not make a release.
2. Merge PRs to `main` with a merge commit, not a squash merge. A merge commit keeps the type of each commit. A squash merge keeps only the PR title.
3. After each merge, CI opens or updates the release PR `chore(main): release x.y.z`. This PR updates `CHANGELOG.md`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
4. Before you merge, check the new section in `CHANGELOG.md` on the release PR. That section becomes the text of the GitHub release. To change the text, edit `CHANGELOG.md` on the release PR branch.
5. To publish, merge the release PR. CI builds the DMG from the merge commit. Then CI makes a hidden draft release, attaches `MacClip-x.y.z.dmg` and `MacClip-x.y.z.dmg.sha256`, and publishes it. The tag `vx.y.z` is created only at that last step.
6. If a step fails, nothing is public. Fix the cause, then use "Re-run failed jobs" on the failed run in the Actions tab. The release job continues from the hidden draft. Until the release is published, release-please does not open a new release PR.

Do not change `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` by hand. The build number is the build number of the last release plus 1.

## License
By contributing, you agree that your contributions will be licensed under the repository’s existing license.