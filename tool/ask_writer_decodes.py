#!/usr/bin/env python3
"""Decode Ask's writer requests with the bundled ask-writer.tflite on this computer.

The app's tests cannot run TFLite on the host, so test/features/ask/ask_writer_test.dart
replays decodes recorded here with the real model, through the app's own checks. Decoding is
the app's decodeReply (lib/src/domain/ask/model_reply_writer.dart) step for step: the same
masking, the same xorshift32 draws and the same sampling at the manifest's temperature.

  1. ASK_WRITER_RECORD=build/ask-writer-requests.json flutter test test/features/ask/ask_writer_test.dart
  2. uv run --project ../pesaclarity-ml python tool/ask_writer_decodes.py \\
       build/ask-writer-requests.json test/fixtures/ask/ask_writer_decodes.json
  3. flutter test test/features/ask/ask_writer_test.dart

Requests already in the output file are kept. It also times each reply with two threads,
the app's setting, as a rough guide to a phone: the timings go into the output file.
Synthetic data only: the requests are fact tokens, never names or amounts.
"""

from __future__ import annotations

import hashlib
import json
import math
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "assets" / "models" / "ask"


class WriterRandom:
    """The app's WriterRandom: xorshift32 from a 64-bit seed."""

    def __init__(self, seed: int) -> None:
        s = (seed ^ 0x9E3779B9) & 0xFFFFFFFF
        self.state = s if s != 0 else 1

    def next(self) -> float:
        x = self.state
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        self.state = x
        return x / 4294967296.0


def decode(logits_at, r: dict) -> list[int] | None:
    """The app's decodeReply."""
    length, vocab, eos = r["length"], r["vocab_size"], r["eos"]
    prefix = r["prefix"]
    if len(prefix) >= length:
        return None
    tokens = [0] * length
    tokens[: len(prefix)] = prefix
    n = len(prefix)
    rng = WriterRandom(r["seed"])
    banned, once, needed = set(r["banned"]), set(r["once"]), set(r["needed"])
    mask, temperature = r["mask"], r["temperature"]
    out: list[int] = []
    while n < length and len(out) <= r["max_reply"]:
        row = logits_at(tokens, n - 1)
        if len(row) != vocab:
            raise ValueError(f"expected {vocab} logits, got {len(row)}")
        has_needed = all(t in out for t in needed)
        weights = []
        best = -math.inf
        for i in range(vocab):
            masked = mask and (
                i in banned or (i in once and i in out) or (i == eos and not has_needed)
            )
            value = float(row[i])
            v = -math.inf if masked or not math.isfinite(value) else value / temperature
            weights.append(v)
            best = max(best, v)
        if best == -math.inf:
            return None
        total = 0.0
        for i in range(vocab):
            w = 0.0 if weights[i] == -math.inf else math.exp(weights[i] - best)
            weights[i] = w
            total += w
        pick = rng.next() * total
        nxt = -1
        for i in range(vocab):
            if weights[i] <= 0:
                continue
            nxt = i
            pick -= weights[i]
            if pick <= 0:
                break
        if nxt == eos:
            return out
        out.append(nxt)
        tokens[n] = nxt
        n += 1
    return None


def key(r: dict) -> str:
    return ",".join(map(str, r["prefix"])) + "|" + str(r["seed"])


def main(requests_path: str, out_path: str) -> int:
    import numpy as np
    import tensorflow as tf

    manifest = json.loads((MODEL_DIR / "ask-writer-manifest.json").read_text())
    model_path = MODEL_DIR / manifest["model_file"]
    blob = model_path.read_bytes()
    if hashlib.sha256(blob).hexdigest() != manifest["model_sha256"]:
        print("the bundled model does not match its manifest", file=sys.stderr)
        return 1
    interpreter = tf.lite.Interpreter(model_path=str(model_path), num_threads=2)
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]["index"]
    out = interpreter.get_output_details()[0]["index"]
    steps = [0]

    def logits_at(tokens: list[int], position: int) -> np.ndarray:
        interpreter.set_tensor(inp, np.array([tokens], dtype=np.int32))
        interpreter.invoke()
        steps[0] += 1
        return interpreter.get_tensor(out)[0, position]

    requests = json.loads(Path(requests_path).read_text())
    target = Path(out_path)
    old = json.loads(target.read_text()) if target.exists() else {}
    if old.get("model_sha256") != manifest["model_sha256"]:
        old = {}
    decodes = {key(d): d for d in old.get("decodes", [])}

    times, step_times = [], []
    for r in requests:
        steps[0] = 0
        start = time.perf_counter()
        ids = decode(logits_at, r)
        ms = (time.perf_counter() - start) * 1000
        times.append(ms)
        step_times.append(ms / max(steps[0], 1))
        decodes[key(r)] = {"prefix": r["prefix"], "seed": r["seed"], "ids": ids}

    result = {
        "model_sha256": manifest["model_sha256"],
        "note": "Real ask-writer decodes of the app's requests, recorded on a computer by "
        "tool/ask_writer_decodes.py. Fact tokens and token ids only.",
        "host_timing": {
            "threads": 2,
            "replies": len(times),
            "median_ms_per_reply": round(statistics.median(times), 1) if times else None,
            "max_ms_per_reply": round(max(times), 1) if times else None,
            "median_ms_per_step": round(statistics.median(step_times), 2) if times else None,
        }
        if times
        else old.get("host_timing"),
        "decodes": sorted(decodes.values(), key=key),
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    # One decode per line, so a re-record shows as a readable diff.
    head = json.dumps({k: v for k, v in result.items() if k != "decodes"}, indent=1)
    rows = ",\n".join("  " + json.dumps(d, separators=(",", ":")) for d in result["decodes"])
    target.write_text(head[:-2] + ',\n "decodes": [\n' + rows + "\n ]\n}\n")
    print(f"{len(requests)} decoded, {len(decodes)} recorded in {target}")
    print(json.dumps(result["host_timing"]))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
