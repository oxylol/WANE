#!/usr/bin/env python3
"""python3 tools/artbuild/build.py [--check] [--jobs N] [--masters] [--no-cache] [asset...]

Builds the SVG part libraries under assets/art/src/ (and the pipeline's own test assets) into
sprite sheets, normal and emissive maps and metadata (ADR-0023 Decision 1). Output is committed
and every file's SHA-256 is in the root's MANIFEST.json (a PNG is hashed by its pixels, ADR-0026).

  --check     rebuild everything without the cache and fail on any difference: a render that is not
              what a fresh build draws (pixels for a PNG, bytes for the rest, and no chunk the
              build does not write), a file anywhere under an out root that no source builds (a
              stock picture, a new folder, the render of an asset whose source is gone), a manifest
              line that does not match or names a file no source builds (CI)
  --jobs N    frames bake in N processes (0 = all cores); the output is the same in any order
  --masters   also write the 4x masters (<asset>@4x.*.png) for the review renders; they are
              build products that are never committed or listed in the manifest
  --no-cache  ignore tools/out/artbuild_cache
"""

from __future__ import annotations

import sys
from pathlib import Path

if __name__ == "__main__" and __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from artbuild.build import main as _main

    raise SystemExit(_main())

import argparse
import json
import os
import re
import shutil
from dataclasses import dataclass

from . import assetbuild, manifest, noise, pack, schema
from .manifest import ManifestError
from .palette import PaletteError
from .pose import PoseError
from .svg import SvgError

REPO = Path(__file__).resolve().parents[2]
CACHE = REPO / "tools" / "out" / "artbuild_cache"
NOISE_PATH = "noise/noise.png"
# The 4x masters of the review: <asset>/<asset>[.pN]@4x.<kind>.png, never committed, never listed.
MASTER = re.compile(r"[^/]+/[^/]+@4x\.(?:shape|normal|parts)\.png")


@dataclass(frozen=True)
class Root:
    """A folder of asset sources, where its sheets go, and whether it also owns the noise."""

    src: str
    out: str
    noise: bool = False


ROOTS = (
    Root("assets/art/src", "assets/art/build", noise=True),
    Root("tests/art/src", "tests/art/build"),
    Root("tools/artbuild/tests/data", "tests/screenshot/data"),
)


def assets_in(root: Path, src: str) -> list[str]:
    base = root / src
    if not base.is_dir():
        return []
    return sorted(p.name for p in base.iterdir() if (p / "parts.svg").exists())


def build_root(
    root: Path,
    r: Root,
    names: list[str] | None,
    *,
    masters: bool,
    jobs: int,
    cache_dir: Path | None,
    versions: dict[str, str],
) -> tuple[dict[str, bytes], list[str]]:
    """Build the root's assets (all, or those in names). Returns {path relative to the root's out
    folder: bytes}, and the asset names built. Problems in a source raise."""
    todo = [n for n in assets_in(root, r.src) if names is None or n in names]
    files: dict[str, bytes] = {}
    for name in todo:
        built = assetbuild.build_asset(
            root / r.src / name, versions=versions, masters=masters, jobs=jobs, cache_dir=cache_dir
        )
        for rel, data in built.items():
            problems = []
            if rel.endswith(".sheet.json"):
                problems = schema.validate(json.loads(data), schema.load_schema())
            if problems:
                raise SvgError(f"{name}: {rel} breaks sheet_schema.json: " + "; ".join(problems[:5]))
            files[f"{name}/{rel}"] = data
    if r.noise and (names is None or "noise" in names):
        files[NOISE_PATH] = pack.png_bytes(noise.texture())
    return files, todo


def is_master(rel: str) -> bool:
    return MASTER.fullmatch(rel) is not None


def scope_of(files: dict[str, bytes], built: list[str]) -> set[str]:
    """The top-level folders (asset names, noise) this build is responsible for."""
    return set(built) | ({"noise"} if NOISE_PATH in files else set())


def sources_of(root: Path, r: Root) -> set[str]:
    """The top-level out folders some source of this root builds."""
    return set(assets_in(root, r.src)) | ({"noise"} if r.noise else set())


def is_build_output(rel: str, known: set[str]) -> bool:
    """Whether the file `rel` (relative to an out root) belongs there: a built file, a review
    master, Godot's `.import` beside one of those, or a file manager's own metadata."""
    if rel in known or is_master(rel) or rel.rsplit("/", 1)[-1] in manifest.OS_METADATA:
        return True
    if rel.endswith(manifest.IMPORT_SUFFIX):
        base = rel[: -len(manifest.IMPORT_SUFFIX)]
        return base in known or is_master(base)
    return False


def write_root(root: Path, r: Root, files: dict[str, bytes], built: list[str]) -> int:
    out = root / r.out
    scope = scope_of(files, built)
    old = manifest.load(out / manifest.NAME)
    # A full build owns the whole manifest; a partial one only its own folders.
    full = built == assets_in(root, r.src) and (not r.noise or NOISE_PATH in files)
    entries = {} if full else {k: v for k, v in old.items() if k.split("/", 1)[0] not in scope}
    changed = 0
    for rel, data in sorted(files.items()):
        path = out / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.read_bytes() != data:
            path.write_bytes(data)
            changed += 1
        if not is_master(rel):
            entries[rel] = manifest.digest(rel, data)
    known = set(files)
    for name in sorted(scope):  # output of a removed action or a renamed file
        for rel in manifest.files_under(out / name):
            if not is_build_output(f"{name}/{rel}", known):
                (out / name / rel).unlink()
                changed += 1
    if full:  # the render of an asset whose source is gone
        for top in sorted({k.split("/", 1)[0] for k in old} - sources_of(root, r)):
            orphan = out / top
            if orphan.is_dir() and not orphan.is_symlink() and orphan.resolve().parent == out.resolve():
                changed += len(manifest.files_under(orphan))
                shutil.rmtree(orphan)
    data = manifest.render(entries)
    mpath = out / manifest.NAME
    if not mpath.exists() or mpath.read_bytes() != data:
        out.mkdir(parents=True, exist_ok=True)
        mpath.write_bytes(data)
        changed += 1
    return changed


def check_root(root: Path, r: Root, files: dict[str, bytes], built: list[str]) -> list[str]:
    """Differences between a fresh build and what is on disk: in the folders this build covers
    (a render that differs or is missing, a manifest line that is stale), and everywhere else under
    the out root (a file no source builds, a manifest line of an asset with no source)."""
    out = root / r.out
    scope = scope_of(files, built)
    sources = sources_of(root, r)
    problems = []
    fresh = {k: manifest.digest(k, v) for k, v in files.items() if not is_master(k)}
    for rel, data in sorted(files.items()):
        path = out / rel
        if not path.exists():
            problems.append(f"missing: {r.out}/{rel}")
        elif not manifest.same(rel, path.read_bytes(), data):
            problems.append(f"differs from a fresh build: {r.out}/{rel}")
    try:
        disk = manifest.load(out / manifest.NAME)
    except ManifestError as e:
        problems.append(f"{r.out}/{manifest.NAME}: {e}")
        disk = {}
    for rel in sorted(disk):
        top = rel.split("/", 1)[0]
        if top not in sources:
            problems.append(f"manifest lists a file of an asset with no source: {r.out}/{rel}")
        elif top in scope and rel not in fresh:
            problems.append(f"manifest lists a file no build makes: {r.out}/{rel}")
    for rel, digest in sorted(fresh.items()):
        if disk.get(rel) != digest:
            problems.append(f"manifest line is stale or missing: {r.out}/{rel}")
    # What the manifest vouches for outside this build's folders is known; everything else is not.
    known = set(fresh) | {rel for rel in disk if rel.split("/", 1)[0] in sources - scope}
    for rel in manifest.files_under(out):
        if rel != manifest.NAME and not is_build_output(rel, known):
            problems.append(f"not build output (renders are never hand-edited): {r.out}/{rel}")
    return problems


def main(argv: list[str] | None = None, *, repo: Path = REPO, roots: tuple[Root, ...] = ROOTS) -> int:
    ap = argparse.ArgumentParser(description="WANE art build (ADR-0023)")
    ap.add_argument("assets", nargs="*", help="asset folder names (default: all)")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--masters", action="store_true")
    ap.add_argument("--no-cache", action="store_true")
    args = ap.parse_args(argv)
    jobs = args.jobs if args.jobs > 0 else (os.cpu_count() or 1)
    pinned = assetbuild.pinned_versions(REPO / "tools" / "requirements.txt")
    installed = assetbuild.installed_versions()
    if installed != pinned:
        msg = f"installed {installed} but tools/requirements.txt pins {pinned}"
        if args.check:
            print(f"artbuild: --check needs the pinned toolchain: {msg}", file=sys.stderr)
            return 2
        print(f"artbuild: warning: {msg}; output may differ from CI's", file=sys.stderr)
    known = {n for r in roots for n in assets_in(repo, r.src)} | {"noise"}
    unknown = [a for a in args.assets if a not in known]
    if unknown:
        print(f"artbuild: unknown asset(s) {unknown}; known: {sorted(known)}", file=sys.stderr)
        return 2
    use_cache = None if (args.no_cache or args.check) else CACHE
    names = args.assets or None
    problems: list[str] = []
    total = 0
    try:
        for r in roots:
            files, built = build_root(
                repo, r, names, masters=args.masters and not args.check, jobs=jobs,
                cache_dir=use_cache, versions=pinned,
            )
            # A root nothing builds is still checked when the whole tree is: its out may hold orphans.
            if not files and (names is not None or not (repo / r.out).exists()):
                continue
            if args.check:
                problems.extend(check_root(repo, r, files, built))
            else:
                total += write_root(repo, r, files, built)
            print(f"artbuild: {r.src}: {', '.join(built) or '(noise only)' if files else '(no sources)'}")
    except (SvgError, PaletteError, PoseError, ManifestError) as e:
        print(f"artbuild: source error: {e}", file=sys.stderr)
        return 1
    if args.check:
        for p in problems:
            print(f"artbuild: {p}", file=sys.stderr)
        print("artbuild: check " + ("FAILED" if problems else "ok"))
        return 1 if problems else 0
    print(f"artbuild: wrote {total} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
