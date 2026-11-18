#!/usr/bin/env bash
# Draws the marketing screenshots (test/screenshots) and writes their
# manifest. Made-up records only; see README, Screenshots.
#
#   tool/screenshots.sh [out-dir]     default: build/screenshots
#
# Writes <screen>-<light|dark>.png, 1170 x 2532 (a 390 x 844 phone at 3x),
# and manifest.json: each screen's name, file, theme and SHA-256, plus a
# digest of them all that changes only when a screen does.
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-build/screenshots}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
rm -f "$out"/*.png "$out/manifest.json"

flutter test test/screenshots \
  --dart-define=SCREENSHOTS=true \
  --dart-define=SCREENSHOTS_OUT="$out"

commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
python3 - "$out" "$commit" <<'PY'
import hashlib, json, pathlib, struct, sys

out, commit = pathlib.Path(sys.argv[1]), sys.argv[2]
screens = []
for png in sorted(out.glob("*.png")):
    data = png.read_bytes()
    width, height = struct.unpack(">II", data[16:24])
    name, _, theme = png.stem.rpartition("-")
    screens.append({
        "name": name,
        "theme": theme,
        "file": png.name,
        "width": width,
        "height": height,
        "sha256": hashlib.sha256(data).hexdigest(),
    })
if not screens:
    sys.exit("No screenshots were drawn.")
digest = hashlib.sha256(
    "".join(f"{s['file']} {s['sha256']}\n" for s in screens).encode()
).hexdigest()
manifest = {
    "version": 1,
    "commit": commit,
    "devicePixelRatio": 3,
    "digest": digest,
    "screens": screens,
}
(out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"{len(screens)} screenshots in {out}, digest {digest[:12]}")
PY
