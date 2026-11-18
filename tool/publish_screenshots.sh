#!/usr/bin/env bash
# Puts the marketing screenshots on a rolling pre-release, for the
# screenshots workflow (.github/workflows/screenshots.yml).
#
#   tool/publish_screenshots.sh <dir> <tag>
#
# <dir> holds the PNGs and manifest.json from tool/screenshots.sh. <tag> is
# `screenshots` for dev and `screenshots-main` for main. The release's files
# are replaced, files for screens that are gone are removed, and its tag is
# pointed at this commit.
#
# Prints changed=true or changed=false (whether any screen differs from the
# manifest already on the release) to $GITHUB_OUTPUT when it is set.
#
# Needs GH_TOKEN, GH_REPO, GITHUB_SHA and RUN_URL, and gh and jq on the path.
set -euo pipefail

dir="$1" tag="$2"
[ -f "$dir/manifest.json" ] || { echo "No manifest.json in $dir" >&2; exit 1; }
digest="$(jq -r .digest "$dir/manifest.json")"
branch="${tag#screenshots}"
branch="${branch#-}"
branch="${branch:-dev}"

previous=""
if gh release view "$tag" > /dev/null 2>&1; then
  prev_dir="$(mktemp -d)"
  if gh release download "$tag" --pattern manifest.json --dir "$prev_dir" 2> /dev/null; then
    previous="$(jq -r '.digest // empty' "$prev_dir/manifest.json")"
  fi
fi
if [ "$previous" = "$digest" ]; then
  changed=false
  echo "Screens unchanged since the last publish (digest ${digest::12})."
else
  changed=true
  echo "Screens changed: ${previous:-none}" "->" "$digest"
fi
[ -n "${GITHUB_OUTPUT:-}" ] && echo "changed=$changed" >> "$GITHUB_OUTPUT"

title="App screenshots ($branch)"
notes="The app's marketing screenshots, drawn from \`$branch\` at commit ${GITHUB_SHA::7} by \`tool/screenshots.sh\` with made-up records. Each push to \`$branch\` that changes the app replaces these files.

- \`<screen>-light.png\` and \`<screen>-dark.png\`: 1170 x 2532 pixels, a 390 x 844 phone at 3x.
- \`manifest.json\`: each screen's name, file, theme and SHA-256, and a digest of them all.

The website (pesaclarity.github.io) turns them into its WebP screens: light for its light mode, dark for its dark mode.

Drawn by $RUN_URL"

files=("$dir"/*.png "$dir/manifest.json")
if gh release view "$tag" > /dev/null 2>&1; then
  gh api -X PATCH "repos/$GH_REPO/git/refs/tags/$tag" \
    -f sha="$GITHUB_SHA" -F force=true > /dev/null
  gh release upload "$tag" "${files[@]}" --clobber
  gh release edit "$tag" --title "$title" --notes "$notes" \
    --prerelease --latest=false
  # Remove files for screens that are no longer drawn.
  keep="$(for f in "${files[@]}"; do basename "$f"; done)"
  gh release view "$tag" --json assets --jq '.assets[].name' |
    while read -r asset; do
      if ! grep -qxF "$asset" <<< "$keep"; then
        gh release delete-asset "$tag" "$asset" --yes
      fi
    done
else
  gh release create "$tag" "${files[@]}" --target "$GITHUB_SHA" \
    --title "$title" --notes "$notes" --prerelease --latest=false
fi
