#!/usr/bin/env python3
"""Keeps docs/CODEMAP.md honest: python3 tools/ci/test_codemap.py

Every repo path written in backticks must exist, a `path:LINE symbol` entry must point inside the
file at a symbol that is really there, every docs/adr/NNNN file must be listed, and the map must
stay small (its whole point is to cost an agent fewer tokens than exploring).
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CODEMAP = ROOT / "docs" / "CODEMAP.md"
MAX_CHARS = 12000
# A backtick span that is a repo path: no spaces or wildcards, optionally `:LINE` and a symbol.
SPAN = re.compile(r"`([^`\n]+)`")
ENTRY = re.compile(r"(?P<path>[\w./-]+)(?::(?P<line>\d+)(?: (?P<symbol>\w+))?)?")
FILE_SUFFIXES = (".gd", ".md", ".tres", ".room", ".fixture", ".sh", ".py", ".txt", ".yml")
ADR_STEM = re.compile(r"\d{4}-[\w-]+")


def entries(text: str) -> list[re.Match[str]]:
    """The backtick spans of `text` that name a repo path (a slash, or a known file suffix)."""
    found = []
    for span in SPAN.findall(text):
        m = ENTRY.fullmatch(span)
        if m and ("/" in m["path"] or m["path"].endswith(FILE_SUFFIXES)):
            found.append(m)
    return found


class Codemap(unittest.TestCase):
    text = CODEMAP.read_text(encoding="utf-8")

    def test_every_path_exists(self) -> None:
        found = entries(self.text)
        self.assertGreater(len(found), 40, "the path pattern no longer finds the map's paths")
        missing = [m["path"] for m in found if not (ROOT / m["path"]).exists()]
        self.assertEqual(missing, [], "paths in docs/CODEMAP.md that do not exist")

    def test_line_entries_point_at_their_symbol(self) -> None:
        stale = []
        for m in entries(self.text):
            if m["line"] is None or not (ROOT / m["path"]).is_file():
                continue
            source = (ROOT / m["path"]).read_text(encoding="utf-8")
            if int(m["line"]) > len(source.split("\n")):
                stale.append(f"{m[0]}: the file has fewer lines")
            elif m["symbol"] and not re.search(rf"\b{m['symbol']}\b", source):
                stale.append(f"{m[0]}: no {m['symbol']} in the file")
        self.assertEqual(stale, [], "stale path:LINE entries in docs/CODEMAP.md")

    def test_every_adr_is_listed(self) -> None:
        stems = sorted(p.stem for p in (ROOT / "docs" / "adr").glob("[0-9][0-9][0-9][0-9]-*.md"))
        self.assertTrue(stems)
        self.assertEqual([s for s in stems if f"`{s}`" not in self.text], [])

    def test_listed_adrs_exist(self) -> None:
        listed = [s for s in SPAN.findall(self.text) if ADR_STEM.fullmatch(s)]
        gone = [s for s in listed if not (ROOT / "docs" / "adr" / f"{s}.md").exists()]
        self.assertEqual(gone, [])

    def test_stays_small(self) -> None:
        self.assertLessEqual(len(self.text), MAX_CHARS, "docs/CODEMAP.md grew too long; prune it")

    def test_entry_pattern(self) -> None:
        sample = "`core/a.gd:12 step` `:5 x` `ci/test.sh` `Fx.SUB` `a b/c.gd` `res://x.gd` `k@m`"
        self.assertEqual(
            [m[0] for m in entries(sample)], ["core/a.gd:12 step", "ci/test.sh"]
        )


if __name__ == "__main__":
    unittest.main()
