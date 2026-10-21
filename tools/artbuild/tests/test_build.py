"""Determinism, sheets, metadata and the byte-identity check (ADR-0023 Decision 1.5, 1.6, 1.8, 6.1)."""

import contextlib
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

from . import common
from artbuild import assetbuild, build, manifest, pack, schema
from artbuild import channels as ch

VERSIONS = assetbuild.pinned_versions(common.ROOT / "tools" / "requirements.txt")


def build_files(path: Path, **kw) -> dict[str, bytes]:
    return assetbuild.build_asset(path, versions=VERSIONS, **kw)


class Determinism(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.first = build_files(common.CANDLE_DIR)

    def test_two_builds_are_byte_identical(self) -> None:
        again = build_files(common.CANDLE_DIR)
        self.assertEqual(sorted(again), sorted(self.first))
        for name, data in self.first.items():
            self.assertEqual(again[name], data, name)

    def test_the_process_pool_changes_nothing(self) -> None:
        parallel = build_files(common.CANDLE_DIR, jobs=3)
        for name, data in self.first.items():
            self.assertEqual(parallel[name], data, name)

    def test_the_cache_changes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cold = build_files(common.CANDLE_DIR, cache_dir=Path(tmp))
            self.assertTrue(list(Path(tmp).glob("*.npz")), "the cold build filled the cache")
            warm = build_files(common.CANDLE_DIR, cache_dir=Path(tmp))
            for name, data in self.first.items():
                self.assertEqual(cold[name], data, name)
                self.assertEqual(warm[name], data, name)

    def test_a_damaged_cache_entry_is_rebuilt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            build_files(common.CANDLE_DIR, cache_dir=Path(tmp))
            victim = sorted(Path(tmp).glob("*.npz"))[0]
            victim.write_bytes(b"not an npz")
            again = build_files(common.CANDLE_DIR, cache_dir=Path(tmp))
            self.assertEqual(again["candle_stump.sheet.json"], self.first["candle_stump.sheet.json"])

    def test_a_changed_source_changes_the_output_and_the_hash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            dst = Path(tmp) / "candle_stump"
            shutil.copytree(common.CANDLE_DIR, dst)
            svg = dst / "parts.svg"
            svg.write_text(svg.read_text().replace("M35.6 15.6", "M35.7 15.6"))
            changed = build_files(dst)
            self.assertNotEqual(changed["candle_stump.sheet.json"], self.first["candle_stump.sheet.json"])
            a = json.loads(changed["candle_stump.sheet.json"])["source_sha256"]
            b = json.loads(self.first["candle_stump.sheet.json"])["source_sha256"]
            self.assertNotEqual(a, b)

    def test_png_files_carry_no_ancillary_chunks(self) -> None:
        for name, data in self.first.items():
            if name.endswith(".png"):
                chunks = []
                pos = 8
                while pos < len(data):
                    n = int.from_bytes(data[pos : pos + 4], "big")
                    chunks.append(data[pos + 4 : pos + 8])
                    pos += 12 + n
                self.assertEqual(set(chunks), {b"IHDR", b"IDAT", b"IEND"}, name)


class Sheets(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.files = build_files(common.CANDLE_DIR, masters=True)
        cls.sheet = json.loads(cls.files["candle_stump.sheet.json"])

    def test_metadata_validates_against_the_schema(self) -> None:
        self.assertEqual(schema.validate(self.sheet, schema.load_schema()), [])

    def test_the_schema_rejects_what_it_should(self) -> None:
        bad = json.loads(json.dumps(self.sheet))
        del bad["actions"]["idle"]["frames"][0]["silhouette_box"]
        bad["actions"]["idle"]["frames"][0]["ticks"] = 0
        bad["surplus"] = 1
        bad["parts"][0]["tags"].append("glow")
        problems = " ".join(schema.validate(bad, schema.load_schema()))
        for word in ("silhouette_box", "ticks", "surplus", "glow"):
            self.assertIn(word, problems)

    def test_json_has_no_nan_and_neither_has_a_sheet(self) -> None:
        """A bare NaN is not JSON: Godot's parser cannot read the sheet that holds one."""
        for bad in (float("nan"), float("inf"), float("-inf")):
            self.assertTrue(schema.validate(bad, {"type": "number"}), bad)
            self.assertTrue(schema.validate([bad], {"type": "array", "items": {"type": ["number", "null"]}}), bad)
        self.assertEqual(schema.validate(1.5, {"type": "number"}), [])
        self.assertEqual(schema.validate(3, {"type": "number"}), [])
        with mock.patch.object(assetbuild, "sheet_json", return_value={"x": float("nan")}):
            with self.assertRaises(ValueError):
                build_files(common.CANDLE_DIR)

    def test_files_per_scale_and_the_masters_flag(self) -> None:
        for s in (1, 2, 4):
            for kind in ("shape", "normal", "parts"):
                self.assertIn(f"candle_stump@{s}x.{kind}.png", self.files)
        self.assertIn("candle_stump.palette.png", self.files)
        plain = build_files(common.CANDLE_DIR)
        self.assertFalse([n for n in plain if "@4x" in n])
        for name, data in plain.items():  # the masters change nothing else
            self.assertEqual(self.files[name], data, name)

    def test_rects_lie_inside_the_pages_and_do_not_overlap(self) -> None:
        sizes = {p["page"]: p["size_u"] for p in self.sheet["pages"]}
        for s in (1, 2, 4):
            seen: list[tuple[int, int, int, int, int]] = []
            for act in self.sheet["actions"].values():
                for fr in act["frames"]:
                    x, y, w, h = fr["rect"][str(s)]
                    pw, ph = sizes[fr["page"]]
                    self.assertLessEqual(x + w, pw * s)
                    self.assertLessEqual(y + h, ph * s)
                    for (px_, py_, pw_, ph_, pg) in seen:
                        if pg == fr["page"]:
                            self.assertTrue(x >= px_ + pw_ or px_ >= x + w or y >= py_ + ph_ or py_ >= y + h)
                    seen.append((x, y, w, h, fr["page"]))

    def test_atlas_cells_are_the_baked_frames(self) -> None:
        for ai, (name, act) in enumerate(self.sheet["actions"].items()):
            for fi, fr in enumerate(act["frames"]):
                cell, res = common.baked(common.CANDLE_DIR, ai, fi)
                for s in (1, 2, 4):
                    x, y, w, h = fr["rect"][str(s)]
                    for kind in ("shape", "normal", "parts"):
                        atlas = assetbuild.png_pixels(self.files[f"candle_stump@{s}x.{kind}.png"])
                        self.assertTrue(np.array_equal(atlas[y : y + h, x : x + w], res.arrays[s][kind]),
                                        f"{name} {fi} {s}x {kind}")

    def test_cells_are_snapped_padded_and_hold_every_frame(self) -> None:
        for name, act in self.sheet["actions"].items():
            w, h = act["cell_u"]
            cox, coy = act["cell_origin_u"]
            self.assertEqual((w % 4, h % 4, cox % 4, coy % 4), (0, 0, 0.0, 0.0), name)
            for fr in act["frames"]:
                x0, y0, x1, y1 = fr["silhouette_box"]
                # The silhouette sits inside the cell with at least the 8 u padding all round.
                self.assertGreaterEqual(cox + x0, pack.PAD_U)
                self.assertGreaterEqual(coy + y0, pack.PAD_U)
                self.assertGreaterEqual(w - (cox + x1), pack.PAD_U)
                self.assertGreaterEqual(h - (coy + y1), pack.PAD_U)

    def test_the_padding_keeps_the_s_range_inside_the_cell(self) -> None:
        """Linear filtering at a cell edge must never read a neighbour's silhouette: S is
        clamped outside the cell's padding, so the outermost texel row is far outside."""
        for ai in range(len(self.sheet["actions"])):
            _, res = common.baked(common.CANDLE_DIR, ai, 0)
            for s in (1, 4):
                sh = res.arrays[s]["shape"]
                rim = np.concatenate([sh[0], sh[-1], sh[:, 0], sh[:, -1]])
                self.assertGreater(int(rim[:, 0].min()), ch.S_ZERO + 6 * ch.S_STEPS_PER_U)

    def test_tagged_parts_report_boxes_and_the_ember_reports_a_region(self) -> None:
        fr = self.sheet["actions"]["idle"]["frames"][0]
        tagged = {b["part"]: b for b in fr["part_boxes"]}
        self.assertEqual(sorted(tagged), ["flame", "pool", "stump"])
        (reg,) = fr["emissive_regions"]
        self.assertEqual((reg["part"], reg["kind"]), ("flame", "ember"))
        fb = tagged["flame"]["box"]
        self.assertAlmostEqual(reg["centre"][0], (fb[0] + fb[2]) / 2, places=3)
        flick = self.sheet["actions"]["flicker"]["frames"]
        self.assertNotEqual(flick[0]["part_boxes"], flick[1]["part_boxes"])  # the pose moved the flame
        self.assertEqual([f["ticks"] for f in flick], [5, 5, 5])

    def test_a_blade_reports_its_tip_through_every_pose_and_nothing_else_does(self) -> None:
        """The review draws the blade's arc through `tip`: the main pose's vertex farthest from the
        posed pivot, not an end of the smear (the box corner it replaced was not a point of the
        blade)."""
        src = common.source(common.PROBE_DIR)
        swing = next(i for i, a in enumerate(src.actions) if a.name == "swing")
        tips = []
        for index in range(len(src.actions[swing].frames)):
            _, res = common.baked(common.PROBE_DIR, swing, index, (1,))
            by_part = {b["part"]: b for b in res.meta["part_boxes"]}
            self.assertEqual([k for k, b in by_part.items() if "tip" in b], ["blade"])
            tip = by_part["blade"]["tip"]
            x0, y0, x1, y1 = by_part["blade"]["box"]
            # Inside the blade's box (which the smear sweep may widen), on the arc's far end.
            self.assertTrue(x0 - 1e-3 <= tip[0] <= x1 + 1e-3 and y0 - 1e-3 <= tip[1] <= y1 + 1e-3)
            tips.append(tip)
        self.assertGreater(len(set(map(tuple, tips))), 1)  # the blade moved, so did its tip
        self.assertTrue(all("tip" not in b for f in self.sheet["actions"]["idle"]["frames"] for b in f["part_boxes"]))

    def test_palette_image_rows_and_slots(self) -> None:
        pal = assetbuild.png_pixels(self.files["candle_stump.palette.png"])
        self.assertEqual(pal.shape, (8, 16, 4))  # base and dusk, four rows each
        self.assertEqual(self.sheet["palette"]["variants"], ["base", "dusk"])
        self.assertEqual([s["material"] for s in self.sheet["palette"]["slots"]], ["wax", "soot", "flame"])
        self.assertEqual(tuple(pal[0, 1]), (0xE2, 0xD8, 0xBA, 255))  # slot 1 wax, lit
        self.assertEqual(tuple(pal[1, 1]), (0x5C, 0x50, 0x48, 255))  # shadow
        self.assertEqual(tuple(pal[4, 1]), (0xB8, 0xA8, 0xB8, 255))  # the dusk variant's lit value
        self.assertEqual(tuple(pal[5, 1]), (0x3A, 0x30, 0x40, 255))
        self.assertEqual(tuple(pal[2, 1]), tuple(pal[6, 1]))  # an unchanged field carries over
        self.assertEqual(tuple(pal[3, 3]), (0xFF, 0xBE, 0x78, 255))  # the flame's emissive, strength 1
        self.assertEqual(int(pal[3, 1, 3]), 0)  # wax does not glow
        self.assertEqual(tuple(pal[:, 0].ravel()), (0,) * 32)  # column 0 is "no part"
        parts_by_id = {p["id"]: p["index"] for p in self.sheet["parts"]}
        self.assertEqual(parts_by_id, {"pool": 1, "stump": 1, "wick": 2, "flame": 3})

    def test_probe_smear_and_actions(self) -> None:
        files = build_files(common.PROBE_DIR)
        sheet = json.loads(files["probe.sheet.json"])
        self.assertEqual(schema.validate(sheet, schema.load_schema()), [])
        swing = sheet["actions"]["swing"]["frames"]
        self.assertEqual([f["smear"] for f in swing], [{"blade": False}, {"blade": True}, {"blade": False}])
        self.assertEqual([f["key"] for f in swing], [True, False, True])
        self.assertFalse(sheet["actions"]["swing"]["loop"])


class Layout(unittest.TestCase):
    def test_actions_start_new_rows_and_wrap_at_the_page_width(self) -> None:
        a = ch.Cell(0, 0, 400, 300)
        b = ch.Cell(0, 0, 500, 100)
        slots, sizes = pack.layout([(a, 7), (b, 2)])
        self.assertEqual([(s.page, s.x, s.y) for s in slots[0]],
                         [(0, 0, 0), (0, 400, 0), (0, 800, 0), (0, 1200, 0), (0, 1600, 0), (0, 0, 300), (0, 400, 300)])
        self.assertEqual([(s.page, s.x, s.y) for s in slots[1]], [(0, 0, 600), (0, 500, 600)])
        self.assertEqual(sizes, [(2000, 700)])

    def test_a_full_page_starts_the_next(self) -> None:
        slots, sizes = pack.layout([(ch.Cell(0, 0, 1000, 1500), 2), (ch.Cell(0, 0, 1000, 1000), 1)])
        self.assertEqual([(s.page, s.x, s.y) for s in slots[0]], [(0, 0, 0), (0, 1000, 0)])
        self.assertEqual([(s.page, s.x, s.y) for s in slots[1]], [(1, 0, 0)])
        self.assertEqual(len(sizes), 2)
        self.assertEqual(pack.page_suffix(0), "")
        self.assertEqual(pack.page_suffix(2), ".p2")

    def test_pages_never_exceed_4096_px_at_2x(self) -> None:
        slots, sizes = pack.layout([(ch.Cell(0, 0, 200, 300), 90)])
        for w, h in sizes:
            self.assertLessEqual(w * 2, 4096)
            self.assertLessEqual(h * 2, 4096)

    def test_an_oversized_cell_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            pack.layout([(ch.Cell(0, 0, 3000, 100), 1)])

    def test_action_cell_snaps_outward_from_the_feet_pivot(self) -> None:
        cell = pack.action_cell((32.0, 61.0), [(21.0, 1.2, 61.5, 61.0), (25.0, -3.0, 70.1, 61.0)])
        # Left: 32 - 21 = 11 -> 12, plus 8; right: 70.1 - 32 = 38.1 -> 40, plus 8.
        self.assertEqual((cell.x0, cell.w), (32 - 12 - 8, 12 + 40 + 16))
        # Top: 61 - (-3) = 64 -> 64, plus 8; bottom: 0 -> 0, plus 8.
        self.assertEqual((cell.y0, cell.h), (61 - 64 - 8, 64 + 16))


class CheckMode(unittest.TestCase):
    """build.py --check: byte identity of the committed output, against tampering."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        shutil.copytree(common.CANDLE_DIR, root / "src" / "candle_stump")
        cls.root = root
        cls.r = build.Root("src", "out", noise=True)
        files, built = build.build_root(root, cls.r, None, masters=False, jobs=1, cache_dir=None, versions=VERSIONS)
        build.write_root(root, cls.r, files, built)
        cls.built = (files, built)  # the sources never change, so every test compares to this one build
        cls.built_one = build.build_root(root, cls.r, ["candle_stump"], masters=False, jobs=1, cache_dir=None,
                                         versions=VERSIONS)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tmp.cleanup()

    def fresh(self):
        return dict(self.built[0]), list(self.built[1])

    def problems(self) -> list[str]:
        files, built = self.fresh()
        return build.check_root(self.root, self.r, files, built)

    def problems_of_one(self) -> list[str]:
        """`build.py --check candle_stump`: the same tree, a build of one asset."""
        files, built = self.built_one
        return build.check_root(self.root, self.r, dict(files), list(built))

    def out(self, *parts: str) -> Path:
        return self.root.joinpath("out", *parts)

    def test_a_clean_tree_passes(self) -> None:
        files, built = self.fresh()
        self.assertEqual(build.check_root(self.root, self.r, files, built), [])
        self.assertIn("noise/noise.png", files)

    def test_a_hand_edited_render_fails_and_a_rebuild_repairs_it(self) -> None:
        target = self.root / "out" / "candle_stump" / "candle_stump@1x.shape.png"
        original = target.read_bytes()
        arr = assetbuild.png_pixels(original).copy()
        arr[10, 10, 0] ^= 1
        target.write_bytes(pack.png_bytes(arr))
        try:
            files, built = self.fresh()
            problems = build.check_root(self.root, self.r, files, built)
            self.assertTrue(any("differs from a fresh build" in p and "shape" in p for p in problems), problems)
            self.assertFalse(any("manifest line is stale" in p for p in problems))
        finally:
            target.write_bytes(original)
        files, built = self.fresh()
        self.assertEqual(build.check_root(self.root, self.r, files, built), [])

    def test_a_stray_file_and_a_stale_manifest_fail(self) -> None:
        stray = self.root / "out" / "candle_stump" / "painted_over.png"
        stray.write_bytes(b"x")
        mpath = self.root / "out" / manifest.NAME
        original = mpath.read_bytes()
        doc = json.loads(original)
        doc["files"]["candle_stump/candle_stump@1x.parts.png"] = "0" * 64
        mpath.write_bytes(json.dumps(doc).encode())
        try:
            files, built = self.fresh()
            problems = " | ".join(build.check_root(self.root, self.r, files, built))
            self.assertIn("not build output", problems)
            self.assertIn("manifest line is stale", problems)
        finally:
            stray.unlink()
            mpath.write_bytes(original)

    def test_godots_import_files_are_not_strays_and_a_missing_file_fails(self) -> None:
        imp = self.root / "out" / "candle_stump" / "candle_stump@1x.shape.png.import"
        imp.write_text("[remap]\n")
        victim = self.root / "out" / "candle_stump" / "candle_stump@2x.normal.png"
        saved = victim.read_bytes()
        victim.unlink()
        try:
            files, built = self.fresh()
            problems = " | ".join(build.check_root(self.root, self.r, files, built))
            self.assertNotIn(".import", problems)
            self.assertIn("missing", problems)
        finally:
            victim.write_bytes(saved)
            imp.unlink()

    # --- what review 2 found: --check looked only inside the folders of the assets it built -----

    def test_a_stock_picture_in_a_new_folder_fails(self) -> None:
        stock = self.out("stock", "wax_stock.png")
        stock.parent.mkdir()
        stock.write_bytes((self.out("candle_stump", "candle_stump@1x.shape.png")).read_bytes())
        try:
            self.assertTrue(any("not build output" in p and "stock/wax_stock.png" in p for p in self.problems()))
            partial = self.problems_of_one()  # a check of one asset sees it too
            self.assertTrue(any("stock/wax_stock.png" in p for p in partial), partial)
        finally:
            stock.unlink()
            stock.parent.rmdir()
        self.assertEqual(self.problems(), [])

    def test_a_picture_at_the_out_root_fails(self) -> None:
        stray = self.out("readme.png")
        stray.write_bytes(b"x")
        try:
            self.assertTrue(any("not build output" in p and "readme.png" in p for p in self.problems()))
        finally:
            stray.unlink()

    def test_a_copied_build_folder_with_no_source_fails(self) -> None:
        ghost = self.out("ghost")
        shutil.copytree(self.out("candle_stump"), ghost)
        try:
            problems = " | ".join(self.problems())
            self.assertIn("out/ghost/candle_stump.sheet.json", problems)
        finally:
            shutil.rmtree(ghost)

    def test_a_deleted_source_leaves_nothing_unflagged(self) -> None:
        """The source is gone: its committed renders and its manifest lines are orphans."""
        src = self.root / "src" / "candle_stump"
        hidden = self.root / "src_gone"
        src.rename(hidden)
        try:
            files, built = build.build_root(self.root, self.r, None, masters=False, jobs=1, cache_dir=None,
                                            versions=VERSIONS)
            self.assertEqual(built, [])
            problems = build.check_root(self.root, self.r, files, built)
            text = " | ".join(problems)
            self.assertIn("manifest lists a file of an asset with no source: out/candle_stump/", text)
            self.assertIn("not build output (renders are never hand-edited): out/candle_stump/candle_stump@1x.shape.png",
                          text)
            self.assertNotIn("noise", text)  # the noise has its source in the build itself
        finally:
            hidden.rename(src)
        self.assertEqual(self.problems(), [])

    def test_a_partial_check_does_not_blame_the_assets_it_did_not_build(self) -> None:
        files, built = build.build_root(self.root, self.r, ["noise"], masters=False, jobs=1, cache_dir=None,
                                        versions=VERSIONS)
        self.assertEqual(built, [])
        self.assertEqual(list(files), ["noise/noise.png"])
        self.assertEqual(build.check_root(self.root, self.r, files, built), [])

    def test_a_chunk_added_by_hand_fails_but_another_deflate_stream_does_not(self) -> None:
        import struct
        import zlib

        def chunks(data: bytes) -> list[tuple[bytes, bytes]]:
            pos, out = 8, []
            while pos < len(data):
                n = struct.unpack(">I", data[pos : pos + 4])[0]
                out.append((data[pos + 4 : pos + 8], data[pos + 8 : pos + 8 + n]))
                pos += 12 + n
            return out

        def png(parts: list[tuple[bytes, bytes]]) -> bytes:
            b = b"\x89PNG\r\n\x1a\n"
            for kind, body in parts:
                b += struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
            return b

        target = self.out("candle_stump", "candle_stump@1x.shape.png")
        original = target.read_bytes()
        parts = chunks(original)
        try:
            raw = zlib.decompress(b"".join(body for kind, body in parts if kind == b"IDAT"))
            other = [(k, b) for k, b in parts if k != b"IDAT"]
            other.insert(1, (b"IDAT", zlib.compress(raw, 1)))
            target.write_bytes(png(other))  # the same pixels through another zlib
            self.assertEqual(self.problems(), [])
            tagged = [parts[0], (b"tEXt", b"Comment\x00painted by hand"), *parts[1:]]
            target.write_bytes(png(tagged))  # the same pixels with a chunk that holds anything
            self.assertTrue(any("differs from a fresh build" in p and "shape" in p for p in self.problems()))
            target.write_bytes(original + b"trailing bytes")
            self.assertTrue(any("differs from a fresh build" in p for p in self.problems()))
        finally:
            target.write_bytes(original)
        self.assertEqual(self.problems(), [])

    def test_a_corrupt_picture_or_manifest_is_a_message(self) -> None:
        target = self.out("candle_stump", "candle_stump@2x.normal.png")
        original = target.read_bytes()
        mpath = self.out(manifest.NAME)
        saved = mpath.read_bytes()
        try:
            damaged = bytearray(original)
            damaged[len(damaged) // 2] ^= 0xFF
            target.write_bytes(bytes(damaged))
            self.assertTrue(any("differs from a fresh build" in p and "normal" in p for p in self.problems()))
            target.write_bytes(b"not a png at all")
            self.assertTrue(any("differs from a fresh build" in p for p in self.problems()))
            target.write_bytes(original)
            mpath.write_bytes(b"{ not json")
            self.assertTrue(any(manifest.NAME in p and "not valid" in p for p in self.problems()))
            mpath.write_bytes(b"[1, 2]")
            self.assertTrue(any(manifest.NAME in p for p in self.problems()))
        finally:
            target.write_bytes(original)
            mpath.write_bytes(saved)
        self.assertEqual(self.problems(), [])

    def test_only_a_real_master_or_the_import_of_a_known_file_is_tolerated(self) -> None:
        folder = self.out("candle_stump")
        ok = [folder / "candle_stump@4x.shape.png", folder / "candle_stump@4x.shape.png.import",
              folder / "candle_stump@1x.parts.png.import"]
        bad = [folder / "stock@4x.png", folder / "candle_stump@3x.shape.png",
               folder / "elsewhere.png.import", folder / "note.uid"]
        junk = self.out(".DS_Store")  # a file manager's own file is not a stock picture
        for f in ok + bad + [junk]:
            f.write_bytes(b"x")
        try:
            text = " | ".join(self.problems())
            for f in ok:
                self.assertNotIn(f.name, text)
            self.assertNotIn(".DS_Store", text)
            for f in bad:
                self.assertIn(f.name, text)
        finally:
            for f in ok + bad + [junk]:
                f.unlink()
        self.assertEqual(self.problems(), [])

    def test_a_partial_build_keeps_the_other_manifest_lines(self) -> None:
        before = manifest.load(self.root / "out" / manifest.NAME)
        files, built = build.build_root(self.root, self.r, ["candle_stump"], masters=False, jobs=1,
                                        cache_dir=None, versions=VERSIONS)
        build.write_root(self.root, self.r, files, built)
        self.assertEqual(manifest.load(self.root / "out" / manifest.NAME), before)
        self.assertIn("noise/noise.png", before)


class Cli(unittest.TestCase):
    """build.main: the toolchain gate, a bad source as a message, a deleted source cleaned up."""

    def run_main(self, argv: list[str], **kw) -> tuple[int, str]:
        err = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            code = build.main(argv, **kw)
        return code, err.getvalue()

    def test_check_needs_the_pinned_toolchain_and_a_build_only_warns(self) -> None:
        other = {"numpy": "0.0.0", "pillow": "0.0.0"}
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(assetbuild, "installed_versions", return_value=other):
                code, err = self.run_main(["--check"], repo=Path(tmp), roots=())
                self.assertEqual(code, 2)
                self.assertIn("pinned toolchain", err)
                code, err = self.run_main([], repo=Path(tmp), roots=())
                self.assertEqual(code, 0)
                self.assertIn("warning", err)
            self.assertEqual(self.run_main(["--check"], repo=Path(tmp), roots=())[0], 0)

    def test_a_bad_source_is_a_message_not_a_traceback(self) -> None:
        """Each of these used to build (a typo, NaN, no glow) or die with a traceback."""
        flame = '"flame": {"lit": "#fff2d2", "shadow": "#ffc486", "rim": "#ffffff", "gloss": 0.0, '
        cases = [
            ("pose.json", '"ticks": 5', '"tiks": 5', "unknown key 'tiks'"),
            ("pose.json", "0.92, 0.0, 0.18", "NaN, 0.0, 0.18", "NaN"),
            ("pose.json", "0.92, 0.0, 0.18, 1.08, 0.04, -1.248", "0, 0, 0, 0, 1, 1", "collapses"),
            ("pose.json", "0.92, 0.0, 0.18, 1.08, 0.04, -1.248", "0.92, 0.0, 0.18, 1.08, 0.04, 1e9", "finite"),
            ("pose.json", "0.92, 0.0, 0.18, 1.08, 0.04, -1.248", "1, 0, 0, 1, 50000, 0", "does not fit"),
            ("parts.svg", 'data-bevel-u="4"', 'data-bevel-u="abc"', "is not a number"),
            ("palette.tres", '"soot": {', '"soot": 5, "unused": {', "must be a dictionary"),
            ("palette.tres", flame + '"emissive": "#ffbe78", "emissive_strength": 1.0}', flame.rstrip(", ") + "}",
             "has no emissive colour"),
        ]
        for name, old, new, needle in cases:
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                shutil.copytree(common.CANDLE_DIR, root / "src" / "candle_stump")
                target = root / "src" / "candle_stump" / name
                text = target.read_text(encoding="utf-8")
                self.assertIn(old, text, (name, old))
                target.write_text(text.replace(old, new, 1), encoding="utf-8")
                for argv in (["--check"], []):
                    code, err = self.run_main(argv, repo=root, roots=(build.Root("src", "out"),))
                    self.assertEqual(code, 1, (needle, argv))
                    self.assertIn("source error", err)
                    self.assertIn(needle, err)
                self.assertFalse((root / "out").exists(), "a source that does not lint writes nothing")

    def test_a_full_build_removes_what_a_deleted_source_or_action_left(self) -> None:
        roots = (build.Root("src", "out"),)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(common.CANDLE_DIR, root / "src" / "candle_stump")
            self.assertEqual(self.run_main([], repo=root, roots=roots)[0], 0)
            folder = root / "out" / "candle_stump"
            keep = folder / "candle_stump@1x.shape.png.import"
            stale = [folder / "old_action@1x.shape.png", folder / "old_action@1x.shape.png.import"]
            for f in [keep, *stale]:
                f.write_bytes(b"x")
            self.assertEqual(self.run_main([], repo=root, roots=roots)[0], 0)
            self.assertTrue(keep.exists(), "Godot's import of a built file stays")
            self.assertFalse(any(f.exists() for f in stale), "a file of a removed action goes, import and all")
            self.assertEqual(self.run_main(["--check"], repo=root, roots=roots)[0], 0)
            (root / "src" / "candle_stump").rename(root / "gone")
            self.assertEqual(self.run_main([], repo=root, roots=roots)[0], 0)
            self.assertFalse(folder.exists(), "the render of an asset whose source is gone is removed")
            self.assertEqual(manifest.load(root / "out" / manifest.NAME), {})
            self.assertEqual(self.run_main(["--check"], repo=root, roots=roots)[0], 0)


class ToolHash(unittest.TestCase):
    """The frame cache is keyed on the code that made a frame (ADR-0023 Decision 1.8)."""

    def test_editing_any_module_of_the_package_changes_the_hash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            code = Path(tmp) / "artbuild"
            shutil.copytree(common.TOOLS / "artbuild", code, ignore=shutil.ignore_patterns("tests", "__pycache__"))
            before = assetbuild.tool_hash(code)
            self.assertEqual(before, assetbuild.tool_hash(code))
            for name in ("channels.py", "pose.py", "frame.py", "svg.py"):
                f = code / name
                saved = f.read_text(encoding="utf-8")
                f.write_text(saved + "\n# edited\n", encoding="utf-8")
                self.assertNotEqual(assetbuild.tool_hash(code), before, name)
                f.write_text(saved, encoding="utf-8")
            self.assertEqual(assetbuild.tool_hash(code), before)
            (code / "newmodule.py").write_text("X = 1\n", encoding="utf-8")
            self.assertNotEqual(assetbuild.tool_hash(code), before, "a new module is code too")

    def test_the_real_hash_covers_the_package_and_keys_the_cache(self) -> None:
        import hashlib

        from artbuild import TOOL_VERSION

        self.assertEqual(assetbuild.tool_hash(), assetbuild.tool_hash(common.TOOLS / "artbuild"))
        self.assertNotEqual(assetbuild.tool_hash(), hashlib.sha256(TOOL_VERSION.encode()).hexdigest())
        src = common.source(common.CANDLE_DIR)
        cell = ch.Cell(0, 0, 64, 64)
        self.assertNotEqual(
            assetbuild._task_key(src, 0, 0, cell, (1, 2), "tool-a"),
            assetbuild._task_key(src, 0, 0, cell, (1, 2), "tool-b"),
        )


class Repository(unittest.TestCase):
    """The committed output is what a fresh build makes (the CI check)."""

    def test_check_passes_on_the_committed_tree(self) -> None:
        self.assertEqual(build.main(["--check"]), 0)

    def test_manifests_match_the_files_on_disk(self) -> None:
        for r in build.ROOTS:
            out = common.ROOT / r.out
            for rel, digest in manifest.load(out / manifest.NAME).items():
                self.assertEqual(manifest.digest(rel, (out / rel).read_bytes()), digest, f"{r.out}/{rel}")

    def test_a_png_is_hashed_by_its_pixels_not_by_its_deflate_stream(self) -> None:
        """docs/review F7: the same picture compressed another way is the same build output."""
        import io

        import numpy as np
        from PIL import Image

        px = np.arange(4 * 4 * 4, dtype=np.uint8).reshape(4, 4, 4)
        a, b = io.BytesIO(), io.BytesIO()
        Image.fromarray(px, "RGBA").save(a, format="PNG", compress_level=9)
        Image.fromarray(px, "RGBA").save(b, format="PNG", compress_level=0)
        self.assertNotEqual(a.getvalue(), b.getvalue())
        self.assertEqual(manifest.digest("x.png", a.getvalue()), manifest.digest("x.png", b.getvalue()))
        self.assertTrue(manifest.same("x.png", a.getvalue(), b.getvalue()))
        px2 = px.copy()
        px2[0, 0, 0] ^= 1
        c = io.BytesIO()
        Image.fromarray(px2, "RGBA").save(c, format="PNG", compress_level=9)
        self.assertNotEqual(manifest.digest("x.png", a.getvalue()), manifest.digest("x.png", c.getvalue()))
        self.assertFalse(manifest.same("x.png", a.getvalue(), c.getvalue()))
        # Anything else is its bytes.
        self.assertNotEqual(manifest.digest("a.json", b"{}"), manifest.digest("a.json", b"{ }"))

    def test_godot_imports_the_data_textures_unaltered(self) -> None:
        """Godot's default fix_alpha_border rewrites the colour of zero-alpha pixels, which is
        most of the data in these textures; project.godot turns it off for new imports and every
        imported texture of the build must agree."""
        project = (common.ROOT / "project.godot").read_text(encoding="utf-8")
        section = project.split("[importer_defaults]", 1)[1].split("\n[", 1)[0]
        self.assertIn('"process/fix_alpha_border": false', section)
        self.assertIn('"process/premult_alpha": false', section)
        self.assertIn('"compress/mode": 0', section)
        self.assertIn('"mipmaps/generate": false', section)
        seen = 0
        for r in build.ROOTS:
            for imp in sorted((common.ROOT / r.out).rglob("*.png.import")):
                if "@4x." in imp.name:
                    continue
                text = imp.read_text(encoding="utf-8")
                for want in ("process/fix_alpha_border=false", "process/premult_alpha=false",
                             "compress/mode=0", "mipmaps/generate=false"):
                    self.assertIn(want, text, imp.name)
                seen += 1
        self.assertGreater(seen, 0, "no imported texture found: run godot --headless --path . --import")

    def test_the_toolchain_is_the_pinned_one(self) -> None:
        self.assertEqual(assetbuild.installed_versions(), VERSIONS)


if __name__ == "__main__":
    unittest.main()
