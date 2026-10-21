"""The channels, measured against analytic shapes and cairosvg (ADR-0023 Decision 1.3, 1.4, 1.9)."""

import math
import time
import unittest

import numpy as np

from . import common
from artbuild import channels as ch
from artbuild import pose

CELL = ch.Cell(0.0, 0.0, 64, 64)


def rect(i: str, z: int, x: float, y: float, w: float, h: float, extra: str = "") -> str:
    return f'<rect id="{i}" data-z="{z}" x="{x}" y="{y}" width="{w}" height="{h}" {extra}/>'


def px(arr: np.ndarray, x: float, y: float, scale: int) -> np.ndarray:
    """The texel whose centre is nearest the world point (x, y)."""
    return arr[int(y * scale), int(x * scale)]


class DecodeConstants(unittest.TestCase):
    def test_the_constants_are_what_the_adr_says(self) -> None:
        self.assertEqual((ch.S_ZERO, ch.S_STEPS_PER_U, ch.U_STEPS_PER_U), (128, 16, 16))
        self.assertEqual(ch.PALETTE_COLUMNS, 16)
        self.assertEqual([ch.FLAG_POGO, ch.FLAG_BLADE, ch.FLAG_EYE, ch.FLAG_SMEAR, ch.FLAG_WAX], [1, 2, 4, 8, 16])

    def test_constants_sit_on_their_own_lines_for_the_shader_test(self) -> None:
        text = (common.TOOLS / "artbuild" / "channels.py").read_text(encoding="utf-8")
        for name in ("S_ZERO", "S_STEPS_PER_U", "U_STEPS_PER_U", "ANGLE_BYTE_MAX", "NORMAL_BYTE_MAX"):
            self.assertRegex(text, rf"(?m)^{name} = \d+")


class SilhouetteDistance(unittest.TestCase):
    def test_s_is_the_exact_signed_distance_to_a_rectangle(self) -> None:
        lib, res = common.bake_svg(rect("a", 0, 20, 20, 24, 16), CELL)
        for s in (1, 2, 4):
            shape = res.arrays[s]["shape"]
            got = common.decode_s(shape)
            ys, xs = np.mgrid[0 : 64 * s, 0 : 64 * s]
            cx, cy = (xs + 0.5) / s, (ys + 0.5) / s
            dx = np.maximum(np.maximum(20 - cx, cx - 44), 0.0)
            dy = np.maximum(np.maximum(20 - cy, cy - 36), 0.0)
            outside = np.hypot(dx, dy)
            inside = -np.minimum(np.minimum(cx - 20, 44 - cx), np.minimum(cy - 20, 36 - cy))
            want = np.where((dx > 0) | (dy > 0), outside, inside)
            inband = np.abs(want) < 7.9
            err = np.abs(got - np.clip(want, -8, 7.9))[inband]
            self.assertLessEqual(float(err.max()), 0.5 / ch.S_STEPS_PER_U + 1e-9, f"scale {s}")

    def test_concave_corner_of_two_overlapping_parts(self) -> None:
        body = rect("a", 0, 10, 10, 20, 20) + rect("b", 1, 20, 20, 20, 20)
        _, res = common.bake_svg(body, CELL)
        s = 4
        shape = res.arrays[s]["shape"]
        # (31.125, 19.125) is outside the union: 1.125 u from the back part's right edge and
        # 0.875 u from the front part's top edge.
        self.assertAlmostEqual(float(common.decode_s(px(shape, 31.125, 19.125, s))), 0.875, delta=0.04)
        # Inside both parts at the overlap's middle, the nearest silhouette edge is the concave
        # corner (30, 20), 7.07 u away; the parts' hidden edges (5 u away) are not silhouette.
        got = float(common.decode_s(px(shape, 25.125, 25.125, s)))
        self.assertAlmostEqual(got, -math.hypot(4.875, 5.125), delta=0.04)
        # (12.625, 20.125) is 2.625 u inside the left edge of the back part.
        self.assertAlmostEqual(float(common.decode_s(px(shape, 12.625, 20.125, s))), -2.625, delta=0.04)

    def test_sign_agrees_with_cairosvg_on_every_firm_pixel(self) -> None:
        for path in common.part_libraries():
            src = common.source(path)
            for ai in range(len(src.actions)):
                for fi in range(len(src.actions[ai].frames)):
                    if ai > 0 and src.actions[ai].frames[fi].parts:
                        continue  # cairo renders the source pose only
                    cell, res = common.baked(path, ai, fi)
                    for s in (1, 2, 4):
                        cov = common.cairo_coverage(path / "parts.svg", cell, s)
                        firm = (cov > 0.98) | (cov < 0.02)
                        mine = common.decode_s(res.arrays[s]["shape"]) < 0
                        agree = float(((cov[firm] > 0.5) == mine[firm]).mean())
                        self.assertEqual(agree, 1.0, f"{path.name} action {ai} frame {fi} at {s}x")

    def test_coverage_from_s_tracks_cairos_antialiasing(self) -> None:
        cell, res = common.baked(common.PROBE_DIR, 0, 0)
        for s in (1, 4):
            cov = common.cairo_coverage(common.PROBE_DIR / "parts.svg", cell, s)
            from_s = np.clip(0.5 - common.decode_s(res.arrays[s]["shape"]) * s, 0.0, 1.0)
            self.assertLess(float(np.abs(from_s - cov).mean()), 0.004, f"{s}x")


class VisibleEdges(unittest.TestCase):
    BODY = rect("back", 0, 10, 10, 20, 20) + rect("front", 1, 20, 20, 20, 20)

    def test_u_ignores_the_edge_a_front_part_covers(self) -> None:
        _, res = common.bake_svg(self.BODY, CELL)
        s = 4
        shape = res.arrays[s]["shape"]
        # (29.625, 25.125) lies 0.375 u from the back part's right edge, which the front part
        # hides: the nearest visible edge is the front part's top edge, 5.125 u away.
        self.assertAlmostEqual(float(common.decode_u(px(shape, 29.625, 25.125, s))), 5.125, delta=0.04)

    def test_side_marks_the_part_that_owns_the_nearest_edge(self) -> None:
        _, res = common.bake_svg(self.BODY, CELL)
        s = 4
        shape = res.arrays[s]["shape"]
        # Inside the front part, near its own left edge: front side (255).
        self.assertEqual(int(px(shape, 22.125, 30.125, s)[2]), 255)
        # In the back part only, just left of that same edge: the edge belongs to the front part, so
        # this pixel is on its back side (0), which is where the thick line stays off.
        self.assertEqual(int(px(shape, 18.125, 25.125, s)[2]), 0)
        self.assertAlmostEqual(float(common.decode_u(px(shape, 18.125, 25.125, s))), 1.875, delta=0.04)
        # Outside every part: never front side.
        self.assertEqual(int(px(shape, 3.0, 3.0, s)[2]), 0)

    def test_u_is_continuous_across_the_part_boundary_where_a_signed_field_would_jump(self) -> None:
        _, res = common.bake_svg(self.BODY, CELL)
        u = common.decode_u(res.arrays[4]["shape"])
        steps = np.abs(np.diff(u, axis=1))
        self.assertLessEqual(float(steps.max()), 0.25 + 1.0 / ch.U_STEPS_PER_U)  # one texel at most

    def test_smear_union_has_no_interior_edges(self) -> None:
        spec = pose.FrameSpec(True, 2, {}, {"b": [(1, 0, 0, 1, -6.0, 0.0), (1, 0, 0, 1, -3.0, 0.0)]})
        _, res = common.bake_svg(rect("b", 0, 30, 20, 16, 8, 'data-tags="blade smear"'), CELL, frame_spec=spec)
        s = 4
        shape = res.arrays[s]["shape"]
        # The union is the rectangle 24 .. 46 by 20 .. 28. At (33.125, 24.125) the top edge is
        # 4.125 u away and the bottom edge 3.875 u. The sub-poses' own left edges (x = 27 and 30)
        # lie inside the union: if they counted, U would be 3.125.
        self.assertAlmostEqual(float(common.decode_u(px(shape, 33.125, 24.125, s))), 3.875, delta=0.04)
        flags = int(px(res.arrays[s]["parts"], 33.125, 24.125, s)[3])
        self.assertEqual(flags & ch.FLAG_SMEAR, ch.FLAG_SMEAR)
        self.assertEqual(flags & ch.FLAG_BLADE, ch.FLAG_BLADE)
        self.assertEqual(res.meta["smear"], {"b": True})
        # The silhouette box is the union's.
        self.assertEqual(res.meta["silhouette_box"], [24 - 32.0, 20 - 64.0, 46 - 32.0, 28 - 64.0])

    def test_a_sparse_smear_arc_bakes_as_one_continuous_wedge(self) -> None:
        from artbuild import geometry as geo

        blade = '<polygon id="b" data-z="0" data-tags="blade smear" data-pivot="20 40" points="20,39.4 44,39.4 44,40.6 20,40.6"/>'
        spec = pose.FrameSpec(True, 2, {"b": geo.rotation_about(10, 20, 40)}, {"b": [geo.rotation_about(-40, 20, 40)]})
        _, res = common.bake_svg(blade, CELL, frame_spec=spec)
        s = 4
        shape = res.arrays[s]["shape"]
        # Halfway through the arc (at -15 degrees) the blade's tip region is inside the ribbon.
        mid = geo.apply(geo.rotation_about(-15, 20, 40), np.array([[38.0, 40.0]]))[0]
        self.assertLess(float(common.decode_s(px(shape, float(mid[0]), float(mid[1]), s))), 0.0)
        # The wedge's own edges are the only ones: at the same radius, in the middle of the wedge,
        # the nearest visible edge is a radial edge of the wedge, several u away, not the sub-poses'.
        self.assertGreater(float(common.decode_u(px(shape, float(mid[0]), float(mid[1]), s))), 1.5)
        # The taper channel of a smear is its age along the arc: 0 at the tail (-40 degrees), 1 at the
        # blade (+10), about half way at -15, rising monotonically (the ribbon's fade and the line's
        # thinning, shaders/ink/ink_common.gdshaderinc).
        parts = res.arrays[s]["parts"]
        ages = []
        for deg in (-38.0, -27.0, -15.0, -3.0, 8.0):
            at = geo.apply(geo.rotation_about(deg, 20, 40), np.array([[38.0, 40.0]]))[0]
            ages.append(int(px(parts, float(at[0]), float(at[1]), s)[2]))
        self.assertEqual(ages, sorted(ages))
        self.assertLess(ages[0], 50)
        self.assertGreater(ages[-1], 205)
        self.assertAlmostEqual(ages[2], 127.5, delta=30)

    def test_overlapping_subpaths_of_one_part_are_a_union(self) -> None:
        body = '<path id="p" data-z="0" d="M10 10 L40 10 L40 40 L10 40 Z M20 20 L30 20 L30 30 L20 30 Z"/>'
        _, res = common.bake_svg(body, CELL)
        shape = res.arrays[4]["shape"]
        # The inner square lies inside the outer one: no edge there, and no hole.
        self.assertLess(float(common.decode_s(px(shape, 25.125, 25.125, 4))), 0.0)
        self.assertAlmostEqual(float(common.decode_u(px(shape, 25.125, 25.125, 4))), 14.875, delta=0.1)


class PartsChannels(unittest.TestCase):
    def test_slot_angle_taper_and_flags(self) -> None:
        body = (rect("fat", 0, 4, 4, 20, 20, 'data-tags="wax"')
                + rect("blade", 1, 30, 30, 24, 1.2, 'data-tags="blade pogo"')
                + rect("post", 2, 8, 34, 1.2, 24))
        _, res = common.bake_svg(body, CELL)
        s = 4
        parts = res.arrays[s]["parts"]
        fat = px(parts, 14, 14, s)
        blade = px(parts, 42, 30.6, s)
        post = px(parts, 8.6, 46, s)
        self.assertEqual(int(fat[0]), 1)  # all three share one material: one slot
        self.assertEqual(int(fat[3]), ch.FLAG_WAX)
        self.assertEqual(int(blade[3]), ch.FLAG_BLADE | ch.FLAG_POGO)
        self.assertEqual(int(fat[1]), 0)  # a square has no axis: angle 0
        self.assertEqual(int(blade[1]), 0)  # horizontal blade
        self.assertAlmostEqual(int(post[1]), 127.5, delta=1.0)  # vertical post: pi/2 of 255
        self.assertEqual(int(fat[2]), 255)  # full pressure on a body
        # Half-thickness 0.6 over 2.5 u: 0.24 of 255.
        self.assertAlmostEqual(int(blade[2]), 0.24 * 255, delta=3)
        self.assertEqual(int(px(parts, 60, 60, s)[0]), 0)  # nothing there: slot 0

    def test_part_boxes_and_emissive_regions_are_relative_to_the_origin(self) -> None:
        body = rect("lamp", 0, 20, 20, 8, 8, 'data-tags="emissive eye"')
        lib, res = common.bake_svg(body, CELL)
        ox, oy = lib.origin  # bottom centre of the 64 u viewBox
        (box,) = res.meta["part_boxes"]
        self.assertEqual(box["box"], [20 - ox, 20 - oy, 28 - ox, 28 - oy])
        (reg,) = res.meta["emissive_regions"]
        self.assertEqual(reg["centre"], [24 - ox, 24 - oy])
        self.assertAlmostEqual(reg["radius"], math.hypot(4, 4), places=3)
        self.assertEqual((reg["kind"], reg["colour"], reg["strength"]), ("eye", "#ff8000", 1.0))
        self.assertEqual(res.meta["silhouette_box"], box["box"])


class Emissive(unittest.TestCase):
    def test_coverage_is_one_inside_zero_outside_and_the_area_is_conserved_across_scales(self) -> None:
        body = rect("body", 0, 10, 10, 30, 30) + '<circle id="lamp" data-z="1" data-tags="emissive" cx="25.3" cy="24.7" r="3.4"/>'
        _, res = common.bake_svg(body, CELL)
        area = math.pi * 3.4**2
        for s in (1, 2, 4):
            a = res.arrays[s]["shape"][..., 3].astype(np.float64) / 255.0
            self.assertEqual(float(px(a, 25.3, 24.7, s)), 1.0)
            self.assertEqual(float(px(a, 40.0, 40.0, s)), 0.0)
            self.assertAlmostEqual(float(a.sum()) / s**2, area, delta=area * 0.03, msg=f"{s}x")

    def test_an_emissive_part_hidden_behind_another_does_not_glow(self) -> None:
        body = '<circle id="lamp" data-z="0" data-tags="emissive" cx="25" cy="25" r="4"/>' + rect("cover", 1, 15, 15, 20, 20)
        _, res = common.bake_svg(body, CELL)
        self.assertEqual(int(res.arrays[4]["shape"][..., 3].max()), 0)


class Normals(unittest.TestCase):
    def test_bevel_normal_leans_outward_and_is_flat_inside(self) -> None:
        _, res = common.bake_svg(rect("a", 0, 20, 20, 24, 24), CELL)
        s = 4
        n = res.arrays[s]["normal"].astype(np.float64) / ch.NORMAL_BYTE_MAX * 2 - 1
        left = n[int(32 * s), int(20.2 * s)]
        right = n[int(32 * s), int(43.8 * s)]
        top = n[int(20.2 * s), int(32 * s)]
        bottom = n[int(43.8 * s), int(32 * s)]
        self.assertLess(left[0], -0.5)
        self.assertGreater(right[0], 0.5)
        self.assertLess(top[1], -0.5)  # y is down: the top edge leans toward -y
        self.assertGreater(bottom[1], 0.5)
        centre = res.arrays[s]["normal"][int(32 * s), int(32 * s)]
        self.assertEqual(tuple(int(v) for v in centre[:3]), (128, 128, 255))
        mask = common.decode_s(res.arrays[s]["shape"]) < -0.3
        length = np.sqrt((n[..., :3][mask] ** 2).sum(axis=1))
        self.assertLess(float(np.abs(length - 1.0).max()), 0.02)

    def test_tilt_follows_the_declared_angle_at_the_edge(self) -> None:
        _, res = common.bake_svg(rect("a", 0, 20, 20, 24, 24, 'data-tilt-deg="40" data-bevel-u="3"'), CELL)
        n = res.arrays[4]["normal"].astype(np.float64) / ch.NORMAL_BYTE_MAX * 2 - 1
        # 0.125 u inside the left edge the tilt is 40 degrees x (1 - 0.125/3).
        v = n[int(32 * 4), int(20.125 * 4)]
        tilt = 40.0 * (1 - 0.125 / 3.0)
        self.assertAlmostEqual(math.degrees(math.acos(v[2])), tilt, delta=2.0)

    def test_flat_and_crease_profiles(self) -> None:
        for profile, expect_edge, expect_mid in (("flat", 0.0, 0.0), ("crease", 45.0, 45.0)):
            _, res = common.bake_svg(
                rect("a", 0, 20, 20, 24, 24, f'data-normal="{profile}" data-tilt-deg="45" data-bevel-u="3"'), CELL
            )
            n = res.arrays[4]["normal"].astype(np.float64) / ch.NORMAL_BYTE_MAX * 2 - 1
            edge = math.degrees(math.acos(n[int(32 * 4), int(20.2 * 4)][2]))
            mid = math.degrees(math.acos(n[int(32 * 4), int(22.5 * 4)][2]))
            deep = math.degrees(math.acos(n[int(32 * 4), int(26 * 4)][2]))
            self.assertAlmostEqual(edge, expect_edge, delta=2.0, msg=profile)
            self.assertAlmostEqual(mid, expect_mid, delta=2.0, msg=profile)
            self.assertAlmostEqual(deep, 0.0, delta=1.0, msg=profile)

    def test_reduced_normals_are_unit_and_agree_with_the_master(self) -> None:
        _, res = common.bake_svg(rect("a", 0, 20, 20, 24, 24), CELL)
        n4 = res.arrays[4]["normal"].astype(np.float64) / 255 * 2 - 1
        for s in (1, 2):
            n = res.arrays[s]["normal"].astype(np.float64) / 255 * 2 - 1
            inside = common.decode_s(res.arrays[s]["shape"]) < -1.0
            length = np.sqrt((n[..., :3][inside] ** 2).sum(axis=1))
            self.assertLess(float(np.abs(length - 1.0).max()), 0.02, f"{s}x")
            # The left edge at 1.5 u inside: the reduced normal leans the same way as the master's.
            m = n4[int(32 * 4), int(21.5 * 4)]
            r = n[int(32 * s), int(21.5 * s)]
            self.assertLess(float(r[0]), -0.1)
            self.assertLess(float(np.abs(r[0] - m[0])), 0.15)

    def test_gloss_comes_from_the_palette_and_is_zero_outside(self) -> None:
        _, res = common.bake_svg(rect("a", 0, 20, 20, 24, 24), CELL)
        for s in (1, 2, 4):
            g = res.arrays[s]["normal"][..., 3]
            self.assertEqual(int(px(g, 32, 32, s)), 128)  # 0.5
            self.assertEqual(int(px(g, 5, 5, s)), 0)


class Speed(unittest.TestCase):
    def test_a_4x_probe_frame_bakes_in_a_second(self) -> None:
        """ADR-0023 Decision 7.1: at most 1.0 s (the spike's was 6.6 s)."""
        src = common.source(common.PROBE_DIR)
        posed = pose.pose_frame(src.lib, src.actions[0].frames[0])
        cell = ch.Cell(0.0, 0.0, 64, 64)
        best = 1e9
        for _ in range(3):
            t = time.perf_counter()
            common.frame.bake(src.lib, src.pal, posed, cell, (4,))
            best = min(best, time.perf_counter() - t)
        self.assertLessEqual(best, 1.0, f"{best:.2f} s")


if __name__ == "__main__":
    unittest.main()
