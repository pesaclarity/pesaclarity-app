#!/usr/bin/env python3
"""Record what rayo reads in the message reader's test messages, the outputs the app must give.

The app runs the message reader on rayo from assets/models/reader/reader.weights (pesaclarity-ml
docs/READER.md). For each message test/features/review/message_reader_test.dart reads, this
runs that very file on the rayo library `flutter test` runs: the one rayo's build hook compiled
for this computer from the commit pubspec.lock pins (under .dart_tool; RAYO_LIB names another
build). It records its float32 outputs for the exact input the app encodes: the kind
probabilities, and the field probabilities of every token of the message. rayo gives the same
floats on every kernel and thread count, and from any compiler and flags: since rayo 21c953e it
is always built with -ffp-contract=off, so no compiler fuses a multiply and an add (the hook's
clang -O3 -mavx2 -mfma build and a plain gcc -O2 one record the same file). Another platform's
C library may still round exp or tanh differently in the last bit, so the test checks the
app's rayo gives these bit for bit on the platform they were recorded on (`abi`), and within
1e-5 with the same labels elsewhere.

As a cross-check it also runs the PyTorch model the weights were quantised from: the reader's
module (akili.reader.model) with the parameters of the release's reader.onnx, whose SHA-256
must be the manifest's source.sha256. The int8 file must give torch's field and kind on every
token where torch's two best scores are clearly apart, and probabilities within twice the
export's tolerance (2e-2 for the fields and for the kind); a message beyond the tolerance
itself is named, and the largest differences are recorded.

  1. READER_RECORD=build/reader-requests.json \\
       flutter test test/features/review/message_reader_test.dart
  2. uv run --project ../pesaclarity-ml --extra torch python tool/reader_decodes.py \\
       path/to/reader.onnx build/reader-requests.json \\
       test/fixtures/reader/reader_decodes.json
  3. flutter test test/features/review/message_reader_test.dart

Messages already in the output file are kept while the weights, the rayo commit and the
platform are the same; otherwise the file starts afresh. Synthetic messages only: invented institutions, people and numbers.
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

MODEL_DIR = ROOT / "assets" / "models" / "reader"

# The export's tolerances, int8 against torch (pesaclarity-ml docs/READER.md).
FIELDS_TOLERANCE = 2e-2
KIND_TOLERANCE = 2e-2


def torch_reader(onnx_bytes: bytes):  # noqa: ANN201
    """akili's reader module with the parameters of ``onnx_bytes``."""
    import onnx
    import torch
    from onnx import numpy_helper

    from akili.reader.model import Reader

    graph = onnx.load_from_string(onnx_bytes).graph
    initializers = {t.name: numpy_helper.to_array(t) for t in graph.initializer}
    # torch.onnx exports a linear layer on a 3-D input as a MatMul with its kernel
    # transposed, under a name of its own.
    for node in graph.node:
        layer = node.output[0].split("/")[1] if node.output[0].startswith("/") else ""
        if node.op_type == "MatMul" and f"{layer}.weight" not in initializers:
            if node.input[1] in initializers:
                initializers[f"{layer}.weight"] = initializers[node.input[1]].T
    module = Reader()
    state = module.state_dict()
    missing = [name for name in state if name not in initializers]
    if missing:
        sys.exit(f"reader.onnx has no {missing}")
    module.load_state_dict({name: torch.from_numpy(initializers[name].copy()) for name in state})
    return module.eval()


def main(onnx_path: str, requests_path: str, out_path: str) -> int:
    import numpy as np
    import torch

    manifest = json.loads((MODEL_DIR / "reader-manifest.json").read_text())
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
    readings = {r["message"]: r for r in old.get("readings", [])}
    worst = old.get("torch_max_abs", {"fields": 0.0, "kind": 0.0})

    for r in requests:
        ids = np.array(r["input"], dtype=np.int32)
        session.run([ids[:n], ids[n:]])
        fields = np.array(session.output(0), dtype=np.float32).reshape(n, -1)
        kind = np.array(session.output(1), dtype=np.float32).reshape(-1)
        with torch.no_grad():
            tf, tk = module(
                torch.from_numpy(ids[None, :n].astype(np.int64)),
                torch.from_numpy(ids[None, n:].astype(np.int64)),
            )
        tf, tk = tf.numpy()[0], tk.numpy()[0]
        count = r["tokens"]
        for t in range(count):
            if margin_apart(tf[t], 2 * FIELDS_TOLERANCE) and fields[t].argmax() != tf[t].argmax():
                print(f"token {t} of {r['message']!r}: rayo and torch disagree", file=sys.stderr)
                return 1
        if margin_apart(tk, 2 * KIND_TOLERANCE) and kind.argmax() != tk.argmax():
            print(f"kind of {r['message']!r}: rayo and torch disagree", file=sys.stderr)
            return 1
        apart = {
            "fields": float(np.abs(fields[:count] - tf[:count]).max(initial=0)),
            "kind": float(np.abs(kind - tk).max()),
        }
        if apart["fields"] > FIELDS_TOLERANCE or apart["kind"] > KIND_TOLERANCE:
            print(f"note: {r['message'][:40]!r} is {apart} from torch", file=sys.stderr)
        worst = {
            "fields": max(worst["fields"], apart["fields"]),
            "kind": max(worst["kind"], apart["kind"]),
        }
        # Each float32 as its shortest repr, which reads back as the same float32.
        readings[r["message"]] = {
            "message": r["message"],
            "input": r["input"],
            "kind": float32s(kind),
            "fields": [float32s(row) for row in fields[:count]],
        }
    # The export holds the int8 file to these tolerances on messages like the ones it trains
    # on; on the vectors' edge cases (96 tokens of one word, say) it can be a little further,
    # so that is noted above, and twice the tolerance fails.
    if worst["fields"] > 2 * FIELDS_TOLERANCE or worst["kind"] > 2 * KIND_TOLERANCE:
        print(f"rayo is too far from torch: {worst}", file=sys.stderr)
        return 1

    result = {
        "weights_sha256": manifest["weights_sha256"],
        "rayo": pinned_commit(),
        "abi": abi(),
        "torch_max_abs": {k: round(v, 6) for k, v in worst.items()},
        "note": "Message reader outputs for the app's test messages, recorded from "
        "reader.weights on the app's rayo library, as its build hook compiled it for abi, by "
        "tool/reader_decodes.py: kind probabilities, and field probabilities for each token "
        "of the message, as float32. torch_max_abs is how far they are from the PyTorch "
        "model they were quantised from.",
        "readings": sorted(readings.values(), key=lambda r: r["message"]),
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
