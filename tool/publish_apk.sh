#!/usr/bin/env bash
# Puts one flavour's APK on GitHub Releases as pesaclarity-<flavor>.apk, for
# the APK workflow (.github/workflows/test-apk.yml).
#
#   tool/publish_apk.sh test-build <apk> <flavor> <build name>
#     Replaces the file on the test-build pre-release and points its tag at
#     this commit. The notes list the changes since the last release.
#
#   tool/publish_apk.sh release <apk> <flavor> <version>
#     Adds the file to release v<version>, which release-please creates on
#     the same push with the changelog as its notes.
#
# Needs GH_TOKEN, GH_REPO, GITHUB_SHA and RUN_URL, and gh on the path.
set -euo pipefail

mode="$1" apk="$2" flavor="$3" name="$4"
out="$(mktemp -d)"
file="$out/pesaclarity-$flavor.apk"
cp "$apk" "$file"

if [ "$mode" = release ]; then
  tag="v$name"
  # release-please makes the release in a job that starts with this one and
  # takes under a minute; wait up to five.
  for _ in $(seq 30); do
    gh release view "$tag" > /dev/null 2>&1 && break
    sleep 10
  done
  gh release view "$tag" > /dev/null 2>&1 || {
    echo "::error::Release $tag not found; did release-please fail on this push?"
    exit 1
  }
  gh release upload "$tag" "$file" --clobber
  exit 0
fi

[ "$mode" = test-build ] || { echo "Unknown mode: $mode" >&2; exit 1; }

# Commit titles since the last release, newest first, without merge commits.
last="$(gh release list --exclude-drafts --exclude-pre-releases --limit 1 \
  --json tagName --jq '.[0].tagName // empty')"
if [ -n "$last" ]; then
  heading="Changes since $last"
  titles="$(gh api "repos/$GH_REPO/compare/$last...$GITHUB_SHA" \
    --jq '[.commits[].commit.message | split("\n")[0]] | reverse | .[]')"
else
  heading="Recent changes"
  titles="$(gh api "repos/$GH_REPO/commits?sha=$GITHUB_SHA&per_page=40" \
    --jq '.[].commit.message | split("\n")[0]')"
fi
changes="$(printf '%s\n' "$titles" \
  | grep -v -E '^Merge (pull request|branch|remote-tracking)' \
  | head -30 | sed 's/^/- /' || true)"

title="Test build $name"
notes="The newest build from \`dev\`: $name, commit ${GITHUB_SHA::7}. It has not been through QA; each push to \`dev\` replaces these files.

- \`pesaclarity-play.apk\`: the Google Play flavour.
- \`pesaclarity-foss.apk\`: the F-Droid flavour, with no Google services.

On Android, open the file and allow installs from this source when asked.

## $heading

${changes:-- No changes listed.}

Built by $RUN_URL"

tag=test-build
if gh release view "$tag" > /dev/null 2>&1; then
  gh api -X PATCH "repos/$GH_REPO/git/refs/tags/$tag" \
    -f sha="$GITHUB_SHA" -F force=true > /dev/null
  gh release upload "$tag" "$file" --clobber
  gh release edit "$tag" --title "$title" --notes "$notes" \
    --prerelease --latest=false
elif ! gh release create "$tag" "$file" --target "$GITHUB_SHA" \
  --title "$title" --notes "$notes" --prerelease --latest=false; then
  # The other flavour's job made the release first.
  gh release upload "$tag" "$file" --clobber
fi
