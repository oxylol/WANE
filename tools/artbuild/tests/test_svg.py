"""The SVG subset and its lint (ADR-0023 Decision 1.1)."""

import unittest

from . import common  # noqa: F401  (puts tools/ on sys.path)
from artbuild import svg

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'


def lib(body: str) -> svg.PartLibrary:
    return svg.parse(f"{HEAD}{body}</svg>")


def rejected(body: str) -> str:
    with unittest.TestCase().assertRaises(svg.SvgError) as cm:
        lib(body)
    return str(cm.exception)


RECT = '<rect id="a" data-z="0" x="10" y="10" width="8" height="8"%s/>'


class SvgLint(unittest.TestCase):
    def test_accepts_every_shape_and_group_transform(self) -> None:
        body = """
        <g transform="translate(2 3)">
          <path id="p" data-z="0" d="M0 0 L10 0 H10 V8 Q5 12 0 8 C-2 6 -2 2 0 0 Z"/>
          <circle id="c" data-z="1" cx="20" cy="20" r="3"/>
          <ellipse id="e" data-z="2" cx="30" cy="20" rx="4" ry="2" data-tags="eye emissive"/>
          <rect id="r" data-z="3" x="40" y="10" width="6" height="6" transform="rotate(45 43 13)"/>
          <polygon id="g" data-z="4" points="50,10 56,10 53,18"/>
        </g>"""
        library = lib(body)
        self.assertEqual([p.id for p in library.parts], ["p", "c", "e", "r", "g"])
        c = library.parts[1]
        self.assertAlmostEqual(float(c.polys[0][:, 0].mean()), 22.0, places=2)  # translate applied
        self.assertEqual(library.parts[2].tags, ("emissive", "eye"))

    def test_parts_sort_by_z_and_origin_defaults_to_bottom_centre(self) -> None:
        library = lib(
            '<rect id="b" data-z="5" x="0" y="0" width="4" height="4"/>'
            '<rect id="a" data-z="2" x="0" y="0" width="4" height="4"/>'
        )
        self.assertEqual([p.id for p in library.parts], ["a", "b"])
        self.assertEqual(library.origin, (32.0, 64.0))

    def test_every_polygon_is_positively_wound(self) -> None:
        from artbuild import geometry as geo

        mirrored = lib('<path id="m" data-z="0" transform="scale(-1 1)" d="M0 0 L10 0 L10 10 L0 10 Z"/>')
        for p in mirrored.parts[0].polys:
            self.assertGreater(geo.signed_area(p), 0.0)

    def test_rejects_paint_in_the_source(self) -> None:
        for attr in ('fill="#fff"', 'stroke="#000"', 'style="fill:red"', 'opacity="0.5"', 'class="x"'):
            msg = rejected(RECT % f" {attr}")
            self.assertIn("not allowed", msg, attr)
            self.assertIn("palette.tres", msg, attr)

    def test_rejects_gradients_and_other_elements(self) -> None:
        for el in ("<defs/>", "<linearGradient id='g'/>", "<text id='t'>x</text>", "<use href='#a'/>",
                   "<line x1='0' y1='0' x2='1' y2='1'/>", "<image href='x.png'/>"):
            self.assertIn("element not allowed", rejected(el), el)

    def test_rejects_bad_parts(self) -> None:
        self.assertIn("needs data-z", rejected('<rect id="a" x="0" y="0" width="4" height="4"/>'))
        self.assertIn("needs an id", rejected('<rect data-z="0" x="0" y="0" width="4" height="4"/>'))
        self.assertIn("unknown tag", rejected(RECT % ' data-tags="glow"'))
        self.assertIn("bevel", rejected(RECT % ' data-bevel-u="0"'))
        self.assertIn("data-tilt-deg", rejected(RECT % ' data-tilt-deg="90"'))
        self.assertIn("data-normal", rejected(RECT % ' data-normal="spiky"'))
        self.assertIn("at least three", rejected('<polygon id="a" data-z="0" points="0,0 4,4"/>'))
        self.assertIn("unsupported path command", rejected('<path id="a" data-z="0" d="M0 0 A5 5 0 0 1 9 9 Z"/>'))
        self.assertIn("duplicate part id", rejected(
            '<rect id="a" data-z="0" x="0" y="0" width="4" height="4"/>'
            '<rect id="a" data-z="1" x="0" y="0" width="4" height="4"/>'))
        self.assertIn("data-z 0 is used by two parts", rejected(
            '<rect id="a" data-z="0" x="0" y="0" width="4" height="4"/>'
            '<rect id="b" data-z="0" x="0" y="0" width="4" height="4"/>'))

    def test_a_number_that_is_not_one_is_a_message(self) -> None:
        for attr in ('data-bevel-u="abc"', 'data-tilt-deg="abc"', 'data-bevel-u=""', 'data-tilt-deg="1,5"'):
            self.assertIn("is not a number", rejected(RECT % f" {attr}"), attr)
        for attr in ('data-bevel-u="nan"', 'data-bevel-u="inf"', 'data-tilt-deg="nan"', 'data-tilt-deg="-inf"'):
            rejected(RECT % f" {attr}")
        self.assertIn("transform", rejected('<g transform="spin(3)">' + RECT % "" + "</g>"))
        self.assertIn("transform", rejected('<g transform="matrix(1 2 3)">' + RECT % "" + "</g>"))

    def test_the_bevel_and_tilt_ranges_have_both_ends(self) -> None:
        """ADR-0026 Decision 7: the bevel is 0.25 to 16 u, the tilt 0 to 89 degrees."""
        for ok in ('data-bevel-u="0.25"', 'data-bevel-u="16"', 'data-tilt-deg="0"', 'data-tilt-deg="89"'):
            lib(RECT % f" {ok}")
        for attr, needle in (
            ('data-bevel-u="0.24"', "data-bevel-u"), ('data-bevel-u="16.01"', "data-bevel-u"),
            ('data-bevel-u="1600"', "data-bevel-u"), ('data-tilt-deg="-0.1"', "data-tilt-deg"),
            ('data-tilt-deg="-90"', "data-tilt-deg"), ('data-tilt-deg="89.1"', "data-tilt-deg"),
        ):
            self.assertIn(needle, rejected(RECT % f" {attr}"), attr)
        self.assertEqual(svg.DEFAULT_BEVEL_U, 8.0)
        self.assertEqual(lib(RECT % "").parts[0].bevel_u, svg.DEFAULT_BEVEL_U)

    def test_a_part_off_the_page_is_rejected(self) -> None:
        big = '<rect id="a" data-z="0" x="0" y="0" width="%s" height="4"/>'
        for width in ("1e9", "1e308", "5000"):
            self.assertIn("beyond", rejected(big % width), width)
        lib(big % "2000")

    def test_needs_a_viewbox_and_parts(self) -> None:
        with self.assertRaises(svg.SvgError):
            svg.parse('<svg xmlns="http://www.w3.org/2000/svg"><rect id="a" data-z="0" x="0" y="0" width="1" height="1"/></svg>')
        with self.assertRaises(svg.SvgError):
            lib("")

    def test_the_shipped_sources_pass(self) -> None:
        for path in (common.PROBE_DIR, common.CANDLE_DIR):
            library = svg.parse_file(path / "parts.svg")
            self.assertGreaterEqual(len(library.parts), 4)


# Each body is a part library in a 64 u viewBox. The syntax a part library may use fills the same
# pixels as cairosvg fills them (ADR-0023 Decision 1.9): the S channel's inside against every pixel
# cairo's coverage calls firmly in (above 0.98) or out (below 0.02).
CAIRO_CASES = {
    "rotate about a point": '<rect id="a" data-z="0" x="20" y="24" width="24" height="10" transform="rotate(30 32 29)"/>',
    "skewX": '<rect id="a" data-z="0" x="20" y="20" width="20" height="14" transform="skewX(25)"/>',
    "skewY": '<rect id="a" data-z="0" x="20" y="20" width="20" height="14" transform="skewY(-20)"/>',
    "nested groups": '<g transform="translate(10 4)"><g transform="scale(1.5 1)"><rect id="a" data-z="0" x="8" y="20" width="12" height="14"/></g></g>',
    "matrix": '<rect id="a" data-z="0" x="10" y="10" width="20" height="12" transform="matrix(1 0.3 -0.2 1 6 4)"/>',
    "relative c and q": '<path id="a" data-z="0" d="m10 30 c8 -12 20 -12 28 0 q4 10 -2 16 l-20 0 z"/>',
    "implicit lineto after M": '<path id="a" data-z="0" d="M12 12 40 14 38 40 14 38 Z"/>',
    "relative h and v": '<path id="a" data-z="0" d="M10 10 h30 v20 h-12 v10 h-18 z"/>',
    "repeated C arguments": '<path id="a" data-z="0" d="M8 40 C8 20 24 20 24 40 24 52 40 52 40 40 Z"/>',
    "two subpaths": '<path id="a" data-z="0" d="M8 8 L24 8 L24 24 L8 24 Z M34 34 L54 34 L54 54 L34 54 Z"/>',
    "exponent numbers": '<path id="a" data-z="0" d="M1e1 1e1 L4.5e1 1e1 L4.5e1 3e1 L1e1 3e1 Z"/>',
    "negatives without separators": '<path id="a" data-z="0" d="M10,40L30,10-10,20 Z" transform="translate(20 10)"/>',
    "rotated ellipse": '<ellipse id="a" data-z="0" cx="32" cy="32" rx="22" ry="8" transform="rotate(-35 32 32)"/>',
    "z then m": '<path id="a" data-z="0" d="M8 8 l16 0 l0 16 z m30 30 l16 0 l0 16 z"/>',
    "a line after Z without a moveto": '<path id="a" data-z="0" d="M10 10 L30 10 L30 30 Z L10 30 L10 50 L40 50 Z"/>',
    "relative lines after z": '<path id="a" data-z="0" d="M30 10 h20 v20 z h-20 v30 l15 0 z"/>',
}


class SyntaxAgainstCairo(unittest.TestCase):
    def test_every_syntax_fills_what_cairosvg_fills(self) -> None:
        import json
        import tempfile
        from pathlib import Path

        from artbuild import channels as ch, frame, palette, pose

        cell = ch.Cell(0, 0, 64, 64)
        mat = {"lit": "#ffffff", "shadow": "#000000", "rim": "#808080", "gloss": 0.5}
        for name, body in CAIRO_CASES.items():
            text = f"{HEAD}{body}</svg>"
            library = svg.parse(text)
            parts = {p.id: "m" for p in library.parts}
            pal = palette.parse(
                "metadata/palette = " + json.dumps({"materials": {"m": mat}, "parts": parts}), library
            )
            posed = pose.pose_frame(library, pose.FrameSpec(True, 3))
            res = frame.bake(library, pal, posed, cell, (4,))
            ours = common.decode_s(res.arrays[4]["shape"]) < 0
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "x.svg"
                path.write_text(text)
                coverage = common.cairo_coverage(path, cell, 4)
            firm_in, firm_out = coverage > 0.98, coverage < 0.02
            self.assertGreater(int(firm_in.sum()), 100, name)
            wrong = int((firm_in & ~ours).sum() + (firm_out & ours).sum())
            self.assertEqual(wrong, 0, f"{name}: {wrong} pixels disagree with cairosvg")


if __name__ == "__main__":
    unittest.main()
