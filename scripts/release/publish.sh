#!/usr/bin/env bash
# Usage: scripts/release/publish.sh <version> <sha> <release-pr-number>
#
# Run from the repo root at <sha>, after build-dmg.sh wrote dist/. Publishes
# the GitHub release v<version> only when every step works:
#   1. Check the DMG, its .sha256 and the CHANGELOG.md section.
#   2. Create a draft release (no tag yet, not public), or reuse a draft.
#   3. Upload the two files to the draft.
#   4. Publish the draft. GitHub creates the tag at <sha> now.
#   5. Mark the release PR "autorelease: tagged", so release-please opens
#      the next release PR.
# A failure stops the script and leaves at most a hidden draft. Running it
# again continues from that draft, or only relabels a published release.
set -euo pipefail

version="${1:?usage: publish.sh <version> <sha> <release-pr-number>}"
sha="${2:?usage: publish.sh <version> <sha> <release-pr-number>}"
pr="${3:?usage: publish.sh <version> <sha> <release-pr-number>}"
tag="v$version"
dmg="dist/MacClip-$version.dmg"

for f in "$dmg" "$dmg.sha256"; do
    if [ ! -s "$f" ]; then
        echo "error: missing $f" >&2
        exit 1
    fi
done

# The section starts at "## [<version>]" or "## <version>" and ends before
# the next "## " heading.
notes="$(mktemp)"
awk -v v="$version" '
    /^## / { if (found) exit; if (index($0, "## [" v "]") == 1 || index($0, "## " v " ") == 1 || $0 == "## " v) { found = 1; next } }
    found { print }
' CHANGELOG.md > "$notes"
if ! grep -q '[^[:space:]]' "$notes"; then
    echo "error: no CHANGELOG.md section for $version" >&2
    exit 1
fi

state="$(gh release list --limit 100 --json tagName,isDraft \
    --jq ".[] | select(.tagName == \"$tag\") | if .isDraft then \"draft\" else \"published\" end")"

if [ "$state" != "published" ]; then
    if [ -z "$state" ]; then
        gh release create "$tag" --draft --target "$sha" --title "$tag" --notes-file "$notes"
    fi
    gh release upload "$tag" "$dmg" "$dmg.sha256" --clobber
    gh release edit "$tag" --draft=false --latest
    echo "published $tag"
else
    echo "$tag is already published"
fi

gh label create "autorelease: tagged" --color ededed --force >/dev/null
gh pr edit "$pr" --remove-label "autorelease: pending" --add-label "autorelease: tagged"
rm -f "$notes"
