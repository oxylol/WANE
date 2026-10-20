"""MANIFEST.json: the SHA-256 of every built file (ADR-0023 Decision 1.8)."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from . import TOOL_VERSION

NAME = "MANIFEST.json"
# Godot writes these beside the imported files; they are not build output.
IGNORED_SUFFIXES = (".import", ".uid")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def render(files: dict[str, str]) -> bytes:
    doc = {"version": 1, "tool": TOOL_VERSION, "files": dict(sorted(files.items()))}
    return (json.dumps(doc, indent=1) + "\n").encode()


def load(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return dict(json.loads(path.read_text(encoding="utf-8")).get("files", {}))


def strays(root: Path, directory: str, known: set[str]) -> list[str]:
    """Files in root/directory that are not in the manifest and are not Godot's own."""
    base = root / directory
    out = []
    if base.is_dir():
        for p in sorted(base.rglob("*")):
            rel = p.relative_to(root).as_posix()
            if p.is_file() and rel not in known and not rel.endswith(IGNORED_SUFFIXES):
                out.append(rel)
    return out
