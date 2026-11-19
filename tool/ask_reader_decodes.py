#!/usr/bin/env python3
"""Record what rayo reads in Ask's test questions, the outputs the app's readers must give.

The app runs the Ask reader on rayo from assets/models/ask/ask-reader.weights (pesaclarity-ml
docs/ASK.md), and in Dart where rayo cannot load. For each question
test/features/ask/ask_reader_test.dart asks, this runs that very file on the rayo library
`flutter test` runs: the one rayo's build hook compiled for this computer from the commit
pubspec.lock pins (under .dart_tool; RAYO_LIB names another build). It feeds the exact input
the app encodes, `tokens` then `shapes` (T = 96), and records the float32 outputs, `slots`
then `intent`: the intent probabilities, and the slot probabilities of every token of the
question. rayo gives the same floats on every kernel and thread count, and from any compiler
and flags (it is built with -ffp-contract=off), so the test checks the app's rayo gives these
bit for bit on the platform they were recorded on (`abi`), and within 1e-5 with the same
labels elsewhere; the Dart reader must give them within 1e-4.

As a cross-check it also runs the PyTorch model the weights were quantised from: akili's
module (akili.ask.reader_model.AskReader) with the parameters of the release's
ask-reader.onnx, whose SHA-256 must be the manifest's source.sha256. The int8 file must be
within the export's parity limits of torch (pesaclarity-ml docs/ASK.md): 0.1 for the intent
and 0.25 for a token's slots, with torch's label wherever torch's two best probabilities are
more than 0.2 apart. The largest differences are recorded.

  1. ASK_READER_RECORD=build/ask-reader-requests.json \\
       flutter test test/features/ask/ask_reader_test.dart
  2. uv run --project ../pesaclarity-ml --extra torch python tool/ask_reader_decodes.py \\
       path/to/ask-reader.onnx build/ask-reader-requests.json \\
       test/fixtures/ask/ask_reader_decodes.json
  3. flutter test test/features/ask/ask_reader_test.dart

Questions already in the output file are kept while the weights, the rayo commit and the
platform are the same; otherwise the file starts afresh (and the test, given recordings of
other weights, asks for every question in step 1). Synthetic questions only: invented names,
no real messages.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from rayo_recording import (
    ROOT,
    abi,
    app_session,
    float32s,
    margin_apart,
    pinned_commit,
    same_recording,
    write_recording,
)

MODEL_DIR = ROOT / "assets" / "models" / "ask"

# The export's parity limits, int8 against torch (pesaclarity-ml docs/ASK.md).
INTENT_TOLERANCE = 0.1
SLOTS_TOLERANCE = 0.25
# Labels must agree where torch's two best probabilities are further apart than this.
LABEL_MARGIN = 0.2


def torch_reader(onnx_bytes: bytes):  # noqa: ANN201
    """akili's Ask reader module with the parameters of ``onnx_bytes``."""
    import onnx
    import torch
    from onnx import numpy_helper

    from akili.ask.reader_model import AskReader

    graph = onnx.load_from_string(onnx_bytes).graph
    initializers = {t.name: numpy_helper.to_array(t) for t in graph.initializer}
    # torch.onnx exports a linear layer on a 3-D input as a MatMul with its kernel
    # transposed, under a name of its own.
    for node in graph.node:
        layer = node.output[0].split("/")[1] if node.output[0].startswith("/") else ""
        if node.op_type == "MatMul" and f"{layer}.weight" not in initializers:
            if node.input[1] in initializers:
                initializers[f"{layer}.weight"] = initializers[node.input[1]].T
    module = AskReader()
    state = module.state_dict()
    missing = [name for name in state if name not in initializers]
    if missing:
        sys.exit(f"ask-reader.onnx has no {missing}")
    module.load_state_dict({name: torch.from_numpy(initializers[name].copy()) for name in state})
    return module.eval()


def main(onnx_path: str, requests_path: str, out_path: str) -> int:
    import numpy as np
    import torch

    manifest = json.loads((MODEL_DIR / "ask-reader-manifest.json").read_text())
    weights = (MODEL_DIR / manifest["weights_file"]).read_bytes()
    if hashlib.sha256(weights).hexdigest() != manifest["weights_sha256"]:
        print("the bundled weights are not the manifest's", file=sys.stderr)
        return 1
    onnx_bytes = Path(onnx_path).read_bytes()
    if hashlib.sha256(onnx_bytes).hexdigest() != manifest["source"]["sha256"]:
        print(f"{onnx_path} is not the source of the bundled weights", file=sys.stderr)
        return 1
    n = manifest["max_tokens"]

    session = app_session(weights)
    session.bind("T", n)
    module = torch_reader(onnx_bytes)

    requests = json.loads(Path(requests_path).read_text())
    target = Path(out_path)
    old = json.loads(target.read_text()) if target.exists() else {}
    if not same_recording(old, manifest["weights_sha256"]):
        old = {}
    readings = {r["question"]: r for r in old.get("readings", [])}
    worst = old.get("torch_max_abs", {"intent": 0.0, "slots": 0.0})

    for r in requests:
        ids = np.array(r["input"], dtype=np.int32)
        # Inputs tokens then shapes; outputs slots then intent.
        session.run([ids[:n], ids[n:]])
        slots = np.array(session.output(0), dtype=np.float32).reshape(n, -1)
        intent = np.array(session.output(1), dtype=np.float32).reshape(-1)
        with torch.no_grad():
            ts, ti = module(
                torch.from_numpy(ids[None, :n].astype(np.int64)),
                torch.from_numpy(ids[None, n:].astype(np.int64)),
            )
        ts, ti = ts.numpy()[0], ti.numpy()[0]
        count = r["tokens"]
        question = r["question"]
        for t in range(count):
            if margin_apart(ts[t], LABEL_MARGIN) and slots[t].argmax() != ts[t].argmax():
                print(f"token {t} of {question!r}: rayo and torch disagree", file=sys.stderr)
                return 1
        if margin_apart(ti, LABEL_MARGIN) and intent.argmax() != ti.argmax():
            print(f"intent of {question!r}: rayo and torch disagree", file=sys.stderr)
            return 1
        apart = {
            "intent": float(np.abs(intent - ti).max()),
            "slots": float(np.abs(slots[:count] - ts[:count]).max(initial=0)),
        }
        if apart["intent"] > INTENT_TOLERANCE or apart["slots"] > SLOTS_TOLERANCE:
            print(f"{question!r} is {apart} from torch", file=sys.stderr)
            return 1
        worst = {k: max(worst[k], apart[k]) for k in worst}
        # Each float32 as its shortest repr, which reads back as the same float32.
        readings[question] = {
            "question": question,
            "input": r["input"],
            "intent": float32s(intent),
            "slots": [float32s(row) for row in slots[:count]],
        }

    result = {
        "weights_sha256": manifest["weights_sha256"],
        "rayo": pinned_commit(),
        "abi": abi(),
        "torch_max_abs": {k: round(v, 6) for k, v in worst.items()},
        "note": "Ask reader outputs for the app's test questions, recorded from "
        "ask-reader.weights on the app's rayo library, as its build hook compiled it for abi, "
        "by tool/ask_reader_decodes.py: intent probabilities, and slot probabilities for each "
        "token of the question, as float32. torch_max_abs is how far they are from the "
        "PyTorch model they were quantised from.",
        "readings": sorted(readings.values(), key=lambda r: r["question"]),
    }
    write_recording(
        target, {k: v for k, v in result.items() if k != "readings"}, result["readings"]
    )
    print(f"{len(requests)} read, {len(readings)} recorded in {target}; from torch: {worst}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
