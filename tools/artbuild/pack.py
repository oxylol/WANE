"""Sprite sheets: cells, shelves, pages and PNG files (ADR-0023 Decision 1.3 and 1.5).

Layout is computed in u and is the same at every scale (pixels = u x scale). Each action has one
cell size (its largest posed bounds, rounded up to 4 u, plus 8 u on every side, so the S range never
reads a neighbour under linear filtering) and starts a new row of frames. A row wraps at the page
width; a page ends at the page height. Pages are at most 4096 px at 2x, so 2048 u.
"""

from __future__ import annotations

import io
import math
from dataclasses import dataclass

import numpy as np
from PIL import Image

from .channels import Cell

PAGE_MAX_U = 2048
PAD_U = 8
SNAP_U = 4


def action_cell(origin: tuple[float, float], boxes: list[tuple[float, float, float, float]]) -> Cell:
    """The cell for an action: the union of the frames' silhouette boxes, snapped outward to
    multiples of 4 u from the feet pivot, plus the padding."""
    x0 = min(b[0] for b in boxes)
    y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes)
    y1 = max(b[3] for b in boxes)
    ox, oy = origin
    cx0 = ox - SNAP_U * math.ceil((ox - x0) / SNAP_U) - PAD_U
    cy0 = oy - SNAP_U * math.ceil((oy - y0) / SNAP_U) - PAD_U
    cx1 = ox + SNAP_U * math.ceil((x1 - ox) / SNAP_U) + PAD_U
    cy1 = oy + SNAP_U * math.ceil((y1 - oy) / SNAP_U) + PAD_U
    w, h = round(cx1 - cx0), round(cy1 - cy0)
    return Cell(cx0, cy0, w, h)


@dataclass(frozen=True)
class Slot:
    page: int
    x: int  # u
    y: int  # u


def layout(cells: list[tuple[Cell, int]]) -> tuple[list[list[Slot]], list[tuple[int, int]]]:
    """Slots for each action's frames (cell, frame count) and each page's size in u."""
    slots: list[list[Slot]] = []
    sizes: list[tuple[int, int]] = [(0, 0)]
    page, y, row_y = 0, 0, 0
    for cell, n in cells:
        if cell.w > PAGE_MAX_U or cell.h > PAGE_MAX_U:
            raise ValueError(f"a {cell.w} x {cell.h} u cell does not fit a {PAGE_MAX_U} u page")
        per_row = PAGE_MAX_U // cell.w
        row: list[Slot] = []
        for k in range(n):
            if k % per_row == 0:  # an action, and each wrapped row of it, starts a new shelf
                if y + cell.h > PAGE_MAX_U:
                    page += 1
                    y = 0
                    sizes.append((0, 0))
                row_y = y
                y += cell.h
            x = (k % per_row) * cell.w
            row.append(Slot(page, x, row_y))
            pw, ph = sizes[page]
            sizes[page] = (max(pw, x + cell.w), max(ph, row_y + cell.h))
        slots.append(row)
    return slots, sizes


def blank_atlas(kind: str, w_px: int, h_px: int) -> np.ndarray:
    """A page filled with what lies far outside a silhouette (or a flat, glossless normal)."""
    a = np.zeros((h_px, w_px, 4), dtype=np.uint8)
    if kind == "shape":
        a[..., 0] = 255
        a[..., 1] = 255
    elif kind == "normal":
        a[..., 0] = 128
        a[..., 1] = 128
        a[..., 2] = 255
    return a


def png_bytes(arr: np.ndarray) -> bytes:
    """RGBA8 to PNG bytes: compression 9, no ancillary chunks, so equal pixels are equal bytes."""
    buf = io.BytesIO()
    Image.fromarray(arr, "RGBA").save(buf, format="PNG", compress_level=9)
    return buf.getvalue()


def page_suffix(page: int) -> str:
    return "" if page == 0 else f".p{page}"

