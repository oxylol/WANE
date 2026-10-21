"""The measurements ci/lighting.sh makes on the review's pictures of the test crawler (review 2: the
64 px silhouette of a wide asset, and an eye that is a point light, not a campfire)."""

import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from . import common  # noqa: F401  (puts tools/ on sys.path)
from artbuild import review_check as rc


def silhouette(size: tuple[int, int], box: tuple[int, int, int, int]) -> Image.Image:
    im = Image.new("RGB", size, (0, 0, 0))
    ImageDraw.Draw(im).rectangle(box, fill=(255, 255, 255))
    return im


class Silhouette(unittest.TestCase):
    def problems(self, im: Image.Image) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sil64.png"
            im.save(path)
            return rc.silhouette_problems(path)

    def test_a_whole_wide_figure_passes(self) -> None:
        self.assertEqual(self.problems(silhouette((213, 96), (13, 17, 199, 82))), [])

    def test_a_figure_that_touches_the_edge_is_clipped(self) -> None:
        """The first review's crawler: 96 px wide, white from the left edge to the right edge."""
        text = " ".join(self.problems(silhouette((96, 96), (0, 22, 95, 72))))
        self.assertIn("clipped", text)
        self.assertIn("clipped", " ".join(self.problems(silhouette((213, 96), (13, 0, 199, 60)))))

    def test_the_figure_is_about_64_px_tall_and_wide(self) -> None:
        self.assertIn("tall", " ".join(self.problems(silhouette((213, 140), (13, 10, 199, 130)))))
        self.assertIn("not wide", " ".join(self.problems(silhouette((96, 96), (30, 17, 70, 82)))))

    def test_nothing_drawn_is_a_problem(self) -> None:
        self.assertIn("nothing", " ".join(self.problems(Image.new("RGB", (96, 96)))))


class Eye(unittest.TestCase):
    SHEET = {"actions": {"idle": {"frames": [{"emissive_regions": [
        {"part": "flame", "kind": "ember", "centre": [-20.0, -30.0]},
        {"part": "eye", "kind": "eye", "centre": [43.0, -12.0]},
    ]}]}}}

    def problems(self, wall: int, glint: int, sheet=None) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            im = Image.new("RGB", (640, 360), (4, 4, 4))
            ex, ey = 395, 296  # MARK (352, 320) + centre (43, -12) - crop origin (0, 12)
            ImageDraw.Draw(im).rectangle((ex - 8, ey - 45, ex + 8, ey - 20), fill=(wall,) * 3)
            ImageDraw.Draw(im).rectangle((ex - 1, ey - 1, ex + 1, ey + 1), fill=(glint,) * 3)
            pitch = Path(tmp) / "pitch1x.png"
            im.save(pitch)
            sheet_path = Path(tmp) / "x.sheet.json"
            sheet_path.write_text(json.dumps(sheet or self.SHEET))
            return rc.eye_problems(pitch, sheet_path)

    def test_the_eye_is_found_by_its_kind_and_lands_where_review_gd_draws_it(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.sheet.json"
            path.write_text(json.dumps(self.SHEET))
            self.assertEqual(rc.eye_pixel(path), (395, 296))

    def test_a_dark_wall_and_a_bright_glint_pass(self) -> None:
        self.assertEqual(self.problems(wall=19, glint=237), [])

    def test_an_eye_lit_as_a_campfire_floods_the_wall(self) -> None:
        text = " ".join(self.problems(wall=52, glint=237))
        self.assertIn("campfire", text)

    def test_no_glint_and_no_eye_region_are_problems(self) -> None:
        self.assertIn("glint", " ".join(self.problems(wall=19, glint=90)))
        none = {"actions": {"idle": {"frames": [{"emissive_regions": []}]}}}
        self.assertIn("no emissive region of kind eye", " ".join(self.problems(wall=19, glint=237, sheet=none)))


if __name__ == "__main__":
    unittest.main()
