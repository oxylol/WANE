"""The SVG part-library subset and its lint (ADR-0023 Decision 1.1).

A source is `parts.svg`: path (M L H V C Q Z), circle, ellipse, rect and polygon elements, grouped
by `g` with a transform. One user unit is one world unit (u). Each leaf element is one part:
`id` (the name), `data-z` (draw order, unique), `data-pivot` ("x y", the rig's), `data-tags`,
`data-bevel-u`, `data-tilt-deg` and `data-normal` (flat, bulge, crease). Fills, strokes,
gradients, styles and everything else are rejected: colour comes from the palette, line and grain
from the shaders (CLAUDE.md: never paint a line or a texture into a source).

The root takes `data-origin-u="x y"`, the feet pivot (default: bottom centre of the viewBox).
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from . import geometry as geo

SVG_NS = "http://www.w3.org/2000/svg"
TAGS = ("emissive", "blade", "eye", "pogo", "wax", "smear")
NORMAL_PROFILES = ("bulge", "flat", "crease")
# A part's normal rises from the rim over this many u: deep enough that a part of a Wick's size
# is rounded through, so the light has a form to find (docs/adr/0025). A flat tile or a thin
# blade says its own bevel.
DEFAULT_BEVEL_U = 8.0
MAX_BEVEL_U = 16.0
DEFAULT_TILT_DEG = 62.0
SHAPES = ("path", "circle", "ellipse", "rect", "polygon")
CONTAINERS = ("svg", "g")
DOCUMENTATION = ("title", "desc")
LEAF_ATTRS = {
    "path": {"d"},
    "circle": {"cx", "cy", "r"},
    "ellipse": {"cx", "cy", "rx", "ry"},
    "rect": {"x", "y", "width", "height"},
    "polygon": {"points"},
}
COMMON_ATTRS = {
    "id",
    "transform",
    "data-z",
    "data-pivot",
    "data-tags",
    "data-bevel-u",
    "data-tilt-deg",
    "data-normal",
}


class SvgError(ValueError):
    """A lint failure; the message names the file and the element."""


@dataclass
class Part:
    """One part in asset coordinates (the element's own and its groups' transforms applied)."""

    id: str
    z: int
    tags: tuple[str, ...]
    pivot: tuple[float, float]
    bevel_u: float
    tilt_deg: float
    normal: str
    polys: list[np.ndarray] = field(default_factory=list)


@dataclass
class PartLibrary:
    parts: list[Part]  # sorted by z, ascending (back to front)
    origin: tuple[float, float]
    viewbox: tuple[float, float, float, float]

    def index(self, part_id: str) -> int:
        for k, p in enumerate(self.parts):
            if p.id == part_id:
                return k
        raise KeyError(part_id)


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def _floats(text: str, count: int, what: str, where: str) -> list[float]:
    v = [float(x) for x in re.findall(geo.NUM, text)]
    if len(v) != count:
        raise SvgError(f"{where}: {what} wants {count} numbers, got {len(v)}")
    return v


def _num(attrs: dict[str, str], key: str, where: str) -> float:
    if key not in attrs:
        raise SvgError(f"{where}: missing {key}")
    try:
        v = float(attrs[key])
    except ValueError as e:
        raise SvgError(f"{where}: {key} is not a number") from e
    if v != v or v in (float("inf"), float("-inf")):
        raise SvgError(f"{where}: {key} is not finite")
    return v


def parse(text: str, name: str = "parts.svg") -> PartLibrary:
    try:
        root = ET.fromstring(text)
    except ET.ParseError as e:
        raise SvgError(f"{name}: not well-formed XML ({e})") from e
    if _local(root.tag) != "svg":
        raise SvgError(f"{name}: root element must be svg")
    vb = root.attrib.get("viewBox")
    if vb is None:
        raise SvgError(f"{name}: svg needs a viewBox (one user unit is one world unit)")
    viewbox = tuple(_floats(vb, 4, "viewBox", name))
    for key in root.attrib:
        if key not in ("viewBox", "width", "height", "data-origin-u") and not key.startswith(
            ("xmlns", "{http://www.w3.org/2000/xmlns/}")
        ):
            raise SvgError(f"{name}: svg attribute {key!r} is not allowed")
    if "data-origin-u" in root.attrib:
        ox, oy = _floats(root.attrib["data-origin-u"], 2, "data-origin-u", name)
    else:
        ox, oy = viewbox[0] + viewbox[2] * 0.5, viewbox[1] + viewbox[3]
    parts: list[Part] = []
    _walk(root, geo.IDENTITY, parts, name, True)
    if not parts:
        raise SvgError(f"{name}: no parts")
    ids = [p.id for p in parts]
    for k, i in enumerate(ids):
        if i in ids[:k]:
            raise SvgError(f"{name}: duplicate part id {i!r}")
    zs = [p.z for p in parts]
    for k, z in enumerate(zs):
        if z in zs[:k]:
            raise SvgError(f"{name}: data-z {z} is used by two parts (draw order must be unique)")
    parts.sort(key=lambda p: p.z)
    return PartLibrary(parts=parts, origin=(ox, oy), viewbox=viewbox)  # type: ignore[arg-type]


def parse_file(path: Path) -> PartLibrary:
    return parse(path.read_text(encoding="utf-8"), path.name)


def _walk(el: ET.Element, xf: geo.Affine, out: list[Part], name: str, is_root: bool) -> None:
    for child in el:
        tag = _local(child.tag)
        where = f"{name}: <{tag}{' id=' + repr(child.attrib['id']) if 'id' in child.attrib else ''}>"
        if tag in DOCUMENTATION:
            continue
        if tag == "g":
            for key in child.attrib:
                if key not in ("id", "transform"):
                    raise SvgError(f"{where}: group attribute {key!r} is not allowed (only id, transform)")
            t = geo.parse_transform(child.attrib["transform"]) if "transform" in child.attrib else geo.IDENTITY
            _walk(child, geo.multiply(xf, t), out, name, False)
            continue
        if tag not in SHAPES:
            raise SvgError(
                f"{where}: element not allowed in a part library "
                f"(use {', '.join(SHAPES)}; gradients, text, images, styles and use are rejected)"
            )
        out.append(_leaf(child, tag, xf, where))


def _leaf(el: ET.Element, tag: str, xf: geo.Affine, where: str) -> Part:
    attrs = {_local(k): v for k, v in el.attrib.items()}
    allowed = LEAF_ATTRS[tag] | COMMON_ATTRS
    for key in attrs:
        if key not in allowed:
            hint = ""
            if key in ("fill", "stroke", "style", "class", "opacity", "fill-opacity", "filter", "mask"):
                hint = " (colour comes from palette.tres, line and grain from the shaders)"
            raise SvgError(f"{where}: attribute {key!r} is not allowed{hint}")
    if len(el) > 0:
        raise SvgError(f"{where}: a part has no children")
    if "id" not in attrs or not re.fullmatch(r"[a-z][a-z0-9_]*", attrs["id"]):
        raise SvgError(f"{where}: needs an id of lower-case letters, digits and underscores")
    if "data-z" not in attrs:
        raise SvgError(f"{where}: needs data-z (draw order)")
    try:
        z = int(attrs["data-z"])
    except ValueError as e:
        raise SvgError(f"{where}: data-z must be an integer") from e
    tags = tuple(sorted(set(attrs.get("data-tags", "").split())))
    for t in tags:
        if t not in TAGS:
            raise SvgError(f"{where}: unknown tag {t!r} (allowed: {', '.join(TAGS)})")
    bevel = float(attrs.get("data-bevel-u", DEFAULT_BEVEL_U))
    tilt = float(attrs.get("data-tilt-deg", DEFAULT_TILT_DEG))
    if not 0.25 <= bevel <= MAX_BEVEL_U:
        raise SvgError(f"{where}: data-bevel-u must be 0.25 to {MAX_BEVEL_U:g} (the normal band)")
    if not 0.0 <= tilt <= 89.0:
        raise SvgError(f"{where}: data-tilt-deg must be 0 to 89")
    profile = attrs.get("data-normal", "bulge")
    if profile not in NORMAL_PROFILES:
        raise SvgError(f"{where}: data-normal must be one of {', '.join(NORMAL_PROFILES)}")
    try:
        if tag == "path":
            raw = geo.parse_path(attrs["d"] if "d" in attrs else "")
        elif tag == "circle":
            r = _num(attrs, "r", where)
            if r <= 0:
                raise SvgError(f"{where}: r must be positive")
            raw = [geo.ellipse_poly(_num(attrs, "cx", where), _num(attrs, "cy", where), r, r)]
        elif tag == "ellipse":
            rx, ry = _num(attrs, "rx", where), _num(attrs, "ry", where)
            if rx <= 0 or ry <= 0:
                raise SvgError(f"{where}: rx and ry must be positive")
            raw = [geo.ellipse_poly(_num(attrs, "cx", where), _num(attrs, "cy", where), rx, ry)]
        elif tag == "rect":
            x, y = _num(attrs, "x", where), _num(attrs, "y", where)
            w, h = _num(attrs, "width", where), _num(attrs, "height", where)
            if w <= 0 or h <= 0:
                raise SvgError(f"{where}: width and height must be positive")
            raw = [[(x, y), (x + w, y), (x + w, y + h), (x, y + h)]]
        else:
            nums = [float(v) for v in re.findall(geo.NUM, attrs.get("points", ""))]
            if len(nums) < 6 or len(nums) % 2:
                raise SvgError(f"{where}: points wants x,y pairs, at least three")
            raw = [list(zip(nums[0::2], nums[1::2]))]
    except SvgError:
        raise
    except ValueError as e:
        raise SvgError(f"{where}: {e}") from e
    if "transform" in attrs:
        try:
            xf = geo.multiply(xf, geo.parse_transform(attrs["transform"]))
        except ValueError as e:
            raise SvgError(f"{where}: {e}") from e
    polys: list[np.ndarray] = []
    for p in raw:
        try:
            polys.append(geo.clean(geo.apply(xf, np.array(p, dtype=np.float64))))
        except ValueError as e:
            raise SvgError(f"{where}: {e}") from e
    if not polys:
        raise SvgError(f"{where}: no geometry")
    if "data-pivot" in attrs:
        px, py = _floats(attrs["data-pivot"], 2, "data-pivot", where)
        pivot = geo.apply(xf, np.array([[px, py]]))[0]
        pivot_t = (float(pivot[0]), float(pivot[1]))
    else:
        x0, y0, x1, y1 = geo.bounds(polys)
        pivot_t = ((x0 + x1) * 0.5, (y0 + y1) * 0.5)
    return Part(
        id=attrs["id"],
        z=z,
        tags=tags,
        pivot=pivot_t,
        bevel_u=bevel,
        tilt_deg=tilt,
        normal=profile,
        polys=polys,
    )
