#!/usr/bin/env python3
"""The timing log and its report (BUILD.md section 13, "Testing and CI"; docs/adr/0023).

Every run of ci/test.sh (per stage, suite, case and fixture), ci/unit.sh, ci/perf.sh (per bench),
ci/build_native.sh, tools/ci/gd_coverage.py and tools/replay/film.gd appends one JSON line per
measured item to reports/timings.jsonl (git-ignored; the file is moved to timings.jsonl.1 at
8 MiB and the report reads both). A line has these fields:

    ts         UTC time stamp of the invocation, 2026-10-20T22:50:39Z
    run        id of the invocation (all its lines share it)
    commit     short SHA of HEAD, or "unknown"
    tool       the script that started the run: ci/test.sh, ci/unit.sh, ci/perf.sh, ...
    stage      compile, content, fixtures, unit, import, perf, native, coverage, film
    kind       stage, suite, case, fixture, bench, build, coverage, film, or total (a whole run)
    item       what was measured: a stage's name, a suite's path, "path::case", a fixture's name
    variant    what must not be compared across ("native=on", "release", "cold"), or ""
    seconds    wall time of the item
    processors the machine's processor count
    load       the 1-minute load average when the run started, or null

    python3 tools/ci/timing_report.py [--log PATH] [--run ID] [--top N] [--markdown] [--brief]

The report lists the slowest stages, suites, cases and fixtures with each item's latest time
against the median of the (up to) 10 runs before it, marks a regression (more than 25 % and
0.1 s slower than that median; the second condition keeps a 7 ms case from "regressing" to 9 ms)
and any new item among the slowest, and prints the totals. --brief is the one line
ci/test.sh --quiet ends with: the slowest three suites of --run and its regressions. The report
only reads; it always exits 0.

Other Python tools write lines with Writer (tools/ci/gd_coverage.py does).
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LOG = ROOT / "reports" / "timings.jsonl"
ENV_LOG = "WANE_TIMING_LOG"
ENV_TOOL = "WANE_TIMING_TOOL"
ENV_RUN = "WANE_TIMING_RUN"
MAX_BYTES = 8 * 1024 * 1024
FIELDS = (
    "ts",
    "run",
    "commit",
    "tool",
    "stage",
    "kind",
    "item",
    "variant",
    "seconds",
    "processors",
    "load",
)
# An item that is this much slower than the median of its last runs, and by at least MIN_DELTA
# seconds, is a regression.
REGRESSION = 0.25
MIN_DELTA = 0.1
HISTORY = 10
TOP = 10
BRIEF_SUITES = 3
BRIEF_REGRESSIONS = 3
# Kinds listed as "stages": the steps of a run, whatever tool ran them.
STAGE_KINDS = ("stage", "bench", "build", "coverage", "film")
SECTIONS = (
    ("slowest stages", STAGE_KINDS),
    ("slowest suites", ("suite",)),
    ("slowest cases", ("case",)),
    ("slowest fixtures", ("fixture",)),
)

Key = tuple[str, str, str, str]


class Writer:
    """Appends lines to the log for one invocation of a Python tool: the time stamp, run id,
    commit, processor count and load average are taken once, when the Writer is made."""

    def __init__(self, tool: str, path: Path | None = None) -> None:
        env_path = os.environ.get(ENV_LOG, "")
        self.path: Path | None
        if path is not None:
            self.path = path
        elif env_path == "off":
            self.path = None
        else:
            self.path = Path(env_path) if env_path else DEFAULT_LOG
        self.tool = os.environ.get(ENV_TOOL) or tool
        self.ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        compact = self.ts.replace("-", "").replace(":", "").rstrip("Z")
        self.run = os.environ.get(ENV_RUN) or f"{compact}-{os.getpid()}"
        self.commit = _git_commit()
        self.processors = os.cpu_count() or 1
        try:
            self.load: float | None = round(os.getloadavg()[0], 2)
        except (AttributeError, OSError):
            self.load = None

    def add(self, stage: str, kind: str, item: str, seconds: float, variant: str = "") -> None:
        """Appends one line; a log that cannot be written is not an error of the run."""
        if self.path is None:
            return
        entry = {
            "ts": self.ts,
            "run": self.run,
            "commit": self.commit,
            "tool": self.tool,
            "stage": stage,
            "kind": kind,
            "item": item,
            "variant": variant,
            "seconds": round(seconds, 3),
            "processors": self.processors,
            "load": self.load,
        }
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            if self.path.exists() and self.path.stat().st_size > MAX_BYTES:
                os.replace(self.path, str(self.path) + ".1")
            with self.path.open("a", encoding="utf-8") as log:
                log.write(json.dumps(entry, separators=(",", ":")) + "\n")
        except OSError:
            pass


def _git_commit() -> str:
    try:
        done = subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    return done.stdout.strip() if done.returncode == 0 and done.stdout.strip() else "unknown"


def read_log(path: Path) -> list[dict]:
    """The entries of the log at `path` (the rotated half first), oldest first. A line that is
    not an entry (a torn write, a hand edit) is skipped."""
    entries: list[dict] = []
    for part in (Path(str(path) + ".1"), path):
        if not part.is_file():
            continue
        for raw in part.read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                entry = json.loads(raw)
            except ValueError:
                continue
            if (
                isinstance(entry, dict)
                and isinstance(entry.get("seconds"), (int, float))
                and all(isinstance(entry.get(k), str) for k in ("run", "kind", "stage", "item"))
            ):
                entry.setdefault("tool", "")
                entry.setdefault("variant", "")
                entry.setdefault("commit", "unknown")
                entry.setdefault("ts", "")
                entries.append(entry)
    return entries


def key_of(entry: dict) -> Key:
    return (entry["kind"], entry["stage"], entry["item"], entry.get("variant") or "")


@dataclass
class Row:
    """One item: its latest sample and the samples before it."""

    key: Key
    latest: dict
    prior: list[dict] = field(default_factory=list)
    new: bool = False

    @property
    def seconds(self) -> float:
        return float(self.latest["seconds"])

    @property
    def median(self) -> float | None:
        if not self.prior:
            return None
        return statistics.median(float(e["seconds"]) for e in self.prior)

    @property
    def change(self) -> float | None:
        """The latest time as a fraction above (or below) the median, or None without one."""
        median = self.median
        if median is None or median <= 0:
            return None
        return self.seconds / median - 1.0

    @property
    def regression(self) -> bool:
        median = self.median
        change = self.change
        return (
            median is not None
            and change is not None
            and change > REGRESSION
            and self.seconds - median >= MIN_DELTA
        )

    @property
    def prior_load(self) -> float | None:
        loads = [e["load"] for e in self.prior if isinstance(e.get("load"), (int, float))]
        return statistics.median(loads) if loads else None


def rows_of(entries: list[dict], run: str | None = None) -> list[Row]:
    """One Row per item. The latest sample is the last in the log, or, with `run`, the one that
    run took (items it did not measure are left out); the prior samples are the HISTORY before
    it. An item is new when every sample it has is from the latest run to log its kind and an
    earlier run logged that kind."""
    series: dict[Key, list[dict]] = {}
    runs_of_kind: dict[str, list[str]] = {}
    for entry in entries:
        series.setdefault(key_of(entry), []).append(entry)
        runs = runs_of_kind.setdefault(entry["kind"], [])
        if entry["run"] not in runs:
            runs.append(entry["run"])
    rows: list[Row] = []
    for key, samples in series.items():
        index = len(samples) - 1
        if run is not None:
            hits = [i for i, e in enumerate(samples) if e["run"] == run]
            if not hits:
                continue
            index = hits[-1]
        prior = [e for e in samples[:index] if e["run"] != samples[index]["run"]][-HISTORY:]
        kind_runs = runs_of_kind[key[0]]
        own_runs = {e["run"] for e in samples}
        latest_kind_run = run if run is not None else kind_runs[-1]
        new = not prior and own_runs == {latest_kind_run} and len(kind_runs) > 1
        rows.append(Row(key, samples[index], prior, new))
    return rows


def label_of(row: Row, ambiguous: set[tuple[str, str, str]]) -> str:
    kind, stage, item, variant = row.key
    if kind in STAGE_KINDS:
        text = item if stage == item else f"{stage}: {item}"
    else:
        text = item
    if (kind, stage, item) in ambiguous and variant:
        text += f" [{variant}]"
    return text


def fmt_seconds(seconds: float) -> str:
    if seconds < 1:
        return f"{seconds:.3f} s"
    if seconds < 10:
        return f"{seconds:.2f} s"
    return f"{seconds:.1f} s"


def fmt_change(row: Row) -> str:
    """What follows an item's latest time: its median and how far it is from it."""
    change, median = row.change, row.median
    if row.new:
        return "NEW"
    if change is None or median is None:
        return "no earlier run"
    text = f"median {fmt_seconds(median)} of {len(row.prior)}, {round(change * 100):+d}%"
    if row.regression:
        text += ", REGRESSION"
    return text


def _ambiguous(entries: list[dict]) -> set[tuple[str, str, str]]:
    variants: dict[tuple[str, str, str], set[str]] = {}
    for e in entries:
        variants.setdefault((e["kind"], e["stage"], e["item"]), set()).add(e.get("variant") or "")
    return {k for k, v in variants.items() if len(v) > 1}


def regression_text(row: Row, ambiguous: set[tuple[str, str, str]], short: bool = False) -> str:
    median = row.median or 0.0
    name = label_of(row, ambiguous)
    if short:
        name = name.rsplit("/", 1)[-1]
    text = (
        f"{row.key[0]} {name}: {fmt_seconds(row.seconds)} vs {fmt_seconds(median)} "
        f"({round((row.change or 0) * 100):+d}%"
    )
    load, before = row.latest.get("load"), row.prior_load
    if short or not isinstance(load, (int, float)) or before is None:
        return text + ")"
    return text + f", load {load:.1f} vs {before:.1f})"


def totals(entries: list[dict]) -> list[str]:
    """The latest run of each tool that timed stages: its wall time (the `total` line, else the
    sum of its stage lines) with the stages that make it up; and the time the whole log covers."""
    lines: list[str] = []
    by_tool: dict[str, list[dict]] = {}
    for e in entries:
        by_tool.setdefault(e["tool"], []).append(e)
    for tool, mine in sorted(by_tool.items()):
        timed = [e for e in mine if e["kind"] in STAGE_KINDS or e["kind"] == "total"]
        if not timed:
            continue
        last = [e for e in mine if e["run"] == timed[-1]["run"]]
        stages = [e for e in last if e["kind"] in STAGE_KINDS]
        whole = [e for e in last if e["kind"] == "total"]
        seconds = whole[-1]["seconds"] if whole else sum(e["seconds"] for e in stages)
        parts = ", ".join(f"{e['item']} {e['seconds']:.1f}" for e in stages)
        head = f"{tool} {last[0]['ts']} {last[0]['commit']}: {fmt_seconds(seconds)}"
        lines.append(head + (f" ({parts})" if parts else ""))
    wholes = [e for e in entries if e["kind"] == "total"]
    if wholes:
        spent = sum(e["seconds"] for e in wholes)
        lines.append(f"all {len(wholes)} logged runs together: {fmt_seconds(spent)}")
    return lines


def report(entries: list[dict], run: str | None = None, top: int = TOP, name: str = "") -> str:
    """The whole report as text."""
    if not entries:
        return f"no timings logged yet{' in ' + name if name else ''}"
    rows = rows_of(entries, run)
    ambiguous = _ambiguous(entries)
    runs: list[str] = []
    for e in entries:
        if e["run"] not in runs:
            runs.append(e["run"])
    last = entries[-1]
    out = [
        (
            f"timing report: {name or 'log'}: {len(entries)} lines, {len(runs)} runs, "
            f"{entries[0]['ts']} to {last['ts']}"
        )
    ]
    load = last.get("load")
    load_text = f"{load:.2f}" if isinstance(load, (int, float)) else "unknown"
    out.append(
        f"latest run: {last['tool']} {last['ts']} commit {last['commit']}, "
        f"{last.get('processors', '?')} processors, load {load_text}"
    )
    for title, kinds in SECTIONS:
        mine = sorted((r for r in rows if r.key[0] in kinds), key=lambda r: -r.seconds)[:top]
        if not mine:
            continue
        out.append("")
        out.append(f"{title} (latest, then the median of up to {HISTORY} earlier runs)")
        for rank, row in enumerate(mine, start=1):
            out.append(
                f"  {rank:2d}. {fmt_seconds(row.seconds):>9}  {label_of(row, ambiguous)}"
                f"  ({fmt_change(row)})"
            )
    flagged = sorted((r for r in rows if r.regression), key=lambda r: -(r.change or 0))
    out.append("")
    if flagged:
        out.append(
            f"regressions: more than {REGRESSION * 100:.0f}% and {MIN_DELTA} s slower than the "
            f"median of the last {HISTORY} runs ({len(flagged)})"
        )
        for row in flagged[:20]:
            out.append("  " + regression_text(row, ambiguous))
        if len(flagged) > 20:
            out.append(f"  ... {len(flagged) - 20} more")
    else:
        out.append("regressions: none")
    out.append("")
    out.append("total")
    out.extend("  " + line for line in totals(entries))
    return "\n".join(out)


def brief(entries: list[dict], run: str | None) -> str:
    """The line ci/test.sh --quiet ends with, or "" when the run measured nothing."""
    if run is None and entries:
        run = entries[-1]["run"]
    rows = rows_of(entries, run)
    if not rows:
        return ""
    ambiguous = _ambiguous(entries)
    what, kinds = "suites", ("suite",)
    for name, group in (
        ("suites", ("suite",)),
        ("fixtures", ("fixture",)),
        ("stages", STAGE_KINDS),
    ):
        if any(r.key[0] in group for r in rows):
            what, kinds = name, group
            break
    slowest = sorted((r for r in rows if r.key[0] in kinds), key=lambda r: -r.seconds)
    shown = ", ".join(
        f"{label_of(r, ambiguous).rsplit('/', 1)[-1]} {fmt_seconds(r.seconds)}"
        for r in slowest[:BRIEF_SUITES]
    )
    flagged = sorted((r for r in rows if r.regression), key=lambda r: -(r.change or 0))
    if flagged:
        texts = [regression_text(r, ambiguous, short=True) for r in flagged[:BRIEF_REGRESSIONS]]
        more = (
            f", +{len(flagged) - BRIEF_REGRESSIONS} more"
            if len(flagged) > BRIEF_REGRESSIONS
            else ""
        )
        verdict = "regression: " + "; ".join(texts) + more
    else:
        verdict = "no regression"
    return f"timing: slowest {what} {shown}; {verdict}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--log", default=os.environ.get(ENV_LOG) or str(DEFAULT_LOG))
    parser.add_argument("--run", default=None, help="limit the report to the items of this run")
    parser.add_argument("--top", type=int, default=TOP)
    parser.add_argument("--brief", action="store_true", help="the one line ci/test.sh ends with")
    parser.add_argument("--markdown", action="store_true", help="for $GITHUB_STEP_SUMMARY")
    args = parser.parse_args(argv)
    if args.log == "off":
        return 0
    path = Path(args.log)
    entries = read_log(path)
    if args.brief:
        text = brief(entries, args.run)
        if text:
            print(text)
        return 0
    text = report(entries, args.run, args.top, str(path.name))
    if args.markdown:
        print("### Timing report\n\n```text\n" + text + "\n```")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
