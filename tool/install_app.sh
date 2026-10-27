#!/usr/bin/env bash
# Installs an APK on the connected device after removing any earlier copy.
# The emulator image is cached between CI runs and may still hold the app
# signed with another runner's debug key, which a plain reinstall refuses.
set -euo pipefail

apk="${1:?usage: install_app.sh path/to/app.apk}"
build_tools="$(find "${ANDROID_HOME:?ANDROID_HOME is not set}/build-tools" \
  -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
package="$("$build_tools/aapt2" dump packagename "$apk")"

adb uninstall "$package" >/dev/null 2>&1 || true
adb install "$apk"
