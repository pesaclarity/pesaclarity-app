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
import os
import platform
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "assets" / "models" / "ask"

# The export's parity limits, int8 against torch (pesaclarity-ml docs/ASK.md).
INTENT_TOLERANCE = 0.1
SLOTS_TOLERANCE = 0.25
# Labels must agree where torch's two best probabilities are further apart than this.
LABEL_MARGIN = 0.2


def pinned_commit() -> str:
    """The rayo commit pubspec.lock resolves."""
    lock = (ROOT / "pubspec.lock").read_text()
    block = lock[lock.index("\n  rayo:") :]
    commit = re.search(r'resolved-ref: "?([0-9a-f]{40})', block)
    if commit is None:
        sys.exit("pubspec.lock pins no rayo commit")
    return commit.group(1)


def app_rayo() -> Path:
    """The rayo library rayo's build hook last compiled for `flutter test` here."""
    if os.environ.get("RAYO_LIB"):
        return Path(os.environ["RAYO_LIB"])
    builds = sorted(
        (ROOT / ".dart_tool" / "hooks_runner" / "shared" / "rayo" / "build").glob("*/librayo.*"),
        key=lambda p: p.stat().st_mtime,
    )
    if not builds:
        sys.exit("no rayo build under .dart_tool: run step 1 first, or set RAYO_LIB")
    return builds[-1]


def abi() -> str:
    """This computer as Dart's Abi.current() names it, such as linux_x64."""
    system = {"linux": "linux", "darwin": "macos", "win32": "windows"}[sys.platform]
    machine = platform.machine().lower()
    return f"{system}_{ {'x86_64': 'x64', 'amd64': 'x64', 'aarch64': 'arm64'}.get(machine, machine)}"


def app_session(model):  # noqa: ANN001, ANN201
    """A rayo session on ``model`` with rayo's default options (one thread).

    rayo_convert's Session passes its own rayo_session_options, which has only `threads`; the
    app's rayo reads a longer struct (the cache and state options too), so the session is
    created with rayo_session_create, which takes none."""
    import ctypes

    from rayo_convert import runtime

    session = runtime.Session.__new__(runtime.Session)
    session.model = model
    session.L = model.lib.lib
    session.ptr = ctypes.c_void_p()
    msg = runtime._Message()  # noqa: SLF001
    if session.L.rayo_session_create(model.ptr, ctypes.byref(session.ptr), ctypes.byref(msg)):
        raise runtime.RayoError(msg.text.decode())
    return session


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


def margin_apart(row, margin: float) -> bool:  # noqa: ANN001
    top = sorted(row, reverse=True)
    return top[0] - top[1] > margin


def main(onnx_path: str, requests_path: str, out_path: str) -> int:
    import numpy as np
    import torch
    from rayo_convert.runtime import Library, Model

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

    model = Model(Library(app_rayo()), weights)
    session = app_session(model)
    session.bind("T", n)
    module = torch_reader(onnx_bytes)

    requests = json.loads(Path(requests_path).read_text())
    target = Path(out_path)
    old = json.loads(target.read_text()) if target.exists() else {}
    same = (manifest["weights_sha256"], pinned_commit(), abi())
    if (old.get("weights_sha256"), old.get("rayo"), old.get("abi")) != same:
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
            "intent": [float(str(np.float32(p))) for p in intent],
            "slots": [[float(str(np.float32(p))) for p in row] for row in slots[:count]],
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
    target.parent.mkdir(parents=True, exist_ok=True)
    # One question per line, so a re-record shows as a readable diff.
    rows = ",\n".join("  " + json.dumps(r, separators=(",", ":")) for r in result["readings"])
    head = json.dumps({k: v for k, v in result.items() if k != "readings"}, indent=1)
    target.write_text(head[:-2] + ',\n "readings": [\n' + rows + "\n ]\n}\n")
    print(f"{len(requests)} read, {len(readings)} recorded in {target}; from torch: {worst}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
