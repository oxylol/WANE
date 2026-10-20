"""The shared noise texture (ADR-0023 Decision 1.7): tileable value noise from an integer hash.

256 x 256 RGBA8, no RNG state. The cell counts are part of the interface, because the shaders turn
a wavelength in u into texture coordinates with them:
- R paper grain: 128 and 64 cells (weights 0.6, 0.4);
- G brush:       32, 64 and 16 cells (0.5, 0.3, 0.2);
- B wobble octave 1: 16 cells;
- A wobble octave 2: 32 cells.
"""

from __future__ import annotations

import zlib

import numpy as np

SIZE = 256
BUILD_SEED = 23
CELLS = {
    "grain": (128, 64),
    "brush": (32, 64, 16),
    "wobble1": (16,),
    "wobble2": (32,),
}
MASK32 = np.uint64(0xFFFFFFFF)


def seed_for(asset_id: str, build_seed: int = BUILD_SEED) -> int:
    """crc32(asset id) xor the build seed: an asset's own stream for its generators."""
    return (zlib.crc32(asset_id.encode("utf-8")) ^ build_seed) & 0xFFFFFFFF


def _lattice(cells: int, salt: int, seed: int) -> np.ndarray:
    i = np.arange(cells, dtype=np.uint64)
    gx, gy = np.meshgrid(i, i)
    h = (gx * np.uint64(0x9E3779B1)) ^ (gy * np.uint64(0x85EBCA77)) ^ np.uint64(
        (seed * 2654435761 + salt * 40503) & 0xFFFFFFFF
    )
    h = ((h ^ (h >> np.uint64(15))) * np.uint64(0x2C1B3C6D)) & MASK32
    h = ((h ^ (h >> np.uint64(12))) * np.uint64(0x297A2D39)) & MASK32
    h = h ^ (h >> np.uint64(15))
    return (h & np.uint64(0xFFFF)).astype(np.float64) / 65535.0


def _octave(cells: int, salt: int, seed: int) -> np.ndarray:
    g = _lattice(cells, salt, seed)
    x = np.arange(SIZE) * cells / SIZE
    i0 = np.floor(x).astype(np.int64)
    f = x - i0
    f = f * f * (3.0 - 2.0 * f)
    i1 = (i0 + 1) % cells
    r0 = g[i0][:, i0] * (1.0 - f)[None, :] + g[i0][:, i1] * f[None, :]
    r1 = g[i1][:, i0] * (1.0 - f)[None, :] + g[i1][:, i1] * f[None, :]
    return r0 * (1.0 - f)[:, None] + r1 * f[:, None]


def texture(seed: int = BUILD_SEED) -> np.ndarray:
    weights = {"grain": (0.6, 0.4), "brush": (0.5, 0.3, 0.2), "wobble1": (1.0,), "wobble2": (1.0,)}
    salt = 1
    planes = []
    for name in ("grain", "brush", "wobble1", "wobble2"):
        acc = np.zeros((SIZE, SIZE))
        for cells, w in zip(CELLS[name], weights[name]):
            acc = acc + w * _octave(cells, salt, seed)
            salt += 1
        planes.append(acc)
    arr = np.stack(planes, axis=2)
    return np.clip(np.floor(arr * 255.0 + 0.5), 0, 255).astype(np.uint8)
