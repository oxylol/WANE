"""palette.tres: the colours of an asset (ADR-0023 Decision 1.1 and 1.3).

A Godot text resource whose `metadata/palette` is a dictionary. Godot's dictionary syntax is JSON
for the subset used here (strings, numbers, arrays, dictionaries), so one file is both a valid
resource and a readable table:

    metadata/palette = {
    "materials": {"wax": {"lit": "#d8cfae", "shadow": "#5a4e48", "rim": "#ffd9a8", "gloss": 0.8,
                          "emissive": "#ffbe78", "emissive_strength": 1.0}},
    "parts": {"stump": "wax"},
    "variants": {"hurt": {"wax": {"lit": "#a86a6e"}}}
    }

A material is two values and a rim (sRGB hex), a gloss 0 to 1 and an optional emissive colour with
a strength 0 to 1. Every part names a material. Parts that share a material share a palette slot,
the value in parts.png's R channel (slots 1 to 15, 0 is none). Variants override fields of
materials by name; "base" is always variant 0. Palette rows: lit, shadow, rim, emissive (alpha =
strength), four rows per variant, sixteen columns.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .channels import PALETTE_COLUMNS, PALETTE_ROWS_PER_VARIANT
from .svg import PartLibrary

FIELDS = ("lit", "shadow", "rim", "gloss", "emissive", "emissive_strength")
HEX = re.compile(r"#[0-9a-fA-F]{6}")


class PaletteError(ValueError):
    pass


@dataclass
class Palette:
    materials: dict[str, dict]
    part_material: dict[str, str]
    variants: dict[str, dict[str, dict]] = field(default_factory=dict)
    slots: list[str] = field(default_factory=list)  # material name per slot, slot 1 first

    def slot_of_part(self, part_id: str) -> int:
        return self.slots.index(self.part_material[part_id]) + 1

    def gloss_of_part(self, part_id: str) -> float:
        return float(self.materials[self.part_material[part_id]].get("gloss", 0.0))

    def material_of(self, part_id: str, variant: str = "base") -> dict:
        name = self.part_material[part_id]
        m = dict(self.materials[name])
        if variant != "base":
            m.update(self.variants[variant].get(name, {}))
        return m

    @property
    def variant_names(self) -> list[str]:
        return ["base", *sorted(self.variants)]


def _hex(value, where: str) -> tuple[int, int, int]:
    if not isinstance(value, str) or not HEX.fullmatch(value):
        raise PaletteError(f"{where}: colours are '#rrggbb'")
    return int(value[1:3], 16), int(value[3:5], 16), int(value[5:7], 16)


def _check_material(name: str, m: dict, partial: bool, where: str) -> None:
    for key in m:
        if key not in FIELDS:
            raise PaletteError(f"{where}: material {name!r} has unknown field {key!r}")
    for key in ("lit", "shadow", "rim", "emissive"):
        if key in m:
            _hex(m[key], f"{where}: {name}.{key}")
        elif not partial and key != "emissive":
            raise PaletteError(f"{where}: material {name!r} needs {key}")
    for key in ("gloss", "emissive_strength"):
        if key in m and not (isinstance(m[key], (int, float)) and 0.0 <= m[key] <= 1.0):
            raise PaletteError(f"{where}: {name}.{key} must be 0 to 1")


def extract_dictionary(text: str, name: str = "palette.tres") -> dict:
    m = re.search(r"^metadata/palette\s*=\s*", text, re.M)
    if not m:
        raise PaletteError(f"{name}: no 'metadata/palette = {{...}}' in the resource")
    depth = 0
    start = m.end()
    in_str = False
    for k in range(start, len(text)):
        c = text[k]
        if in_str:
            if c == '"' and text[k - 1] != "\\":
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[start : k + 1])
                except json.JSONDecodeError as e:
                    raise PaletteError(f"{name}: palette dictionary is not valid ({e})") from e
    raise PaletteError(f"{name}: unterminated palette dictionary")


def parse(text: str, lib: PartLibrary, name: str = "palette.tres") -> Palette:
    doc = extract_dictionary(text, name)
    materials = doc.get("materials")
    parts = doc.get("parts")
    if not isinstance(materials, dict) or not isinstance(parts, dict):
        raise PaletteError(f"{name}: needs 'materials' and 'parts' dictionaries")
    for mname, m in materials.items():
        _check_material(mname, m, False, name)
    ids = [p.id for p in lib.parts]
    for pid in ids:
        if pid not in parts:
            raise PaletteError(f"{name}: part {pid!r} has no material")
    for pid, mname in parts.items():
        if pid not in ids:
            raise PaletteError(f"{name}: material for unknown part {pid!r}")
        if mname not in materials:
            raise PaletteError(f"{name}: part {pid!r} uses unknown material {mname!r}")
    variants = doc.get("variants", {})
    for vname, over in variants.items():
        if vname == "base":
            raise PaletteError(f"{name}: 'base' is the materials themselves")
        for mname, m in over.items():
            if mname not in materials:
                raise PaletteError(f"{name}: variant {vname!r} overrides unknown material {mname!r}")
            _check_material(mname, m, True, f"{name} variant {vname}")
    slots: list[str] = []
    for p in lib.parts:  # z order, back to front: stable and independent of the file's order
        if parts[p.id] not in slots:
            slots.append(parts[p.id])
    if len(slots) > PALETTE_COLUMNS - 1:
        raise PaletteError(
            f"{name}: {len(slots)} distinct materials in use; the palette has "
            f"{PALETTE_COLUMNS - 1} slots (parts may share a material)"
        )
    return Palette(materials, dict(parts), variants, slots)


def parse_file(path: Path, lib: PartLibrary) -> Palette:
    return parse(path.read_text(encoding="utf-8"), lib, path.name)


def image(pal: Palette) -> np.ndarray:
    """The palette texture: (4 rows per variant, 16 columns, RGBA8)."""
    names = pal.variant_names
    img = np.zeros((PALETTE_ROWS_PER_VARIANT * len(names), PALETTE_COLUMNS, 4), dtype=np.uint8)
    for v, vname in enumerate(names):
        for s, mname in enumerate(pal.slots):
            m = dict(pal.materials[mname])
            if vname != "base":
                m.update(pal.variants[vname].get(mname, {}))
            col = s + 1
            r0 = v * PALETTE_ROWS_PER_VARIANT
            for row, key in enumerate(("lit", "shadow", "rim")):
                img[r0 + row, col, :3] = _hex(m[key], key)
                img[r0 + row, col, 3] = 255
            if "emissive" in m:
                img[r0 + 3, col, :3] = _hex(m["emissive"], "emissive")
                strength = float(m.get("emissive_strength", 1.0))
                img[r0 + 3, col, 3] = int(np.floor(strength * 255.0 + 0.5))
    return img
