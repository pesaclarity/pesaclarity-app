#!/usr/bin/env bash
# Measures cold start on a connected Android phone (USB debugging on).
#
#   tool/startup_timing.sh [RUNS]   build a profile APK, install it, then
#                                   cold-start it RUNS times (default 5)
#   tool/startup_timing.sh --trace  one `flutter run --profile --trace-startup`
#                                   and its build/start_up_info.json
#
# Each cold start prints Android's own launch time (`am start -W`, process
# start to first frame drawn) and the app's startup phases, which debug and
# profile builds log as "Startup: <phase> <ms> ms", in ms since Dart's main:
#   main, look read, first frame, database key read, database open,
#   home data shown
# then the median of each. "home data shown" needs the app set up and app
# lock off, or it waits at the lock screen until the timeout.
#
# Settings: FLAVOR (foss or play, default foss), APP_ID (default
# com.pesaclarity.app), SKIP_BUILD=1 to time the APK already installed,
# WAIT_SECONDS (default 60) to wait for Home on each start.
set -euo pipefail

cd "$(dirname "$0")/.."

flavor="${FLAVOR:-foss}"
app_id="${APP_ID:-com.pesaclarity.app}"
wait_seconds="${WAIT_SECONDS:-60}"
phases=(main "look read" "first frame" "database key read" "database open" "home data shown")

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is not on PATH: install the Android SDK platform-tools." >&2
  exit 1
fi
if [ "$(adb get-state 2>/dev/null)" != device ]; then
  echo "No phone connected: plug one in with USB debugging on (adb devices)." >&2
  exit 1
fi

if [ "${1:-}" = --trace ]; then
  # Quits after the first frame and writes build/start_up_info.json.
  flutter run --profile --flavor "$flavor" --trace-startup
  echo
  cat build/start_up_info.json
  echo
  exit 0
fi

runs="${1:-5}"
case "$runs" in '' | *[!0-9]*) echo "RUNS must be a number" >&2; exit 2 ;; esac

if [ "${SKIP_BUILD:-}" != 1 ]; then
  flutter build apk --profile --flavor "$flavor"
  tool/install_app.sh "build/app/outputs/flutter-apk/app-$flavor-profile.apk"
fi

echo "Phone: $(adb shell getprop ro.product.model | tr -d '\r'), Android $(adb shell getprop ro.build.version.release | tr -d '\r')"
echo "Cold starts of $app_id ($flavor, profile build), times in ms:"
printf '%-6s %8s' run launch
for p in "${phases[@]}"; do printf ' %18s' "$p"; done
echo

results="$(mktemp)"
trap 'rm -f "$results"' EXIT

for run in $(seq 1 "$runs"); do
  adb shell am force-stop "$app_id"
  sleep 2
  adb logcat -c
  launch="$(adb shell am start -W -n "$app_id/.MainActivity" | tr -d '\r' |
    sed -n 's/^TotalTime: //p')"
  # Wait for Home's numbers, or give up and print what was reached.
  for _ in $(seq 1 "$wait_seconds"); do
    adb logcat -d -s flutter | grep -q 'Startup: home data shown' && break
    sleep 1
  done
  log="$(adb logcat -d -s flutter | tr -d '\r')"
  printf '%-6s %8s' "$run" "${launch:--}"
  line="$run ${launch:--}"
  for p in "${phases[@]}"; do
    ms="$(printf '%s\n' "$log" | sed -n "s/.*Startup: $p \([0-9]*\) ms.*/\1/p" | head -1)"
    printf ' %18s' "${ms:--}"
    line="$line ${ms:--}"
  done
  echo
  echo "$line" >>"$results"
done

# Median of each column, skipping runs that did not reach a phase.
printf '%-6s' median
for col in $(seq 2 $((${#phases[@]} + 2))); do
  median="$(awk -v c="$col" '$c != "-" { print $c }' "$results" | sort -n |
    awk '{ v[NR] = $1 } END { if (NR) print v[int((NR + 1) / 2)]; else print "-" }')"
  if [ "$col" = 2 ]; then printf ' %8s' "$median"; else printf ' %18s' "$median"; fi
done
echo
