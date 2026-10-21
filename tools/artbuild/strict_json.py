"""JSON for sources that are data a designer edits: no NaN or Infinity, no key given twice.

Python's json accepts `NaN`, `Infinity` and `-Infinity` and silently keeps the last of two equal keys.
A source that holds either is a mistake that would otherwise surface far away (a sheet.json no
parser can read, a frame that keeps the timing the designer typed first), so the readers of
`pose.json` and `palette.tres` stop here with a message instead (ADR-0023 addendum, review 2).
"""

from __future__ import annotations

import json


def loads(text: str, error: type[ValueError], name: str):
    """json.loads(text), raising `error` (naming `name`) for bad syntax, a non-finite constant or a
    repeated key."""

    def constant(token: str):
        raise error(f"{name}: {token} is not a number a source may hold")

    def pairs(items: list[tuple[str, object]]) -> dict:
        out: dict = {}
        for key, value in items:
            if key in out:
                raise error(f"{name}: the key {key!r} is given twice")
            out[key] = value
        return out

    try:
        return json.loads(text, parse_constant=constant, object_pairs_hook=pairs)
    except json.JSONDecodeError as e:
        raise error(f"{name}: not valid JSON ({e})") from e
