"""The channels of the three textures, and their decode constants (ADR-0023 Decision 1.3 and 1.4).

The shaders decode with the constants in the block below, which tests compare against
`shaders/ink/ink_common.gdshaderinc`. Keep each constant on its own line as `NAME = number`.

shape  (linear)  R S, G U, B side, A emissive
normal (linear)  R nx, G ny (y down), B nz, A gloss
parts  (nearest) R palette slot, G brush angle, B taper, A flags
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from . import sdf
from .shapes import Geometry
from .svg import PartLibrary

# --- decode constants (shader twin) -------------------------------------------------------------
S_ZERO = 128  # shape.R = S_ZERO + S_STEPS_PER_U * S, S the signed silhouette distance in u
S_STEPS_PER_U = 16
U_STEPS_PER_U = 16  # shape.G = U_STEPS_PER_U * U, U the distance to the nearest visible edge
ANGLE_BYTE_MAX = 255  # parts.G = ANGLE_BYTE_MAX * angle / pi
NORMAL_BYTE_MAX = 255  # normal.RGB = NORMAL_BYTE_MAX * (0.5 + 0.5 n)
FLAG_POGO = 1
FLAG_BLADE = 2
FLAG_EYE = 4
FLAG_SMEAR = 8
FLAG_WAX = 16
PALETTE_COLUMNS = 16
PALETTE_ROWS_PER_VARIANT = 4
# ------------------------------------------------------------------------------------------------

S_BAND_U = 8.5  # S is searched this far from a silhouette edge, U this far from a visible one
U_BAND_U = 16.5
MASTER_SCALE = 4
SCALES = (1, 2, 4)
TAG_FLAGS = {"pogo": FLAG_POGO, "blade": FLAG_BLADE, "eye": FLAG_EYE, "wax": FLAG_WAX}
PROFILE_STEPS = 1024


@dataclass(frozen=True)
class PartInfo:
    """What the channels need to know about a part beyond its outline."""

    slot: int
    gloss: float
    smeared: bool


@dataclass(frozen=True)
class Cell:
    """The window of asset space one frame is baked into (multiples of 4 u, so every scale is whole)."""

    x0: float
    y0: float
    w: int
    h: int

    def grid(self, scale: int) -> sdf.Grid:
        return sdf.Grid(self.x0, self.y0, self.w * scale, self.h * scale, scale)


def q8(v: np.ndarray) -> np.ndarray:
    return np.clip(np.floor(v + 0.5), 0, 255).astype(np.uint8)


def _profile_tables(tilt_deg: float):
    """sin and cos of the tilt at x in [0, 1] (x = 1 - depth/bevel), by libm, for np.interp."""
    xs = [k / PROFILE_STEPS for k in range(PROFILE_STEPS + 1)]
    sin = np.array([math.sin(math.radians(tilt_deg) * x) for x in xs])
    cos = np.array([math.cos(math.radians(tilt_deg) * x) for x in xs])
    return np.array(xs), sin, cos


def _tilt(profile: str, tilt_deg: float, t: np.ndarray):
    """sin and cos of the normal's tilt from the viewer axis at relative depth t (0 edge, 1 deep)."""
    if profile == "flat":
        return np.zeros_like(t), np.ones_like(t)
    if profile == "crease":  # a chamfer: full tilt across the whole bevel band, a fold at its end
        full = (t < 1.0).astype(np.float64)
        return (
            full * math.sin(math.radians(tilt_deg)),
            1.0 - full + full * math.cos(math.radians(tilt_deg)),
        )
    xs, sin, cos = _profile_tables(tilt_deg)  # bulge: the angle falls linearly to flat
    x = 1.0 - t
    return np.interp(x, xs, sin), np.interp(x, xs, cos)


def render_scale(
    lib: PartLibrary,
    geom: Geometry,
    info: list[PartInfo],
    angles: list[float],
    grid: sdf.Grid,
    master: bool,
):
    """The shape, parts and (at the master scale) normal channels for one grid.

    Returns (shape, parts, extra): shape and parts are (ny, nx, 4) uint8. `extra` is None, except at
    the master scale, where it is the float planes the reductions start from: normal x, y, z,
    gloss, silhouette coverage and emissive coverage. The shape's emissive channel is filled in
    here only at the master scale; the other scales average the master's (see frame.bake).
    """
    n = grid.nx * grid.ny
    # Which parts cover each pixel centre; the top part is the highest z among them.
    ins = np.zeros((len(lib.parts), n), dtype=bool)
    for k, polys_seg in enumerate(geom.part_segments):
        ins[k] = sdf.inside_grid(*polys_seg, grid).ravel()
    top = np.full(n, -1, dtype=np.int64)
    for k in range(len(lib.parts)):
        top = np.where(ins[k], k, top)
    union = top >= 0
    # S: signed distance to the silhouette, outward positive.
    d_sil, _, _ = sdf.nearest_banded(grid, geom.silhouette.a, geom.silhouette.b, S_BAND_U)
    s_field = np.where(union, -d_sil, d_sil)
    # U, side: distance to the nearest visible edge; side is 255 inside the part that owns it.
    d_vis, k_vis, _ = sdf.nearest_banded(grid, geom.visible.a, geom.visible.b, U_BAND_U)
    found = k_vis >= 0
    owner = np.where(found, geom.visible.part[np.maximum(k_vis, 0)], 0)
    side = found & ins[owner, np.arange(n)]
    taper = np.where(found, geom.visible.taper[np.maximum(k_vis, 0)], 0.0)
    emis = np.zeros(n)
    slot = np.zeros(n)
    angle = np.zeros(n)
    flags = np.zeros(n)
    gloss = np.zeros(n)
    nx = np.zeros(n)
    ny = np.zeros(n)
    nz = np.ones(n)
    for k, part in enumerate(lib.parts):
        sel = top == k
        if not sel.any():
            continue
        slot[sel] = info[k].slot
        angle[sel] = angles[k]
        f = 0
        for tag in part.tags:
            f |= TAG_FLAGS.get(tag, 0)
        if info[k].smeared:
            f |= FLAG_SMEAR
        flags[sel] = f
        gloss[sel] = info[k].gloss
    extra = None
    if master:
        emissive = np.zeros(n)
        for k, part in enumerate(lib.parts):
            sel = top == k
            wants_emissive = "emissive" in part.tags
            if not sel.any() and not wants_emissive:
                continue
            ea, eb = geom.own_segments(k)
            band = max(part.bevel_u, 1.0)
            msk = sel.reshape(grid.ny, grid.nx)
            if wants_emissive:
                # The AA ring just outside the part counts too: evaluate within half a texel.
                msk = msk | _dilate(ins[k].reshape(grid.ny, grid.nx))
            d, idx, v = sdf.nearest_banded(grid, ea, eb, band, mask=msk)
            if wants_emissive:
                inside_k = ins[k]
                sgn_d = np.where(inside_k, d, -d)
                cov = np.clip(sgn_d * grid.s + 0.5, 0.0, 1.0)
                visible = (top == k) | (top < k)
                emissive = np.where(msk.ravel() & visible, np.maximum(emissive, cov), emissive)
            sel_idx = np.nonzero(sel)[0]
            depth = d[sel_idx]
            vec = v[sel_idx]
            safe = np.maximum(depth, 1e-9)
            g = -vec / safe[:, None]
            g[depth < 1e-9] = 0.0
            t = np.clip(depth / part.bevel_u, 0.0, 1.0)
            sin_t, cos_t = _tilt(part.normal, part.tilt_deg, t)
            nx[sel_idx] = g[:, 0] * sin_t
            ny[sel_idx] = g[:, 1] * sin_t
            nz[sel_idx] = cos_t
        emis = emissive
        extra = (
            nx.reshape(grid.ny, grid.nx),
            ny.reshape(grid.ny, grid.nx),
            nz.reshape(grid.ny, grid.nx),
            gloss.reshape(grid.ny, grid.nx),
            union.reshape(grid.ny, grid.nx),
            emis.reshape(grid.ny, grid.nx),
        )
    shape = np.stack(
        [
            q8(S_ZERO + s_field * S_STEPS_PER_U),
            q8(d_vis * U_STEPS_PER_U),
            q8(side * 255.0),
            q8(emis * 255.0),
        ],
        axis=1,
    ).reshape(grid.ny, grid.nx, 4)
    parts_tex = np.stack(
        [
            q8(slot),
            np.mod(q8(angle * (ANGLE_BYTE_MAX / math.pi)), ANGLE_BYTE_MAX),  # pi is 0
            q8(taper * 255.0),
            q8(flags),
        ],
        axis=1,
    ).reshape(grid.ny, grid.nx, 4)
    return shape, parts_tex, extra


def _dilate(m: np.ndarray) -> np.ndarray:
    """m grown by one pixel (4-neighbourhood), for the AA ring of an emissive part."""
    out = m.copy()
    out[1:, :] |= m[:-1, :]
    out[:-1, :] |= m[1:, :]
    out[:, 1:] |= m[:, :-1]
    out[:, :-1] |= m[:, 1:]
    return out


# --- reductions from the 4x master (Decision 1.4) ------------------------------------------------


def mitchell(x: np.ndarray) -> np.ndarray:
    """Mitchell-Netravali with B = C = 1/3, support 2."""
    b = c = 1.0 / 3.0
    x = np.abs(x)
    near = ((12 - 9 * b - 6 * c) * x**3 + (-18 + 12 * b + 6 * c) * x**2 + (6 - 2 * b)) / 6.0
    far = (
        (-b - 6 * c) * x**3 + (6 * b + 30 * c) * x**2 + (-12 * b - 48 * c) * x + (8 * b + 24 * c)
    ) / 6.0
    return np.where(x < 1, near, np.where(x < 2, far, 0.0))


def _kernel_taps(f: int):
    """Offsets and normalised weights of the separable reduction by integer factor f.

    Output pixel i covers input pixels f*i .. f*i + f - 1, so its centre sits at input index
    f*i + (f - 1)/2; a tap at f*i + t has weight mitchell((t - (f - 1)/2)/f).
    """
    centre = (f - 1) / 2.0
    taps = [t for t in range(-3 * f, 3 * f) if abs((t - centre) / f) < 2.0]
    w = mitchell(np.array([(t - centre) / f for t in taps]))
    return taps, w / math.fsum(w.tolist())


def _convolve_reduce(plane: np.ndarray, f: int) -> np.ndarray:
    """Separable Mitchell reduction of a 2-D plane by integer f with edge replication."""
    taps, w = _kernel_taps(f)
    pad = 3 * f
    ny, nx = plane.shape
    p = np.pad(plane, pad, mode="edge")
    out_x = np.zeros((p.shape[0], nx // f))
    for t, wt in zip(taps, w):
        out_x = out_x + wt * p[:, pad + t : pad + t + nx : f][:, : nx // f]
    out = np.zeros((ny // f, nx // f))
    for t, wt in zip(taps, w):
        out = out + wt * out_x[pad + t : pad + t + ny : f, :][: ny // f]
    return out


def box_reduce(plane: np.ndarray, f: int) -> np.ndarray:
    ny, nx = plane.shape
    out = np.zeros((ny // f, nx // f))
    for dy in range(f):
        for dx in range(f):
            out = out + plane[dy::f, dx::f]
    return out / (f * f)


def reduce_normal(nx, ny, nz, gloss, cov, f: int):
    """Normal and gloss planes reduced by Mitchell weighted by coverage, then renormalised."""
    w = _convolve_reduce(cov.astype(np.float64), f)
    ok = w > 1e-6
    safe = np.where(ok, w, 1.0)
    rx = _convolve_reduce(nx * cov, f) / safe
    ry = _convolve_reduce(ny * cov, f) / safe
    rz = _convolve_reduce(nz * cov, f) / safe
    rg = _convolve_reduce(gloss * cov, f) / safe
    length = np.sqrt(rx * rx + ry * ry + rz * rz)
    good = ok & (length > 1e-9)
    inv = np.where(good, 1.0 / np.where(good, length, 1.0), 0.0)
    rx, ry = np.where(good, rx * inv, 0.0), np.where(good, ry * inv, 0.0)
    rz = np.where(good, rz * inv, 1.0)
    return rx, ry, rz, np.where(good, np.clip(rg, 0.0, 1.0), 0.0)


def encode_normal(nx, ny, nz, gloss) -> np.ndarray:
    return np.stack(
        [
            q8((0.5 + 0.5 * nx) * NORMAL_BYTE_MAX),
            q8((0.5 + 0.5 * ny) * NORMAL_BYTE_MAX),
            q8((0.5 + 0.5 * nz) * NORMAL_BYTE_MAX),
            q8(gloss * 255.0),
        ],
        axis=-1,
    )
