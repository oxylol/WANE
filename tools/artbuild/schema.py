"""A small JSON Schema validator (draft-07 subset), so CI needs no package beyond the pinned ones.

Supports $ref to #/definitions/..., type (including a list of types), enum, const, required, properties, additionalProperties
(false or a schema), items, minItems, maxItems, minimum, maximum, minLength and pattern.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
}


def validate(value, schema: dict, path: str = "$", root: dict | None = None) -> list[str]:
    """Problems found (empty when the value satisfies the schema)."""
    root = root if root is not None else schema
    if "$ref" in schema:
        node = root
        for part in schema["$ref"].removeprefix("#/").split("/"):
            node = node[part]
        return validate(value, node, path, root)
    errors: list[str] = []
    types = schema.get("type")
    if types is not None:
        names = types if isinstance(types, list) else [types]
        if not any(TYPES[t](value) for t in names):
            return [f"{path}: expected {'/'.join(names)}, got {type(value).__name__}"]
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} is not one of {schema['enum']}")
    if "const" in schema and value != schema["const"]:
        errors.append(f"{path}: must be {schema['const']!r}")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing {key!r}")
        props = schema.get("properties", {})
        extra = schema.get("additionalProperties", True)
        for key, v in value.items():
            if key in props:
                errors.extend(validate(v, props[key], f"{path}.{key}", root))
            elif extra is False:
                errors.append(f"{path}: unexpected {key!r}")
            elif isinstance(extra, dict):
                errors.extend(validate(v, extra, f"{path}.{key}", root))
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"{path}: needs at least {schema['minItems']} items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{path}: needs at most {schema['maxItems']} items")
        if "items" in schema:
            for k, v in enumerate(value):
                errors.extend(validate(v, schema["items"], f"{path}[{k}]", root))
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: {value} is below {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: {value} is above {schema['maximum']}")
    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(f"{path}: too short")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append(f"{path}: {value!r} does not match {schema['pattern']}")
    return errors


def load_schema() -> dict:
    return json.loads((Path(__file__).parent / "sheet_schema.json").read_text(encoding="utf-8"))
