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

## License
By contributing, you agree that your contributions will be licensed under the repository’s existing license.