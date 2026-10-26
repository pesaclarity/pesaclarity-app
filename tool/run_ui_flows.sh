#!/usr/bin/env bash
# Runs every Maestro flow in .maestro/ on the connected Android device or
# emulator, once in light mode and once in dark mode. The app must already be
# installed. Reports and screenshots go to build/maestro/<theme>/.
#
# The onboarding flow runs first as a smoke test. If it fails, the other flows
# in that theme are skipped and device diagnostics are saved instead.
set -uo pipefail

# A crashed emulator makes adb wait forever; give up after a minute.
adb_bin="$(command -v adb)"
adb() { timeout 60 "$adb_bin" "$@"; }

out_dir="${1:-build/maestro}"
here="$(cd "$(dirname "$0")" && pwd)"
status=0

# upload-artifact rejects these characters in paths; Maestro names output
# folders after flows.
sanitise_paths() {
  find "$out_dir" -depth -name '*[<>:"|?*\\]*' | while IFS= read -r path; do
    # shellcheck disable=SC1003
    base="$(basename "$path" | tr '<>:"|?*\\' '________')"
    mv "$path" "$(dirname "$path")/$base"
  done
}

run_flows() {
  local theme="$1" report="$2"
  shift 2
  maestro test "$@" \
    -e THEME="$theme" \
    --format junit \
    --output "$out_dir/$theme/$report" \
    --test-output-dir "$out_dir/$theme"
}

# A cold-booted emulator often shows "System UI isn't responding" over the app.
# Hide system error dialogs and close any already showing.
adb shell settings put global hide_error_dialogs 1
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null

for theme in light dark; do
  if [ "$theme" = dark ]; then night=yes; else night=no; fi
  adb shell cmd uimode night "$night"
  sleep 2
  mkdir -p "$out_dir/$theme"

  if ! run_flows "$theme" smoke.xml .maestro/onboarding.yaml; then
    echo "Smoke flow failed in $theme mode; skipping the other flows."
    "$here/ui_diagnostics.sh" "$out_dir/diagnostics/$theme"
    status=1
    continue
  fi
  run_flows "$theme" report.xml .maestro/ --exclude-tags onboarding || status=1
done

adb shell cmd uimode night no
sanitise_paths
exit "$status"
