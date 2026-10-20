"""Shared helpers for the artbuild tests: the probe, the test prop, and cairosvg's reference."""

from __future__ import annotations

import functools
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import cairosvg  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

from artbuild import assetbuild, channels as ch, frame, pose  # noqa: E402

PROBE_DIR = ROOT / "tools" / "artbuild" / "tests" / "data" / "probe"
CANDLE_DIR = ROOT / "tests" / "art" / "src" / "candle_stump"


@functools.lru_cache(maxsize=None)
def source(path: Path) -> assetbuild.Source:
    return assetbuild.load_source(path)


@functools.lru_cache(maxsize=None)
def baked(path: Path, action: int = 0, index: int = 0, scales: tuple[int, ...] = (1, 2, 4)):
    src = source(path)
    cell = assetbuild.action_cells(src)[action]
    posed = pose.pose_frame(src.lib, src.actions[action].frames[index])
    return cell, frame.bake(src.lib, src.pal, posed, cell, scales)


def cairo_coverage(svg_path: Path, cell: ch.Cell, scale: int) -> np.ndarray:
    """cairosvg's anti-aliased coverage of the source SVG over the cell's window, 0 to 1."""
    text = svg_path.read_text(encoding="utf-8")
    text = re.sub(r'viewBox="[^"]*"', f'viewBox="{cell.x0} {cell.y0} {cell.w} {cell.h}"', text, count=1)
    png = cairosvg.svg2png(
        bytestring=text.encode(), output_width=cell.w * scale, output_height=cell.h * scale
    )
    return np.array(Image.open(io.BytesIO(png)).convert("RGBA"))[:, :, 3].astype(np.float64) / 255.0


def decode_s(shape: np.ndarray) -> np.ndarray:
    return (shape[..., 0].astype(np.float64) - ch.S_ZERO) / ch.S_STEPS_PER_U


def decode_u(shape: np.ndarray) -> np.ndarray:
    return shape[..., 1].astype(np.float64) / ch.U_STEPS_PER_U


def bake_svg(body: str, cell: ch.Cell, scales=(1, 2, 4), frame_spec=None):
    """Bake an in-memory part library (SVG body inside a 64 u viewBox) with one grey material."""
    import json

    from artbuild import palette, svg

    lib = svg.parse(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">{body}</svg>')
    mats = {
        "m": {"lit": "#ffffff", "shadow": "#000000", "rim": "#808080", "gloss": 0.5},
        "e": {
            "lit": "#ffffff",
            "shadow": "#000000",
            "rim": "#808080",
            "gloss": 0.0,
            "emissive": "#ff8000",
            "emissive_strength": 1.0,
        },
    }
    parts = {p.id: ("e" if "emissive" in p.tags else "m") for p in lib.parts}
    pal = palette.parse("[resource]\nmetadata/palette = " + json.dumps({"materials": mats, "parts": parts}), lib)
    posed = pose.pose_frame(lib, frame_spec or pose.FrameSpec(True, 3))
    return lib, frame.bake(lib, pal, posed, cell, scales)
