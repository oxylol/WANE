"""Affines, flattening and polygon moments (ADR-0023 Decision 1.2)."""

import math
import unittest

import numpy as np

from . import common  # noqa: F401
from artbuild import geometry as geo


class Transforms(unittest.TestCase):
    def test_list_applies_left_to_right(self) -> None:
        m = geo.parse_transform("translate(10 0) scale(2)")
        p = geo.apply(m, np.array([[1.0, 1.0]]))[0]
        self.assertEqual((p[0], p[1]), (12.0, 2.0))  # scale first, then translate

    def test_rotate_about_a_point_fixes_that_point(self) -> None:
        m = geo.parse_transform("rotate(90 5 5)")
        p = geo.apply(m, np.array([[5.0, 5.0], [6.0, 5.0]]))
        self.assertTrue(np.allclose(p[0], [5.0, 5.0]))
        self.assertTrue(np.allclose(p[1], [5.0, 6.0]))  # y down: +90 turns +x to +y
        r = geo.rotation_about(90, 5, 5)
        self.assertTrue(np.allclose(r, m, atol=1e-12))

    def test_multiply_composes(self) -> None:
        a = geo.parse_transform("rotate(30)")
        b = geo.parse_transform("translate(3 4)")
        both = geo.multiply(a, b)
        pt = np.array([[1.0, 2.0]])
        self.assertTrue(np.allclose(geo.apply(both, pt), geo.apply(a, geo.apply(b, pt))))

    def test_bad_transform_raises(self) -> None:
        with self.assertRaises(ValueError):
            geo.parse_transform("wobble(3)")


class Flattening(unittest.TestCase):
    def test_cubic_stays_within_tolerance_of_the_true_curve(self) -> None:
        p0, p1, p2, p3 = (0, 0), (0, 40), (40, 40), (40, 0)
        pts = [p0, *geo._cubic(p0, p1, p2, p3, geo.FLAT_TOL_U)]
        # Sample the true curve densely and measure its distance to the polyline.
        t = np.linspace(0, 1, 4001)[:, None]
        c = ((1 - t) ** 3 * np.array(p0) + 3 * (1 - t) ** 2 * t * np.array(p1)
             + 3 * (1 - t) * t**2 * np.array(p2) + t**3 * np.array(p3))
        a = np.array(pts[:-1], dtype=float)
        b = np.array(pts[1:], dtype=float)
        worst = 0.0
        for q in c[::20]:
            ab = b - a
            tt = np.clip(((q - a) * ab).sum(1) / (ab * ab).sum(1), 0, 1)
            d = np.sqrt((((a + ab * tt[:, None]) - q) ** 2).sum(1)).min()
            worst = max(worst, float(d))
        self.assertLessEqual(worst, geo.FLAT_TOL_U)

    def test_quad_and_circle_within_tolerance(self) -> None:
        pts = geo.ellipse_poly(0, 0, 9, 9)
        worst = max(9 - math.hypot((a[0] + b[0]) / 2, (a[1] + b[1]) / 2) for a, b in zip(pts, pts[1:] + pts[:1]))
        self.assertLessEqual(worst, geo.FLAT_TOL_U)
        q = geo.parse_path("M0 0 Q10 20 20 0 Z")[0]
        mid = q[len(q) // 2]
        self.assertAlmostEqual(mid[1], 10.0, delta=geo.FLAT_TOL_U * 2)

    def test_path_relative_commands_and_implicit_lineto(self) -> None:
        (poly,) = geo.parse_path("m10 10 l5 0 0 5 h-5 z")
        self.assertEqual(poly, [(10.0, 10.0), (15.0, 10.0), (15.0, 15.0), (10.0, 15.0)])

    def test_two_subpaths_make_two_polygons(self) -> None:
        self.assertEqual(len(geo.parse_path("M0 0 L4 0 L4 4 Z M10 10 L14 10 L14 14 Z")), 2)
        # A Z followed by a moveto leaves no one-point subpath behind.
        self.assertEqual([len(p) for p in geo.parse_path("M0 0 L4 0 L4 4 Z M10 10 L14 10 L14 14 Z")], [3, 3])

    def test_a_drawing_command_after_z_starts_at_the_closed_subpaths_start(self) -> None:
        """SVG 1.1 8.3.3: after a closepath the current point is the subpath's initial point, and a
        command that is not a moveto starts a new subpath there (docs/review: L, H and V lost it)."""
        want = [[(10.0, 10.0), (30.0, 10.0), (30.0, 30.0)],
                [(10.0, 10.0), (10.0, 30.0), (10.0, 50.0), (40.0, 50.0)]]
        self.assertEqual(geo.parse_path("M10 10 L30 10 L30 30 Z L10 30 L10 50 L40 50 Z"), want)
        (a, b) = geo.parse_path("M10 10 h20 v20 z h-5 v20 l30 0 z")
        self.assertEqual(b[0], (10.0, 10.0))
        self.assertEqual(b[1:3], [(5.0, 10.0), (5.0, 30.0)])
        # C and Q already seeded from the current point; they must still.
        (_, c) = geo.parse_path("M0 0 L8 0 L8 8 Z C2 2 4 4 0 8 L0 0")
        self.assertEqual(c[0], (0.0, 0.0))

    def test_path_data_must_begin_with_a_moveto(self) -> None:
        for d in ("L5 5 L9 0 Z", "H4 V4 Z", "5 5 L9 0 L0 9 Z"):
            with self.assertRaises(ValueError, msg=d):
                geo.parse_path(d)


class Moments(unittest.TestCase):
    def test_major_axis_of_rectangles(self) -> None:
        wide = geo.clean([(0, 0), (20, 0), (20, 2), (0, 2)])
        tall = geo.clean([(0, 0), (2, 0), (2, 20), (0, 20)])
        diag = geo.clean([(0, 0), (20, 20), (19, 21), (-1, 1)])
        self.assertAlmostEqual(geo.second_moment_angle([wide]), 0.0, places=6)
        self.assertAlmostEqual(geo.second_moment_angle([tall]), math.pi / 2, places=6)
        self.assertAlmostEqual(geo.second_moment_angle([diag]), math.pi / 4, places=6)

    def test_a_circle_has_no_axis(self) -> None:
        circle = geo.clean(geo.ellipse_poly(0, 0, 5, 5))
        self.assertEqual(geo.second_moment_angle([circle]), 0.0)

    def test_area_not_vertex_density_decides(self) -> None:
        # A long thin triangle with many vertices crowded at one end: the axis is still along it.
        pts = [(0, 0)] + [(20 - 0.01 * k, 1.0 - 0.0005 * k) for k in range(0, 400, 1)] + [(0, 2)]
        poly = geo.clean(pts)
        self.assertLess(min(geo.second_moment_angle([poly]), math.pi - geo.second_moment_angle([poly])), 0.1)


if __name__ == "__main__":
    unittest.main()
