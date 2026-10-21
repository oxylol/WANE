"""Affines, curve flattening and polygon helpers (ADR-0023 Decision 1.2).

An affine is the tuple (a, b, c, d, e, f) of SVG's matrix(): x' = a x + c y + e, y' = b x + d y + f.
Curves flatten to FLAT_TOL_U (0.01 u) by a deviation bound, not by a fixed step. Trigonometry uses
Python's math (libm), never numpy's SIMD sin and cos, whose last bit varies between CPUs.
"""

from __future__ import annotations

import math
import re

import numpy as np

FLAT_TOL_U = 0.01
IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
NUM = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"

Affine = tuple[float, float, float, float, float, float]


def multiply(m: Affine, n: Affine) -> Affine:
    """The affine that applies n first, then m."""
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (
        a * a2 + c * b2,
        b * a2 + d * b2,
        a * c2 + c * d2,
        b * c2 + d * d2,
        a * e2 + c * f2 + e,
        b * e2 + d * f2 + f,
    )


def determinant(m: Affine) -> float:
    return m[0] * m[3] - m[1] * m[2]


def apply(m: Affine, pts: np.ndarray) -> np.ndarray:
    a, b, c, d, e, f = m
    out = np.empty_like(pts)
    out[:, 0] = a * pts[:, 0] + c * pts[:, 1] + e
    out[:, 1] = b * pts[:, 0] + d * pts[:, 1] + f
    return out


def parse_transform(text: str) -> Affine:
    """SVG transform list (matrix, translate, scale, rotate, skewX, skewY), left to right."""
    result = IDENTITY
    pos = 0
    text = text.strip()
    pattern = re.compile(r"\s*(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)\s*,?")
    while pos < len(text):
        m = pattern.match(text, pos)
        if not m:
            raise ValueError(f"bad transform {text!r}")
        pos = m.end()
        name = m.group(1)
        v = [float(x) for x in re.findall(NUM, m.group(2))]
        if name == "matrix" and len(v) == 6:
            t: Affine = (v[0], v[1], v[2], v[3], v[4], v[5])
        elif name == "translate" and len(v) in (1, 2):
            t = (1.0, 0.0, 0.0, 1.0, v[0], v[1] if len(v) == 2 else 0.0)
        elif name == "scale" and len(v) in (1, 2):
            t = (v[0], 0.0, 0.0, v[1] if len(v) == 2 else v[0], 0.0, 0.0)
        elif name == "rotate" and len(v) in (1, 3):
            t = rotation_about(v[0], v[1], v[2]) if len(v) == 3 else rotation_about(v[0], 0, 0)
        elif name == "skewX" and len(v) == 1:
            t = (1.0, 0.0, math.tan(math.radians(v[0])), 1.0, 0.0, 0.0)
        elif name == "skewY" and len(v) == 1:
            t = (1.0, math.tan(math.radians(v[0])), 0.0, 1.0, 0.0, 0.0)
        else:
            raise ValueError(f"bad transform {m.group(0).strip()!r}")
        result = multiply(result, t)
    return result


def rotation_about(deg: float, cx: float, cy: float) -> Affine:
    """Rotation by deg degrees (y down, so positive turns clockwise on screen) about (cx, cy)."""
    r = math.radians(deg)
    co, si = math.cos(r), math.sin(r)
    return (co, si, -si, co, cx - co * cx + si * cy, cy - si * cx - co * cy)


def _cubic(p0, p1, p2, p3, tol: float) -> list[tuple[float, float]]:
    d1 = (p0[0] - 2 * p1[0] + p2[0], p0[1] - 2 * p1[1] + p2[1])
    d2 = (p1[0] - 2 * p2[0] + p3[0], p1[1] - 2 * p2[1] + p3[1])
    m = max(math.hypot(*d1), math.hypot(*d2))
    n = max(2, math.ceil(math.sqrt(0.75 * m / tol)))
    out = []
    for i in range(1, n + 1):
        t = i / n
        u = 1.0 - t
        out.append(
            (
                u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
                u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
            )
        )
    return out


def _quad(p0, p1, p2, tol: float) -> list[tuple[float, float]]:
    m = math.hypot(p0[0] - 2 * p1[0] + p2[0], p0[1] - 2 * p1[1] + p2[1])
    n = max(2, math.ceil(math.sqrt(m / (4.0 * tol))))
    out = []
    for i in range(1, n + 1):
        t = i / n
        u = 1.0 - t
        out.append(
            (
                u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1],
            )
        )
    return out


def parse_path(d: str, tol: float = FLAT_TOL_U) -> list[list[tuple[float, float]]]:
    """Path data (M L H V C Q Z, absolute and relative) to closed polylines (implicit close)."""
    toks = re.findall(r"[A-Za-z]|" + NUM, d)
    polys: list[list[tuple[float, float]]] = []
    pts: list[tuple[float, float]] = []
    cur = (0.0, 0.0)
    start = cur
    cmd = ""
    i = 0
    counts = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "Q": 4}
    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]
            i += 1
            if cmd not in "MLHVCQZmlhvcqz":
                raise ValueError(f"unsupported path command {cmd!r}")
            if cmd in "Zz":
                if pts:
                    polys.append(pts)
                pts, cur = [], start
                continue
        if not cmd:
            raise ValueError("path data must start with a command")
        rel = cmd.islower()
        c = cmd.upper()
        need = counts[c]
        v = [float(x) for x in toks[i : i + need]]
        if len(v) != need:
            raise ValueError(f"path command {cmd} wants {need} numbers")
        i += need
        ox, oy = cur if rel else (0.0, 0.0)
        if c == "M":
            if pts:
                polys.append(pts)
            cur = (v[0] + ox, v[1] + oy)
            start = cur
            pts = [cur]
            cmd = "l" if rel else "L"
        elif c == "L":
            cur = (v[0] + ox, v[1] + oy)
            pts.append(cur)
        elif c == "H":
            cur = (v[0] + (ox if rel else 0.0), cur[1])
            pts.append(cur)
        elif c == "V":
            cur = (cur[0], v[0] + (oy if rel else 0.0))
            pts.append(cur)
        elif c == "C":
            p1 = (v[0] + ox, v[1] + oy)
            p2 = (v[2] + ox, v[3] + oy)
            p3 = (v[4] + ox, v[5] + oy)
            if not pts:
                pts = [cur]
            pts.extend(_cubic(cur, p1, p2, p3, tol))
            cur = p3
        else:
            p1 = (v[0] + ox, v[1] + oy)
            p2 = (v[2] + ox, v[3] + oy)
            if not pts:
                pts = [cur]
            pts.extend(_quad(cur, p1, p2, tol))
            cur = p2
    if pts:
        polys.append(pts)
    return polys


def ellipse_poly(cx: float, cy: float, rx: float, ry: float, tol: float = FLAT_TOL_U):
    r = max(rx, ry)
    n = max(24, math.ceil(math.pi / math.acos(max(-1.0, 1.0 - tol / r))))
    return [
        (cx + rx * math.cos(k * 2 * math.pi / n), cy + ry * math.sin(k * 2 * math.pi / n))
        for k in range(n)
    ]


def signed_area(p: np.ndarray) -> float:
    """Shoelace area, positive when wound with +x to +y. fsum is exact, so the sign never depends
    on how numpy happens to associate a sum on this CPU."""
    x, y = p[:, 0], p[:, 1]
    return 0.5 * math.fsum((x * np.roll(y, -1) - np.roll(x, -1) * y).tolist())


def clean(poly) -> np.ndarray:
    """Float64 vertex array without repeated points or a closing duplicate, positively wound.

    Every subpath of a part is a filled region and the parts are unions, so all of a part's
    polygons share one orientation (nonzero winding then equals the union).
    """
    p = np.array(poly, dtype=np.float64).reshape(-1, 2)
    keep = [0]
    for k in range(1, len(p)):
        if p[k, 0] != p[keep[-1], 0] or p[k, 1] != p[keep[-1], 1]:
            keep.append(k)
    p = p[keep]
    if len(p) > 1 and p[0, 0] == p[-1, 0] and p[0, 1] == p[-1, 1]:
        p = p[:-1]
    if len(p) < 3:
        raise ValueError("a polygon needs at least three distinct points")
    if signed_area(p) < 0.0:
        p = p[::-1].copy()
    return p


def segments(polys: list[np.ndarray]) -> tuple[np.ndarray, np.ndarray]:
    """Closed polygons to segment endpoint arrays (A, B), polygon by polygon."""
    a = np.concatenate(polys)
    b = np.concatenate([np.roll(p, -1, axis=0) for p in polys])
    return a, b


def bounds(polys: list[np.ndarray]) -> tuple[float, float, float, float]:
    pts = np.concatenate(polys)
    return (
        float(pts[:, 0].min()),
        float(pts[:, 1].min()),
        float(pts[:, 0].max()),
        float(pts[:, 1].max()),
    )


def second_moment_angle(polys: list[np.ndarray]) -> float:
    """The major axis of the filled polygons (area second moments), in [0, pi)."""
    area = 0.0
    sx = sy = 0.0
    sxx = syy = sxy = 0.0
    for p in polys:
        x, y = p[:, 0], p[:, 1]
        x2, y2 = np.roll(x, -1), np.roll(y, -1)
        cr = x * y2 - x2 * y
        area += math.fsum(cr.tolist()) * 0.5
        sx += math.fsum(((x + x2) * cr).tolist())
        sy += math.fsum(((y + y2) * cr).tolist())
        sxx += math.fsum(((x * x + x * x2 + x2 * x2) * cr).tolist())
        syy += math.fsum(((y * y + y * y2 + y2 * y2) * cr).tolist())
        sxy += math.fsum(((x * y2 + 2 * x * y + 2 * x2 * y2 + x2 * y) * cr).tolist())
    if abs(area) < 1e-12:
        return 0.0
    cx, cy = sx / (6 * area), sy / (6 * area)
    ixx = sxx / 12.0 - area * cx * cx
    iyy = syy / 12.0 - area * cy * cy
    ixy = sxy / 24.0 - area * cx * cy
    scale = max(abs(ixx), abs(iyy), 1e-12)
    if abs(ixx - iyy) < 1e-9 * scale and abs(ixy) < 1e-9 * scale:
        return 0.0  # isotropic: a circle has no axis
    return (0.5 * math.atan2(2 * ixy, ixx - iyy)) % math.pi
