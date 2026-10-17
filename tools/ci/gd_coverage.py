#!/usr/bin/env python3
"""Line coverage of core/ under the headless test suite (BUILD.md section 13: "core coverage
>= 85%").

GDScript has no coverage tooling, so this instruments a scratch copy of the project: before every
statement that starts a logical line inside a function body in core/**/*.gd it inserts a call to
a probe, runs the replay fixtures and the unit suites there, and reads back which probes fired.

    python3 tools/ci/gd_coverage.py [--godot PATH] [--min 85] [--report out.txt]

Exit status 1 if total coverage is below --min. The real project is never modified.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE_CLASS = "CoverageProbe"
HITS_DIR = "coverage_hits"
PASS_MARKER = "ALL STAGES PASSED"
TIME_LIMIT_SECONDS = 900
PROBE_SOURCE = f'''class_name {PROBE_CLASS}
extends RefCounted
## Injected by tools/ci/gd_coverage.py into a scratch copy of the project. Never committed.

static var _hits: Dictionary = {{}}
static var _hooked: bool = false


static func hit(file_id: int, line: int) -> void:
\tif not _hooked:
\t\t_hooked = true
\t\tvar tree: SceneTree = Engine.get_main_loop() as SceneTree
\t\tif tree != null:
\t\t\ttree.root.tree_exiting.connect(dump)
\t_hits[file_id * 1000000 + line] = true


static func dump() -> void:
\tvar dir: String = ProjectSettings.globalize_path("res://{HITS_DIR}")
\tDirAccess.make_dir_recursive_absolute(dir)
\tvar f: FileAccess = FileAccess.open(dir.path_join("%d.txt" % OS.get_process_id()), FileAccess.WRITE)
\tfor key: int in _hits.keys():
\t\tf.store_line(str(key))
\tf.close()
'''

BLOCK_HEADER = re.compile(r"^(static\s+)?func\b|^class\b")
NO_PROBE = re.compile(r"^(elif\b|else\b|func\b|static\s+func\b|class\b|@|#)")


def _strip(line: str, in_triple: str) -> tuple[str, str]:
    """Code part of a line (strings blanked, comment removed) and the triple quote (\"\"\" or
    \'\'\') still open at its end, or ""."""
    out = []
    quote = in_triple
    i = 0
    while i < len(line):
        if len(quote) == 3:
            if line.startswith(quote, i):
                quote = ""
                out.append('"')
                i += 3
            else:
                i += 1
            continue
        c = line[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = ""
                out.append(c)
            i += 1
            continue
        if c == "#":
            break
        if line.startswith('"""', i) or line.startswith("\'\'\'", i):
            quote = line[i : i + 3]
            out.append('"')
            i += 3
            continue
        if c in "\"'":
            quote = c
        out.append(c)
        i += 1
    return "".join(out), quote if len(quote) == 3 else ""


def probe_lines(source: str) -> list[int]:
    """1-based line numbers of statements that start a logical line inside a function body."""
    lines = source.split("\n")
    result: list[int] = []
    depth = 0  # bracket depth carried across lines
    continued = False  # previous line ended with a backslash
    func_indent: int | None = None  # indentation of the enclosing func header
    match_patterns: list[int] = []  # indentation levels whose lines are match patterns
    in_triple = ""
    for number, raw in enumerate(lines, start=1):
        was_in_triple = in_triple != ""
        code, in_triple = _strip(raw, in_triple)
        stripped = code.strip()
        starts_logical = depth == 0 and not continued and not was_in_triple
        indent = len(raw) - len(raw.lstrip("\t"))
        if stripped and starts_logical:
            while match_patterns and indent < match_patterns[-1]:
                match_patterns.pop()
            if func_indent is not None and indent <= func_indent:
                func_indent = None
            if BLOCK_HEADER.match(stripped) or re.match(r"^static\s+func\b", stripped):
                if stripped.startswith("class"):
                    func_indent = None
                else:
                    func_indent = indent
            elif func_indent is not None and indent > func_indent:
                is_pattern = bool(match_patterns) and indent == match_patterns[-1]
                if not is_pattern and not NO_PROBE.match(stripped):
                    result.append(number)
                if re.match(r"^match\b", stripped):
                    match_patterns.append(indent + 1)
        for c in code:
            if c in "([{":
                depth += 1
            elif c in ")]}":
                depth = max(depth - 1, 0)
        continued = code.rstrip().endswith("\\")
    return result


def instrument(source: str, file_id: int) -> tuple[str, list[int]]:
    probes = probe_lines(source)
    lines = source.split("\n")
    wanted = set(probes)
    out = []
    for number, raw in enumerate(lines, start=1):
        if number in wanted:
            indent = raw[: len(raw) - len(raw.lstrip("\t"))]
            out.append(f"{indent}{PROBE_CLASS}.hit({file_id}, {number})")
        out.append(raw)
    return "\n".join(out), probes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--min", type=float, default=85.0)
    parser.add_argument("--report", default="")
    args = parser.parse_args()

    core_files = sorted(p for p in (ROOT / "core").rglob("*.gd"))
    with tempfile.TemporaryDirectory(prefix="wane-coverage-") as tmp:
        work = Path(tmp) / "project"
        shutil.copytree(
            ROOT,
            work,
            ignore=shutil.ignore_patterns(".git", ".godot", "reports", "__pycache__"),
        )
        probes: dict[int, tuple[Path, list[int]]] = {}
        for file_id, path in enumerate(core_files):
            rel = path.relative_to(ROOT)
            text, lines = instrument(path.read_text(encoding="utf-8"), file_id)
            (work / rel).write_text(text, encoding="utf-8")
            probes[file_id] = (rel, lines)
        (work / "tools" / "ci" / "coverage_probe.gd").write_text(PROBE_SOURCE, encoding="utf-8")
        subprocess.run(
            [args.godot, "--headless", "--path", str(work), "--import"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=TIME_LIMIT_SECONDS,
        )
        # A script that fails to compile makes Godot idle instead of exiting, so the run has a
        # time limit and must print run_tests.gd's pass marker (as in ci/test.sh).
        try:
            run = subprocess.run(
                [
                    args.godot,
                    "--headless",
                    "--path",
                    str(work),
                    "--script",
                    "tools/ci/run_tests.gd",
                    "--",
                    # Instrumented scripts run several times slower than real ones.
                    "--no-time-budget",
                    "--stage",
                    "fixtures",
                    "--stage",
                    "unit",
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=TIME_LIMIT_SECONDS,
            )
        except subprocess.TimeoutExpired as expired:
            for stream, out in ((sys.stdout, expired.stdout), (sys.stderr, expired.stderr)):
                if out:
                    text_out = out.decode(errors="replace") if isinstance(out, bytes) else out
                    stream.write(text_out[-4000:])
            print(
                f"coverage: the instrumented test run hit the {TIME_LIMIT_SECONDS} s limit",
                file=sys.stderr,
            )
            return 1
        if run.returncode != 0 or PASS_MARKER not in run.stdout:
            sys.stdout.write(run.stdout[-4000:])
            sys.stderr.write(run.stderr[-4000:])
            print("coverage: the instrumented test run failed", file=sys.stderr)
            return 1
        hit: set[int] = set()
        hit_files = sorted((work / HITS_DIR).glob("*.txt"))
        for hits_file in hit_files:
            hit.update(int(x) for x in hits_file.read_text().split())
        # One file from the fixtures stage (this process) and one from the gdUnit4 child.
        if len(hit_files) < 2:
            print(f"coverage: expected hits from 2 processes, got {len(hit_files)}", file=sys.stderr)
            return 1
    rows = []
    total = covered = 0
    for file_id, (rel, lines) in probes.items():
        got = [n for n in lines if file_id * 1000000 + n in hit]
        missed = [n for n in lines if file_id * 1000000 + n not in hit]
        total += len(lines)
        covered += len(got)
        pct = 100.0 * len(got) / len(lines) if lines else 100.0
        rows.append((str(rel), len(got), len(lines), pct, missed))
    percent = 100.0 * covered / total if total else 100.0
    report = [f"{'file':48} {'covered':>8} {'lines':>6} {'%':>6}  missed lines"]
    for rel, got, n, pct, missed in rows:
        report.append(f"{rel:48} {got:8d} {n:6d} {pct:6.1f}  {','.join(map(str, missed[:30]))}")
    report.append(f"{'TOTAL core/':48} {covered:8d} {total:6d} {percent:6.1f}")
    text = "\n".join(report)
    print(text)
    if args.report:
        Path(args.report).write_text(text + "\n", encoding="utf-8")
    if percent < args.min:
        print(f"coverage: {percent:.1f}% is below the {args.min:.0f}% gate", file=sys.stderr)
        return 1
    print(f"coverage: {percent:.1f}% (gate {args.min:.0f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
