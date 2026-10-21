"""The channels of the three textures, and their decode constants (ADR-0023 Decision 1.3 and 1.4).

The shaders decode with the constants in the block below, which tests compare against
`shaders/ink/ink_common.gdshaderinc`. Keep each constant on its own line as `NAME = number`.

shape  (linear)  R S, G U, B side, A emissive
normal (linear)  R nx, G ny (y down), B nz, A gloss
parts  (nearest) R palette slot, G brush angle, B taper (a smear: its age along the arc), A flags

A smear's age is per pixel: where along its arc the part last covered the pixel, 0 at the tail and 1
at the part's own pose, interpolated between the arc's sub-poses (`sweep_ages`). Its flag, age, slot
and angle also reach SMEAR_FRINGE_U past its silhouette, where the shader's anti-aliasing still
draws (`_smear_fringe`).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from . import geometry as geo
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
# How far past a smear's silhouette its parts texels reach: the shader's anti-aliasing (0.75 of a
# pixel of U) plus the line's wobble (0.32 u) at 1x, with room to spare.
SMEAR_FRINGE_U = 1.5


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
    sweeps: dict[int, list[tuple[float, list[np.ndarray]]]] | None = None,
):
    """The shape, parts and (at the master scale) normal channels for one grid.

    `sweeps` maps a smeared part's index to its pieces in arc order, (age, polygons) each: its
    pixels' taper channel is then their age along the arc (`sweep_ages`), and its parts texels
    reach over its anti-aliased fringe.

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
    for k, pieces in (sweeps or {}).items():
        sel = top == k
        if sel.any():
            taper[sel] = sweep_ages(grid, pieces, sel)[sel]
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
    if sweeps:
        _smear_fringe(parts_tex, (top < 0).reshape(grid.ny, grid.nx), grid.s)
    return shape, parts_tex, extra


def sweep_ages(
    grid: sdf.Grid, pieces: list[tuple[float, list[np.ndarray]]], want: np.ndarray
) -> np.ndarray:
    """A smear's age at each wanted pixel (flat mask): where along its arc the part last covered it.

    The pieces are the part's poses along the arc in order, (age, polygons) each, the last its own
    pose (age 1). A pixel the last piece covers has age 1; one last covered by piece i lies between
    that piece's outline and the next's, and its age is interpolated between theirs by its distance
    to each (the boundary sweeping over it from one pose to the next), so the age rises smoothly
    along the arc from 0 at the tail. Elsewhere the result is 1.
    """
    n = grid.nx * grid.ny
    out = np.ones(n)
    idx = np.nonzero(want)[0]
    if len(idx) == 0 or not pieces:
        return out
    segs = [geo.segments(polys) for _, polys in pieces]
    last = np.full(len(idx), -1, dtype=np.int64)
    for i, (a, b) in enumerate(segs):
        covered = sdf.inside_grid(a, b, grid).ravel()[idx]
        last = np.where(covered, i, last)
    pts = grid.points()[idx]
    ages = np.ones(len(idx))
    for i in range(len(pieces) - 1):
        sel = np.nonzero(last == i)[0]
        if len(sel) == 0:
            continue
        d_in, _, _ = sdf.nearest(pts[sel], *segs[i])
        d_out, _, _ = sdf.nearest(pts[sel], *segs[i + 1])
        frac = d_in / np.maximum(d_in + d_out, 1e-12)
        a0, a1 = pieces[i][0], pieces[i + 1][0]
        ages[sel] = a0 + frac * (a1 - a0)
    out[idx] = np.clip(ages, 0.0, 1.0)
    return out


def _smear_fringe(parts_tex: np.ndarray, empty: np.ndarray, scale: int) -> None:
    """Copy a smear's parts texels (slot, angle, age, flags) onto the empty pixels within
    SMEAR_FRINGE_U of it, nearest first, in place: the anti-aliased fringe just outside a silhouette
    is drawn by the shader, which reads the flag and the age there (nearest sampling), so without
    them the fringe of a faint tail drew as opaque ink."""
    smear = (parts_tex[..., 3] & FLAG_SMEAR) > 0
    todo = empty & ~smear
    for _ in range(math.ceil(SMEAR_FRINGE_U * scale)):
        grown = np.zeros_like(smear)
        src = np.zeros_like(parts_tex)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            shifted = np.zeros_like(smear)
            moved = np.zeros_like(parts_tex)
            ys = slice(max(dy, 0), smear.shape[0] + min(dy, 0))
            yd = slice(max(-dy, 0), smear.shape[0] + min(-dy, 0))
            xs = slice(max(dx, 0), smear.shape[1] + min(dx, 0))
            xd = slice(max(-dx, 0), smear.shape[1] + min(-dx, 0))
            shifted[yd, xd] = smear[ys, xs]
            moved[yd, xd] = parts_tex[ys, xs]
            take = shifted & todo & ~grown
            src[take] = moved[take]
            grown |= take
        if not grown.any():
            return
        parts_tex[grown] = src[grown]
        smear |= grown
        todo &= ~grown


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
