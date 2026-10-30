# Secret detection: design

Date: 2026-10-30. Status: draft, for review.

Design canvas: https://claude.ai/artifact/REhTjHvSy9VkLAUrrGrAgS (artboards "Clip window — secrets", "Clip window — secret preview", "Settings — Privacy" and "Secrets in history — messages").

## Intent

MaClip is for IT people and developers (see `docs/superpowers/todo.md`, section 6). Developers copy API keys, tokens and private keys many times each day. Now MaClip saves these values as plain clips. They stay in the history for weeks, and anyone who opens the clip window can read them.

MaClip already protects passwords from password managers: the password manager marks the copy as concealed, and MaClip hides the clip and deletes it after some minutes. A key that you copy from a terminal, a browser or an `.env` file has no such mark. Secret detection finds these values in the text, and MaClip then handles them as concealed clips.

Success: a developer copies a GitHub token. The clip window shows a hidden row with the name "GitHub token" and a countdown. The token is not in the history after the countdown ends.

## Goals

1. Find common secrets in new text clips and link clips, and treat each one as a concealed clip.
2. Show the kind of secret ("GitHub token") on the hidden row and in the preview.
3. Let the user correct a wrong match with "Not a Secret".
4. Let the user find and hide or delete secrets that are already in the history.
5. Let the user search for secrets with `tag:secret`.

## Non-goals

- No detection in images. OCR runs only when the user asks for it.
- No detection in file clips. MaClip does not read the files.
- No "Mark as Secret" action for a clip that MaClip did not detect. This item is for a later version.
- No list of custom patterns in Settings.
- No entropy check ("random-looking text"). It finds too many hashes, UUIDs and IDs.
- No network calls. MaClip never sends a value anywhere to check it.

## Anti-goals

These results make the feature a failure, even if the code works:

- **Many false matches.** If MaClip hides UUIDs, Git commit hashes, CSS colors or normal code, users turn the feature off. Each rule must match a known format, or a key name with a real value.
- **Lost data without a reason.** MaClip deletes a detected secret only by the same rules as a concealed clip. The user can see the countdown on the row.
- **A secret on screen.** The row, the preview, the ⌘K menu, the hover help and the accessibility label never show the value of a hidden secret. The value shows only after "Show for 5 Seconds".
- **A slow app.** Detection runs at each clipboard change. It must not delay the clipboard check.

## What the user sees

### Clip window

A detected secret is a concealed clip. All concealed behavior stays as it is: the orange lock tile, the masked dots, "Show for 5 Seconds" (⌘U), and the "clears in m:ss" countdown.

The difference: the row shows the kind of secret after the dots, in secondary text. Example: `•••••••••••• GitHub token`. A concealed clip from a password manager shows the dots only, as now.

The preview of a hidden secret says "This clip is a GitHub token" in place of "This clip is concealed". Under it, a line in secondary text says "MaClip deletes it in 4:32." with the live countdown. A clip without a countdown has no such line. The button "Show for 5 Seconds" stays. The header of the preview shows the kind after the date: "Today at 10:42 · GitHub token".

The button row of the preview shows **Not a Secret** in place of **Edit…** for a detected secret.

The ⌘K menu of a detected secret has one more item, **Not a Secret**, after "Show for 5 Seconds". It has no key. "Not a Secret" makes the clip a normal clip: it shows the text, stops the countdown, and removes the kind. A concealed clip from a password manager does not have this item.

### Search

`tag:secret` finds all clips with a detected kind. The tag comes from the saved kind of the clip, not from the text, so a clip marked "Not a Secret" does not have it. The tag does not change the icon of the row: a hidden secret shows the lock, as a concealed clip does. A search with text also finds hidden secrets, as it does for concealed clips now. The rows stay masked.

### Settings → Privacy

A new section **Secrets** comes after "Concealed clips":

| Row | Control | Default |
|---|---|---|
| Find secrets in copied text | Switch | On |
| Caption | "API keys, tokens and private keys become concealed clips. The concealed clip settings above apply to them." | |
| Secrets in history | Button "Find Secrets in History…" | |

The settings in "Concealed clips" apply to detected secrets:

- "Don't save concealed clips" on: MaClip does not save a detected secret.
- "Delete concealed clips after" sets the countdown of a detected secret.

The Settings window keeps its size (680 × `min(656, screen height − 68)` points). The Privacy tab then is taller than the window and scrolls, as a tab does now on a small screen. When the settings focus moves to the Secrets section, the tab scrolls to it, as it does for the other controls.

The new switch and button get settings focus IDs. The keyboard model of Settings (↑ ↓ ⇥ Space) then reaches them, as for the other controls.

### Find Secrets in History

The button checks all text clips and link clips in the history. It does not check concealed clips (they are hidden already) or clips marked "Not a Secret". The check works also when "Find secrets in copied text" is off.

- **0 found:** an alert "No secrets found" with the text "MaClip checked N clips." (N is the number of text clips and link clips that it checked) and the button OK.
- **1 or more found:** an alert "3 secrets found" with the text "1 private key and 2 GitHub tokens. Hide them, or delete them now." The buttons are **Delete 3 Clips** (destructive), **Hide**, and **Cancel**. Cancel is the default for Esc.
  - Hide: each clip becomes a concealed clip with its kind. These clips get no countdown, because the user did not copy them now. They stay until the user deletes them.
  - Delete: MaClip deletes the clips.

The alert text names at most 3 kinds, in the order of the table below. The secrets of the other kinds become "and N other secrets", for example "1 private key, 2 AWS access keys, 3 GitHub tokens and 2 other secrets." The alert uses singular and plural forms: "1 secret found", "1 GitHub token".

## The detection rules

MaClip checks the text in this order and uses the first rule that matches. It checks only the first 65,536 characters of a clip.

| Kind | Name on the row | Rule (Swift regex, outline) |
|---|---|---|
| privateKey | Private key | `-----BEGIN (RSA \|EC \|DSA \|OPENSSH \|ENCRYPTED \|PGP )?PRIVATE KEY( BLOCK)?-----` |
| awsAccessKey | AWS access key | `\b(AKIA\|ASIA)[0-9A-Z]{16}\b` |
| githubToken | GitHub token | `\bgh[pousr]_[A-Za-z0-9]{36,}\b` or `\bgithub_pat_[A-Za-z0-9_]{22,}\b` |
| gitlabToken | GitLab token | `\bglpat-[A-Za-z0-9_-]{20,}` |
| slackToken | Slack token | `\bxox[abprs]-[A-Za-z0-9-]{10,}` |
| slackWebhook | Slack webhook | `https://hooks\.slack\.com/services/[A-Za-z0-9/]+` |
| discordWebhook | Discord webhook | `https://(canary\.)?discord(app)?\.com/api/webhooks/\d+/[A-Za-z0-9_-]+` |
| stripeKey | Stripe key | `\b(sk\|rk)_(live\|test)_[A-Za-z0-9]{16,}\b` |
| anthropicKey | Anthropic API key | `\bsk-ant-[A-Za-z0-9_-]{20,}` |
| openAIKey | OpenAI API key | `\bsk-(proj-\|svcacct-)?[A-Za-z0-9_-]{20,}`, checked after anthropicKey |
| googleAPIKey | Google API key | `\bAIza[0-9A-Za-z_-]{35}\b` |
| npmToken | npm token | `\bnpm_[A-Za-z0-9]{36}\b` |
| jwt | JWT | `\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{10,}` |
| linkPassword | Password in a link | `scheme://user:password@host` with a password of 3 or more characters |
| keyValue | Secret value | A `KEY=value` or `KEY: value` line. See below. |

### The keyValue rule

A line matches when all of these are true:

- The line starts with the key. Spaces at the start and `export ` are allowed before it. The key is letters, digits, `_`, `-` and `.`, and it can be in double quotes, as in JSON.
- The key contains one of these words, without regard to case: `SECRET`, `TOKEN`, `PASSWORD`, `PASSWD`, `API_KEY`, `APIKEY`, `ACCESS_KEY`, `PRIVATE_KEY`, `AUTH_KEY`.
- After the key comes `=` with no spaces, or `:` and one or more spaces.
- The value has 8 or more characters, after MaClip removes quotes around it and a comma at the end.
- The value is not a placeholder. These values are placeholders:
  - a value that starts with `$`, `<`, `{` or `%`,
  - a value that contains `(` or a space,
  - a value of one character repeated, such as `xxxxxxxx`,
  - `changeme`, `password`, `your_token_here` and other values that start with `your`, `example`, `null`, `none`, `true` or `false`.

Examples:

| Text | Result |
|---|---|
| `DB_PASSWORD=s3cr3t-Pa55w0rd` | Secret value |
| `export GITHUB_TOKEN="ghp_…"` (a real token) | GitHub token, because that rule comes first |
| `password = getPassword()` | No match: a space comes before `=` |
| `API_KEY=${API_KEY}` | No match: the value starts with `$` |
| `TOKEN_TTL=3600` | No match: the value has fewer than 8 characters |
| `const token = req.headers.authorization` | No match: the line does not start with the key |
| `  "client_secret": "abcd1234efgh",` (JSON) | Secret value |

### What is never a secret

These texts must not match any rule. The tests check each one:

- A UUID: `123e4567-e89b-12d3-a456-426614174000`
- A Git commit hash: `a0036a7f3c9d1e2b4f5a6c7d8e9f0a1b2c3d4e5f`
- A SHA-256 hash with 64 hex digits
- A CSS color: `#5E5CE6`
- A normal link: `https://github.com/jokot/mac-clipboard`
- A link with a user and no password: `ssh://git@github.com/jokot/mac-clipboard.git`
- Swift and JavaScript code without a key-value secret
- The word "token" in normal text: "Copy the token from the dashboard."

## Behavior details

### New clips

`ClipboardMonitor` reads the text before it makes the clip. When "Find secrets in copied text" is on, it checks:

- the text of a text clip,
- the text of a link clip (the link as text, before MaClip makes the URL).

If a rule matches and the pasteboard has no concealed mark:

- "Don't save concealed clips" on: MaClip does not save the clip.
- Else: the clip is concealed, with the kind, and with the countdown from "Delete concealed clips after".

If the pasteboard has a concealed mark, the clip is concealed as now. MaClip also adds the kind if a rule matches.

When "Find secrets in copied text" is off, MaClip does not check new clips. Clips that have a kind keep it.

### The same text again

When the user copies a text that is already in the history, MaClip moves the earlier clip to the top. It keeps the flags of the earlier clip (no change).

One exception: the new copy is a detected secret, and the earlier clip is a normal clip that the user did not mark "Not a Secret". Then the earlier clip becomes a concealed clip with the kind and a new countdown. Without this rule, a token that was in the history before this version stays visible.

A clip marked "Not a Secret" stays a normal clip when the user copies it again.

If "Don't save concealed clips" is on, MaClip does not save the new copy, so the earlier clip does not change. "Find Secrets in History…" finds it.

### Saved data

Each clip gets two new values. Both are optional in the saved record, so older history files load without a change:

- `secretKind: String?`: the raw value of the kind, for example `githubToken`. An unknown value loads as no kind. The clip stays concealed if its `isConcealed` value is true.
- `secretDismissed: Bool?`: true after "Not a Secret".

Encryption of the history does not change. The new values go into the same record.

### Edits and other actions

- An edit of a secret clip keeps its flags, as an edit of a concealed clip does now.
- Paste, Copy Only and the ⌘1–⌘9 keys work as for a concealed clip. They paste the real text.
- The Appearance preview gets no change.

## Constraints

- Swift and SwiftUI, macOS 13 and later, no new packages.
- Detection is a pure function, `SecretDetector.kind(in: String) -> SecretKind?`, with precompiled `NSRegularExpression` values. It runs on the thread that checks the clipboard now.
- Detection of a 65,536-character text takes less than 5 ms on an Apple silicon Mac in a Release build.
- **Test data and GitHub push protection.** GitHub blocks a push that contains a string in the format of a real token. Tests must build token strings at run time, for example `"ghp_" + String(repeating: "a", count: 36)`. The only literal key allowed in a test is the AWS documentation example `AKIAIOSFODNN7EXAMPLE`.
- Copy follows the app's rules: sentence case for titles of rows, title case for buttons and menu items, "Show for 5 Seconds" style.
- One PR, a `feat:` commit, squash merge.

## Decisions I made (please check)

These choices are mine, not the user's:

1. "Find secrets in copied text" is **on** by default, also for users who update. It protects only new clips. The history changes only after "Find Secrets in History…".
2. Detected secrets use the **concealed clip settings**. There is no separate countdown for secrets.
3. Secrets that "Find Secrets in History…" hides get **no countdown**. The user decides with Delete in the alert.
4. The list of rules in the table above. It covers the services that most developers use. More rules can come later.
5. "Not a Secret" has **no key**. The user finds it in ⌘K and in the preview.
6. No "Mark as Secret" in this version.
7. The Settings window **keeps its size**, and the Privacy tab scrolls. You made the window smaller on purpose, so I did not make it taller for one tab.

## Left to the builder

- The names of types and files, if they follow the code style of the repo.
- The exact regex text, if it passes every example in this document.
- Where the alert code goes.
- The layout of the Secrets section, within the canvas design.

## Builder check

I read this document as the builder, because no reviewer agent was used. I answered these questions in the text above:

- Which clips "Find Secrets in History…" checks.
- Where `tag:secret` comes from, and what the row icon is.
- What happens when the switch is off.
- What happens to an earlier copy when "Don't save concealed clips" is on.
- How the Privacy tab fits in the window.
