#!/usr/bin/env bash
# Tests for sync-version.sh. Run from the repo root: bash scripts/release/test-sync-version.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/sync-version.sh"
pass=0
fail=0

# A temp repo tagged v1.10.1 (build 14), then bumped to 1.11.0 the way release-please does it.
make_fixture() {
    local dir
    dir="$(mktemp -d)"
    mkdir -p "$dir/MacClipboard.xcodeproj"
    cat > "$dir/project.yml" <<'EOF'
targets:
  MacClipboard:
    settings:
      CURRENT_PROJECT_VERSION: 14
      MARKETING_VERSION: 1.10.1 # x-release-please-version
EOF
    cat > "$dir/MacClipboard.xcodeproj/project.pbxproj" <<'EOF'
		Debug = {
				CURRENT_PROJECT_VERSION = 14;
				MARKETING_VERSION = 1.10.1;
		};
		Release = {
				CURRENT_PROJECT_VERSION = 14;
				MARKETING_VERSION = 1.10.1;
		};
EOF
    (
        cd "$dir"
        git init -q
        git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
        git add -A
        git -c user.name=t -c user.email=t@t commit -q -m "release 1.10.1"
        git tag v1.10.1
        sed -i.bak 's/MARKETING_VERSION: 1.10.1/MARKETING_VERSION: 1.11.0/' project.yml
        rm project.yml.bak
    )
    echo "$dir"
}

check() {
    local name="$1"; shift
    if "$@"; then
        pass=$((pass + 1)); echo "ok   $name"
    else
        fail=$((fail + 1)); echo "FAIL $name"
    fi
}

test_sets_build_to_tag_plus_one() {
    local dir out
    dir="$(make_fixture)"
    out="$(cd "$dir" && "$SCRIPT" v1.10.1)" || return 1
    [ "$out" = "version=1.11.0 build=15" ] || { echo "  output: $out"; return 1; }
    grep -q '^      CURRENT_PROJECT_VERSION: 15$' "$dir/project.yml"
}

test_syncs_pbxproj() {
    local dir pbx
    dir="$(make_fixture)"
    (cd "$dir" && "$SCRIPT" v1.10.1 >/dev/null) || return 1
    pbx="$dir/MacClipboard.xcodeproj/project.pbxproj"
    [ "$(grep -c 'MARKETING_VERSION = 1.11.0;' "$pbx")" = 2 ] &&
        [ "$(grep -c 'CURRENT_PROJECT_VERSION = 15;' "$pbx")" = 2 ]
}

test_idempotent() {
    local dir
    dir="$(make_fixture)"
    (
        cd "$dir" &&
            "$SCRIPT" v1.10.1 >/dev/null &&
            git add -A && git -c user.name=t -c user.email=t@t commit -q -m run1 &&
            "$SCRIPT" v1.10.1 >/dev/null &&
            git diff --quiet &&
            [ -z "$(git status --porcelain)" ]
    )
}

test_keeps_annotation() {
    local dir
    dir="$(make_fixture)"
    (cd "$dir" && "$SCRIPT" v1.10.1 >/dev/null) || return 1
    grep -q '^      MARKETING_VERSION: 1.11.0 # x-release-please-version$' "$dir/project.yml"
}

test_missing_tag_fails() {
    local dir out code
    dir="$(make_fixture)"
    out="$(cd "$dir" && "$SCRIPT" v9.9.9 2>&1)"
    code=$?
    [ "$code" = 1 ] && [ "$out" = "error: tag v9.9.9 not found" ] || { echo "  exit $code: $out"; return 1; }
}

check test_sets_build_to_tag_plus_one test_sets_build_to_tag_plus_one
check test_syncs_pbxproj test_syncs_pbxproj
check test_idempotent test_idempotent
check test_keeps_annotation test_keeps_annotation
check test_missing_tag_fails test_missing_tag_fails

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
