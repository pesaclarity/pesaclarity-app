#!/usr/bin/env bash
# Builds the signed Google Play App Bundle on your machine, for uploading by
# hand in Play Console (no GitHub Actions minutes needed).
#
# Build settings come from an env file (copy release.env.example to
# release.env; it is git-ignored). The server address can come from Secret
# Manager instead: set GCP_PROJECT_ID and PESACLARITY_API_URL_SECRET, and the
# script reads the latest version with gcloud. The vault is on the same server
# unless PESACLARITY_VAULT_URL says otherwise.
#
# Signing uses android/key.properties with the upload key (see RELEASING.md).
#
# Usage: tool/build_release.sh [env file]   (default: release.env)
set -euo pipefail

cd "$(dirname "$0")/.."
env_file="${1:-release.env}"
[ -f "$env_file" ] || { echo "No $env_file; copy release.env.example and fill it in." >&2; exit 1; }
set -a
# shellcheck source=/dev/null
. "./$env_file"
set +a

[ -f android/key.properties ] || { echo "No android/key.properties: add the upload key (RELEASING.md)." >&2; exit 1; }

if [ -z "${PESACLARITY_API_URL:-}" ] && [ -n "${PESACLARITY_API_URL_SECRET:-}" ]; then
  : "${GCP_PROJECT_ID:?set GCP_PROJECT_ID to read the secret}"
  PESACLARITY_API_URL="$(gcloud secrets versions access latest \
    --secret "$PESACLARITY_API_URL_SECRET" --project "$GCP_PROJECT_ID")"
fi
case "${PESACLARITY_API_URL:-}" in
  https://*) ;;
  *) echo "PESACLARITY_API_URL must be an https address." >&2; exit 1 ;;
esac
PESACLARITY_VAULT_URL="${PESACLARITY_VAULT_URL:-$PESACLARITY_API_URL}"
: "${BUILD_NUMBER:?set BUILD_NUMBER, higher than any version code uploaded before}"

SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"
export SOURCE_DATE_EPOCH
version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
symbols="build/symbols/play-$version-$BUILD_NUMBER"

flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build appbundle --release --flavor play \
  --build-number="$BUILD_NUMBER" \
  --obfuscate --split-debug-info="$symbols" \
  --dart-define=PESACLARITY_API_URL="$PESACLARITY_API_URL" \
  --dart-define=PESACLARITY_VAULT_URL="$PESACLARITY_VAULT_URL" \
  --dart-define=PESACLARITY_GOOGLE_SERVER_CLIENT_ID="${PESACLARITY_GOOGLE_SERVER_CLIENT_ID:-}" \
  --dart-define=PESACLARITY_PLAY_CLOUD_PROJECT="${PESACLARITY_PLAY_CLOUD_PROJECT:-}" \
  --dart-define=PESACLARITY_PINNED_HOSTS="${PESACLARITY_PINNED_HOSTS:-}" \
  --dart-define=PESACLARITY_TRUSTED_ROOTS="${PESACLARITY_TRUSTED_ROOTS:-}" \
  --dart-define=PESACLARITY_RATES_URL="${PESACLARITY_RATES_URL:-}" \
  --dart-define=PESACLARITY_RATES_SOURCE_NAME="${PESACLARITY_RATES_SOURCE_NAME:-}" \
  --dart-define=PESACLARITY_RATES_SOURCE_URL="${PESACLARITY_RATES_SOURCE_URL:-}"

echo
echo "Bundle:  build/app/outputs/bundle/playRelease/app-play-release.aab"
echo "Mapping: build/app/outputs/mapping/playRelease/mapping.txt"
echo "Symbols: $symbols (keep these with the release)"
echo "Upload the bundle in Play Console > Test and release > Internal testing (or Closed testing)."
