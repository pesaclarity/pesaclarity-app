#!/usr/bin/env bash
# Runs every Maestro flow in .maestro/ on the connected Android device or
# emulator, once in light mode and once in dark mode. The app must already be
# installed. Reports and screenshots go to build/maestro/<theme>/.
set -uo pipefail

out_dir="${1:-build/maestro}"
status=0

for theme in light dark; do
  if [ "$theme" = dark ]; then night=yes; else night=no; fi
  adb shell cmd uimode night "$night"
  sleep 2

  mkdir -p "$out_dir/$theme"
  maestro test .maestro/ \
    -e THEME="$theme" \
    --format junit \
    --output "$out_dir/$theme/report.xml" \
    --test-output-dir "$out_dir/$theme" ||
    status=1
done

adb shell cmd uimode night no
exit "$status"
