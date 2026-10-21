"""Poses: what a frame looks like before it is baked (ADR-0023 Decision 1.2).

The animator (Phase 2 task 2) will emit this JSON from its `.pose.tres` files; until then it is the
test format (`pose.json` beside `parts.svg`):

    {"version": 1,
     "actions": {
       "<action>": {"fps": 24, "loop": true,
         "frames": [{"key": true, "ticks": 3,
                     "parts": {"<part id>": [a, b, c, d, e, f]},
                     "smear": {"<part id>": [[a, b, c, d, e, f], ...]}}]}}}

`parts` holds the per-part affine of the frame, in asset coordinates (SVG matrix order; a part
that is not named stays in its source pose). `smear` holds the part's earlier sub-frame poses along
its arc; the part's drawn shape is the union of those and its pose in `parts`, and the frame's
`smear` flag for the part is true. Between two poses of an arc the baker adds poses (a polar
decomposition about the part's pivot: the rotation angle, the stretch and the pivot's position are
interpolated) until no vertex moves more than SMEAR_STEP_U between neighbours, so a few keys sweep
a continuous ribbon and not a fan of copies. Actions keep the order of the file. A source without a pose file
is one action, `idle`, of one frame.

The reader is strict, because frame timing is the animation spec (CLAUDE.md rule 5): an unknown key
(`tiks`) is an error and not a default, `key` and `loop` are booleans, `fps` (1 to 60) and `ticks` (1 or
more) are integers, an affine is six finite numbers whose determinant is not 0, and the file may hold
no NaN, no Infinity and no key twice (strict_json).
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from . import geometry as geo
from . import strict_json
from .svg import PartLibrary

DEFAULT_FPS = 24
DEFAULT_TICKS = 3
FPS_RANGE = (1, 60)
# An affine entry is in u (a scale, a sine, a translation): this is the far side of any page.
MAX_AFFINE = 1.0e5
POSE_KEYS = frozenset({"version", "actions"})
ACTION_KEYS = frozenset({"fps", "loop", "frames"})
FRAME_KEYS = frozenset({"key", "ticks", "parts", "smear"})
SMEAR_STEP_U = 0.5  # the farthest any vertex may jump between two sub-poses of a smear
SMEAR_MAX_STEPS = 64


class PoseError(ValueError):
    pass


@dataclass
class FrameSpec:
    key: bool
    ticks: int
    parts: dict[str, geo.Affine] = field(default_factory=dict)
    smear: dict[str, list[geo.Affine]] = field(default_factory=dict)


@dataclass
class ActionSpec:
    name: str
    fps: int
    loop: bool
    frames: list[FrameSpec]


@dataclass
class Piece:
    """One drawn outline set of a part: the part itself, or one of its smear sub-poses."""

    part: int  # index into PartLibrary.parts
    polys: list[np.ndarray]
    # Where the piece lies along its part's smear arc: 0 at the tail, 1 at the part's own pose (and
    # for every part that does not smear). It becomes the taper channel of a smear's edges.
    age: float = 1.0


@dataclass
class Posed:
    pieces: list[Piece]
    smear: dict[str, bool]  # part id -> smeared on this frame, for every smear-tagged part
    # part id -> the vertex of the part's main pose (not its smear) farthest from its posed pivot,
    # for every blade-tagged part: the blade tip the review draws its arc through
    tips: dict[str, tuple[float, float]] = field(default_factory=dict)


def _affine(v, where: str) -> geo.Affine:
    if (
        not isinstance(v, list)
        or len(v) != 6
        or not all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v)
    ):
        raise PoseError(f"{where}: an affine is six numbers [a, b, c, d, e, f]")
    if not all(math.isfinite(x) and abs(x) <= MAX_AFFINE for x in v):
        raise PoseError(f"{where}: an affine holds finite numbers of at most {MAX_AFFINE:g}")
    m = (float(v[0]), float(v[1]), float(v[2]), float(v[3]), float(v[4]), float(v[5]))
    if geo.determinant(m) == 0.0:
        raise PoseError(f"{where}: the affine collapses the part to a line or a point (determinant 0)")
    return m


def _object(v, what: str, where: str) -> dict:
    if not isinstance(v, dict):
        raise PoseError(f"{where}: {what} must be an object")
    return v


def _known(d: dict, allowed: frozenset[str], where: str) -> None:
    """A key nothing reads is a typo that would silently build with the default (`tiks`)."""
    for key in d:
        if key not in allowed:
            raise PoseError(f"{where}: unknown key {key!r} (known: {', '.join(sorted(allowed))})")


def _flag(d: dict, key: str, default: bool, where: str) -> bool:
    v = d.get(key, default)
    if not isinstance(v, bool):
        raise PoseError(f"{where}: {key} must be true or false")
    return v


def default_actions() -> list[ActionSpec]:
    return [ActionSpec("idle", DEFAULT_FPS, True, [FrameSpec(True, DEFAULT_TICKS)])]


def load(path: Path | None, lib: PartLibrary) -> list[ActionSpec]:
    if path is None or not path.exists():
        return default_actions()
    doc = strict_json.loads(path.read_text(encoding="utf-8"), PoseError, path.name)
    return parse(doc, lib, path.name)


def parse(doc: dict, lib: PartLibrary, name: str = "pose.json") -> list[ActionSpec]:
    _object(doc, "the document", name)
    _known(doc, POSE_KEYS, name)
    if doc.get("version") != 1:
        raise PoseError(f"{name}: version must be 1")
    ids = {p.id for p in lib.parts}
    actions = []
    acts = doc.get("actions")
    if not isinstance(acts, dict) or not acts:
        raise PoseError(f"{name}: needs a non-empty actions object")
    for aname, a in acts.items():
        where = f"{name}: action {aname!r}"
        if not re.fullmatch(r"[a-z][a-z0-9_]*", aname):
            raise PoseError(f"{where}: names are lower-case letters, digits and underscores")
        _object(a, "an action", where)
        _known(a, ACTION_KEYS, where)
        fps = a.get("fps", DEFAULT_FPS)
        if isinstance(fps, bool) or not isinstance(fps, int) or not FPS_RANGE[0] <= fps <= FPS_RANGE[1]:
            raise PoseError(f"{where}: fps must be an integer {FPS_RANGE[0]} to {FPS_RANGE[1]}")
        loop = _flag(a, "loop", True, where)
        frames = []
        raw_frames = a.get("frames")
        if not isinstance(raw_frames, list) or not raw_frames:
            raise PoseError(f"{where}: needs frames")
        for k, fr in enumerate(raw_frames):
            fwhere = f"{where} frame {k}"
            _object(fr, "a frame", fwhere)
            _known(fr, FRAME_KEYS, fwhere)
            ticks = fr.get("ticks", DEFAULT_TICKS)
            if isinstance(ticks, bool) or not isinstance(ticks, int) or ticks < 1:
                raise PoseError(f"{fwhere}: ticks must be an integer of at least 1")
            parts = {}
            for pid, m in _object(fr.get("parts", {}), "parts", fwhere).items():
                if pid not in ids:
                    raise PoseError(f"{fwhere}: no part {pid!r}")
                parts[pid] = _affine(m, f"{fwhere} part {pid}")
            smear = {}
            for pid, arc in _object(fr.get("smear", {}), "smear", fwhere).items():
                if pid not in ids:
                    raise PoseError(f"{fwhere}: no part {pid!r} to smear")
                if not isinstance(arc, list) or not arc:
                    raise PoseError(f"{fwhere}: smear {pid!r} wants a list of affines")
                smear[pid] = [_affine(m, f"{fwhere} smear {pid}") for m in arc]
            frames.append(FrameSpec(_flag(fr, "key", False, fwhere), ticks, parts, smear))
        actions.append(ActionSpec(aname, fps, loop, frames))
    return actions


def _polar(m: geo.Affine) -> tuple[float, float, float, float]:
    """The linear part of m as a rotation angle and a symmetric stretch (p00, p01, p11)."""
    a, b, c, d = m[0], m[1], m[2], m[3]  # columns (a, b) and (c, d)
    theta = math.atan2(b - c, a + d)
    co, si = math.cos(theta), math.sin(theta)
    # P = R^T A
    p00 = co * a + si * b
    p01 = co * c + si * d
    p10 = -si * a + co * b
    p11 = -si * c + co * d
    return theta, p00, 0.5 * (p01 + p10), p11


def _between(m0: geo.Affine, m1: geo.Affine, t: float, pivot: tuple[float, float]) -> geo.Affine:
    th0, a0, b0, d0 = _polar(m0)
    th1, a1, b1, d1 = _polar(m1)
    dth = (th1 - th0 + math.pi) % (2 * math.pi) - math.pi
    th = th0 + t * dth
    co, si = math.cos(th), math.sin(th)
    pa, pb, pd = a0 + t * (a1 - a0), b0 + t * (b1 - b0), d0 + t * (d1 - d0)
    a, b = co * pa + -si * pb, si * pa + co * pb
    c, d = co * pb + -si * pd, si * pb + co * pd
    q = np.array([pivot])
    g0, g1 = geo.apply(m0, q)[0], geo.apply(m1, q)[0]
    gx, gy = g0[0] + t * (g1[0] - g0[0]), g0[1] + t * (g1[1] - g0[1])
    return (a, b, c, d, float(gx - (a * pivot[0] + c * pivot[1])), float(gy - (b * pivot[0] + d * pivot[1])))


def _max_jump(m0: geo.Affine, m1: geo.Affine, n: int, pts: np.ndarray, pivot) -> float:
    prev = geo.apply(m0, pts)
    worst = 0.0
    for k in range(1, n + 1):
        cur = geo.apply(m1 if k == n else _between(m0, m1, k / n, pivot), pts)
        worst = max(worst, float(np.sqrt(((cur - prev) ** 2).sum(axis=1).max())))
        prev = cur
    return worst


def sweep(arc: list[geo.Affine], pts: np.ndarray, pivot: tuple[float, float]) -> list[geo.Affine]:
    """The arc's poses with poses added between neighbours until no point of `pts` jumps more than
    SMEAR_STEP_U from one pose to the next (measured on the swept poses, not on their chord)."""
    out = [arc[0]]
    for m0, m1 in zip(arc, arc[1:]):
        n = 1
        while n < SMEAR_MAX_STEPS:
            jump = _max_jump(m0, m1, n, pts, pivot)
            if jump <= SMEAR_STEP_U:
                break
            n = min(SMEAR_MAX_STEPS, max(n + 1, math.ceil(n * jump / SMEAR_STEP_U)))
        out.extend(_between(m0, m1, k / n, pivot) for k in range(1, n))
        out.append(m1)
    return out


def pose_frame(lib: PartLibrary, spec: FrameSpec) -> Posed:
    pieces: list[Piece] = []
    smear_flags: dict[str, bool] = {}
    tips: dict[str, tuple[float, float]] = {}
    for k, part in enumerate(lib.parts):
        main = spec.parts.get(part.id, geo.IDENTITY)
        arcs = [*spec.smear.get(part.id, []), main]
        if len(arcs) > 1:
            arcs = sweep(arcs, np.concatenate(part.polys), part.pivot)
        for i, m in enumerate(arcs):
            age = i / (len(arcs) - 1) if len(arcs) > 1 else 1.0
            try:
                polys = [geo.clean(geo.apply(m, p)) for p in part.polys]
            except ValueError as e:  # a pose so small that every vertex lands on one point
                raise PoseError(f"part {part.id!r}: its pose collapses it to a point ({e})") from e
            pieces.append(Piece(k, polys, age))
        if "smear" in part.tags:
            smear_flags[part.id] = part.id in spec.smear
        if "blade" in part.tags:
            pts = np.concatenate([geo.apply(main, p) for p in part.polys])
            pv = geo.apply(main, np.array([part.pivot], dtype=np.float64))[0]
            far = ((pts[:, 0] - pv[0]) ** 2 + (pts[:, 1] - pv[1]) ** 2).argmax()
            tips[part.id] = (float(pts[far, 0]), float(pts[far, 1]))
    return Posed(pieces, smear_flags, tips)


def posed_bounds(posed: Posed) -> tuple[float, float, float, float]:
    return geo.bounds([p for piece in posed.pieces for p in piece.polys])
