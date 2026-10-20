"""WANE art build (ADR-0023 Decision 1): SVG part libraries to baked distance-field sheets.

Run as `python3 tools/artbuild/build.py [--check] [--jobs N] [asset...]`. Everything here is
float64 numpy with IEEE-exact operations (+, -, *, /, sqrt, comparisons) and integer maths, so two
builds on the pinned image are byte-identical (Decision 6.1).
"""

TOOL_VERSION = "1.0.0"
