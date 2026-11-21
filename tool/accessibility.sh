#!/usr/bin/env bash
# The accessibility check: every screen of the marketing screenshots
# (test/screenshots) at 1, 1.3, 1.5 and 2 times the text size, in light and
# dark, and in high contrast at the usual size. Fails on anything that
# overflows, an amount cut short, a field's label cut short, a row name in
# Activity or Money cut before its second line, a word drawn across two
# lines in any text, a tap target under 48 x 48 (Android) or 44 x 44
# (iPhone) and a button with no label. Text contrast is
# reported in <out-dir>/contrast.jsonl and summarised; it fails only on the
# screens in must_pass below, which once fell short and were fixed.
#
#   tool/accessibility.sh [--shots] [out-dir]   default: build/accessibility
#
# --shots also saves each screen as <screen>-<theme>-<scale>x.png.
set -euo pipefail

cd "$(dirname "$0")/.."
shots=false
if [ "${1:-}" = --shots ]; then
  shots=true
  shift
fi
out="${1:-build/accessibility}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
rm -f "$out"/*.png "$out"/*.jsonl

flutter test test/screenshots \
  --dart-define=ACCESSIBILITY=true \
  --dart-define=ACCESSIBILITY_SHOTS="$shots" \
  --dart-define=ACCESSIBILITY_OUT="$out"

python3 - "$out/contrast.jsonl" <<'PY'
import json, sys

rows = [json.loads(line) for line in open(sys.argv[1])]
failed = [r for r in rows if not r["passed"]]
print(f"Text contrast: {len(rows) - len(failed)} of {len(rows)} screens pass")
for r in failed:
    print(f"- {r['screen']} ({r['theme']}):")
    for line in r["reason"].strip().splitlines():
        print(f"    {line}")

# Their small print once measured under 4.5:1 and now takes the darker
# muted colour (PesaColors.mutedSmall): they must keep passing.
must_pass = {"close-day", "support"}
regressed = sorted({f"{r['screen']} ({r['theme']})" for r in failed
                    if r["screen"] in must_pass})
missing = must_pass - {r["screen"] for r in rows}
if regressed or missing:
    for name in regressed:
        print(f"FAILED: text contrast fell short on {name}")
    for name in sorted(missing):
        print(f"FAILED: no contrast reading for {name}")
    sys.exit(1)
PY
