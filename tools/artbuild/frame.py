"""Bake one posed frame at every scale (ADR-0023 Decision 1.2 to 1.4)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from . import channels as ch
from . import geometry as geo
from . import shapes
from .palette import Palette
from .pose import Posed, posed_bounds
from .svg import PartLibrary


@dataclass
class FrameResult:
    arrays: dict[int, dict[str, np.ndarray]]  # scale -> shape, normal, parts (RGBA8, cell sized)
    meta: dict  # silhouette_box, part_boxes, emissive_regions, smear (all in u about the origin)


def _box(b: tuple[float, float, float, float], origin: tuple[float, float]) -> list[float]:
    return [
        round(b[0] - origin[0], 4),
        round(b[1] - origin[1], 4),
        round(b[2] - origin[0], 4),
        round(b[3] - origin[1], 4),
    ]


def _kind(tags: tuple[str, ...]) -> str:
    for kind in ("eye", "blade", "pogo"):
        if kind in tags:
            return kind
    return "ember"


def frame_meta(lib: PartLibrary, pal: Palette, posed: Posed, part_polys) -> dict:
    origin = lib.origin
    meta: dict = {
        "silhouette_box": _box(posed_bounds(posed), origin),
        "part_boxes": [],
        "emissive_regions": [],
        "smear": {k: bool(v) for k, v in sorted(posed.smear.items())},
    }
    for k, part in enumerate(lib.parts):
        if not part.tags:
            continue
        b = geo.bounds(part_polys[k])
        entry = {"part": part.id, "tags": list(part.tags), "box": _box(b, origin)}
        if part.id in posed.tips:
            tx, ty = posed.tips[part.id]
            entry["tip"] = [round(tx - origin[0], 4), round(ty - origin[1], 4)]
        meta["part_boxes"].append(entry)
        if "emissive" in part.tags:
            cx, cy = (b[0] + b[2]) * 0.5, (b[1] + b[3]) * 0.5
            pts = np.concatenate(part_polys[k])
            r = float(np.sqrt(((pts[:, 0] - cx) ** 2 + (pts[:, 1] - cy) ** 2).max()))
            mat = pal.material_of(part.id)
            meta["emissive_regions"].append(
                {
                    "part": part.id,
                    "centre": [round(cx - origin[0], 4), round(cy - origin[1], 4)],
                    "radius": round(r, 4),
                    "colour": str(mat.get("emissive", mat["lit"])).lower(),
                    "strength": float(mat.get("emissive_strength", 1.0)),
                    "kind": _kind(part.tags),
                }
            )
    return meta


def bake(
    lib: PartLibrary, pal: Palette, posed: Posed, cell: ch.Cell, scales: tuple[int, ...]
) -> FrameResult:
    geom = shapes.build(lib, posed)
    angles = [geo.second_moment_angle(p) for p in geom.part_polys]
    info = [
        ch.PartInfo(
            pal.slot_of_part(p.id),
            pal.gloss_of_part(p.id),
            bool(posed.smear.get(p.id, False)),
        )
        for p in lib.parts
    ]
    shape4, parts4, extra = ch.render_scale(lib, geom, info, angles, cell.grid(ch.MASTER_SCALE), True)
    nx, ny, nz, gloss, union, emis = extra
    arrays: dict[int, dict[str, np.ndarray]] = {}
    for s in sorted(scales):
        if s == ch.MASTER_SCALE:
            arrays[s] = {
                "shape": shape4,
                "normal": ch.encode_normal(nx, ny, nz, gloss),
                "parts": parts4,
            }
            continue
        shape, parts, _ = ch.render_scale(lib, geom, info, angles, cell.grid(s), False)
        f = ch.MASTER_SCALE // s
        shape[..., 3] = ch.q8(ch.box_reduce(emis, f) * 255.0)
        normal = ch.encode_normal(*ch.reduce_normal(nx, ny, nz, gloss, union.astype(np.float64), f))
        arrays[s] = {"shape": shape, "normal": normal, "parts": parts}
    return FrameResult(arrays, frame_meta(lib, pal, posed, geom.part_polys))
