#!/usr/bin/env python3
"""Runs the art build's unit tests: python3 tools/ci/test_artbuild.py

The tests live beside the code in tools/artbuild/tests/ (ADR-0023 Decision 7.1): the SVG lint, the
exact distances against analytic shapes and cairosvg, the channels, byte-identical builds (serial,
parallel, cached), the sheet metadata against its schema, and `build.py --check` on the committed
output. Needs the packages pinned in tools/requirements.txt and libcairo2.
"""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    sys.path.insert(0, str(ROOT / "tools"))
    suite = unittest.defaultTestLoader.discover(
        str(ROOT / "tools" / "artbuild" / "tests"), pattern="test_*.py", top_level_dir=str(ROOT / "tools")
    )
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
