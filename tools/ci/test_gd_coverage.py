#!/usr/bin/env python3
"""Self-test for tools/ci/gd_coverage.py's statement finder: python3 tools/ci/test_gd_coverage.py"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gd_coverage as coverage  # noqa: E402

SAMPLE = """class_name Thing
extends RefCounted
const A: int = 1
var b: int = 2


func f(x: int) -> int:
\tvar y: int = (
\t\tx
\t\t+ 1
\t)
\tif y > 2:
\t\treturn y
\telif y < 0:
\t\tpass
\telse:
\t\ty += 1
\tmatch y:
\t\t1:
\t\t\treturn 1
\t\t_:
\t\t\tpass
\tvar s: String = "# not a comment"  # comment
\treturn y


class Inner:
\tvar z: int = 0

\tfunc g() -> void:
\t\tz += 1
"""


class ProbeLines(unittest.TestCase):
    def test_statement_lines(self) -> None:
        lines = SAMPLE.split("\n")
        found = [lines[n - 1].strip() for n in coverage.probe_lines(SAMPLE)]
        self.assertEqual(
            found,
            [
                "var y: int = (",
                "if y > 2:",
                "return y",
                "pass",
                "y += 1",
                "match y:",
                "return 1",
                "pass",
                'var s: String = "# not a comment"  # comment',
                "return y",
                "z += 1",
            ],
        )

    def test_triple_quoted_strings_are_skipped(self) -> None:
        src = 'func f() -> String:\n\tvar s: String = """\n\tline one (\n\t"""\n\treturn s\n'
        lines = src.split("\n")
        found = [lines[n - 1].strip() for n in coverage.probe_lines(src)]
        self.assertEqual(found, ['var s: String = """', "return s"])

    def test_single_quoted_triple_strings_are_skipped(self) -> None:
        src = "func f() -> String:\n\tvar s: String = \'\'\'\n\tline one (\n\t\'\'\'\n\treturn s\n"
        lines = src.split("\n")
        found = [lines[n - 1].strip() for n in coverage.probe_lines(src)]
        self.assertEqual(found, ["var s: String = \'\'\'", "return s"])

    def test_instrumented_source_keeps_original_lines(self) -> None:
        text, probes = coverage.instrument(SAMPLE, 3)
        self.assertEqual(len(text.split("\n")), len(SAMPLE.split("\n")) + len(probes))
        self.assertIn("\tCoverageProbe.hit(3, 8)\n\tvar y: int = (", text)


if __name__ == "__main__":
    unittest.main()
