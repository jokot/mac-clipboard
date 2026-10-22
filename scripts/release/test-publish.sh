#!/usr/bin/env bash
# Tests for publish.sh with a fake gh. Run from the repo root:
#   bash scripts/release/test-publish.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/publish.sh"
pass=0
fail=0

# A work dir with CHANGELOG.md, the DMG files, and a fake gh on PATH.
# The fake gh keeps the release state in $dir/state ("none", "draft" or
# "published") and writes each call to $dir/calls.
make_fixture() {
    local state="$1" dir
    dir="$(mktemp -d)"
    mkdir -p "$dir/dist" "$dir/bin"
    cat > "$dir/CHANGELOG.md" <<'EOF'
# Changelog

## [1.11.0](https://example.com/compare/v1.10.1...v1.11.0) (2026-10-22)

### Features

* **editor:** edit image clips

## [1.10.1](https://example.com/compare/v1.10.0...v1.10.1) (2026-07-14)

- old entry
EOF
    echo dmg > "$dir/dist/MacClip-1.11.0.dmg"
    echo "abc  MacClip-1.11.0.dmg" > "$dir/dist/MacClip-1.11.0.dmg.sha256"
    echo "$state" > "$dir/state"
    : > "$dir/calls"
    cat > "$dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")/.." && pwd)"
echo "$*" >> "$dir/calls"
state="$(cat "$dir/state")"
case "$1 $2" in
  "release list")
    case "$state" in
      none) json='[]' ;;
      draft) json='[{"tagName":"v1.11.0","isDraft":true}]' ;;
      published) json='[{"tagName":"v1.11.0","isDraft":false}]' ;;
    esac
    # Apply --jq like the real gh does.
    filter=""; for a in "$@"; do [ "$prev" = "--jq" ] && filter="$a"; prev="$a"; done
    if [ -n "$filter" ]; then echo "$json" | jq -r "$filter"; else echo "$json"; fi ;;
  "release create")
    for a in "$@"; do case "$prev" in --notes-file) cp "$a" "$dir/notes" ;; esac; prev="$a"; done
    echo draft > "$dir/state" ;;
  "release upload")
    [ -n "${FAKE_GH_UPLOAD_FAILS:-}" ] && { echo "upload failed" >&2; exit 1; } ;;
  "release edit")
    echo published > "$dir/state" ;;
esac
exit 0
EOF
    chmod +x "$dir/bin/gh"
    echo "$dir"
}

run() { (cd "$1" && PATH="$1/bin:$PATH" "$SCRIPT" 1.11.0 deadbeef 42) >"$1/out" 2>&1; }

# Line number of the first call that starts with $2 (0 when absent).
call_line() { grep -n "^$2" "$1/calls" | head -1 | cut -d: -f1 | sed 's/^$/0/'; }

check() {
    local name="$1"; shift
    if "$@"; then pass=$((pass + 1)); echo "ok   $name"
    else fail=$((fail + 1)); echo "FAIL $name"; fi
}

test_new_release_is_draft_until_assets_upload() {
    local d c u e
    d="$(make_fixture none)"
    run "$d" || { cat "$d/out"; return 1; }
    c="$(call_line "$d" 'release create')"; u="$(call_line "$d" 'release upload')"; e="$(call_line "$d" 'release edit')"
    grep -q '^release create v1.11.0 .*--draft' "$d/calls" &&
        grep -q -- '--target deadbeef' "$d/calls" &&
        grep -q '^release upload v1.11.0 dist/MacClip-1.11.0.dmg dist/MacClip-1.11.0.dmg.sha256' "$d/calls" &&
        grep -q '^release edit v1.11.0 --draft=false' "$d/calls" &&
        [ "$c" -gt 0 ] && [ "$c" -lt "$u" ] && [ "$u" -lt "$e" ] &&
        [ "$(cat "$d/state")" = published ] || { cat "$d/calls"; return 1; }
}

test_notes_come_from_changelog_section() {
    local d
    d="$(make_fixture none)"
    run "$d" || return 1
    grep -q 'edit image clips' "$d/notes" && ! grep -q 'old entry' "$d/notes" && ! grep -q '^## \[1.11.0\]' "$d/notes"
}

test_reuses_leftover_draft() {
    local d
    d="$(make_fixture draft)"
    run "$d" || return 1
    ! grep -q '^release create' "$d/calls" &&
        grep -q '^release upload' "$d/calls" && grep -q '^release edit v1.11.0 --draft=false' "$d/calls"
}

test_already_published_only_relabels() {
    local d
    d="$(make_fixture published)"
    run "$d" || return 1
    ! grep -qE '^release (create|upload|edit)' "$d/calls" &&
        grep -q '^pr edit 42 --remove-label autorelease: pending --add-label autorelease: tagged' "$d/calls"
}

test_relabels_after_publish() {
    local d e l
    d="$(make_fixture none)"
    run "$d" || return 1
    e="$(call_line "$d" 'release edit')"; l="$(call_line "$d" 'pr edit 42')"
    grep -q '^label create autorelease: tagged' "$d/calls" && [ "$l" -gt "$e" ]
}

test_missing_dmg_makes_no_release() {
    local d
    d="$(make_fixture none)"
    rm "$d/dist/MacClip-1.11.0.dmg"
    run "$d" && return 1
    grep -q 'error: missing dist/MacClip-1.11.0.dmg' "$d/out" && [ ! -s "$d/calls" ]
}

test_missing_changelog_section_makes_no_release() {
    local d
    d="$(make_fixture none)"
    sed -i.bak 's/^## \[1.11.0\].*$/## [1.11.9](x)/' "$d/CHANGELOG.md"
    run "$d" && return 1
    grep -q 'error: no CHANGELOG.md section for 1.11.0' "$d/out" && [ ! -s "$d/calls" ]
}

test_upload_failure_keeps_draft_hidden() {
    local d
    d="$(make_fixture none)"
    (cd "$d" && FAKE_GH_UPLOAD_FAILS=1 PATH="$d/bin:$PATH" "$SCRIPT" 1.11.0 deadbeef 42) >"$d/out" 2>&1 && return 1
    ! grep -q '^release edit' "$d/calls" && ! grep -q '^pr edit' "$d/calls" && [ "$(cat "$d/state")" = draft ]
}

check test_new_release_is_draft_until_assets_upload test_new_release_is_draft_until_assets_upload
check test_notes_come_from_changelog_section test_notes_come_from_changelog_section
check test_reuses_leftover_draft test_reuses_leftover_draft
check test_already_published_only_relabels test_already_published_only_relabels
check test_relabels_after_publish test_relabels_after_publish
check test_missing_dmg_makes_no_release test_missing_dmg_makes_no_release
check test_missing_changelog_section_makes_no_release test_missing_changelog_section_makes_no_release
check test_upload_failure_keeps_draft_hidden test_upload_failure_keeps_draft_hidden

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
