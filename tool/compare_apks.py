#!/usr/bin/env python3
"""Tells whether two APKs hold the same files, ignoring how each was signed.

Reproducible builds (docs/reproducible-builds.md) need a rebuild to match ours byte for byte
before signing. Two builds signed with the same key should be identical files; when they are
not, this lists the entries that differ, so the cause can be found.

Usage: tool/compare_apks.py first.apk second.apk
Exit status: 0 when every entry matches, 1 otherwise.
"""

import hashlib
import sys
import zipfile

# Signature files of the v1 (JAR) scheme. The v2 and v3 signatures sit outside the entries.
SIGNATURE_SUFFIXES = (".SF", ".RSA", ".DSA", ".EC")


def is_signature(name: str) -> bool:
    return name.startswith("META-INF/") and (
        name.endswith(SIGNATURE_SUFFIXES) or name == "META-INF/MANIFEST.MF"
    )


def entries(path: str) -> dict[str, tuple[str, int, int, str]]:
    """Each entry's content hash, compression method, external attributes and extra field."""
    out = {}
    with zipfile.ZipFile(path) as apk:
        for info in apk.infolist():
            if is_signature(info.filename):
                continue
            digest = hashlib.sha256(apk.read(info)).hexdigest()
            out[info.filename] = (digest, info.compress_type, info.external_attr, info.extra.hex())
    return out


def main(first: str, second: str) -> int:
    a, b = entries(first), entries(second)
    differ = False
    for name in sorted(a.keys() - b.keys()):
        print(f"only in {first}: {name}")
        differ = True
    for name in sorted(b.keys() - a.keys()):
        print(f"only in {second}: {name}")
        differ = True
    for name in sorted(a.keys() & b.keys()):
        if a[name] != b[name]:
            labels = ("content", "method", "attrs", "extra")
            fields = [label for label, x, y in zip(labels, a[name], b[name]) if x != y]
            print(f"differs ({', '.join(fields)}): {name}")
            differ = True
    if list(a) != list(b) and not differ:
        print("same entries, in a different order")
        differ = True
    if not differ:
        print(f"{len(a)} entries match")
    return 1 if differ else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-2], file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
