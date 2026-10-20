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

    def test_needs_a_viewbox_and_parts(self) -> None:
        with self.assertRaises(svg.SvgError):
            svg.parse('<svg xmlns="http://www.w3.org/2000/svg"><rect id="a" data-z="0" x="0" y="0" width="1" height="1"/></svg>')
        with self.assertRaises(svg.SvgError):
            lib("")

    def test_the_shipped_sources_pass(self) -> None:
        for path in (common.PROBE_DIR, common.CANDLE_DIR):
            library = svg.parse_file(path / "parts.svg")
            self.assertGreaterEqual(len(library.parts), 4)


if __name__ == "__main__":
    unittest.main()
