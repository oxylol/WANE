"""One asset, sources to files (ADR-0023 Decision 1.3, 1.5, 1.6, 1.8).

`build_asset` returns {relative path: bytes} for the asset's directory and writes nothing, so the
build, the byte-identity check and the tests all use the same function. Frames bake independently
(in any order, in parallel processes) and are cached under the hash of the sources and the tool.
"""

from __future__ import annotations

import hashlib
import io
import json
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import TOOL_VERSION
from . import channels as ch
from . import frame, pack, palette, pose, svg

SHEET_VERSION = 1
KINDS = ("shape", "normal", "parts")
SHIPPED_SCALES = (1, 2)
MASTER_SCALES = (4,)
PINNED = ("numpy", "pillow")


@dataclass
class Source:
    name: str
    lib: svg.PartLibrary
    pal: palette.Palette
    actions: list[pose.ActionSpec]
    sha256: str


def source_files(src_dir: Path) -> list[Path]:
    return [p for p in (src_dir / "parts.svg", src_dir / "palette.tres", src_dir / "pose.json") if p.exists()]


def load_source(src_dir: Path) -> Source:
    svg_path = src_dir / "parts.svg"
    if not svg_path.exists():
        raise svg.SvgError(f"{src_dir}: no parts.svg")
    lib = svg.parse_file(svg_path)
    pal_path = src_dir / "palette.tres"
    if not pal_path.exists():
        raise palette.PaletteError(f"{src_dir}: no palette.tres")
    pal = palette.parse_file(pal_path, lib)
    actions = pose.load(src_dir / "pose.json", lib)
    h = hashlib.sha256()
    for f in source_files(src_dir):
        h.update(f.name.encode() + b"\0" + f.read_bytes() + b"\0")
    return Source(src_dir.name, lib, pal, actions, h.hexdigest())


def tool_hash(code_dir: Path | None = None) -> str:
    """Hash of the build's own code (every .py file of the package, or of `code_dir`): a cache
    entry is only valid for the code that made it, so editing channels.py or pose.py must change
    this (ADR-0023 Decision 1.8)."""
    h = hashlib.sha256(TOOL_VERSION.encode())
    for f in sorted((code_dir or Path(__file__).parent).glob("*.py")):
        h.update(f.name.encode() + b"\0" + f.read_bytes())
    return h.hexdigest()


def pinned_versions(requirements: Path) -> dict[str, str]:
    """The versions pinned in tools/requirements.txt for the packages that shape the output."""
    out = {}
    for line in requirements.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if "==" in line and not line.startswith("#"):
            name, ver = line.split("==", 1)
            if name.lower() in PINNED:
                out[name.lower()] = ver.strip()
    return out


def installed_versions() -> dict[str, str]:
    import PIL

    return {"numpy": np.__version__, "pillow": PIL.__version__}


# --- planning ------------------------------------------------------------------------------------


@dataclass
class Task:
    source: Source
    action: int
    index: int
    cell: ch.Cell
    scales: tuple[int, ...]
    cache_dir: str | None
    key: str


def action_cells(src: Source) -> list[ch.Cell]:
    cells = []
    for act in src.actions:
        boxes = [pose.posed_bounds(pose.pose_frame(src.lib, f)) for f in act.frames]
        cells.append(pack.action_cell(src.lib.origin, boxes))
    return cells


def _task_key(src: Source, action: int, index: int, cell: ch.Cell, scales, th: str) -> str:
    spec = json.dumps(
        [src.sha256, action, index, [cell.x0, cell.y0, cell.w, cell.h], list(scales)]
    )
    return hashlib.sha256((th + spec).encode()).hexdigest()


def run_task(task: Task) -> frame.FrameResult:
    cache = Path(task.cache_dir) / f"{task.key}.npz" if task.cache_dir else None
    if cache is not None and cache.exists():
        try:
            with np.load(cache, allow_pickle=False) as z:
                arrays = {
                    s: {k: z[f"{s}_{k}"] for k in KINDS} for s in task.scales
                }
                meta = json.loads(str(z["meta"]))
            return frame.FrameResult(arrays, meta)
        except (OSError, ValueError, KeyError):
            pass  # a damaged entry is rebuilt
    spec = task.source.actions[task.action].frames[task.index]
    posed = pose.pose_frame(task.source.lib, spec)
    res = frame.bake(task.source.lib, task.source.pal, posed, task.cell, task.scales)
    if cache is not None:
        cache.parent.mkdir(parents=True, exist_ok=True)
        flat = {f"{s}_{k}": v for s, d in res.arrays.items() for k, v in d.items()}
        tmp = cache.with_name(cache.name + f".{id(res)}.tmp.npz")
        np.savez(tmp, meta=json.dumps(res.meta), **flat)
        tmp.replace(cache)
    return res


# --- assembly ------------------------------------------------------------------------------------


def build_asset(
    src_dir: Path,
    *,
    versions: dict[str, str],
    masters: bool = False,
    jobs: int = 1,
    cache_dir: Path | None = None,
) -> dict[str, bytes]:
    src = load_source(src_dir)
    name = src.name
    scales = SHIPPED_SCALES + (MASTER_SCALES if masters else ())
    cells = action_cells(src)
    try:
        slots, sizes = pack.layout([(c, len(a.frames)) for c, a in zip(cells, src.actions)])
    except ValueError as e:  # a pose that throws a part off the page
        raise pose.PoseError(f"{name}: {e}") from e
    th = tool_hash()
    tasks = [
        Task(src, ai, fi, cells[ai], scales, str(cache_dir) if cache_dir else None,
             _task_key(src, ai, fi, cells[ai], scales, th))
        for ai, act in enumerate(src.actions)
        for fi in range(len(act.frames))
    ]
    if jobs > 1 and len(tasks) > 1:
        with ProcessPoolExecutor(max_workers=jobs) as pool:
            results = list(pool.map(run_task, tasks, chunksize=1))
    else:
        results = [run_task(t) for t in tasks]
    files: dict[str, bytes] = {}
    all_scales = SHIPPED_SCALES + MASTER_SCALES
    # Atlases, one per page, scale and kind.
    atlases = {
        (pg, s, k): pack.blank_atlas(k, sizes[pg][0] * s, sizes[pg][1] * s)
        for pg in range(len(sizes))
        for s in scales
        for k in KINDS
    }
    frames_meta: list[list[dict]] = [[] for _ in src.actions]
    n = 0
    for ai, act in enumerate(src.actions):
        cell = cells[ai]
        for fi, spec in enumerate(act.frames):
            res, slot = results[n], slots[ai][fi]
            n += 1
            rect = {}
            for s in all_scales:
                rect[str(s)] = [slot.x * s, slot.y * s, cell.w * s, cell.h * s]
            for s in scales:
                for k in KINDS:
                    a = atlases[(slot.page, s, k)]
                    a[slot.y * s : (slot.y + cell.h) * s, slot.x * s : (slot.x + cell.w) * s] = res.arrays[s][k]
            entry = {
                "index": fi,
                "key": spec.key,
                "ticks": spec.ticks,
                "page": slot.page,
                "rect": rect,
            }
            entry.update(res.meta)
            frames_meta[ai].append(entry)
    for (pg, s, k), arr in sorted(atlases.items()):
        files[f"{name}{pack.page_suffix(pg)}@{s}x.{k}.png"] = pack.png_bytes(arr)
    pal_img = palette.image(src.pal)
    files[f"{name}.palette.png"] = pack.png_bytes(
        np.ascontiguousarray(pal_img)
    )
    files[f"{name}.sheet.json"] = (
        json.dumps(sheet_json(src, cells, sizes, frames_meta, versions), indent=1, allow_nan=False) + "\n"
    ).encode()
    return files


def sheet_json(src, cells, sizes, frames_meta, versions) -> dict:
    ox, oy = src.lib.origin
    doc = {
        "version": SHEET_VERSION,
        "asset": src.name,
        "source_sha256": src.sha256,
        "tools": {"artbuild": TOOL_VERSION, **versions},
        "scales": list(SHIPPED_SCALES),
        "masters": list(MASTER_SCALES),
        "origin_u": [ox, oy],
        "cell_u": [max(c.w for c in cells), max(c.h for c in cells)],
        "pages": [{"page": i, "size_u": [w, h]} for i, (w, h) in enumerate(sizes)],
        "palette": {
            "file": f"{src.name}.palette.png",
            "columns": ch.PALETTE_COLUMNS,
            "rows_per_variant": ch.PALETTE_ROWS_PER_VARIANT,
            "variants": src.pal.variant_names,
            "slots": [{"slot": i + 1, "material": m} for i, m in enumerate(src.pal.slots)],
        },
        "parts": [
            {
                "id": p.id,
                "index": src.pal.slot_of_part(p.id),
                "z": p.z,
                "tags": list(p.tags),
                "material": src.pal.part_material[p.id],
                "pivot_u": [round(p.pivot[0] - ox, 4), round(p.pivot[1] - oy, 4)],
            }
            for p in src.lib.parts
        ],
        "actions": {},
    }
    for act, cell, frs in zip(src.actions, cells, frames_meta):
        doc["actions"][act.name] = {
            "fps": act.fps,
            "loop": act.loop,
            "cell_u": [cell.w, cell.h],
            "cell_origin_u": [ox - cell.x0, oy - cell.y0],
            "frames": frs,
        }
    return doc


def png_pixels(data: bytes) -> np.ndarray:
    from PIL import Image

    return np.array(Image.open(io.BytesIO(data)).convert("RGBA"))
