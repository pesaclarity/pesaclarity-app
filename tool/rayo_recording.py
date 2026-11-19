"""What tool/*_decodes.py share: the app's rayo library, a session on it, and the file format.

Each recording tool runs a bundled model's weights on the rayo library `flutter test` runs (the
one rayo's build hook compiled for this computer from the commit pubspec.lock pins) and writes
its float32 outputs, keyed by the weights' SHA-256, that rayo commit and the platform. Run the
tools as scripts (`python tool/x_decodes.py`), so this file is on their path.
"""

from __future__ import annotations

import ctypes
import json
import os
import platform
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent


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


def app_session(weights: bytes):  # noqa: ANN201
    """A session on ``weights`` on the app's rayo library, with rayo's default options (one
    thread).

    rayo_convert's Session passes its own rayo_session_options, which has only `threads`; the
    app's rayo reads a longer struct (the cache and state options too) and refuses it as bad
    session options, so the session is created with rayo_session_create, which takes none."""
    from rayo_convert import runtime

    model = runtime.Model(runtime.Library(app_rayo()), weights)
    session = runtime.Session.__new__(runtime.Session)
    session.model = model
    session.L = model.lib.lib
    session.ptr = ctypes.c_void_p()
    msg = runtime._Message()  # noqa: SLF001
    if session.L.rayo_session_create(model.ptr, ctypes.byref(session.ptr), ctypes.byref(msg)):
        raise runtime.RayoError(msg.text.decode())
    return session


def margin_apart(row: Any, margin: float) -> bool:
    """Whether the two best of ``row`` are more than ``margin`` apart."""
    top = sorted(row, reverse=True)
    return top[0] - top[1] > margin


def float32s(values: Any) -> list[float]:
    """Each value as its float32's shortest repr, which reads back as the same float32."""
    import numpy as np

    return [float(str(np.float32(v))) for v in values]


def same_recording(old: dict[str, Any], weights_sha256: str) -> bool:
    """Whether ``old`` was recorded from these weights on this rayo commit and platform."""
    return (old.get("weights_sha256"), old.get("rayo"), old.get("abi")) == (
        weights_sha256,
        pinned_commit(),
        abi(),
    )


def write_recording(target: Path, head: dict[str, Any], readings: list[dict[str, Any]]) -> None:
    """``head`` (with weights_sha256, rayo and abi), then ``readings`` one per line, so a
    re-record shows as a readable diff."""
    target.parent.mkdir(parents=True, exist_ok=True)
    rows = ",\n".join("  " + json.dumps(r, separators=(",", ":")) for r in readings)
    text = json.dumps(head, indent=1)
    target.write_text(text[:-2] + ',\n "readings": [\n' + rows + "\n ]\n}\n")
