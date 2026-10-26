#!/usr/bin/env bash
# Launches the installed app outside Maestro and saves what the device shows:
# logcat (app, Flutter and crash lines), the top activity, a raw screenshot and
# the view hierarchy. Used by run_ui_flows.sh when a flow cannot find the app.
set -uo pipefail

# A crashed emulator makes adb wait forever; give up after a minute.
adb_bin="$(command -v adb)"
adb() { timeout 60 "$adb_bin" "$@"; }

out_dir="${1:-build/maestro/diagnostics}"
app_id="${APP_ID:-com.pesaclarity.app}"
mkdir -p "$out_dir"

adb shell settings put global hide_error_dialogs 1
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null
adb shell am force-stop "$app_id"
adb logcat -c
adb shell monkey -p "$app_id" -c android.intent.category.LAUNCHER 1 \
  >"$out_dir/monkey.txt" 2>&1
sleep 20

pid="$(adb shell pidof "$app_id" | tr -d '\r')"
echo "pid=${pid:-not running}" >"$out_dir/pid.txt"
adb logcat -d -v threadtime >"$out_dir/logcat-all.txt"
if [ -n "$pid" ]; then
  adb logcat -d -v threadtime --pid="$pid" >"$out_dir/logcat-app.txt"
fi
grep -E "flutter|AndroidRuntime|FATAL|DEBUG +:|libc +:|$app_id" \
  "$out_dir/logcat-all.txt" >"$out_dir/logcat-crash.txt" || true

adb shell dumpsys activity top | head -60 >"$out_dir/activity-top.txt"
adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" \
  >"$out_dir/window-focus.txt" || true
adb exec-out screencap -p >"$out_dir/screen.png"

adb shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 &&
  adb pull /sdcard/window_dump.xml "$out_dir/uiautomator.xml" >/dev/null 2>&1
timeout 180 maestro hierarchy >"$out_dir/maestro-hierarchy.json" 2>&1 || true
# Echo the key evidence to the job log as well, since artifacts are not
# always easy to fetch.
{
  echo "--- $(cat "$out_dir/pid.txt")"
  echo "--- window focus"
  cat "$out_dir/window-focus.txt"
  echo "--- on-screen text"
  grep -o 'text="[^"]*"\|content-desc="[^"]*"\|resource-id="[^"]*"' \
    "$out_dir/uiautomator.xml" 2>/dev/null | grep -v '=""' | head -40
  echo "--- crash and Flutter log lines (last 80)"
  tail -80 "$out_dir/logcat-crash.txt"
} || true
echo "Diagnostics saved to $out_dir"
