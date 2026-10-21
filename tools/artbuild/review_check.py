#!/usr/bin/env python3
"""python3 tools/artbuild/review_check.py <review dir> <sheet.json>

Measures two pictures that tools/artbuild/review.gd draws of a wide asset with an eye (the test
crawler, `tests/art/src/crawler/`) and exits 1 listing what is wrong (ci/lighting.sh runs it):

- `sil64.png` holds the whole silhouette: nothing white touches the picture's edge, the figure is
  about 64 px tall (the checklist's "identifiable by silhouette alone at 64 pixels tall") and wider
  than it is tall, so a wide low enemy is drawn whole and not cut to a white bar (review 2 T3);
- `pitch1x.png` lights the eye as an eye: BUILD.md section 10 (Lighting) makes an enemy's eyes
  "point lights, tiny", so at Pitch the wall just above the head stays dark and the glint itself is
  bright. An eye lit as a campfire (kind `fire`, radius 160 u) lights the body and the wall around
  it, and the Clinger line "the ember reveals it 30 frames before it drops" is judged on that
  picture (review 2 T2).

The numbers: the crawler measures 19 for the wall above the eye with the eye light and 52 when the
review used the fire light; the limit sits between them. The geometry is review.gd's (MARK, the 1x
crop of 640 x 360 u centred on (320, 192)).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

MARK = (352.0, 320.0)  # review.gd MARK: where the asset's feet pivot stands, in room u
CROP_ORIGIN = (0.0, 12.0)  # review.gd CROP_CENTRE (320, 192) minus half of CROP_1X (640, 360)
SIL_HEIGHT_PX = 64
SIL_HEIGHT_SLACK_PX = 14  # the 64 px is above the feet; a hanging jaw, the line and the AA add
WHITE = 200
WIDE_RATIO = 1.5
WALL_ABOVE_U = (24, 40)  # the band of wall above the eye that a fire light would flood
WALL_HALF_WIDTH_PX = 6
WALL_MAX_LUMA = 35.0
GLINT_MIN_LUMA = 200


def silhouette_problems(path: Path) -> list[str]:
    im = Image.open(path).convert("L")
    w, h = im.size
    px = im.load()
    white = [(x, y) for y in range(h) for x in range(w) if px[x, y] > WHITE]
    if not white:
        return [f"{path.name}: nothing is drawn"]
    xs, ys = [p[0] for p in white], [p[1] for p in white]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    problems = []
    if x0 == 0 or y0 == 0 or x1 == w - 1 or y1 == h - 1:
        problems.append(f"{path.name}: the silhouette touches the picture's edge: it is clipped ({w} x {h})")
    height, width = y1 - y0 + 1, x1 - x0 + 1
    if height > SIL_HEIGHT_PX + SIL_HEIGHT_SLACK_PX:
        problems.append(f"{path.name}: the figure is {height} px tall, not about {SIL_HEIGHT_PX}")
    if width < WIDE_RATIO * height:
        problems.append(f"{path.name}: a wide asset is {width} x {height} px, which is not wide")
    return problems


def eye_pixel(sheet: Path) -> tuple[int, int] | None:
    """Where the first eye region of the first action's first frame lands in pitch1x.png."""
    doc = json.loads(sheet.read_text(encoding="utf-8"))
    first = next(iter(doc["actions"].values()))["frames"][0]
    for region in first.get("emissive_regions", []):
        if region.get("kind") == "eye":
            cx, cy = region["centre"]
            return round(MARK[0] + cx - CROP_ORIGIN[0]), round(MARK[1] + cy - CROP_ORIGIN[1])
    return None


def eye_problems(pitch: Path, sheet: Path) -> list[str]:
    at = eye_pixel(sheet)
    if at is None:
        return [f"{sheet.name}: no emissive region of kind eye in the first frame"]
    im = Image.open(pitch).convert("L")
    px = im.load()
    ex, ey = at
    glint = max(px[x, y] for x in range(ex - 3, ex + 4) for y in range(ey - 3, ey + 4))
    band = [
        px[x, y]
        for x in range(ex - WALL_HALF_WIDTH_PX, ex + WALL_HALF_WIDTH_PX + 1)
        for y in range(ey - WALL_ABOVE_U[1], ey - WALL_ABOVE_U[0])
    ]
    wall = sum(band) / len(band)
    problems = []
    if glint < GLINT_MIN_LUMA:
        problems.append(f"{pitch.name}: the eye at {at} is {glint}, not a bright glint")
    if wall > WALL_MAX_LUMA:
        problems.append(
            f"{pitch.name}: the wall above the eye is {wall:.1f} bright (limit {WALL_MAX_LUMA}): "
            "the eye is lit like a campfire, not as a tiny point light"
        )
    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    out, sheet = Path(argv[0]), Path(argv[1])
    problems = silhouette_problems(out / "sil64.png") + eye_problems(out / "pitch1x.png", sheet)
    for p in problems:
        print(f"review check: {p}", file=sys.stderr)
    if not problems:
        print("review check: the wide silhouette is whole and the eye is a point light")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
