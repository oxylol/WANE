"""Exact distances and winding on a pixel grid (ADR-0023 Decision 1.2).

All four queries are exact in float64 and use only +, -, *, /, sqrt and comparisons, so the result
does not depend on the CPU:
- `inside_grid`: nonzero winding at every pixel centre by scanline accumulation (a crossing per
  segment per pixel row, a cumulative sum along the row), replacing the spike's per-pixel test;
- `inside_points`: nonzero winding at arbitrary points (segment midpoints and probes), half-open on
  the outline (a point on it is in or out by which side it lies on, so it is no test of the outline);
- `near_outline`: which points lie on the outline, to a tolerance (a piece's edge along another's);
- `nearest_banded`: the exact nearest segment, searched per 16 x 16 px tile among only the
  segments within the band of that tile (identical to brute force inside the band).

A grid is (x0, y0, nx, ny, s): pixel (i, j) has its centre at (x0 + (j + 0.5)/s, y0 + (i + 0.5)/s)
in u, s pixels per u.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

TILE_PX = 16


@dataclass(frozen=True)
class Grid:
    x0: float
    y0: float
    nx: int
    ny: int
    s: int

    def points(self) -> np.ndarray:
        """Pixel centres, row-major, as an (ny*nx, 2) array in u."""
        xs = self.x0 + (np.arange(self.nx) + 0.5) / self.s
        ys = self.y0 + (np.arange(self.ny) + 0.5) / self.s
        gx, gy = np.meshgrid(xs, ys)
        return np.stack([gx.ravel(), gy.ravel()], axis=1)


def inside_grid(a: np.ndarray, b: np.ndarray, grid: Grid) -> np.ndarray:
    """Boolean (ny, nx): nonzero winding of the closed polygons (segments a->b) at pixel centres.

    A segment crosses the row centre y when min(ay, by) <= y < max(ay, by) (half-open, so a vertex
    on a row centre counts once). The crossing adds its direction to the first pixel whose centre
    lies to its right; a cumulative sum along the row is then the winding to the left of each
    pixel, which is the winding number up to the sign of the total (zero stays zero).
    """
    s = grid.s
    ay, by = a[:, 1], b[:, 1]
    keep = ay != by
    a, b = a[keep], b[keep]
    ay, by = a[:, 1], b[:, 1]
    ymin, ymax = np.minimum(ay, by), np.maximum(ay, by)
    i_lo = np.ceil((ymin - grid.y0) * s - 0.5).astype(np.int64) - 1
    i_hi = np.ceil((ymax - grid.y0) * s - 0.5).astype(np.int64) + 1
    i_lo = np.clip(i_lo, 0, grid.ny)
    i_hi = np.clip(i_hi, 0, grid.ny)
    counts = np.maximum(i_hi - i_lo, 0)
    total = int(counts.sum())
    acc = np.zeros(grid.ny * grid.nx, dtype=np.float64)
    if total:
        seg = np.repeat(np.arange(len(a)), counts)
        first = np.cumsum(counts) - counts
        rows = np.arange(total) - np.repeat(first, counts) + np.repeat(i_lo, counts)
        yc = grid.y0 + (rows + 0.5) / s
        sa, sb = a[seg], b[seg]
        hit = (np.minimum(sa[:, 1], sb[:, 1]) <= yc) & (yc < np.maximum(sa[:, 1], sb[:, 1]))
        seg, rows, yc, sa, sb = seg[hit], rows[hit], yc[hit], sa[hit], sb[hit]
        x = sa[:, 0] + (yc - sa[:, 1]) * (sb[:, 0] - sa[:, 0]) / (sb[:, 1] - sa[:, 1])
        w = np.where(sb[:, 1] > sa[:, 1], 1.0, -1.0)
        col = np.floor((x - grid.x0) * s - 0.5).astype(np.int64) + 1
        col = np.maximum(col, 0)
        ok = col < grid.nx
        acc = np.bincount(
            rows[ok] * grid.nx + col[ok], weights=w[ok], minlength=grid.ny * grid.nx
        )
    wind = np.cumsum(acc.reshape(grid.ny, grid.nx), axis=1)
    return wind != 0.0


def inside_points(points: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Nonzero winding of each point (N x 2) against closed polygons given as segments a->b."""
    out = np.zeros(len(points), dtype=bool)
    if len(points) == 0 or len(a) == 0:
        return out
    lo = np.minimum(a, b).min(axis=0)
    hi = np.maximum(a, b).max(axis=0)
    cand = np.nonzero(
        (points[:, 0] >= lo[0]) & (points[:, 0] <= hi[0]) & (points[:, 1] >= lo[1]) & (points[:, 1] <= hi[1])
    )[0]
    if len(cand) == 0:
        return out
    ay, by = a[:, 1], b[:, 1]
    keep = ay != by
    ax, ay, bx, by = a[keep, 0], ay[keep], b[keep, 0], by[keep]
    px_all, py_all = points[cand, 0], points[cand, 1]
    wind = np.zeros(len(cand), dtype=np.int64)
    for s in range(0, len(ax), 256):
        sax, say, sbx, sby = ax[s : s + 256], ay[s : s + 256], bx[s : s + 256], by[s : s + 256]
        px, py = px_all[:, None], py_all[:, None]
        cross = (sbx - sax) * (py - say) - (px - sax) * (sby - say)
        up = (say <= py) & (sby > py) & (cross > 0)
        down = (say > py) & (sby <= py) & (cross < 0)
        wind += up.sum(axis=1) - down.sum(axis=1)
    out[cand] = wind != 0
    return out


def near_outline(points: np.ndarray, a: np.ndarray, b: np.ndarray, tol: float) -> np.ndarray:
    """Which points (N x 2) lie within `tol` of some segment a->b: on the outline, to rounding.

    `inside_points` is half-open (a point on a left or top edge counts as inside, one on a right or
    bottom edge as outside), so it cannot tell a point on the outline from one just off it. This
    can; the build uses it to find where one piece's edge lies along another's.
    """
    out = np.zeros(len(points), dtype=bool)
    if len(points) == 0 or len(a) == 0:
        return out
    lo = np.minimum(a, b).min(axis=0) - tol
    hi = np.maximum(a, b).max(axis=0) + tol
    cand = np.nonzero(
        (points[:, 0] >= lo[0]) & (points[:, 0] <= hi[0]) & (points[:, 1] >= lo[1]) & (points[:, 1] <= hi[1])
    )[0]
    if len(cand) == 0:
        return out
    px, py = points[cand, 0][:, None], points[cand, 1][:, None]
    near = np.zeros(len(cand), dtype=bool)
    for s in range(0, len(a), 256):
        sa, sb = a[s : s + 256], b[s : s + 256]
        ex, ey = (sb[:, 0] - sa[:, 0])[None, :], (sb[:, 1] - sa[:, 1])[None, :]
        l2 = np.maximum(ex * ex + ey * ey, 1e-18)
        dx, dy = px - sa[None, :, 0], py - sa[None, :, 1]
        t = np.clip((dx * ex + dy * ey) / l2, 0.0, 1.0)
        vx, vy = dx - t * ex, dy - t * ey
        near |= ((vx * vx + vy * vy) <= tol * tol).any(axis=1)
    out[cand] = near
    return out


def nearest(points: np.ndarray, a: np.ndarray, b: np.ndarray):
    """Distance from each point to the nearest segment, that segment's index and the vector from
    the nearest point on it to the point. Ties go to the lowest index."""
    n = len(points)
    best = np.full(n, np.inf)
    idx = np.zeros(n, dtype=np.int64)
    vec = np.zeros((n, 2))
    rng = np.arange(n)
    for s in range(0, len(a), 128):
        aa, bb = a[s : s + 128], b[s : s + 128]
        ab = bb - aa
        l2 = np.maximum(ab[:, 0] * ab[:, 0] + ab[:, 1] * ab[:, 1], 1e-18)
        dx = points[:, None, 0] - aa[None, :, 0]
        dy = points[:, None, 1] - aa[None, :, 1]
        t = np.clip((dx * ab[None, :, 0] + dy * ab[None, :, 1]) / l2[None, :], 0.0, 1.0)
        vx = dx - t * ab[None, :, 0]
        vy = dy - t * ab[None, :, 1]
        d2 = vx * vx + vy * vy
        k = np.argmin(d2, axis=1)
        dk = np.sqrt(d2[rng, k])
        better = dk < best
        best = np.where(better, dk, best)
        idx = np.where(better, k + s, idx)
        vec[better, 0] = vx[rng, k][better]
        vec[better, 1] = vy[rng, k][better]
    return best, idx, vec


def _could_be_nearest(tile_points: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Which segments can be the nearest one for some point of the tile.

    If the tile's centre is d from its nearest segment and the tile's half diagonal is r, every
    point of the tile has a segment within d + r, so a segment farther than d + 2r from the centre
    is farther than that from every point. Exact: it only drops segments that cannot win, and
    keeps ties, so the lowest-index tie-break is unchanged.
    """
    lo, hi = tile_points.min(axis=0), tile_points.max(axis=0)
    c = (lo + hi) * 0.5
    r = float(np.hypot(*(hi - lo))) * 0.5
    ab = b - a
    l2 = np.maximum(ab[:, 0] * ab[:, 0] + ab[:, 1] * ab[:, 1], 1e-18)
    t = np.clip(((c[0] - a[:, 0]) * ab[:, 0] + (c[1] - a[:, 1]) * ab[:, 1]) / l2, 0.0, 1.0)
    vx = c[0] - (a[:, 0] + t * ab[:, 0])
    vy = c[1] - (a[:, 1] + t * ab[:, 1])
    d = np.sqrt(vx * vx + vy * vy)
    return d <= d.min() + 2.0 * r + 1e-9


def nearest_banded(
    grid: Grid,
    a: np.ndarray,
    b: np.ndarray,
    band: float,
    mask: np.ndarray | None = None,
):
    """`nearest` at every pixel centre of the grid, but only against segments within `band` of
    each 16 x 16 px tile; a pixel with none within `band` gets distance `band` and index -1.

    With `mask` (ny, nx) only the masked pixels are evaluated (others get `band` and -1).
    Returns flat arrays of ny*nx: distance, segment index, vector to the point.
    """
    n = grid.nx * grid.ny
    best = np.full(n, band)
    idx = np.full(n, -1, dtype=np.int64)
    vec = np.zeros((n, 2))
    if len(a) == 0:
        return best, idx, vec
    lo, hi = np.minimum(a, b), np.maximum(a, b)
    pts = grid.points().reshape(grid.ny, grid.nx, 2)
    flat = np.arange(n).reshape(grid.ny, grid.nx)
    for ty in range(0, grid.ny, TILE_PX):
        for tx in range(0, grid.nx, TILE_PX):
            sel_px = flat[ty : ty + TILE_PX, tx : tx + TILE_PX]
            tp = pts[ty : ty + TILE_PX, tx : tx + TILE_PX]
            if mask is not None:
                m = mask[ty : ty + TILE_PX, tx : tx + TILE_PX]
                if not m.any():
                    continue
                sel_px, tp = sel_px[m], tp[m]
            else:
                sel_px, tp = sel_px.ravel(), tp.reshape(-1, 2)
            tmin, tmax = tp.min(axis=0) - band, tp.max(axis=0) + band
            sel = np.nonzero(np.all(hi >= tmin, axis=1) & np.all(lo <= tmax, axis=1))[0]
            if len(sel) == 0:
                continue
            if len(sel) > 8:
                sel = sel[_could_be_nearest(tp, a[sel], b[sel])]
            d, k, v = nearest(tp, a[sel], b[sel])
            ok = d < band
            rows = sel_px[ok]
            best[rows] = d[ok]
            idx[rows] = sel[k[ok]]
            vec[rows] = v[ok]
    return best, idx, vec
