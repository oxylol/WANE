"""palette.tres, pose.json and the noise texture (ADR-0023 Decision 1.1, 1.3, 1.7)."""

import json
import unittest

import numpy as np

from . import common
from artbuild import noise, palette, pose, svg
from artbuild import geometry as geo

LIB = svg.parse(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
    '<rect id="a" data-z="0" x="0" y="0" width="8" height="8"/>'
    '<rect id="b" data-z="1" x="8" y="0" width="8" height="8" data-tags="smear"/></svg>'
)


def pal_text(doc: dict) -> str:
    return "[gd_resource type=\"Resource\" format=3]\n\n[resource]\nmetadata/palette = " + json.dumps(doc, indent=1) + "\n"


MAT = {"lit": "#ffffff", "shadow": "#000000", "rim": "#808080"}


class Palette(unittest.TestCase):
    def test_parses_godots_dictionary_and_shares_slots_by_material(self) -> None:
        p = palette.parse(pal_text({"materials": {"m": MAT}, "parts": {"a": "m", "b": "m"}}), LIB)
        self.assertEqual((p.slot_of_part("a"), p.slot_of_part("b")), (1, 1))

    def test_slots_follow_z_order_not_file_order(self) -> None:
        doc = {"materials": {"y": MAT, "x": MAT}, "parts": {"b": "y", "a": "x"}}
        p = palette.parse(pal_text(doc), LIB)
        self.assertEqual(p.slots, ["x", "y"])  # a (z 0) first

    def test_rejects_mistakes_with_a_message(self) -> None:
        cases = {
            "has no material": {"materials": {"m": MAT}, "parts": {"a": "m"}},
            "unknown material": {"materials": {"m": MAT}, "parts": {"a": "m", "b": "n"}},
            "unknown part": {"materials": {"m": MAT}, "parts": {"a": "m", "b": "m", "c": "m"}},
            "needs lit": {"materials": {"m": {"shadow": "#000000", "rim": "#000000"}}, "parts": {"a": "m", "b": "m"}},
            "'#rrggbb'": {"materials": {"m": {**MAT, "lit": "red"}}, "parts": {"a": "m", "b": "m"}},
            "must be 0 to 1": {"materials": {"m": {**MAT, "gloss": 2}}, "parts": {"a": "m", "b": "m"}},
            "unknown field": {"materials": {"m": {**MAT, "shine": 1}}, "parts": {"a": "m", "b": "m"}},
            "overrides unknown": {"materials": {"m": MAT}, "parts": {"a": "m", "b": "m"}, "variants": {"v": {"q": {}}}},
        }
        for needle, doc in cases.items():
            with self.assertRaises(palette.PaletteError, msg=needle) as cm:
                palette.parse(pal_text(doc), LIB)
            self.assertIn(needle, str(cm.exception))

    def test_sixteen_columns_hold_fifteen_materials(self) -> None:
        body = "".join(f'<rect id="p{k}" data-z="{k}" x="{k}" y="0" width="1" height="1"/>' for k in range(16))
        lib = svg.parse(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">{body}</svg>')
        mats = {f"m{k}": MAT for k in range(16)}
        with self.assertRaises(palette.PaletteError) as cm:
            palette.parse(pal_text({"materials": mats, "parts": {f"p{k}": f"m{k}" for k in range(16)}}), lib)
        self.assertIn("15 slots", str(cm.exception))
        shared = {f"p{k}": f"m{k % 15}" for k in range(16)}
        palette.parse(pal_text({"materials": mats, "parts": shared}), lib)  # 15 materials: fine

    def test_wrong_types_are_messages_not_tracebacks(self) -> None:
        part_of = {"a": "m", "b": "m"}
        cases = {
            "'materials' and 'parts' dictionaries": {"materials": [], "parts": part_of},
            "material 'm' must be a dictionary": {"materials": {"m": 5}, "parts": part_of},
            "names a material by its string": {"materials": {"m": MAT}, "parts": {"a": 5, "b": "m"}},
            "'variants' must be a dictionary": {"materials": {"m": MAT}, "parts": part_of, "variants": []},
            "variant 'v' must be a dictionary": {"materials": {"m": MAT}, "parts": part_of, "variants": {"v": []}},
            "overrides material 'm' with a dictionary": {"materials": {"m": MAT}, "parts": part_of,
                                                          "variants": {"v": {"m": 5}}},
            "must be 0 to 1": {"materials": {"m": {**MAT, "gloss": True}}, "parts": part_of},
        }
        for needle, doc in cases.items():
            with self.assertRaises(palette.PaletteError, msg=needle) as cm:
                palette.parse(pal_text(doc), LIB)
            self.assertIn(needle, str(cm.exception))
        # The dictionary is read as strictly as a pose: no NaN, no key twice.
        for text, needle in (
            ('metadata/palette = {"materials": {"m": {"lit": "#ffffff", "shadow": "#000000", "rim": "#000000", '
             '"gloss": NaN}}, "parts": {"a": "m", "b": "m"}}', "NaN"),
            ('metadata/palette = {"materials": {"m": {"lit": "#ffffff", "lit": "#000000", "shadow": "#000000", '
             '"rim": "#000000"}}, "parts": {"a": "m", "b": "m"}}', "given twice"),
        ):
            with self.assertRaises(palette.PaletteError, msg=needle) as cm:
                palette.parse(text, LIB)
            self.assertIn(needle, str(cm.exception))

    def test_an_emissive_part_needs_a_material_that_glows(self) -> None:
        """A part tagged `emissive` whose material has no emissive colour (or strength 0) is drawn
        with no ink and no glow: it vanishes while sheet.json still reports a lit region."""
        glow = svg.parse(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
            '<rect id="a" data-z="0" x="0" y="0" width="8" height="8"/>'
            '<rect id="b" data-z="1" x="8" y="0" width="8" height="8" data-tags="eye emissive"/></svg>'
        )
        parts = {"a": "m", "b": "e"}
        lit = {**MAT, "emissive": "#ffc486"}
        palette.parse(pal_text({"materials": {"m": MAT, "e": lit}, "parts": parts}), glow)
        faint = {**lit, "emissive_strength": 0.05}
        palette.parse(pal_text({"materials": {"m": MAT, "e": faint}, "parts": parts}), glow)
        off = {**lit, "emissive_strength": 0}
        for mat, needle in ((MAT, "has no emissive colour"), (off, "emissive_strength above 0")):
            with self.assertRaises(palette.PaletteError, msg=needle) as cm:
                palette.parse(pal_text({"materials": {"m": MAT, "e": mat}, "parts": parts}), glow)
            self.assertIn(needle, str(cm.exception))
            self.assertIn("'b'", str(cm.exception))
            self.assertIn("'e'", str(cm.exception))
        # A variant may switch a glow off (closed eyes): only the base material is held to it.
        closed = {"closed": {"e": {"emissive_strength": 0}}}
        palette.parse(pal_text({"materials": {"m": MAT, "e": lit}, "parts": parts, "variants": closed}), glow)
        # A material shared with a part that does not glow is fine.
        palette.parse(pal_text({"materials": {"e": lit}, "parts": {"a": "e", "b": "e"}}), glow)

    def test_the_dictionary_may_contain_braces_in_strings(self) -> None:
        doc = {"materials": {"m": MAT}, "parts": {"a": "m", "b": "m"}, "note": "a } brace"}
        palette.parse(pal_text(doc), LIB)

    def test_no_palette_dictionary(self) -> None:
        with self.assertRaises(palette.PaletteError):
            palette.parse("[resource]\n", LIB)


class Poses(unittest.TestCase):
    DOC = {"version": 1, "actions": {"run": {"fps": 24, "loop": True, "frames": [
        {"key": True, "ticks": 2, "parts": {"a": [1, 0, 0, 1, 5, 0]}},
        {"ticks": 3, "smear": {"b": [[1, 0, 0, 1, -2, 0]]}},
    ]}}}

    def test_parse_and_pose(self) -> None:
        (act,) = pose.parse(self.DOC, LIB)
        self.assertEqual((act.name, act.fps, act.loop, len(act.frames)), ("run", 24, True, 2))
        posed = pose.pose_frame(LIB, act.frames[0])
        self.assertEqual(len(posed.pieces), 2)
        self.assertAlmostEqual(float(posed.pieces[0].polys[0][:, 0].min()), 5.0)
        self.assertEqual(posed.smear, {"b": False})
        posed2 = pose.pose_frame(LIB, act.frames[1])
        # a has one piece; b's arc (a 2 u move, at most 0.5 u a step) is swept in 4 steps: 5 poses.
        self.assertEqual(len(posed2.pieces), 6)
        self.assertEqual(posed2.smear, {"b": True})

    def test_rejects_mistakes(self) -> None:
        def bad(mutate, needle):
            doc = json.loads(json.dumps(self.DOC))
            mutate(doc)
            with self.assertRaises(pose.PoseError, msg=needle) as cm:
                pose.parse(doc, LIB)
            self.assertIn(needle, str(cm.exception))

        bad(lambda d: d.update(version=2), "version")
        bad(lambda d: d["actions"]["run"]["frames"][0]["parts"].update(zz=[1, 0, 0, 1, 0, 0]), "no part")
        bad(lambda d: d["actions"]["run"]["frames"][0]["parts"].update(a=[1, 0, 0]), "six numbers")
        bad(lambda d: d["actions"]["run"].update(fps=0), "fps")
        bad(lambda d: d["actions"]["run"]["frames"][0].update(ticks=0), "ticks")
        bad(lambda d: d["actions"]["run"].update(frames=[]), "needs frames")
        bad(lambda d: d["actions"].update({"Bad Name": d["actions"]["run"]}), "lower-case")
        bad(lambda d: d["actions"]["run"]["frames"][1]["smear"].update(b=[]), "list of affines")

    def _bad(self, mutate, needle: str) -> None:
        doc = json.loads(json.dumps(self.DOC))
        mutate(doc)
        with self.assertRaises(pose.PoseError, msg=needle) as cm:
            pose.parse(doc, LIB)
        self.assertIn(needle, str(cm.exception))

    def test_a_typo_is_an_error_not_a_default(self) -> None:
        """Frame timing is the animation spec (CLAUDE.md rule 5): `tiks` must not build as 3 ticks."""
        frame = lambda d: d["actions"]["run"]["frames"][0]  # noqa: E731
        self._bad(lambda d: frame(d).update(tiks=5), "unknown key 'tiks'")
        self._bad(lambda d: d["actions"]["run"].update(loops=False), "unknown key 'loops'")
        self._bad(lambda d: d.update(action={}), "unknown key 'action'")
        self._bad(lambda d: frame(d).update(part={}), "unknown key 'part'")

    def test_every_field_has_its_type(self) -> None:
        frame = lambda d: d["actions"]["run"]["frames"][0]  # noqa: E731
        self._bad(lambda d: frame(d).update(key="false"), "key must be true or false")
        self._bad(lambda d: frame(d).update(key=1), "key must be true or false")
        self._bad(lambda d: d["actions"]["run"].update(loop="no"), "loop must be true or false")
        self._bad(lambda d: d["actions"]["run"].update(fps=True), "fps")
        self._bad(lambda d: d["actions"]["run"].update(fps=24.0), "fps")
        self._bad(lambda d: frame(d).update(ticks=True), "ticks")
        self._bad(lambda d: frame(d).update(ticks=2.5), "ticks")
        self._bad(lambda d: frame(d).update(parts=[]), "parts must be an object")
        self._bad(lambda d: frame(d).update(smear=[]), "smear must be an object")
        self._bad(lambda d: d["actions"].update(run=[]), "must be an object")
        self._bad(lambda d: d["actions"]["run"].update(frames=[5]), "must be an object")
        self._bad(lambda d: d["actions"]["run"].update(frames="x"), "needs frames")
        self._bad(lambda d: d.update(actions=[]), "actions object")
        with self.assertRaises(pose.PoseError):
            pose.parse([], LIB)

    def test_fps_and_ticks_have_their_bounds(self) -> None:
        for fps in (1, 60):
            doc = json.loads(json.dumps(self.DOC))
            doc["actions"]["run"]["fps"] = fps
            pose.parse(doc, LIB)
        for fps in (0, 61, 6000, -1):
            self._bad(lambda d, f=fps: d["actions"]["run"].update(fps=f), "fps must be an integer 1 to 60")
        doc = json.loads(json.dumps(self.DOC))
        doc["actions"]["run"]["frames"][0]["ticks"] = 1
        pose.parse(doc, LIB)
        self._bad(lambda d: d["actions"]["run"]["frames"][0].update(ticks=0), "ticks")

    def test_an_affine_is_six_finite_numbers_that_keep_the_part(self) -> None:
        def put(m):
            return lambda d: d["actions"]["run"]["frames"][0]["parts"].update(a=m)

        for bad in ([float("nan")] * 6, [float("inf"), 0, 0, 1, 0, 0], [1, 0, 0, 1, float("-inf"), 0]):
            self._bad(put(bad), "finite")
        self._bad(put([1, 0, 0, 1, 1e9, 0]), "finite")  # off the page by a million cells
        self._bad(put([True, 0, 0, 1, 0, 0]), "six numbers")
        self._bad(put(["1", 0, 0, 1, 0, 0]), "six numbers")
        self._bad(put([0, 0, 0, 0, 5, 5]), "collapses")  # scale 0: a polygon of one point
        self._bad(put([1, 2, 2, 4, 0, 0]), "collapses")  # det 0: a line
        arc = lambda d: d["actions"]["run"]["frames"][1]["smear"].update(b=[[float("nan")] * 6])  # noqa: E731
        self._bad(arc, "finite")

    def test_the_file_may_not_hold_nan_or_a_key_twice(self) -> None:
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "pose.json"
            for text, needle in (
                ('{"version": 1, "actions": {"a": {"frames": [{"parts": {"a": [NaN, 0, 0, 1, 0, 0]}}]}}}', "NaN"),
                ('{"version": 1, "actions": {"a": {"frames": [{"parts": {"a": [Infinity, 0, 0, 1, 0, 0]}}]}}}', "Infinity"),
                ('{"version": 1, "actions": {"a": {"fps": 12, "fps": 24, "frames": [{}]}}}', "given twice"),
                ('{"version": 1, "actions": ', "not valid JSON"),
            ):
                path.write_text(text, encoding="utf-8")
                with self.assertRaises(pose.PoseError, msg=text) as cm:
                    pose.load(path, LIB)
                self.assertIn(needle, str(cm.exception))

    def test_a_pose_that_collapses_a_part_names_it(self) -> None:
        """A near-singular affine passes the parse and flattens a polygon to a point."""
        spec = pose.FrameSpec(True, 3, {"a": (1e-300, 0.0, 0.0, 1e-300, 5.0, 5.0)})
        with self.assertRaises(pose.PoseError) as cm:
            pose.pose_frame(LIB, spec)
        self.assertIn("'a'", str(cm.exception))

    def test_between_two_rotations_about_the_pivot_is_the_rotation_between(self) -> None:
        m0, m1 = geo.rotation_about(-20, 44, 39.6), geo.rotation_about(20, 44, 39.6)
        mid = pose._between(m0, m1, 0.5, (44.0, 39.6))
        self.assertTrue(np.allclose(mid, geo.rotation_about(0, 44, 39.6), atol=1e-9))
        quarter = pose._between(m0, m1, 0.25, (44.0, 39.6))
        self.assertTrue(np.allclose(quarter, geo.rotation_about(-10, 44, 39.6), atol=1e-9))

    def test_between_keeps_a_stretch_and_takes_the_short_way_round(self) -> None:
        m0 = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
        m1 = (2.0, 0.0, 0.0, 2.0, 10.0, 0.0)
        mid = pose._between(m0, m1, 0.5, (0.0, 0.0))
        self.assertTrue(np.allclose(mid, (1.5, 0.0, 0.0, 1.5, 5.0, 0.0)))
        over = pose._between(geo.rotation_about(170, 0, 0), geo.rotation_about(-170, 0, 0), 0.5, (0.0, 0.0))
        self.assertTrue(np.allclose(over, geo.rotation_about(180, 0, 0), atol=1e-9))

    def test_a_sparse_smear_arc_is_swept_into_a_ribbon(self) -> None:
        pts = np.array([[44.0, 39.6], [61.0, 22.0]])
        arc = [geo.rotation_about(-30, 44, 39.6), geo.rotation_about(30, 44, 39.6)]
        swept = pose.sweep(arc, pts, (44.0, 39.6))
        self.assertGreater(len(swept), 40)  # the tip moves 24 u: at most 0.5 u per step
        for m0, m1 in zip(swept, swept[1:]):
            jump = np.sqrt(((geo.apply(m1, pts) - geo.apply(m0, pts)) ** 2).sum(axis=1)).max()
            self.assertLessEqual(float(jump), pose.SMEAR_STEP_U + 1e-9)
        self.assertEqual((swept[0], swept[-1]), (arc[0], arc[1]))
        # Every pose of the sweep keeps the pivot where it was.
        for m in swept:
            self.assertTrue(np.allclose(geo.apply(m, pts[:1]), pts[:1], atol=1e-9))

    def test_a_dense_arc_is_left_alone(self) -> None:
        pts = np.array([[44.0, 39.6], [46.0, 39.6]])
        arc = [geo.rotation_about(0, 44, 39.6), geo.rotation_about(5, 44, 39.6)]
        self.assertEqual(len(pose.sweep(arc, pts, (44.0, 39.6))), 2)

    def test_no_file_is_one_idle_frame(self) -> None:
        (act,) = pose.load(None, LIB)
        self.assertEqual((act.name, len(act.frames)), ("idle", 1))

    def test_a_reflected_pose_stays_positively_wound(self) -> None:
        spec = pose.FrameSpec(True, 3, {"a": (-1, 0, 0, 1, 20, 0)})
        posed = pose.pose_frame(LIB, spec)
        self.assertGreater(geo.signed_area(posed.pieces[0].polys[0]), 0.0)


class Noise(unittest.TestCase):
    TEX = noise.texture()

    def test_shape_and_determinism(self) -> None:
        self.assertEqual((self.TEX.shape, self.TEX.dtype), ((256, 256, 4), np.uint8))
        self.assertTrue(np.array_equal(self.TEX, noise.texture()))
        self.assertFalse(np.array_equal(self.TEX, noise.texture(seed=24)))

    def test_it_tiles(self) -> None:
        t = self.TEX.astype(np.float64)
        interior = np.abs(np.diff(t, axis=1)).mean(axis=(0, 1))
        seam = np.abs(t[:, 0] - t[:, -1]).mean(axis=0)
        self.assertTrue((seam < interior * 2.5).all(), (seam, interior))
        seam_y = np.abs(t[0] - t[-1]).mean(axis=0)
        self.assertTrue((seam_y < np.abs(np.diff(t, axis=0)).mean(axis=(0, 1)) * 2.5).all())

    def test_each_channel_has_the_documented_scale(self) -> None:
        """The cell counts are the interface: grain is finest, wobble octave 1 the coarsest."""
        t = self.TEX.astype(np.float64)
        rough = np.abs(np.diff(t, axis=1)).mean(axis=(0, 1))  # mean step: grows with frequency
        grain, brush, wob1, wob2 = rough
        self.assertGreater(grain, brush)
        self.assertGreater(brush, wob1)
        self.assertGreater(wob2, wob1)
        for c in range(4):
            self.assertGreater(float(t[..., c].std()), 15.0)

    def test_seed_for_is_crc32_xor_the_build_seed(self) -> None:
        import zlib

        self.assertEqual(noise.seed_for("ash"), zlib.crc32(b"ash") ^ noise.BUILD_SEED)
        self.assertNotEqual(noise.seed_for("ash"), noise.seed_for("wick"))

    def test_the_committed_texture_is_the_built_one(self) -> None:
        from artbuild import assetbuild

        on_disk = assetbuild.png_pixels((common.ROOT / "assets/art/build/noise/noise.png").read_bytes())
        self.assertTrue(np.array_equal(on_disk, self.TEX))


if __name__ == "__main__":
    unittest.main()
