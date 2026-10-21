"""From a posed frame to the edge sets the channels are measured against (ADR-0023 Decision 1.2).

Every outline segment is cut where it crosses another piece's outline, so each cut piece lies
wholly inside or wholly outside every other piece, and a midpoint test classifies it exactly (the
spike cut at a fixed 0.25 u and mis-classified up to 0.125 u around each crossing). A piece is one
polygon of a part, in one of its sub-poses.
- silhouette edge: inside no other piece;
- visible edge: inside no piece of the same part and no piece of a part with higher `data-z`
  (the silhouette plus every interior overlap, such as an arm over the body);
- own edge: inside no other piece of the same part (the part's own outline, for its bevel).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from . import geometry as geo
from . import sdf
from .pose import Piece, Posed
from .svg import PartLibrary

TAPER_U = 2.5
INWARD_PROBE_U = 0.05
CUT_EPS = 1e-9


@dataclass
class Edges:
    """Cut segments with the part each belongs to (index into PartLibrary.parts)."""

    a: np.ndarray
    b: np.ndarray
    part: np.ndarray
    taper: np.ndarray  # visible edges only; zeros elsewhere
    # Where the edge's piece lies along its smear arc, 0 tail to 1 (1 off a smear). The bake's age
    # channel is per pixel (channels.sweep_ages), so the edges only carry it.
    age: np.ndarray


@dataclass
class Geometry:
    silhouette: Edges
    visible: Edges
    own: Edges
    part_polys: list[list[np.ndarray]]  # per part, all its polygons over all its pieces
    part_segments: list[tuple[np.ndarray, np.ndarray]]  # per part, its uncut outline segments

    def own_segments(self, k: int) -> tuple[np.ndarray, np.ndarray]:
        """Part k's own outline (cut, minus any inside another piece of the same part)."""
        sel = self.own.part == k
        return self.own.a[sel], self.own.b[sel]


def _bbox(a: np.ndarray, b: np.ndarray) -> tuple[float, float, float, float]:
    lo, hi = np.minimum(a, b).min(axis=0), np.maximum(a, b).max(axis=0)
    return float(lo[0]), float(lo[1]), float(hi[0]), float(hi[1])


def _overlap(p: tuple[float, ...], q: tuple[float, ...]) -> bool:
    return not (p[2] < q[0] or q[2] < p[0] or p[3] < q[1] or q[3] < p[1])


def _cuts(a, b, other_a, other_b, other_box) -> list[tuple[int, float]]:
    """(segment index, parameter) where segments a->b cross segments other_a->other_b."""
    lo, hi = np.minimum(a, b), np.maximum(a, b)
    sel = np.nonzero(
        (hi[:, 0] >= other_box[0])
        & (lo[:, 0] <= other_box[2])
        & (hi[:, 1] >= other_box[1])
        & (lo[:, 1] <= other_box[3])
    )[0]
    if len(sel) == 0:
        return []
    r = (b - a)[sel]
    s = other_b - other_a
    out: list[tuple[int, float]] = []
    for c0 in range(0, len(other_a), 512):
        oa, sv = other_a[c0 : c0 + 512], s[c0 : c0 + 512]
        qpx = oa[None, :, 0] - a[sel][:, None, 0]
        qpy = oa[None, :, 1] - a[sel][:, None, 1]
        denom = r[:, None, 0] * sv[None, :, 1] - r[:, None, 1] * sv[None, :, 0]
        with np.errstate(divide="ignore", invalid="ignore"):
            t = (qpx * sv[None, :, 1] - qpy * sv[None, :, 0]) / denom
            u = (qpx * r[:, None, 1] - qpy * r[:, None, 0]) / denom
        hit = (denom != 0) & (t > CUT_EPS) & (t < 1.0 - CUT_EPS) & (u >= 0.0) & (u <= 1.0)
        ii, _ = np.nonzero(hit)
        for i, tv in zip(ii.tolist(), t[hit].tolist()):
            out.append((int(sel[i]), tv))
    return out


def _cut_piece(a: np.ndarray, b: np.ndarray, cuts: list[tuple[int, float]]):
    """Sub-segment endpoints of a->b after cutting at the given (segment, t) pairs."""
    n = len(a)
    seg = np.concatenate([np.arange(n), np.arange(n), np.array([c[0] for c in cuts], dtype=np.int64)])
    t = np.concatenate([np.zeros(n), np.ones(n), np.array([c[1] for c in cuts], dtype=np.float64)])
    order = np.lexsort((t, seg))
    seg, t = seg[order], t[order]
    same = (seg[1:] == seg[:-1]) & (t[1:] > t[:-1] + CUT_EPS)
    i0 = np.nonzero(same)[0]
    s0, t0, t1 = seg[i0], t[i0], t[i0 + 1]
    d = b[s0] - a[s0]
    pa = np.where((t0 == 0.0)[:, None], a[s0], a[s0] + d * t0[:, None])
    pb = np.where((t1 == 1.0)[:, None], b[s0], a[s0] + d * t1[:, None])
    return pa, pb


def _ray_hits(m: np.ndarray, n: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Distance along n from each m to the first outline segment ahead (inf if none)."""
    best = np.full(len(m), np.inf)
    e = b - a
    for c0 in range(0, len(a), 256):
        ac, ec = a[c0 : c0 + 256], e[c0 : c0 + 256]
        qpx = ac[None, :, 0] - m[:, None, 0]
        qpy = ac[None, :, 1] - m[:, None, 1]
        denom = n[:, None, 0] * ec[None, :, 1] - n[:, None, 1] * ec[None, :, 0]
        with np.errstate(divide="ignore", invalid="ignore"):
            lam = (qpx * ec[None, :, 1] - qpy * ec[None, :, 0]) / denom
            u = (qpx * n[:, None, 1] - qpy * n[:, None, 0]) / denom
        ok = (denom != 0) & (lam > 1e-6) & (u >= 0.0) & (u <= 1.0)
        best = np.minimum(best, np.where(ok, lam, np.inf).min(axis=1))
    return best


def build(lib: PartLibrary, posed: Posed) -> Geometry:
    # Each polygon of each piece classifies on its own, so a part's overlapping subpaths (a drip
    # drawn over its candle) and a smear's sub-poses are unions with no interior edges.
    pieces = [Piece(p.part, [poly], p.age) for p in posed.pieces for poly in p.polys]
    segs = [geo.segments(p.polys) for p in pieces]
    boxes = [_bbox(a, b) for a, b in segs]
    # 1. Cut every piece's outline where it crosses another piece's outline.
    cut_a: list[np.ndarray] = []
    cut_b: list[np.ndarray] = []
    for k, (a, b) in enumerate(segs):
        cuts: list[tuple[int, float]] = []
        for j, (oa, ob) in enumerate(segs):
            if j != k and _overlap(boxes[k], boxes[j]):
                cuts.extend(_cuts(a, b, oa, ob, boxes[j]))
        pa, pb = _cut_piece(a, b, cuts)
        cut_a.append(pa)
        cut_b.append(pb)
    # 2. Classify each cut segment by its midpoint against every other piece.
    n_parts = len(lib.parts)
    sil, vis, own = ([], [], [])
    for k, piece in enumerate(pieces):
        pa, pb = cut_a[k], cut_b[k]
        mid = (pa + pb) * 0.5
        other = np.zeros(len(mid), dtype=bool)
        same = np.zeros(len(mid), dtype=bool)
        front = np.zeros(len(mid), dtype=bool)
        for j, q in enumerate(pieces):
            if j == k or not _overlap(boxes[k], boxes[j]):
                continue
            hit = sdf.inside_points(mid, *segs[j])
            other |= hit
            if q.part == piece.part:
                same |= hit
            elif lib.parts[q.part].z > lib.parts[piece.part].z:
                front |= hit
        for lst, keep in ((sil, ~other), (vis, ~same & ~front), (own, ~same)):
            n_keep = int(keep.sum())
            lst.append(
                (pa[keep], pb[keep], np.full(n_keep, piece.part, dtype=np.int64), np.full(n_keep, piece.age))
            )
    part_polys: list[list[np.ndarray]] = [[] for _ in range(n_parts)]
    for piece in pieces:
        part_polys[piece.part].extend(piece.polys)
    part_segments = [geo.segments(p) for p in part_polys]

    def pack(rows, taper=None) -> Edges:
        a = np.concatenate([r[0] for r in rows]) if rows else np.zeros((0, 2))
        b = np.concatenate([r[1] for r in rows]) if rows else np.zeros((0, 2))
        part = np.concatenate([r[2] for r in rows]) if rows else np.zeros(0, dtype=np.int64)
        age = np.concatenate([r[3] for r in rows]) if rows else np.zeros(0)
        return Edges(a, b, part, taper if taper is not None else np.zeros(len(a)), age)

    visible = pack(vis)
    own_edges = pack(own)
    visible.taper = _tapers(visible, part_segments, own_edges)
    return Geometry(pack(sil), visible, own_edges, part_polys, part_segments)


def _tapers(edges: Edges, part_segments, own: Edges) -> np.ndarray:
    """Pressure taper per visible edge: half the part's thickness across the edge, over TAPER_U.

    The thickness is found by casting a ray inward from the edge's midpoint to the part's own
    outline (the spike walked 24 steps; this is exact), where "own outline" leaves out the outlines
    of a smear's sub-poses that lie inside its union. Thin at blade tips and fingers, 1 on a body.
    A smear's pixels carry their age along the arc in this channel instead, per pixel and not per
    edge (channels.sweep_ages): an edge's age gave the half of the fan nearest the tail edge age 0.
    """
    taper = np.ones(len(edges.a))
    for k, (pa, pb) in enumerate(part_segments):
        sel = np.nonzero(edges.part == k)[0]
        if len(sel) == 0:
            continue
        a, b = edges.a[sel], edges.b[sel]
        oa, ob = own.a[own.part == k], own.b[own.part == k]
        mid = (a + b) * 0.5
        e = b - a
        length = np.maximum(np.sqrt(e[:, 0] * e[:, 0] + e[:, 1] * e[:, 1]), 1e-12)
        n = np.stack([e[:, 1], -e[:, 0]], axis=1) / length[:, None]
        probe = mid + n * INWARD_PROBE_U
        flip = ~sdf.inside_points(probe, pa, pb)
        n[flip] *= -1.0
        hit = _ray_hits(mid, n, oa, ob)
        taper[sel] = np.clip(hit * 0.5 / TAPER_U, 0.0, 1.0)
    return taper
