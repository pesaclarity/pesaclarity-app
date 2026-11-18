#!/usr/bin/env bash
# Copies six marketing screenshots into the F-Droid listing's phone
# screenshots (fastlane/metadata/android/en-US/images/phoneScreenshots),
# 780 x 1688 like the website's, light theme.
#
#   tool/fastlane_screenshots.sh <dir>
#
# <dir> holds the PNGs from tool/screenshots.sh. Needs ImageMagick.
set -euo pipefail

cd "$(dirname "$0")/.."
dir="$1"
dest=fastlane/metadata/android/en-US/images/phoneScreenshots

# The listing's order: position, then screen.
order="1 home
2 activity
3 plan
4 debts
5 insights
6 today"

magick=convert
command -v magick > /dev/null 2>&1 && magick=magick
while read -r n screen; do
  src="$dir/$screen-light.png"
  [ -f "$src" ] || { echo "Missing $src" >&2; exit 1; }
  # No metadata (dates), so the bytes only change when the screen does.
  "$magick" "$src" -resize 780x1688 -alpha off -strip \
    -define png:compression-level=9 -define png:color-type=2 \
    -define png:exclude-chunks=date,time "$dest/$n.png"
done <<< "$order"
