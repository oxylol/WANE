"""Winding and exact nearest-segment search (ADR-0023 Decision 1.2)."""

import math
import random
import unittest

import numpy as np

from . import common  # noqa: F401
from artbuild import geometry as geo
from artbuild import sdf


def star(n: int = 7, r0: float = 18.0, r1: float = 7.0) -> np.ndarray:
    pts = []
    for k in range(2 * n):
        r = r0 if k % 2 == 0 else r1
        a = k * math.pi / n
        pts.append((32 + r * math.cos(a), 32 + r * math.sin(a)))
    return geo.clean(pts)


def brute_dist(p, a, b):
    best = math.inf
    for (ax, ay), (bx, by) in zip(a.tolist(), b.tolist()):
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / max(dx * dx + dy * dy, 1e-18)))
        best = min(best, math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy)))
    return best


class Winding(unittest.TestCase):
    def test_scanline_matches_point_test_on_a_concave_polygon(self) -> None:
        poly = star()
        a, b = geo.segments([poly])
        for s in (1, 2, 4):
            grid = sdf.Grid(0.0, 0.0, 64 * s, 64 * s, s)
            by_scan = sdf.inside_grid(a, b, grid).ravel()
            by_point = sdf.inside_points(grid.points(), a, b)
            self.assertTrue(np.array_equal(by_scan, by_point), f"scale {s}")
            self.assertGreater(by_scan.sum(), 100)

    def test_matches_on_an_offset_grid_and_two_overlapping_polygons(self) -> None:
        p1 = geo.clean([(10.013, 10.071), (40.37, 12.113), (30.211, 40.317)])
        p2 = geo.clean([(25, 5.3), (50.2, 30), (20, 35.1)])  # no pixel centre exactly on an edge
        a, b = geo.segments([p1, p2])
        grid = sdf.Grid(-3.25, 2.5, 200, 120, 4)
        self.assertTrue(
            np.array_equal(sdf.inside_grid(a, b, grid).ravel(), sdf.inside_points(grid.points(), a, b))
        )

    def test_a_rectangle_covers_exactly_the_pixels_whose_centres_it_contains(self) -> None:
        r = geo.clean([(4, 4), (12, 4), (12, 8), (4, 8)])
        a, b = geo.segments([r])
        grid = sdf.Grid(0.0, 0.0, 16, 16, 1)
        got = sdf.inside_grid(a, b, grid)
        want = np.zeros((16, 16), dtype=bool)
        want[4:8, 4:12] = True  # centres at 4.5 .. 7.5 and 4.5 .. 11.5
        self.assertTrue(np.array_equal(got, want))


class Nearest(unittest.TestCase):
    def test_banded_equals_brute_force_inside_the_band(self) -> None:
        rnd = random.Random(7)
        polys = [geo.clean([(rnd.uniform(5, 59), rnd.uniform(5, 59)) for _ in range(5)]) for _ in range(4)]
        a, b = geo.segments(polys)
        grid = sdf.Grid(0.0, 0.0, 64, 64, 1)
        band = 8.5
        d, idx, vec = sdf.nearest_banded(grid, a, b, band)
        pts = grid.points()
        for k in rnd.sample(range(len(pts)), 300):
            want = brute_dist(pts[k], a, b)
            if want < band:
                self.assertAlmostEqual(d[k], want, places=12, msg=f"pixel {k}")
                self.assertGreaterEqual(idx[k], 0)
                self.assertAlmostEqual(math.hypot(*vec[k]), want, places=12)
            else:
                self.assertEqual(d[k], band)
                self.assertEqual(idx[k], -1)

    def test_mask_restricts_the_pixels_evaluated(self) -> None:
        a, b = geo.segments([star()])
        grid = sdf.Grid(0.0, 0.0, 64, 64, 1)
        mask = np.zeros((64, 64), dtype=bool)
        mask[30:34, 30:34] = True
        d, idx, _ = sdf.nearest_banded(grid, a, b, 8.5, mask=mask)
        d2 = d.reshape(64, 64)
        self.assertTrue((idx.reshape(64, 64)[~mask] == -1).all())
        full, _, _ = sdf.nearest_banded(grid, a, b, 8.5)
        self.assertTrue(np.array_equal(d2[mask], full.reshape(64, 64)[mask]))

    def test_ties_go_to_the_lowest_segment(self) -> None:
        a = np.array([[0.0, 0.0], [0.0, 0.0]])
        b = np.array([[10.0, 0.0], [10.0, 0.0]])
        d, idx, _ = sdf.nearest(np.array([[5.0, 3.0]]), a, b)
        self.assertEqual((d[0], idx[0]), (3.0, 0))


if __name__ == "__main__":
    unittest.main()
