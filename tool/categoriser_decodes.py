#!/usr/bin/env python3
"""Record what rayo gives for the categoriser's test rows, the outputs the app must give.

The app runs the categoriser on rayo from assets/models/categoriser/categoriser.weights
(pesaclarity-ml docs/CATEGORISER.md). For each row test/features/categoriser/
categoriser_model_test.dart scores (the encoded rows of feature_vectors.v1.json), this runs
that very file on the rayo library `flutter test` runs: the one rayo's build hook compiled for
this computer from the commit pubspec.lock pins (under .dart_tool; RAYO_LIB names another
build). It feeds the exact row the app encodes, `features` int32 [13], and records the float32
softmax `category` [27], in labels.json order. rayo gives the same floats on every kernel and
thread count, and from any compiler and flags (it is built with -ffp-contract=off), so the test
checks the app's rayo gives these bit for bit on the platform they were recorded on (`abi`),
and within 1e-5 with the same labels elsewhere.

As a cross-check it also runs the PyTorch model the weights were quantised from: akili's
module (akili.model.Categoriser) with the parameters of the release's categoriser.onnx, whose
SHA-256 must be the manifest's source.sha256. The int8 file must be within the export's parity
limits of torch (pesaclarity-ml docs/CATEGORISER.md): 0.25 on any probability, with torch's
label wherever torch's two best probabilities are more than 0.2 apart. The largest difference
is recorded.

  1. CATEGORISER_RECORD=build/categoriser-requests.json \\
       flutter test test/features/categoriser/categoriser_model_test.dart
  2. uv run --project ../pesaclarity-ml --extra torch python tool/categoriser_decodes.py \\
       path/to/categoriser.onnx build/categoriser-requests.json \\
       test/fixtures/categoriser/categoriser_decodes.json
  3. flutter test test/features/categoriser/categoriser_model_test.dart

Rows already in the output file are kept while the weights, the rayo commit and the platform
are the same; otherwise the file starts afresh. Synthetic rows only: the feature vectors'
invented payees.
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

MODEL_DIR = ROOT / "assets" / "models" / "categoriser"

# The export's parity limits, int8 against torch (pesaclarity-ml docs/CATEGORISER.md).
TOLERANCE = 0.25
# Labels must agree where torch's two best probabilities are further apart than this.
LABEL_MARGIN = 0.2


def torch_categoriser(onnx_bytes: bytes, manifest: dict, n_classes: int):  # noqa: ANN001, ANN201
    """akili's categoriser module with the parameters of ``onnx_bytes``."""
    import onnx
    import torch
    from onnx import numpy_helper

    from akili.config import FeatureConfig, ModelConfig
    from akili.model import Categoriser

    graph = onnx.load_from_string(onnx_bytes).graph
    initializers = {t.name: numpy_helper.to_array(t) for t in graph.initializer}
    shapes = manifest["fine_tune"]["weights"]
    module = Categoriser(
        FeatureConfig(**manifest["feature_config"]),
        ModelConfig(
            token_embedding_dim=int(initializers["token_embedding.weight"].shape[1]),
            hidden_units=shapes["hidden.kernel"][0],
        ),
        n_classes,
    )
    state = module.state_dict()
    missing = [name for name in state if name not in initializers]
    if missing:
        sys.exit(f"categoriser.onnx has no {missing}")
    module.load_state_dict({name: torch.from_numpy(initializers[name].copy()) for name in state})
    return module.eval()


def main(onnx_path: str, requests_path: str, out_path: str) -> int:
    import numpy as np
    import torch

    manifest = json.loads((MODEL_DIR / "model-manifest.json").read_text())
    labels = json.loads((MODEL_DIR / "labels.json").read_text())["labels"]
    weights = (MODEL_DIR / manifest["weights_file"]).read_bytes()
    if hashlib.sha256(weights).hexdigest() != manifest["weights_sha256"]:
        print("the bundled weights are not the manifest's", file=sys.stderr)
        return 1
    onnx_bytes = Path(onnx_path).read_bytes()
    if hashlib.sha256(onnx_bytes).hexdigest() != manifest["source"]["sha256"]:
        print(f"{onnx_path} is not the source of the bundled weights", file=sys.stderr)
        return 1

    session = app_session(weights)
    module = torch_categoriser(onnx_bytes, manifest, len(labels))

    requests = json.loads(Path(requests_path).read_text())
    target = Path(out_path)
    old = json.loads(target.read_text()) if target.exists() else {}
    if not same_recording(old, manifest["weights_sha256"]):
        old = {}
    readings = {r["id"]: r for r in old.get("readings", [])}
    worst = old.get("torch_max_abs", {"category": 0.0})

    for r in requests:
        row = np.array(r["input"], dtype=np.int32)
        session.run([row])
        category = np.array(session.output(0), dtype=np.float32).reshape(-1)
        with torch.no_grad():
            want = module(torch.from_numpy(row[None, :].astype(np.int64))).numpy()[0]
        if margin_apart(want, LABEL_MARGIN) and category.argmax() != want.argmax():
            print(f"{r['id']}: rayo and torch disagree", file=sys.stderr)
            return 1
        apart = float(np.abs(category - want).max())
        if apart > TOLERANCE:
            print(f"{r['id']} is {apart} from torch", file=sys.stderr)
            return 1
        worst = {"category": max(worst["category"], apart)}
        readings[r["id"]] = {"id": r["id"], "input": r["input"], "category": float32s(category)}

    head = {
        "weights_sha256": manifest["weights_sha256"],
        "rayo": pinned_commit(),
        "abi": abi(),
        "torch_max_abs": {k: round(v, 6) for k, v in worst.items()},
        "note": "Categoriser outputs for the app's test rows (feature_vectors.v1.json's encoded "
        "rows, by case id), recorded from categoriser.weights on the app's rayo library, as its "
        "build hook compiled it for abi, by tool/categoriser_decodes.py: the category "
        "probabilities in labels.json order, as float32. torch_max_abs is how far they are "
        "from the PyTorch model they were quantised from.",
    }
    write_recording(target, head, sorted(readings.values(), key=lambda r: r["id"]))
    print(f"{len(requests)} scored, {len(readings)} recorded in {target}; from torch: {worst}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
