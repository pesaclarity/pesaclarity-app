#!/usr/bin/env bash
# Prepares this checkout for the F-Droid build, which accepts no prebuilt
# native libraries. It edits files in place, so run it on a throwaway
# checkout only: the F-Droid recipe (prebuild) and the foss release build.
#
# - Removes PDFium (pdfrx_engine and pdfium_flutter); the app then hides
#   statement import.
# - Compiles SQLCipher from source: tool/foss/build_sqlcipher_sources.sh
#   fetches the pinned SQLCipher and LibTomCrypt (or takes SQLCIPHER_SRC and
#   LIBTOMCRYPT_SRC), checks their hashes and writes the C files to
#   tool/foss/sqlcipher; package:sqlite3's build hook then compiles them
#   (`source: source`) instead of downloading its prebuilt libsqlcipher. The
#   flags match the prebuilt's, with LibTomCrypt in place of OpenSSL; the
#   database format is the same. The result links Android's liblog, so the
#   prepared checkout builds for Android only (not `flutter test` on a host).
#
# rayo, which runs the Ask models, needs nothing here: its build hook always
# compiles its C from source, in every build.
#
# Usage: tool/prepare_foss.sh [checkout]   (default: the current directory)
set -euo pipefail

root="${1:-.}"
cd "$root"

[ -f pubspec.yaml ] || { echo "No pubspec.yaml in $(pwd)" >&2; exit 1; }

# PDFium: drop the packages, the code that imports them, and their test.
sed -i -E '/^  # Statement PDFs are read on the phone with PDFium/,/^  pdfium_flutter:/d' pubspec.yaml
if grep -q -E '^  (pdfrx_engine|pdfium_flutter):' pubspec.yaml; then
  echo "Could not remove PDFium from pubspec.yaml" >&2
  exit 1
fi
cp tool/foss/pdf_engine.dart lib/src/features/statements/data/pdf_engine.dart
rm -f lib/src/features/statements/data/pdfium_text_extractor.dart \
  test/features/statements/pdfium_text_extractor_test.dart

# SQLCipher from source.
sqlcipher_dir=tool/foss/sqlcipher
tool/foss/build_sqlcipher_sources.sh "$(pwd)/$sqlcipher_dir"
grep -q -x '      source: sqlcipher' pubspec.yaml ||
  { echo "pubspec.yaml does not select the prebuilt SQLCipher" >&2; exit 1; }
hooks="$(mktemp)"
{
  echo "      source: source"
  echo "      path:"
  while read -r file; do echo "        - $sqlcipher_dir/$file"; done <"$sqlcipher_dir/sources.txt"
  echo "      additional_includes:"
  echo "        - $sqlcipher_dir/libtomcrypt/src/headers"
  # Android's logcat, where SQLCipher logs, as in the prebuilt.
  echo "      additional_libraries:"
  echo "        - log"
  # Keep this checkout's path out of the library (LibTomCrypt's __FILE__).
  echo "      additional_flags:"
  echo "        - -ffile-prefix-map=$(pwd)/="
  # package:sqlite3's defaults plus what its SQLCipher build adds
  # (tool/build_sqlite.dart in sqlite3.dart 3.8.0), with LibTomCrypt as
  # the crypto provider instead of OpenSSL.
  echo "      defines:"
  echo "        defines:"
  for define in SQLITE_HAS_CODEC SQLITE_TEMP_STORE=2 \
    SQLITE_EXTRA_INIT=sqlcipher_extra_init SQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown \
    HAVE_USLEEP SQLITE_USE_URI SQLITE_ENABLE_MEMORY_MANAGEMENT \
    SQLCIPHER_CRYPTO_LIBTOMCRYPT LTC_SOURCE; do
    echo "          - $define"
  done
} >"$hooks"
sed -i -e "/^      source: sqlcipher\$/{r $hooks" -e 'd}' pubspec.yaml
rm -f "$hooks"
grep -q -x '      source: source' pubspec.yaml ||
  { echo "Could not switch pubspec.yaml to SQLCipher from source" >&2; exit 1; }

echo "Prepared $(pwd) for the foss build."
