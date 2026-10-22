#!/usr/bin/env bash
# Usage: scripts/release/sync-version.sh <last-release-tag>
#
# Run from the repo root on the release PR branch, after release-please has
# set MARKETING_VERSION in project.yml. Sets CURRENT_PROJECT_VERSION to the
# build number at <last-release-tag> + 1, and copies both values into the
# Xcode project. Running it again gives the same result.
set -euo pipefail

tag="${1:?usage: sync-version.sh <last-release-tag>}"
yml="project.yml"
pbx="MacClipboard.xcodeproj/project.pbxproj"

if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "error: tag $tag not found" >&2
    exit 1
fi

version="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*([0-9][0-9.]*).*/\1/p' "$yml" | head -1)"
last_build="$(git show "$tag:$yml" | sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
if [ -z "$version" ] || [ -z "$last_build" ]; then
    echo "error: cannot read MARKETING_VERSION or CURRENT_PROJECT_VERSION" >&2
    exit 1
fi
build=$((last_build + 1))

# -i.bak works with both BSD sed (macOS) and GNU sed (Linux runners).
sed -E -i.bak "s/^([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*)[0-9]+/\1$build/" "$yml"
sed -E -i.bak \
    -e "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1$build;/" \
    -e "s/(MARKETING_VERSION = )[0-9][0-9.]*;/\1$version;/" \
    "$pbx"
rm -f "$yml.bak" "$pbx.bak"

echo "version=$version build=$build"
