#!/usr/bin/env bash
# Tests for build-dmg.sh. Run from the repo root: bash scripts/release/test-build-dmg.sh
# Each test runs a full Release build, so the file takes a few minutes.
set -uo pipefail

SCRIPT="scripts/release/build-dmg.sh"
VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*([0-9][0-9.]*).*/\1/p' project.yml | head -1)"
LOG="${TMPDIR:-/tmp}/test-build-dmg.log"
pass=0
fail=0

check() {
    local name="$1"; shift
    if "$@"; then
        pass=$((pass + 1)); echo "ok   $name"
    else
        fail=$((fail + 1)); echo "FAIL $name (log: $LOG)"
    fi
}

test_version_mismatch_fails() {
    local out code
    rm -f dist/MacClip-0.0.1.dmg dist/MacClip-0.0.1.dmg.sha256
    out="$("$SCRIPT" 0.0.1 2>&1)"
    code=$?
    echo "$out" > "$LOG"
    [ "$code" = 1 ] || { echo "  exit $code"; return 1; }
    echo "$out" | tail -1 | grep -qx "error: app version $VERSION does not match 0.0.1" || { echo "  last line: $(echo "$out" | tail -1)"; return 1; }
    [ ! -e dist/MacClip-0.0.1.dmg ] && [ ! -e dist/MacClip-0.0.1.dmg.sha256 ]
}

test_builds_dmg() {
    local mnt ok=0
    rm -f "dist/MacClip-$VERSION.dmg" "dist/MacClip-$VERSION.dmg.sha256"
    "$SCRIPT" "$VERSION" > "$LOG" 2>&1 || { echo "  build failed"; return 1; }
    (cd dist && shasum -a 256 -c "MacClip-$VERSION.dmg.sha256") | grep -q ': OK$' || { echo "  checksum"; return 1; }
    mnt="$(mktemp -d)"
    hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "dist/MacClip-$VERSION.dmg" >/dev/null || return 1
    if [ -d "$mnt/MaClip.app" ] && [ -L "$mnt/Applications" ] && codesign -v "$mnt/MaClip.app" 2>/dev/null; then
        ok=1
    else
        echo "  contents: $(ls "$mnt" | tr '\n' ' ')"
    fi
    hdiutil detach -quiet "$mnt"
    [ "$ok" = 1 ]
}

check test_version_mismatch_fails test_version_mismatch_fails
check test_builds_dmg test_builds_dmg

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
