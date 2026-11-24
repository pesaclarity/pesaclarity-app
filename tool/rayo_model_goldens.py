#!/usr/bin/env python3
"""Writes integration_test/rayo_model_goldens.dart from the recorded model
outputs in test/fixtures (the *_decodes.json files that tool/*_decodes.py
record), so the on-phone model test has them without reading the host's
files. Run it after recording afresh:

    python3 tool/rayo_model_goldens.py
"""
import json
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
fixtures = {
    "askReaderDecodes": "test/fixtures/ask/ask_reader_decodes.json",
    "messageReaderDecodes": "test/fixtures/reader/reader_decodes.json",
    "categoriserDecodes": "test/fixtures/categoriser/categoriser_decodes.json",
    "askWriterDecodes": "test/fixtures/ask/ask_writer_decodes.json",
}
out = [
    "// Written by tool/rayo_model_goldens.py from test/fixtures; do not edit.",
    "// ignore_for_file: lines_longer_than_80_chars",
    "",
]
for name, path in fixtures.items():
    data = json.loads((root / path).read_text())
    text = json.dumps(data, separators=(",", ":"))
    assert "'''" not in text
    out += [f"/// {path}.", f"const {name} = r'''{text}''';", ""]
(root / "integration_test/rayo_model_goldens.dart").write_text("\n".join(out))
