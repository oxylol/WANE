"""Parts that share an exact edge have no crack in the silhouette (ADR-0023 Decision 1.2, addendum
2026-10-21).

Two parts that meet along a line (abutting rects, tiles, the pieces of a rig at a joint) are one
shape: the seam is not on the outline, so S there is the distance to the union's real edge. Before
the fix a midpoint exactly on another piece's outline counted as outside it for one of the two
coincident edges (the crossing test is half-open), the other piece's edge stayed in the silhouette
set and S read -0.5 u at the seam instead of -8.

The oracle is the signed distance to the union polygon written out by hand, in plain numpy and
independent of the build's own `sdf`.
"""

from __future__ import annotations

import unittest

import numpy as np

from . import common
from artbuild import channels as ch
from artbuild import geometry as geo
from artbuild import pose, shapes

CELL = ch.Cell(0.0, 0.0, 64, 64)
S_ERR = 0.5 / ch.S_STEPS_PER_U + 1e-9


def rect(i: str, z: int, x: float, y: float, w: float, h: float, extra: str = "") -> str:
    return f'<rect id="{i}" data-z="{z}" x="{x}" y="{y}" width="{w}" height="{h}" {extra}/>'


def polygon_sd(points: np.ndarray, verts: list[tuple[float, float]]) -> np.ndarray:
    """Signed distance (outside positive) to a simple polygon, by even-odd ray casting and the
    brute-force nearest segment."""
    a = np.array(verts, dtype=np.float64)
    b = np.roll(a, -1, axis=0)
    px, py = points[:, 0:1], points[:, 1:2]
    ay, by = a[None, :, 1], b[None, :, 1]
    straddle = (ay <= py) != (by <= py)
    xs = a[None, :, 0] + (py - ay) * (b[None, :, 0] - a[None, :, 0]) / np.where(by == ay, 1.0, by - ay)
    inside = ((straddle & (xs > px)).sum(axis=1) % 2) == 1
    e = b - a
    l2 = (e * e).sum(axis=1)
    t = np.clip(((px - a[None, :, 0]) * e[None, :, 0] + (py - a[None, :, 1]) * e[None, :, 1]) / l2, 0.0, 1.0)
    dx = px - (a[None, :, 0] + t * e[None, :, 0])
    dy = py - (a[None, :, 1] + t * e[None, :, 1])
    d = np.sqrt(dx * dx + dy * dy).min(axis=1)
    return np.where(inside, -d, d)


def texel_centres(scale: int) -> np.ndarray:
    ys, xs = np.mgrid[0 : 64 * scale, 0 : 64 * scale]
    return np.stack([(xs.ravel() + 0.5) / scale, (ys.ravel() + 0.5) / scale], axis=1)


class SharedEdgeCase(unittest.TestCase):
    def assert_union_outline(self, body: str, union: list[tuple[float, float]], frame_spec=None, label="") -> None:
        """S matches the signed distance to the union polygon on every texel it can see (|S| < 7.9)."""
        _, res = common.bake_svg(body, CELL, frame_spec=frame_spec)
        for s in (1, 2, 4):
            got = common.decode_s(res.arrays[s]["shape"]).ravel()
            want = polygon_sd(texel_centres(s), union)
            inband = np.abs(want) < 7.9
            err = np.abs(got - np.clip(want, -8.0, 7.9))[inband]
            worst = int(np.argmax(err))
            where = texel_centres(s)[inband][worst]
            self.assertLessEqual(
                float(err.max()),
                S_ERR,
                f"{label} at {s}x: S off by {float(err.max()):.3f} u near ({where[0]:.3f}, {where[1]:.3f})",
            )


class Abutting(SharedEdgeCase):
    # Two rects sharing the line x = 22 (or y = 24), 20 u long, so the seam is 10 u from every
    # outer edge and S there is the clamp, -8 (the finding measured -0.5).
    VERTICAL = [(12.0, 14.0), (32.0, 14.0), (32.0, 34.0), (12.0, 34.0)]
    HORIZONTAL = [(12.0, 14.0), (32.0, 14.0), (32.0, 34.0), (12.0, 34.0)]

    def test_a_vertical_seam_is_not_a_silhouette_edge_whichever_part_is_in_front(self) -> None:
        for za, zb in ((0, 1), (1, 0)):
            body = rect("a", za, 12, 14, 10, 20) + rect("b", zb, 22, 14, 10, 20)
            self.assert_union_outline(body, self.VERTICAL, label=f"z {za},{zb}")
            _, res = common.bake_svg(body, CELL)
            for s in (1, 2, 4):
                row = common.decode_s(res.arrays[s]["shape"])[int(24.1 * s)]
                seam = row[int(20 * s) : int(24 * s)]  # 8.5 u or more from the outer edges
                self.assertLessEqual(float(seam.max()), -7.9, f"z {za},{zb} at {s}x")

    def test_a_horizontal_seam_is_not_a_silhouette_edge_whichever_part_is_in_front(self) -> None:
        for za, zb in ((0, 1), (1, 0)):
            body = rect("a", za, 14, 12, 20, 10) + rect("b", zb, 14, 22, 20, 10)
            union = [(14.0, 12.0), (34.0, 12.0), (34.0, 32.0), (14.0, 32.0)]
            self.assert_union_outline(body, union, label=f"z {za},{zb}")

    def test_the_seam_is_the_front_parts_visible_edge_and_only_that(self) -> None:
        for za, zb, front_left in ((0, 1, False), (1, 0, True)):
            body = rect("a", za, 12, 14, 10, 20) + rect("b", zb, 22, 14, 10, 20)
            _, res = common.bake_svg(body, CELL)
            s = 4
            shape = res.arrays[s]["shape"]
            row = int(24.125 * s)
            left, right = shape[row, int(21.625 * s)], shape[row, int(22.375 * s)]
            # The joint line is still drawn, once, at x = 22: U is the distance to it from both sides.
            self.assertAlmostEqual(float(common.decode_u(left)), 0.375, delta=0.04)
            self.assertAlmostEqual(float(common.decode_u(right)), 0.375, delta=0.04)
            # It belongs to the front part: 255 inside it, 0 on the back part's side of it.
            self.assertEqual((int(left[2]), int(right[2])), (255, 0) if front_left else (0, 255))

    def test_the_cut_edges_carry_no_seam_in_the_silhouette_set(self) -> None:
        lib, _ = common.bake_svg(rect("a", 0, 12, 14, 10, 20) + rect("b", 1, 22, 14, 10, 20), CELL)
        geom = shapes.build(lib, pose.pose_frame(lib, pose.FrameSpec(True, 3)))
        sil = geom.silhouette
        on_seam = (np.abs(sil.a[:, 0] - 22.0) < 1e-6) & (np.abs(sil.b[:, 0] - 22.0) < 1e-6)
        self.assertFalse(on_seam.any(), "a silhouette segment lies on the seam")
        # Their total length is the union's perimeter: 2 * (20 + 20).
        length = float(np.hypot(*(sil.b - sil.a).T).sum())
        self.assertAlmostEqual(length, 80.0, places=6)
        vis = geom.visible
        on_seam = (np.abs(vis.a[:, 0] - 22.0) < 1e-6) & (np.abs(vis.b[:, 0] - 22.0) < 1e-6)
        self.assertEqual(set(vis.part[on_seam].tolist()), {1}, "the seam is drawn once, by the front part")

    def test_a_grid_of_tiles_is_one_shape(self) -> None:
        # Nine 8 u tiles, each its own part: four tiles meet at every inner corner.
        body = "".join(rect(f"t{r}{c}", r * 3 + c, 20 + 8 * c, 20 + 8 * r, 8, 8) for r in range(3) for c in range(3))
        union = [(20.0, 20.0), (44.0, 20.0), (44.0, 44.0), (20.0, 44.0)]
        self.assert_union_outline(body, union, label="tiles")
        lib, _ = common.bake_svg(body, CELL)
        geom = shapes.build(lib, pose.pose_frame(lib, pose.FrameSpec(True, 3)))
        length = float(np.hypot(*(geom.silhouette.b - geom.silhouette.a).T).sum())
        self.assertAlmostEqual(length, 96.0, places=6)

    def test_a_seam_under_a_group_rotation_is_still_one_shape(self) -> None:
        body = '<g transform="rotate(30 32 32)">' + rect("a", 0, 12, 14, 10, 20) + rect("b", 1, 22, 14, 10, 20) + "</g>"
        m = geo.rotation_about(30.0, 32.0, 32.0)
        union = [tuple(p) for p in geo.apply(m, np.array([(12.0, 14.0), (32.0, 14.0), (32.0, 34.0), (12.0, 34.0)]))]
        self.assert_union_outline(body, union, label="rotated group")


class TJunction(SharedEdgeCase):
    # A is 12..22 by 14..34; B butts against its right edge over y 19..29 only, so the edge is
    # shared in the middle and exposed above and below.
    UNION = [(12, 14), (22, 14), (22, 19), (32, 19), (32, 29), (22, 29), (22, 34), (12, 34)]

    def test_the_shared_stretch_is_interior_and_the_exposed_stretches_stay_on_the_outline(self) -> None:
        for za, zb in ((0, 1), (1, 0)):
            body = rect("a", za, 12, 14, 10, 20) + rect("b", zb, 22, 19, 10, 10)
            self.assert_union_outline(body, self.UNION, label=f"z {za},{zb}")
            _, res = common.bake_svg(body, CELL)
            shape = res.arrays[4]["shape"]
            # Along the seam the nearest outline is the notch corner, 4.875 u from (22.125, 24.125).
            self.assertAlmostEqual(float(common.decode_s(shape[int(24.125 * 4), int(22.125 * 4)])), -4.875, delta=0.04)
            # The exposed stretch above B is still an edge: 0.125 u inside it.
            self.assertAlmostEqual(float(common.decode_s(shape[int(16.125 * 4), int(21.875 * 4)])), -0.125, delta=0.04)

    def test_a_shorter_part_on_the_other_side_and_on_a_horizontal_edge(self) -> None:
        # The long part is B this time, and the shared edge is horizontal (A's bottom, y = 34).
        body = rect("a", 0, 19, 24, 10, 10) + rect("b", 1, 12, 34, 24, 10)
        union = [(19, 24), (29, 24), (29, 34), (36, 34), (36, 44), (12, 44), (12, 34), (19, 34)]
        self.assert_union_outline(body, union, label="horizontal T")


class RotatedPart(SharedEdgeCase):
    # Rotating by 90 degrees leaves coordinates 1e-15 off (cos 90 is 6e-17): the shared edge is
    # shared to rounding, not to the bit.
    UNION = [(12, 14), (22, 14), (22, 19), (34, 19), (34, 29), (22, 29), (22, 34), (12, 34)]

    def test_an_svg_transform(self) -> None:
        # Before the turn B is 10 wide and 12 tall about (28, 24); after it, 12 wide and 10 tall.
        body = rect("a", 0, 12, 14, 10, 20) + rect("b", 1, 23, 18, 10, 12, 'transform="rotate(90 28 24)"')
        self.assert_union_outline(body, self.UNION, label="transform")

    def test_a_pose(self) -> None:
        body = rect("a", 0, 12, 14, 10, 20) + rect("b", 1, 23, 18, 10, 12)
        spec = pose.FrameSpec(True, 3, {"b": geo.rotation_about(90.0, 28.0, 24.0)})
        self.assert_union_outline(body, self.UNION, frame_spec=spec, label="pose")

    def test_the_other_three_quarter_turns_and_a_half_turn(self) -> None:
        for deg in (180.0, 270.0, -90.0):
            # A rect with a half turn about the centre of the slot it must fill.
            if deg == 180.0:
                body = rect("a", 0, 12, 14, 10, 20) + rect("b", 1, 22, 19, 12, 10)
                spec = pose.FrameSpec(True, 3, {"b": geo.rotation_about(deg, 28.0, 24.0)})
            else:
                body = rect("a", 0, 12, 14, 10, 20) + rect("b", 1, 23, 18, 10, 12)
                spec = pose.FrameSpec(True, 3, {"b": geo.rotation_about(deg, 28.0, 24.0)})
            self.assert_union_outline(body, self.UNION, frame_spec=spec, label=f"{deg} degrees")

    def test_both_parts_rotated_together_about_an_arbitrary_point(self) -> None:
        body = rect("a", 0, 12, 14, 10, 20) + rect("b", 1, 22, 19, 10, 10)
        m = geo.rotation_about(37.0, 20.0, 30.0)
        spec = pose.FrameSpec(True, 3, {"a": m, "b": m})
        union = [tuple(p) for p in geo.apply(m, np.array([(12.0, 14.0), (22.0, 14.0), (22.0, 19.0), (32.0, 19.0), (32.0, 29.0), (22.0, 29.0), (22.0, 34.0), (12.0, 34.0)]))]
        self.assert_union_outline(body, union, frame_spec=spec, label="37 degrees")


class SameSidedEdges(SharedEdgeCase):
    def test_two_parts_that_share_a_boundary_edge_and_lie_on_the_same_side_keep_it(self) -> None:
        # B sits in A's top-left corner: their top and left edges coincide and both parts lie below
        # and right of them. That is the union's outline, not a seam.
        body = rect("a", 0, 12, 14, 20, 20) + rect("b", 1, 12, 14, 10, 10)
        union = [(12.0, 14.0), (32.0, 14.0), (32.0, 34.0), (12.0, 34.0)]
        self.assert_union_outline(body, union, label="corner")
        _, res = common.bake_svg(body, CELL)
        shape = res.arrays[4]["shape"]
        self.assertAlmostEqual(float(common.decode_s(shape[int(16.125 * 4), int(14.125 * 4)])), -2.125, delta=0.04)
        self.assertAlmostEqual(float(common.decode_s(shape[int(13.875 * 4), int(14.125 * 4)])), 0.125, delta=0.04)

    def test_the_back_part_is_hidden_by_a_front_edge_on_the_same_line(self) -> None:
        # B sits in a corner of A, so a top edge and a bottom edge coincide in turn. The winding
        # rule calls one of those on the outline inside B and the other outside it; the build must
        # not: A's edge is drawn only where B does not already draw the same line.
        for name, b_y, edge_y in (("top", 14, 14.0), ("bottom", 24, 34.0)):
            lib, _ = common.bake_svg(rect("a", 0, 12, 14, 20, 20) + rect("b", 1, 12, b_y, 10, 10), CELL)
            geom = shapes.build(lib, pose.pose_frame(lib, pose.FrameSpec(True, 3)))
            vis = geom.visible
            on_line = (np.abs(vis.a[:, 1] - edge_y) < 1e-6) & (np.abs(vis.b[:, 1] - edge_y) < 1e-6)
            a_edge = on_line & (vis.part == 0)
            xs = np.concatenate([vis.a[a_edge][:, 0], vis.b[a_edge][:, 0]])
            self.assertEqual((float(xs.min()), float(xs.max())), (22.0, 32.0), name)
            b_edge = on_line & (vis.part == 1)
            xs = np.concatenate([vis.a[b_edge][:, 0], vis.b[b_edge][:, 0]])
            self.assertEqual((float(xs.min()), float(xs.max())), (12.0, 22.0), name)


if __name__ == "__main__":
    unittest.main()
