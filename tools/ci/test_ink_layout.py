#!/usr/bin/env python3
"""The channel layout is written in two languages: tools/artbuild/channels.py encodes it and
shaders/ink/ink_common.gdshaderinc decodes it (docs/adr/0023 Decisions 1.3 and 7.2). The decode
constants must be the same in both. Run: python3 tools/ci/test_ink_layout.py

The shader half is always checked against the ADR's numbers (S: byte = 128 + 16 d, U: byte = 16 d,
brush angle: byte 255 is pi, 16 palette columns of 4 rows). The artbuild half is checked as soon as
tools/artbuild/channels.py exists: it must define S_ZERO, S_STEPS_PER_U, U_STEPS_PER_U,
PALETTE_COLUMNS, PALETTE_ROWS_PER_VARIANT and FLAG_SMEAR with the same values (the names are this test's contract with
the artbuild builder; see docs/adr/0023 Decision 7.2's last test)."""

import ast
import pathlib
import re
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHADER = ROOT / "shaders" / "ink" / "ink_common.gdshaderinc"
CHANNELS = ROOT / "tools" / "artbuild" / "channels.py"
NOISE = ROOT / "tools" / "artbuild" / "noise.py"

# shader constant -> (channels.py name, the ADR's value)
PAIRS = {
    "INK_S_ZERO": ("S_ZERO", 128.0),
    "INK_S_STEPS_PER_U": ("S_STEPS_PER_U", 16.0),
    "INK_U_STEPS_PER_U": ("U_STEPS_PER_U", 16.0),
    "INK_PALETTE_COLUMNS": ("PALETTE_COLUMNS", 16),
    "INK_PALETTE_ROWS": ("PALETTE_ROWS_PER_VARIANT", 4),
    "INK_FLAG_SMEAR": ("FLAG_SMEAR", 8),
}
NOISE_CELLS = {"INK_WOBBLE1_CELLS": 16.0, "INK_WOBBLE2_CELLS": 32.0}


def shader_constants() -> dict:
    text = SHADER.read_text()
    out = {}
    for m in re.finditer(r"const\s+(?:float|int)\s+(\w+)\s*=\s*([0-9.]+)\s*;", text):
        out[m.group(1)] = float(m.group(2))
    return out


def channels_constants() -> dict:
    tree = ast.parse(CHANNELS.read_text())
    out = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target = node.targets[0]
            if isinstance(target, ast.Name):
                try:
                    out[target.id] = ast.literal_eval(node.value)
                except ValueError:
                    pass
    return out


def noise_constants() -> dict:
    """SIZE and CELLS of tools/artbuild/noise.py, read as literals (the module is not imported, so
    this test needs no numpy)."""
    out = {}
    for node in ast.parse(NOISE.read_text()).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id in ("SIZE", "CELLS"):
                out[node.targets[0].id] = ast.literal_eval(node.value)
    return out


class InkLayout(unittest.TestCase):
    def test_the_shader_decodes_the_adrs_layout(self):
        consts = shader_constants()
        for shader_name, (_, value) in PAIRS.items():
            self.assertEqual(consts.get(shader_name), float(value), shader_name)
        for shader_name, value in NOISE_CELLS.items():
            self.assertEqual(consts.get(shader_name), value, shader_name)
        # The angle byte spans 0 to pi.
        self.assertAlmostEqual(consts["INK_ANGLE_RANGE"], 3.14159265, places=7)

    def test_the_shader_and_artbuild_agree(self):
        if not CHANNELS.exists():
            self.skipTest("tools/artbuild/channels.py is not in this tree yet")
        theirs = channels_constants()
        consts = shader_constants()
        for shader_name, (their_name, _) in PAIRS.items():
            self.assertIn(their_name, theirs, f"channels.py must define {their_name}")
            self.assertEqual(float(theirs[their_name]), consts[shader_name], shader_name)

    def test_the_noise_cell_counts_are_the_shaders(self):
        """ADR-0023 Decision 1.7: the cell counts are part of the interface, because the shaders
        turn a wavelength in u into texture coordinates with them. noise.py's counts and the
        shader's constants must be the same numbers, whichever side moves."""
        theirs = noise_constants()
        consts = shader_constants()
        cells = theirs["CELLS"]
        self.assertEqual(consts["INK_NOISE_PX"], float(theirs["SIZE"]))
        self.assertEqual((consts["INK_WOBBLE1_CELLS"],), tuple(float(c) for c in cells["wobble1"]))
        self.assertEqual((consts["INK_WOBBLE2_CELLS"],), tuple(float(c) for c in cells["wobble2"]))
        # The brush tile is the span of the brush noise in u: its coarsest cell is 1 u.
        self.assertEqual(consts["INK_BRUSH_TILE_U"] / float(min(cells["brush"])), 1.0)
        self.assertEqual(sorted(cells), ["brush", "grain", "wobble1", "wobble2"])


if __name__ == "__main__":
    sys.exit(unittest.main(verbosity=1))
