# Secret detection and secret actions: design

Date: 2026-10-30. Updated 2026-11-15: the secret actions are now part of the same PR. Status: draft, for review.

Design canvas: https://claude.ai/artifact/REhTjHvSy9VkLAUrrGrAgS. Artboards:

- "Clip window — secrets": hidden rows, the LIVE pill, and the ⌘K menu of a GitHub token.
- "Clip window — secret preview": the preview, with the facts list.
- "Clip window — JWT": the decoded view of a JWT.
- "Clip window — private key": the facts and the buttons of a private key.
- "Secret actions — menus by kind": the ⌘K menu for five more kinds.
- "Settings — Privacy" and "Secrets in history — messages".

## Intent

MaClip is for IT people and developers (see `docs/superpowers/todo.md`, section 6). Developers copy API keys, tokens and private keys many times each day. Now MaClip saves these values as plain clips. They stay in the history for weeks, and anyone who opens the clip window can read them.

MaClip already protects passwords from password managers: the password manager marks the copy as concealed, and MaClip hides the clip and deletes it after some minutes. A key that you copy from a terminal, a browser or an `.env` file has no such mark. Secret detection finds these values in the text, and MaClip then handles them as concealed clips.

When MaClip knows the kind of a secret, it can also help with that secret. A developer wants to read the claims of a JWT, or get the public key of a private key. They also want to paste a log into an issue without the token in it. Secret actions do these tasks on the Mac, with no network calls.

Success:

- A developer copies a GitHub token. The clip window shows a hidden row with the name "GitHub token" and a countdown. The token is not in the history after the countdown ends.
- A developer copies a JWT and selects Decode JWT in ⌘K. The preview shows the claims, and shows that the token expired 3 days ago.

## Goals

1. Find common secrets in new text clips and link clips, and treat each one as a concealed clip.
2. Show the kind of secret ("GitHub token") on the hidden row and in the preview.
3. Let the user correct a wrong match with "Not a Secret".
4. Let the user find and hide or delete secrets that are already in the history.
5. Let the user search for secrets with `tag:secret`.
6. Give each kind of secret the ⌘K actions that a developer needs for it.
7. Show the facts that are safe to show about a secret in the preview, also while the clip is hidden. Examples: the type of a token, the mode of a Stripe key, the fingerprint of a private key.
8. Decode a JWT on the Mac, as jwt.io does.

## Non-goals

- No detection in images. OCR runs only when the user asks for it.
- No detection in file clips. MaClip does not read the files.
- No "Mark as Secret" action for a clip that MaClip did not detect. This item is for a later version.
- No list of custom patterns in Settings.
- No entropy check ("random-looking text"). It finds too many hashes, UUIDs and IDs.
- No network calls. MaClip never sends a value anywhere to check it.
- No check that a key still works. That check needs a call to the provider.
- No check of a JWT signature.
- No secret actions for a clip without a kind. Example: a JWT that MaClip did not detect because the setting is off. The ⌘K transform actions in the todo list can add "Decode JWT" for any text later.
- MaClip never decrypts a private key and never asks for a passphrase.

## Anti-goals

These results make the feature a failure, even if the code works:

- **Many false matches.** If MaClip hides UUIDs, Git commit hashes, CSS colors or normal code, users turn the feature off. Each rule must match a known format, or a key name with a real value.
- **Lost data without a reason.** MaClip deletes a detected secret only by the same rules as a concealed clip. The user can see the countdown on the row.
- **A secret on screen.** The row, the preview, the ⌘K menu, the hover help and the accessibility label never show the value of a hidden secret. The value shows only after "Show for 5 Seconds".
- **An action that leaks the secret.** A copy action that puts the secret value into a new clip must make that clip concealed. A visible copy of the token in the history is the problem that this feature must stop.
- **A slow app.** Detection runs at each clipboard change. It must not delay the clipboard check.

## What the user sees

### Clip window

A detected secret is a concealed clip. All concealed behavior stays as it is: the orange lock tile, the masked dots, "Show for 5 Seconds" (⌘U), and the "clears in m:ss" countdown.

The difference: the row shows the kind of secret after the dots, in secondary text. Example: `•••••••••••• GitHub token`. A concealed clip from a password manager shows the dots only, as now.

A live Stripe key also shows an orange **LIVE** pill after the kind. No other kind gets a pill on the row. A live key can move money, so this case must be easy to see.

The preview of a hidden secret says "This clip is a GitHub token" in place of "This clip is concealed". Under it, a line in secondary text says "MaClip deletes it in 4:32." with the live countdown. A clip without a countdown has no such line. The button "Show for 5 Seconds" stays. The header of the preview shows the kind after the date: "Today at 10:42 · GitHub token".

Under the main content, the preview shows a **facts list** for the kinds in the section "Facts about a secret". The list shows in both states, hidden and shown, because it never contains the value.

The button row of the preview shows **Not a Secret** in place of **Edit…** for a detected secret. Two kinds have their own buttons:

- Private key: Not a Secret, Copy Public Key, and Paste.
- JWT in the decoded view: Copy Header, Copy Payload, and Paste.

The ⌘K menu of a detected secret has one more item, **Not a Secret**, after "Show for 5 Seconds". It has no key. "Not a Secret" makes the clip a normal clip: it shows the text, stops the countdown, and removes the kind. A concealed clip from a password manager does not have this item. After "Not a Secret" come the secret actions of the kind. See "Secret actions".

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

The alert text names at most 3 kinds, in the order of the rules table below. The secrets of the other kinds become "and N other secrets", for example "1 private key, 2 AWS access keys, 3 GitHub tokens and 2 other secrets." The alert uses singular and plural forms: "1 secret found", "1 GitHub token".

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

### Each match: the secret part and the value

The actions need to know where each secret is in the text. For each match, the detector gives:

- **The secret part:** the characters that a mask hides. Usually this is the whole token. For a password in a link, it is the password. For a webhook, it is the last part of the path. For a secret value, it is the value after the key.
- **The value:** the full credential that an export copies. For a webhook and a password in a link, it is the whole link. For the other kinds, it is the secret part.
- **The key:** for a secret value only, the key of the line (`DB_PASSWORD`).

The **main secret** of a clip is the first match of the kind of the clip. The actions for one secret use it. Copy Masked and Copy Redacted Text use all matches. When two matches overlap, the rule that comes first in the table wins.

## Secret actions

### The ⌘K menu

After "Not a Secret" comes a separator, then the secret actions of the kind, then a separator and "Edit…". The menu shows only the actions that apply. No secret action has a key, so no action takes a key from an existing item.

| Action | Kinds | What it copies or does | New clip |
|---|---|---|---|
| Copy Masked | All, except a clip that is only a private key | The text, with each secret masked: `ghp_••••a1b2` | Normal |
| Copy Redacted Text | All, when the clip has text other than its secrets | The text, with each secret replaced by `[REDACTED GitHub token]` | Normal |
| Copy as .env | All, except privateKey and jwt | `GITHUB_TOKEN=ghp_…` | Concealed |
| Copy as Shell Export | All, except privateKey and jwt | `export GITHUB_TOKEN=ghp_…` | Concealed |
| Copy as JSON | keyValue | `{"DB_PASSWORD": "…"}`, formatted | Concealed |
| Copy as YAML | keyValue | `DB_PASSWORD: …` | Concealed |
| Copy Key Only | keyValue | `DB_PASSWORD` | Normal |
| Copy Value Only | keyValue | The value | Concealed |
| Copy Link Without Password | linkPassword | `postgres://admin@db.local:5432/app` | Normal |
| Copy Password Only | linkPassword | The password | Concealed |
| Copy User | linkPassword | `admin` | Normal |
| Decode JWT | jwt | Opens the preview with the decoded view | — |
| Copy Header | jwt | The header as formatted JSON | Normal |
| Copy Payload | jwt | The payload as formatted JSON | Normal |
| Copy Public Key | privateKey, when MaClip can read the public key | `ssh-ed25519 AAAA…` | Normal |
| Copy Fingerprint | privateKey, when MaClip can read the public key | `SHA256:…` | Normal |
| Save as File… | privateKey | A save panel in `~/.ssh` | — |
| Open Key Page on *Provider* | The kinds in "Key pages" | Opens the key page of the provider in the browser | — |

The menu shows the actions in the order of this table. The canvas shows the menu of each kind.

For a secret value, the format actions convert every key-value line of the clip, also the lines that are not secrets. Other lines, such as comments, are not in the result. For the other kinds, the format actions use the main secret and the name in this table:

| Kind | Name |
|---|---|
| awsAccessKey | `AWS_ACCESS_KEY_ID` |
| githubToken | `GITHUB_TOKEN` |
| gitlabToken | `GITLAB_TOKEN` |
| slackToken | `SLACK_TOKEN` |
| slackWebhook | `SLACK_WEBHOOK_URL` |
| discordWebhook | `DISCORD_WEBHOOK_URL` |
| stripeKey | `STRIPE_SECRET_KEY` for `sk_`, `STRIPE_RESTRICTED_KEY` for `rk_` |
| anthropicKey | `ANTHROPIC_API_KEY` |
| openAIKey | `OPENAI_API_KEY` |
| googleAPIKey | `GOOGLE_API_KEY` |
| npmToken | `NPM_TOKEN` |
| linkPassword | `REDIS_URL` for `redis` and `rediss`, `AMQP_URL` for `amqp` and `amqps`, else `DATABASE_URL` |

Quotes:

- `.env`: no quotes when the value has only letters, digits and `_ . / : @ % + = , -`. Else double quotes, with `\` before each `"` and `\`.
- Shell export: the same safe characters need no quotes. Else single quotes, and each `'` becomes `'\''`.
- JSON: `JSONSerialization` with sorted keys and pretty print.
- YAML: the same safe characters need no quotes. Else the value is a JSON string, which is also valid YAML.

### Key pages

"Open Key Page on *Provider*" opens a fixed web page where the user can see and revoke keys. The URL never contains the secret.

| Kind | Title | URL |
|---|---|---|
| githubToken, `ghp_` | Open Key Page on GitHub | `https://github.com/settings/tokens` |
| githubToken, `github_pat_` | Open Key Page on GitHub | `https://github.com/settings/personal-access-tokens` |
| githubToken, other prefixes | Open Key Page on GitHub | `https://github.com/settings/applications` |
| gitlabToken | Open Key Page on GitLab | `https://gitlab.com/-/user_settings/personal_access_tokens` |
| awsAccessKey | Open Key Page on AWS | `https://console.aws.amazon.com/iam/home#/security_credentials` |
| slackToken, slackWebhook | Open Key Page on Slack | `https://api.slack.com/apps` |
| stripeKey, live | Open Key Page on Stripe | `https://dashboard.stripe.com/apikeys` |
| stripeKey, test | Open Key Page on Stripe | `https://dashboard.stripe.com/test/apikeys` |
| anthropicKey | Open Key Page on Anthropic | `https://console.anthropic.com/settings/keys` |
| openAIKey | Open Key Page on OpenAI | `https://platform.openai.com/api-keys` |
| googleAPIKey | Open Key Page on Google Cloud | `https://console.cloud.google.com/apis/credentials` |

The other kinds have no key page, because they have no fixed URL. Before the PR, the builder opens each URL in a browser where the user is signed in, and removes a row whose page does not open.

### Copies that hold the secret

A copy action puts its text on the clipboard. The new clip goes to the top of the list, and the window stays open, as for "Copy Path".

The new clip is concealed in two cases:

- The "New clip" column of the action table says "Concealed". The kind of the new clip is the kind that the detector finds in the new text. If the detector finds no kind, the new clip gets the kind of the source clip. Example: Copy Value Only of `GITHUB_TOKEN=ghp_…` gives a GitHub token. Copy Password Only gives a password in a link.
- The column says "Normal", but the detector still finds a secret in the new text. Then the new clip is concealed with that kind. This rule protects against a mistake in a mask.

For a concealed result:

- MaClip also adds `org.nspasteboard.ConcealedType` to the clipboard, so other clipboard apps do not save it.
- "Don't save concealed clips" on: MaClip puts the text on the clipboard, but does not add a clip to the history.
- Else: the new clip gets the countdown from "Delete concealed clips after".

These rules apply also when "Find secrets in copied text" is off, because the source clip is a known secret.

### Masks

- MaClip keeps the known prefix of the token, then 4 dots, then the last 4 characters. It shows the last 4 characters only when the secret part has 20 or more characters. The number of dots is always 4, so the mask does not show the length.
- The known prefixes: `ghp_` and the other `gh?_` prefixes, `github_pat_`, `glpat-`, `xox?-`, `sk_live_`, `sk_test_`, `rk_live_`, `rk_test_`, `sk-ant-`, `sk-proj-`, `sk-svcacct-`, `sk-`, `AKIA`, `ASIA`, `AIza`, `npm_` and `eyJ`.
- A webhook keeps its link. Only the last part of the path is masked.
- A password in a link: `postgres://admin:••••@db.local:5432/app`.
- A secret value: the key stays. `DB_PASSWORD=••••`.
- A private key: the whole block becomes `[Private key]`.
- A redacted secret: `[REDACTED GitHub token]`, with the name of the kind. A redacted private key is `[REDACTED Private key]`.
- Copy Masked and Copy Redacted Text check the whole text, not only the first 65,536 characters. They run only when the user asks, so speed is less important than for detection.

| Text | Copy Masked |
|---|---|
| `ghp_` + 36 characters, last 4 `a1b2` | `ghp_••••a1b2` |
| `DB_PASSWORD=s3cr3t-Pa55w0rd` | `DB_PASSWORD=••••` |
| `https://hooks.slack.com/services/T000/B000/` + 24 characters | `https://hooks.slack.com/services/T000/B000/••••` + last 4 |
| `export GITHUB_TOKEN="ghp_…a1b2"` | `export GITHUB_TOKEN="ghp_••••a1b2"` |

### Facts about a secret

The facts list in the preview shows these rows. A kind that is not in this table has no list.

| Kind | Rows |
|---|---|
| githubToken | Type: Classic personal access token (`ghp_`), Fine-grained personal access token (`github_pat_`), OAuth token (`gho_`), User-to-server token (`ghu_`), Server-to-server token (`ghs_`) or Refresh token (`ghr_`) |
| awsAccessKey | Type: Long-term access key (`AKIA`) or Temporary session key (`ASIA`) |
| stripeKey | Mode: Live (orange) or Test. Type: Secret key (`sk_`) or Restricted key (`rk_`) |
| slackToken | Type: Bot token (`xoxb`), User token (`xoxp`), App token (`xoxa`), Refresh token (`xoxr`) or Session token (`xoxs`) |
| slackWebhook | Team: the `T…` part. Webhook: the `B…` part |
| discordWebhook | Webhook ID: the number in the link |
| anthropicKey | Type: Admin key (`sk-ant-admin`) or API key |
| openAIKey | Type: Project key (`sk-proj-`), Service account key (`sk-svcacct-`) or User key |
| jwt | Algorithm. Expiry: the status line of the decoded view |
| privateKey | Type: "Ed25519", "RSA 4096", "ECDSA P-256", "DSA key", "PGP key" or "Private key". Fingerprint. Passphrase: Yes or No |
| linkPassword | Service, User, Host, Port and Database. A row without a value is not shown |
| keyValue | Key: the key of the main secret. Lines: the number of key-value lines, when more than 1 |

The service names: `postgres` and `postgresql` → PostgreSQL, `mysql` → MySQL, `mariadb` → MariaDB, `mongodb` and `mongodb+srv` → MongoDB, `redis` and `rediss` → Redis, `amqp` and `amqps` → RabbitMQ. Other schemes show as they are. The database is the path of the link without the first `/`.

### The JWT decoded view

"Decode JWT" selects the clip and opens the preview with the decoded view. The view stays until the preview closes or the selection moves. It shows:

- A status line:
  - "Expired 3 days ago" in orange, when `exp` is in the past.
  - "Not valid until Nov 16, 2026 at 09:00" in orange, when `nbf` is in the future.
  - "Expires in 2 hours", when `exp` is in the future.
  - "No expiry date", when there is no `exp`.
- "This token is not signed (alg: none)." in orange, when `alg` is `none`, without regard to case.
- The claims list: Algorithm (`alg`), Type (`typ`), Issuer (`iss`), Subject (`sub`), Audience (`aud`, a list with commas), Issued at (`iat`), Expires (`exp`) and Not before (`nbf`). Dates show as "Nov 15, 2026 at 10:42". A claim that is not in the token has no row.
- The header and the payload as formatted JSON with sorted keys, in monospaced text.
- A note at the end: "MaClip does not check the signature."

The view never shows the signature or the full token. The header and the payload are not the credential. But the payload can contain names and email addresses, so the view shows only after the user selects Decode JWT. Decode JWT is not a 5-second view, because the user must have time to read the claims.

MaClip reads the parts as base64url, with or without `=` padding. Date claims can be integers or decimals. When MaClip cannot read the header or the payload, the menu does not show Decode JWT, Copy Header and Copy Payload, and the facts list does not show.

### Private keys

MaClip reads the first key block of the clip. It uses CryptoKit, the Security framework and a small DER reader. It does not use the keychain.

| Format | Type and size | Public key and fingerprint |
|---|---|---|
| OpenSSH (`BEGIN OPENSSH PRIVATE KEY`) | Yes, from the public part | Yes, also with a passphrase, because OpenSSH keeps the public key unencrypted |
| PKCS#1 RSA (`BEGIN RSA PRIVATE KEY`) | Yes | Yes, when there is no passphrase |
| SEC1 EC (`BEGIN EC PRIVATE KEY`) | P-256, P-384 and P-521 | Yes, when there is no passphrase |
| PKCS#8 (`BEGIN PRIVATE KEY`) | RSA, EC and Ed25519 | Yes |
| Encrypted PKCS#8 (`BEGIN ENCRYPTED PRIVATE KEY`), or a PEM block with `Proc-Type: 4,ENCRYPTED` | "Private key", Passphrase: Yes | No |
| DSA, PGP | "DSA key", "PGP key" | No |

- The fingerprint has the format of `ssh-keygen -lf`: `SHA256:` and then the SHA-256 hash of the SSH public key blob, in base64 without `=`.
- The public key has the format of a `.pub` file, without a comment: `ssh-ed25519 AAAA…`.
- **Save as File…** opens a save panel in `~/.ssh`. The file name is `id_ed25519`, `id_rsa` or `id_ecdsa`, else `private_key`. MaClip writes the key block with a newline at the end, then sets the permission to 600 (`-rw-------`). The panel asks before it replaces a file, as macOS does. If the write fails, an alert shows the error.
- An input that MaClip cannot read gives "Private key" and no public key. It never makes MaClip stop.

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

Encryption of the history does not change. The new values go into the same record. The facts, the matches and the decoded JWT are not saved. MaClip finds them again from the text when it needs them.

### Edits and other actions

- An edit of a secret clip keeps its flags, as an edit of a concealed clip does now.
- Paste, Copy Only and the ⌘1–⌘9 keys work as for a concealed clip. They paste the real text.
- The Appearance preview gets no change.

## Constraints

- Swift and SwiftUI, macOS 13 and later, no new packages. CryptoKit and the Security framework are part of macOS.
- Detection is a pure function, `SecretDetector.kind(in: String) -> SecretKind?`, with precompiled `NSRegularExpression` values. It runs on the thread that checks the clipboard now.
- Detection of a 65,536-character text takes less than 5 ms on an Apple silicon Mac in a Release build.
- The masks, the formats, the facts, the JWT decoder and the key reader are pure functions with tests. The views only show their results.
- All actions run on the Mac. "Open Key Page" opens a fixed URL that does not contain the secret.
- The key reader checks every length before it reads. Bad input gives a "Private key" result, never a crash.
- **Test data and GitHub push protection.** GitHub blocks a push that contains a string in the format of a real token. Tests must build token strings at run time, for example `"ghp_" + String(repeating: "a", count: 36)`. The only literal key allowed in a test is the AWS documentation example `AKIAIOSFODNN7EXAMPLE`.
- **Test keys.** Tests make private keys at run time, with CryptoKit and with `SecKeyCreateRandomKey` (`kSecAttrIsPermanent` false, so the key never goes into the keychain). Tests build the `-----BEGIN` lines at run time. One fixed check uses the public RFC 8032 test 1 key (`d75a9801…f707511a`). Its fingerprint is `SHA256:bbXpuKG6zhzdmnxq256TlqzFBzRl2f6OOg722cYNbU8`, as `ssh-keygen -lf` gives.
- Copy follows the app's rules: sentence case for titles of rows, title case for buttons and menu items, "Show for 5 Seconds" style.
- One PR, a `feat:` commit, squash merge.

## Decisions

The user decided:

- The secret actions go in the same PR as secret detection (2026-11-15).

These choices are mine, not the user's (please check):

1. "Find secrets in copied text" is **on** by default, also for users who update. It protects only new clips. The history changes only after "Find Secrets in History…".
2. Detected secrets use the **concealed clip settings**. There is no separate countdown for secrets.
3. Secrets that "Find Secrets in History…" hides get **no countdown**. The user decides with Delete in the alert.
4. The list of rules in the table above. It covers the services that most developers use. More rules can come later.
5. "Not a Secret" has **no key**. The user finds it in ⌘K and in the preview.
6. No "Mark as Secret" in this version.
7. The Settings window **keeps its size**, and the Privacy tab scrolls. You made the window smaller on purpose, so I did not make it taller for one tab.
8. A copy that holds the secret is a **concealed clip**, and the clipboard gets the concealed mark.
9. The **decoded JWT view stays** until the preview closes. It is not a 5-second view.
10. **No keys** for the secret actions. Most keys are in use, and these actions are not used many times each day.
11. Only a **live Stripe key** gets a pill on the row.
12. After a copy action, the **window stays open**, as for "Copy Path".
13. "Open Key Page" only for providers with a fixed page. npm, Discord and GitLab on your own server have none.
14. Copy Masked and Copy Redacted Text are **two actions**. A masked token is still useful to recognize a key. A redacted log is safer to share.

## Left to the builder

- The names of types and files, if they follow the code style of the repo.
- The exact regex text, if it passes every example in this document.
- Where the alert code and the save panel code go.
- The layout of the Secrets section, the facts list and the decoded view, within the canvas design.

## Builder check

I read this document as the builder, because no reviewer agent was used. I answered these questions in the text above:

- Which clips "Find Secrets in History…" checks.
- Where `tag:secret` comes from, and what the row icon is.
- What happens when the switch is off, for detection and for the actions.
- What happens to an earlier copy when "Don't save concealed clips" is on.
- How the Privacy tab fits in the window.
- Which secret each action uses when a clip has more than one.
- Why a copy of a secret value cannot become a visible clip.
- How long the decoded JWT view stays, and why it is not 5 seconds.
- What happens with a key that MaClip cannot read.
