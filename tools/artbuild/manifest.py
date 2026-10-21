"""MANIFEST.json: the SHA-256 of every built file (ADR-0023 Decision 1.8).

A PNG is hashed by what it shows (its mode, size and decoded pixel bytes), not by the bytes of the
file: those depend on the deflate implementation Pillow was built against, and a contributor on
another zlib would see a mismatch of nothing. So that "what it shows" is all there is, `same` also
requires the file to hold the chunk types the build writes (IHDR, IDAT, IEND) and nothing after
IEND: a text chunk added by hand carries data the pixels do not. Everything else is hashed as it is.
"""

from __future__ import annotations

import hashlib
import io
import json
import struct
from pathlib import Path

from PIL import Image

from . import TOOL_VERSION

NAME = "MANIFEST.json"
# Godot writes these beside the imported files; they are not build output.
IMPORT_SUFFIX = ".import"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_CHUNKS = frozenset({b"IHDR", b"IDAT", b"IEND"})


class ManifestError(ValueError):
    """A MANIFEST.json that cannot be read, or a PNG whose structure cannot be."""


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def digest(rel: str, data: bytes) -> str:
    """The manifest's hash of a built file: of the pixels for a PNG, of the bytes otherwise."""
    if rel.endswith(".png"):
        with Image.open(io.BytesIO(data)) as im:
            im.load()
            return sha256(f"{im.mode}|{im.width}x{im.height}|".encode() + im.tobytes())
    return sha256(data)


def png_chunk_types(data: bytes) -> list[bytes]:
    """The chunk types of a PNG in file order, with b"<trailing>" for bytes after IEND. Raises
    ManifestError for a file that is not a PNG or whose chunks run off its end."""
    if not data.startswith(PNG_SIGNATURE):
        raise ManifestError("not a PNG")
    types: list[bytes] = []
    pos = len(PNG_SIGNATURE)
    while pos < len(data):
        if pos + 12 > len(data):
            raise ManifestError("a chunk header runs off the end of the file")
        (size,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        pos += 12 + size
        if pos > len(data):
            raise ManifestError("a chunk runs off the end of the file")
        types.append(kind)
        if kind == b"IEND":
            if pos < len(data):
                types.append(b"<trailing>")
            break
    return types


def same(rel: str, a: bytes, b: bytes) -> bool:
    """Whether two renderings of the file `rel` are the same build output. Never raises: a file
    that cannot be read is not the same as one that can."""
    if a == b:
        return True
    if not rel.endswith(".png"):
        return False
    try:
        kinds_a, kinds_b = set(png_chunk_types(a)), set(png_chunk_types(b))
        return kinds_a == kinds_b and kinds_a <= PNG_CHUNKS and digest(rel, a) == digest(rel, b)
    except (ManifestError, OSError, SyntaxError, ValueError, struct.error):
        return False


def render(files: dict[str, str]) -> bytes:
    doc = {"version": 1, "tool": TOOL_VERSION, "files": dict(sorted(files.items()))}
    return (json.dumps(doc, indent=1) + "\n").encode()


def load(path: Path) -> dict[str, str]:
    """The manifest's {file: hash} (empty if there is no manifest). Raises ManifestError for one
    that is not a manifest."""
    if not path.exists():
        return {}
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        raise ManifestError(f"{NAME} is not valid JSON ({e})") from e
    files = doc.get("files") if isinstance(doc, dict) else None
    if not isinstance(files, dict) or not all(isinstance(v, str) for v in files.values()):
        raise ManifestError(f'{NAME} is not valid: it needs a "files" object of hashes')
    return dict(files)


def files_under(root: Path) -> list[str]:
    """Every file below root, as a sorted path relative to it with forward slashes."""
    if not root.is_dir():
        return []
    return sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file())
