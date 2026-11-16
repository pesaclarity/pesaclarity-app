#!/usr/bin/env python3
"""Run Ask's questions through the bundled ask-reader.tflite on this computer.

The app's tests cannot run TFLite on the host, so test/features/ask/ask_reader_test.dart
replays the real model's outputs recorded here: for each question, the intent probabilities and
the slot label probabilities of its tokens, for the exact input the app encodes.

  1. ASK_READER_RECORD=build/ask-reader-requests.json flutter test test/features/ask/ask_reader_test.dart
  2. uv run --project ../pesaclarity-ml python tool/ask_reader_decodes.py \\
       build/ask-reader-requests.json test/fixtures/ask/ask_reader_decodes.json
  3. flutter test test/features/ask/ask_reader_test.dart

Questions already in the output file are kept while the model is the same; a new model starts
the file afresh. Synthetic questions only: invented names, no real messages.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "assets" / "models" / "ask"


def main(requests_path: str, out_path: str) -> int:
    import numpy as np
    import tensorflow as tf

    manifest = json.loads((MODEL_DIR / "ask-reader-manifest.json").read_text())
    model_path = MODEL_DIR / manifest["model_file"]
    if hashlib.sha256(model_path.read_bytes()).hexdigest() != manifest["model_sha256"]:
        print("the bundled model does not match its manifest", file=sys.stderr)
        return 1
    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    inp = interpreter.get_input_details()[0]
    interpreter.resize_tensor_input(inp["index"], [1, 2 * manifest["max_tokens"]])
    interpreter.allocate_tensors()
    # Read the outputs by rank, as the app does: rank 2 is the intent, rank 3 the slots.
    outputs = {len(d["shape"]): d["index"] for d in interpreter.get_output_details()}

    requests = json.loads(Path(requests_path).read_text())
    target = Path(out_path)
    old = json.loads(target.read_text()) if target.exists() else {}
    if old.get("model_sha256") != manifest["model_sha256"]:
        old = {}
    readings = {r["question"]: r for r in old.get("readings", [])}

    for r in requests:
        ids = r["input"]
        interpreter.set_tensor(inp["index"], np.array([ids], dtype=np.int32))
        interpreter.invoke()
        intent = interpreter.get_tensor(outputs[2])[0]
        slots = interpreter.get_tensor(outputs[3])[0]
        n = r["tokens"]
        readings[r["question"]] = {
            "question": r["question"],
            "input": ids,
            "intent": [round(float(p), 5) for p in intent],
            "slots": [[round(float(p), 5) for p in row] for row in slots[:n]],
        }

    result = {
        "model_sha256": manifest["model_sha256"],
        "note": "Real ask-reader outputs for the app's questions, recorded on a computer by "
        "tool/ask_reader_decodes.py: intent probabilities, and slot probabilities for each "
        "token of the question.",
        "readings": sorted(readings.values(), key=lambda r: r["question"]),
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    # One question per line, so a re-record shows as a readable diff.
    rows = ",\n".join(
        "  " + json.dumps(r, separators=(",", ":")) for r in result["readings"]
    )
    head = json.dumps({k: v for k, v in result.items() if k != "readings"}, indent=1)
    target.write_text(head[:-2] + ',\n "readings": [\n' + rows + "\n ]\n}\n")
    print(f"{len(requests)} read, {len(readings)} recorded in {target}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
