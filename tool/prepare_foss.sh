#!/usr/bin/env bash
# Prepares this checkout for the F-Droid build, which accepts no prebuilt
# native libraries. It edits files in place, so run it on a throwaway
# checkout only: the F-Droid recipe (prebuild) and the foss release build.
#
# - Removes PDFium (pdfrx_engine and pdfium_flutter); the app then hides
#   statement import.
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

echo "Prepared $(pwd) for the foss build."
