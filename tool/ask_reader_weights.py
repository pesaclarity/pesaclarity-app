#!/usr/bin/env python3
"""Spike: export ask-reader.tflite's weights as plain tensors for the pure-Dart reader.

Reads the weights out of the bundled .tflite (the bytes that ship, not a retrained copy) and
writes them in a small format that lib/src/domain/ml_dart/ reads without TFLite:

  "PCW1", uint32 little-endian header length, a UTF-8 JSON header, zero padding to 4 bytes,
  then the tensors' raw little-endian bytes at the offsets the header gives.

The header lists the model's sha256, the layers in order and each tensor's name, dtype
("int8" or "float32"), shape and offset. int8 weights keep their per-channel float32 scales
(tensor "<name>.scale"), so the file stays about the size of the model.

With --check it also runs a NumPy copy of the Dart forward pass on the recorded inputs in
test/fixtures/ask/ask_reader_decodes.json and prints how far it is from TFLite.

  uv run --project ../pesaclarity-ml python tool/ask_reader_weights.py \\
      test/fixtures/ask/ask-reader.weights [--check]

This is a spike for the on-device ML decision record, not a release tool.
"""

from __future__ import annotations

import hashlib
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "assets" / "models" / "ask"
FIXTURE = ROOT / "test" / "fixtures" / "ask" / "ask_reader_decodes.json"

# (layer, kind, kernel size, dilation): the model's layers in the order they run. The tensor
# names are the Keras layer names inside the converted graph.
LAYERS = [
    ("token_embedding", "embedding", 0, 0),
    ("shape_embedding", "embedding", 0, 0),
    ("conv_1", "conv1d", 3, 1),
    ("conv_2", "conv1d", 5, 1),
    ("conv_3", "conv1d", 3, 3),
    ("slot_hidden", "dense", 0, 0),
    ("slot_context", "conv1d", 5, 1),
    ("slot_span", "conv1d", 3, 2),
    ("slots", "dense", 0, 0),
    ("intent_hidden", "dense", 0, 0),
    ("intent", "dense", 0, 0),
]


def _weights(interpreter):
    """Each layer's kernel (int8 or float32, with scales) and bias, read from the graph."""
    details = interpreter.get_tensor_details()
    by_index = {d["index"]: d for d in details}
    ops = interpreter._get_ops_details()  # noqa: SLF001 - the graph's op list
    out = {}

    def tensor(i):
        d = by_index[i]
        return d, interpreter.get_tensor(i)

    def add(name, i):
        d, value = tensor(i)
        q = d["quantization_parameters"]
        out[name] = value.copy()
        if value.dtype.name == "int8":
            out[name + ".scale"] = q["scales"].astype("float32")

    for layer, kind, _, _ in LAYERS:
        prefix = f"akili_ask_reader_1/{layer}_1/"
        if kind == "embedding":
            table = [d for d in details if d["name"].startswith(prefix + "GatherV2/ReadVariableOp")
                     and len(d["shape"]) == 2]
            add(layer + ".table", table[0]["index"])
            continue
        # The op whose kernel is this layer's (a constant named after the layer).
        op = next(
            o for o in ops
            if o["op_name"] in ("CONV_2D", "FULLY_CONNECTED")
            and by_index[o["inputs"][1]]["name"].startswith(prefix)
        )
        kernel = int(op["inputs"][1])
        add(layer + ".kernel", kernel)
        biases = []
        if op["inputs"][2] >= 0:
            biases.append(tensor(int(op["inputs"][2]))[1])
        # Dilated convolutions and Tensordot denses add their bias in a separate ADD.
        for d in details:
            n = d["name"]
            if (n == prefix + "Squeeze" or n == prefix + "BiasAdd/ReadVariableOp") and len(
                d["shape"]
            ) == 1:
                biases.append(interpreter.get_tensor(d["index"]))
        out[layer + ".bias"] = sum(b.astype("float32") for b in biases).astype("float32")
    return out


def _forward(w, ids, *, hybrid):
    """NumPy copy of the Dart forward pass for one question (int32 [192])."""
    import numpy as np

    t = 96
    tokens, shapes = np.asarray(ids[:t]), np.asarray(ids[t:])
    mask = (shapes > 0).astype("float32")[:, None]
    n = max(mask.sum(), 1.0)
    tok = w["token_embedding.table"][tokens].astype("float32") * w["token_embedding.table.scale"][0]
    emb = np.concatenate([tok, w["shape_embedding.table"][shapes]], axis=1)

    def quantised(x):
        # TFLite's hybrid kernels quantise a float input to int8 on the fly, asymmetrically,
        # with one scale and zero point per input row (tensor_utils AsymmetricQuantizeFloats).
        if not hybrid:
            return x
        lo, hi = min(float(x.min()), 0.0), max(float(x.max()), 0.0)
        if lo == hi:
            return np.zeros_like(x)
        scale = (hi - lo) / 255.0
        zp_min, zp_max = -128 - lo / scale, 127 - hi / scale
        zp = zp_min if 128 + abs(lo / scale) < 127 + abs(hi / scale) else zp_max
        zp = -128 if zp <= -128 else 127 if zp >= 127 else round(zp)
        inv = np.float32(1.0) / np.float32(scale)
        q = np.clip(np.round(zp + x * inv), -128, 127)
        return ((q - zp) * np.float32(scale)).astype("float32")

    def kernel(name):
        k = w[name + ".kernel"]
        if k.dtype.name == "int8":
            k = k.astype("float32") * w[name + ".kernel.scale"].reshape(-1, *([1] * (k.ndim - 1)))
        return k

    def conv(x, name, size, dilation):
        k = kernel(name)  # [out, 1, size, in]
        if w[name + ".kernel"].dtype.name == "int8":
            # A dilated convolution runs as SPACE_TO_BATCH_ND: each of the `dilation` phases
            # (rows i with i % dilation == p) is its own batch row, quantised on its own.
            x = x.copy()
            for p in range(dilation):
                x[p::dilation] = quantised(x[p::dilation])
        pad = dilation * (size - 1) // 2
        xp = np.pad(x, ((pad, pad), (0, 0)))
        y = np.zeros((t, k.shape[0]), "float32")
        for j in range(size):
            y += xp[j * dilation : j * dilation + t] @ k[:, 0, j, :].T
        return np.maximum(y + w[name + ".bias"], 0)

    def dense(x, name, relu):
        if w[name + ".kernel"].dtype.name == "int8":
            x = np.stack([quantised(row) for row in np.atleast_2d(x)]).reshape(x.shape)
        y = x @ kernel(name).T + w[name + ".bias"]
        return np.maximum(y, 0) if relu else y

    def softmax(x):
        e = np.exp(x - x.max(axis=-1, keepdims=True))
        return e / e.sum(axis=-1, keepdims=True)

    x = conv(emb, "conv_1", 3, 1)
    x = x + conv(x, "conv_2", 5, 1)
    x = x + conv(x, "conv_3", 3, 3)
    s = dense(np.concatenate([x, emb], axis=1), "slot_hidden", True)
    s = s + conv(s, "slot_context", 5, 1)
    s = s + conv(s, "slot_span", 3, 2)
    slots = softmax(dense(s, "slots", False))
    pooled = np.concatenate(
        [(x * mask - (1 - mask) * 1e4).max(axis=0), (x * mask).sum(axis=0) / n,
         (emb * mask).sum(axis=0) / n]
    )
    intent = softmax(dense(dense(pooled, "intent_hidden", True), "intent", False))
    return intent, slots


def main(args: list[str]) -> int:
    import tensorflow as tf

    manifest = json.loads((MODEL_DIR / "ask-reader-manifest.json").read_text())
    model_path = MODEL_DIR / manifest["model_file"]
    sha = hashlib.sha256(model_path.read_bytes()).hexdigest()
    if sha != manifest["model_sha256"]:
        print("the bundled model does not match its manifest", file=sys.stderr)
        return 1
    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    w = _weights(interpreter)

    tensors, blobs, offset = [], [], 0
    for name, value in w.items():
        data = value.astype("<" + value.dtype.str[1:]).tobytes()
        tensors.append(
            {"name": name, "dtype": value.dtype.name, "shape": list(value.shape), "offset": offset}
        )
        data += b"\0" * (-len(data) % 4)
        blobs.append(data)
        offset += len(data)
    header = json.dumps(
        {
            "model_sha256": sha,
            "layers": [
                {"name": n, "kind": k, **({"size": s, "dilation": d} if k == "conv1d" else {})}
                for n, k, s, d in LAYERS
            ],
            "tensors": tensors,
        },
        separators=(",", ":"),
    ).encode()
    header += b" " * (-(8 + len(header)) % 4)
    out = Path(args[0])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(b"PCW1" + struct.pack("<I", len(header)) + header + b"".join(blobs))
    params = sum(v.size for k, v in w.items() if not k.endswith(".scale"))
    print(f"{params} parameters, {out.stat().st_size} bytes in {out}")

    if "--check" in args:
        import numpy as np

        inp = interpreter.get_input_details()[0]
        outputs = {len(d["shape"]): d["index"] for d in interpreter.get_output_details()}
        readings = json.loads(FIXTURE.read_text())["readings"]
        for hybrid in (False, True):
            worst = 0.0
            for r in readings:
                interpreter.set_tensor(inp["index"], np.array([r["input"]], dtype=np.int32))
                interpreter.invoke()
                ti = interpreter.get_tensor(outputs[2])[0]
                ts = interpreter.get_tensor(outputs[3])[0]
                di, ds = _forward(w, r["input"], hybrid=hybrid)
                n = len(r["slots"])  # the question's tokens, as the fixture holds
                worst = max(
                    worst, float(np.abs(ti - di).max()), float(np.abs(ts[:n] - ds[:n]).max())
                )
            print(f"hybrid={hybrid}: max |TFLite - NumPy| probability {worst:.2e}")
    return 0


if __name__ == "__main__":
    if not sys.argv[1:]:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
