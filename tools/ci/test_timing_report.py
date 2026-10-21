#!/usr/bin/env python3
"""Test of tools/ci/timing_report.py and ci/timing.sh: python3 tools/ci/test_timing_report.py."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import ClassVar

sys.path.insert(0, str(Path(__file__).resolve().parent))
import timing_report as report  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def entry(
    run: str,
    item: str,
    seconds: float,
    kind: str = "suite",
    stage: str = "unit",
    variant: str = "",
    load: float | None = 1.0,
    tool: str = "ci/test.sh",
) -> dict:
    return {
        "ts": "2026-10-20T22:50:39Z",
        "run": run,
        "commit": "abc1234",
        "tool": tool,
        "stage": stage,
        "kind": kind,
        "item": item,
        "variant": variant,
        "seconds": seconds,
        "processors": 4,
        "load": load,
    }


def history(item: str, times: list[float], **kwargs) -> list[dict]:
    """One sample per run, run ids r01, r02, ... in order."""
    return [entry(f"r{i + 1:02d}", item, t, **kwargs) for i, t in enumerate(times)]


def row_of(entries: list[dict], item: str, run: str | None = None) -> report.Row:
    return next(r for r in report.rows_of(entries, run) if r.key[2] == item)


class Regression(unittest.TestCase):
    def test_more_than_a_quarter_and_a_tenth_of_a_second_is_a_regression(self) -> None:
        slow = history("a.gd", [10.0] * 5 + [12.6])
        self.assertTrue(row_of(slow, "a.gd").regression)
        edge = history("a.gd", [10.0] * 5 + [12.5])
        self.assertFalse(row_of(edge, "a.gd").regression, "exactly 25% is not more than 25%")
        fine = history("a.gd", [10.0] * 5 + [9.0])
        self.assertFalse(row_of(fine, "a.gd").regression)

    def test_jitter_of_a_fast_item_is_not_a_regression(self) -> None:
        jitter = history("t", [0.007] * 5 + [0.030], kind="case")
        row = row_of(jitter, "t")
        self.assertGreater(row.change, report.REGRESSION)
        self.assertFalse(row.regression, "0.023 s slower is under the 0.1 s floor")
        real = history("t", [0.007] * 5 + [0.300], kind="case")
        self.assertTrue(row_of(real, "t").regression)

    def test_the_median_is_of_the_ten_runs_before_the_latest(self) -> None:
        # 20 old slow runs, then 10 at 5 s, then the latest at 6 s: only the ten count.
        samples = history("a.gd", [50.0] * 20 + [5.0] * 10 + [6.0])
        row = row_of(samples, "a.gd")
        self.assertEqual(len(row.prior), report.HISTORY)
        self.assertEqual(row.median, 5.0)
        self.assertEqual(row.seconds, 6.0)
        self.assertFalse(row.regression)

    def test_one_outlier_run_does_not_move_the_median(self) -> None:
        samples = history("a.gd", [5.0, 5.0, 40.0, 5.0, 5.0, 5.2])
        self.assertEqual(row_of(samples, "a.gd").median, 5.0)

    def test_an_item_with_no_earlier_run_has_no_regression(self) -> None:
        row = row_of(history("a.gd", [3.0]), "a.gd")
        self.assertIsNone(row.median)
        self.assertFalse(row.regression)

    def test_a_run_filter_compares_that_run_with_the_runs_before_it(self) -> None:
        samples = history("a.gd", [10.0, 10.0, 10.0, 20.0, 10.0])
        # Run r04 was slow; seen from r04 it regressed, seen from the latest (r05) it did not.
        self.assertTrue(row_of(samples, "a.gd", "r04").regression)
        self.assertFalse(row_of(samples, "a.gd", "r05").regression)
        self.assertEqual(len(row_of(samples, "a.gd", "r04").prior), 3)

    def test_an_item_the_filtered_run_did_not_measure_is_left_out(self) -> None:
        samples = history("a.gd", [1.0, 1.0]) + [entry("r02", "b.gd", 2.0)]
        names = [r.key[2] for r in report.rows_of(samples, "r02")]
        self.assertEqual(sorted(names), ["a.gd", "b.gd"])
        self.assertEqual([r.key[2] for r in report.rows_of(samples, "r01")], ["a.gd"])

    def test_variants_are_separate_series(self) -> None:
        samples = [
            entry("r01", "a.gd", 2.0, variant="native=on"),
            entry("r02", "a.gd", 20.0, variant="native=off"),
            entry("r03", "a.gd", 2.1, variant="native=on"),
        ]
        rows = {r.key[3]: r for r in report.rows_of(samples)}
        self.assertEqual(rows["native=on"].median, 2.0)
        self.assertIsNone(rows["native=off"].median)


class NewItems(unittest.TestCase):
    def test_a_suite_first_seen_in_the_latest_run_is_new(self) -> None:
        samples = history("old.gd", [5.0, 5.0, 5.0]) + [entry("r03", "fresh.gd", 9.0)]
        self.assertTrue(row_of(samples, "fresh.gd").new)
        self.assertFalse(row_of(samples, "old.gd").new)

    def test_nothing_is_new_in_the_first_run_of_a_kind(self) -> None:
        self.assertFalse(row_of(history("a.gd", [5.0]), "a.gd").new)

    def test_a_kind_that_never_ran_before_does_not_make_everything_new(self) -> None:
        samples = history("a.gd", [5.0, 5.0]) + [entry("r02", "build", 9.0, kind="build")]
        self.assertFalse(row_of(samples, "build").new)

    def test_an_item_seen_in_an_earlier_run_is_not_new(self) -> None:
        samples = [entry("r01", "a.gd", 5.0), entry("r02", "a.gd", 5.0), entry("r02", "b.gd", 1.0)]
        self.assertFalse(row_of(samples, "a.gd").new)
        self.assertTrue(row_of(samples, "b.gd").new)


class Reading(unittest.TestCase):
    def test_torn_and_foreign_lines_are_skipped_and_the_rotated_half_comes_first(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "timings.jsonl"
            old = json.dumps(entry("r01", "a.gd", 1.0))
            new = json.dumps(entry("r02", "a.gd", 2.0))
            Path(str(log) + ".1").write_text(old + "\n", encoding="utf-8")
            log.write_text(f'{{"torn": \n[1, 2]\n{{"seconds": "x"}}\n{new}\n', encoding="utf-8")
            got = report.read_log(log)
        self.assertEqual([e["run"] for e in got], ["r01", "r02"])

    def test_a_missing_log_reads_as_empty(self) -> None:
        self.assertEqual(report.read_log(Path(tempfile.gettempdir()) / "no-such-timings.jsonl"), [])


class Report(unittest.TestCase):
    def sample_log(self) -> list[dict]:
        entries: list[dict] = []
        for i in range(1, 7):
            run = f"r{i:02d}"
            entries.append(entry(run, "unit", 250.0, kind="stage", stage="unit"))
            entries.append(entry(run, "compile", 4.0, kind="stage", stage="compile"))
            entries.append(entry(run, "tests/unit/a/test_big.gd", 40.0))
            entries.append(entry(run, "tests/unit/a/test_mid.gd", 20.0))
            entries.append(entry(run, "tests/unit/a/test_small.gd", 2.0))
            entries.append(entry(run, "tests/unit/a/test_big.gd::test_x", 12.0, kind="case"))
            entries.append(entry(run, "jump_tap", 0.5, kind="fixture", stage="fixtures"))
            entries.append(entry(run, "ci/test.sh", 270.0, kind="total", stage="total"))
        entries.append(entry("r07", "tests/unit/a/test_mid.gd", 31.0, load=3.4))
        entries.append(entry("r07", "tests/unit/a/test_new.gd", 8.0))
        return entries

    def test_the_slowest_come_first_with_their_medians_and_the_regression_is_named(self) -> None:
        text = report.report(self.sample_log(), name="timings.jsonl")
        order = [text.index(n) for n in ("test_mid.gd  (", "test_new.gd  (", "test_small.gd  (")]
        self.assertEqual(order, sorted(order))
        self.assertIn("slowest stages", text)
        self.assertIn("slowest suites", text)
        self.assertIn("slowest cases", text)
        self.assertIn("slowest fixtures", text)
        self.assertIn(
            "suite tests/unit/a/test_mid.gd: 31.0 s vs 20.0 s (+55%, load 3.4 vs 1.0)", text
        )
        self.assertIn("test_new.gd  (NEW)", text)
        self.assertIn("test_mid.gd  (median 20.0 s of 6, +55%, REGRESSION)", text)

    def test_the_total_is_the_latest_run_of_each_tool(self) -> None:
        text = report.report(self.sample_log())
        self.assertIn(
            "ci/test.sh 2026-10-20T22:50:39Z abc1234: 270.0 s (unit 250.0, compile 4.0)", text
        )
        self.assertIn("all 6 logged runs together: 1620.0 s", text)

    def test_a_quiet_log_says_regressions_none(self) -> None:
        text = report.report(history("a.gd", [5.0, 5.0, 5.0]))
        self.assertIn("regressions: none", text)

    def test_the_top_list_is_cut_to_n(self) -> None:
        entries = [entry("r01", f"s{i:02d}.gd", float(i)) for i in range(30)]
        text = report.report(entries, top=5)
        self.assertEqual(text.count(" s  s"), 5)

    def test_an_empty_log_says_so(self) -> None:
        self.assertIn("no timings logged yet", report.report([], name="x.jsonl"))

    def test_a_variant_is_shown_when_the_same_item_has_several(self) -> None:
        entries = [
            entry("r01", "a.gd", 2.0, variant="native=on"),
            entry("r01", "a.gd", 9.0, variant="native=off"),
            entry("r01", "b.gd", 1.0, variant="native=on"),
        ]
        text = report.report(entries)
        self.assertIn("a.gd [native=off]", text)
        self.assertNotIn("b.gd [native=on]", text)

    def test_markdown_fences_the_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "timings.jsonl"
            log.write_text(json.dumps(entry("r01", "a.gd", 1.0)) + "\n", encoding="utf-8")
            done = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tools/ci/timing_report.py"),
                    "--log",
                    str(log),
                    "--markdown",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(done.returncode, 0)
        self.assertTrue(done.stdout.startswith("### Timing report\n\n```text\n"))
        self.assertTrue(done.stdout.rstrip().endswith("```"))


class Processes(unittest.TestCase):
    def processes(self, run: str, times: list[float]) -> list[dict]:
        return [
            entry(run, f"unit process {k} of {len(times)}", t, kind="process")
            for k, t in enumerate(times)
        ]

    def test_the_latest_runs_processes_and_how_even_they_were_are_reported(self) -> None:
        entries = self.processes("r01", [200.0, 50.0]) + self.processes(
            "r02", [90.0, 100.0, 110.0, 100.0]
        )
        text = report.report(entries)
        self.assertIn(
            "0: 90.0 s, 1: 100.0 s, 2: 110.0 s, 3: 100.0 s; slowest is 1.10 x the mean", text
        )
        self.assertNotIn("200.0 s", text)

    def test_processes_are_not_listed_as_items_or_flagged(self) -> None:
        entries = self.processes("r01", [50.0, 50.0]) + self.processes("r02", [90.0, 90.0])
        text = report.report(entries)
        self.assertIn("regressions: none", text)
        self.assertNotIn("slowest stages", text)
        self.assertEqual(report.brief(entries, "r02"), "")

    def test_a_log_without_processes_has_no_such_line(self) -> None:
        self.assertNotIn("unit processes", report.report(history("a.gd", [1.0, 1.0])))


class Brief(unittest.TestCase):
    def test_it_names_the_three_slowest_suites_of_the_run_and_the_regression(self) -> None:
        entries = Report().sample_log()
        line = report.brief(entries, "r07")
        self.assertTrue(
            line.startswith("timing: slowest suites test_mid.gd 31.0 s, test_new.gd 8.00 s")
        )
        self.assertIn("regression: suite test_mid.gd: 31.0 s vs 20.0 s (+55%)", line)
        self.assertNotIn("\n", line)

    def test_no_regression_is_said(self) -> None:
        line = report.brief(history("a/test_a.gd", [5.0, 5.0, 5.0]), "r03")
        self.assertEqual(line, "timing: slowest suites test_a.gd 5.00 s; no regression")

    def test_more_than_three_regressions_are_counted(self) -> None:
        entries: list[dict] = []
        for n in range(5):
            entries += history(f"s{n}.gd", [10.0, 10.0, 10.0, 20.0 + n])
        line = report.brief(entries, "r04")
        self.assertIn("+2 more", line)
        self.assertEqual(line.count("regression:"), 1)

    def test_a_run_without_suites_falls_back_to_fixtures_then_stages(self) -> None:
        fixtures = [entry("r01", "jump", 0.5, kind="fixture", stage="fixtures")]
        self.assertIn("slowest fixtures jump 0.500 s", report.brief(fixtures, "r01"))
        stages = [entry("r01", "compile", 4.0, kind="stage", stage="compile")]
        self.assertIn("slowest stages compile 4.00 s", report.brief(stages, "r01"))

    def test_a_run_that_measured_nothing_has_no_line(self) -> None:
        self.assertEqual(report.brief([], None), "")
        self.assertEqual(report.brief(history("a.gd", [1.0]), "other-run"), "")


class Writers(unittest.TestCase):
    FIELD_TYPES: ClassVar[dict[str, type]] = {
        "ts": str,
        "run": str,
        "commit": str,
        "tool": str,
        "stage": str,
        "kind": str,
        "item": str,
        "variant": str,
        "seconds": float,
        "processors": int,
    }

    def check_line(self, line: dict) -> None:
        self.assertEqual(tuple(line), report.FIELDS)
        for name, kind in self.FIELD_TYPES.items():
            self.assertIsInstance(line[name], (int, float) if kind is float else kind, name)
        self.assertTrue(line["load"] is None or isinstance(line["load"], (int, float)))

    def test_the_python_writer_writes_the_documented_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "reports" / "timings.jsonl"
            writer = report.Writer("tools/ci/gd_coverage.py", log)
            writer.add("coverage", "coverage", 'a "quoted" item', 12.3456, "native=on")
            writer.add("coverage", "coverage", "second", 1.0)
            lines = [json.loads(x) for x in log.read_text(encoding="utf-8").splitlines()]
        self.assertEqual(len(lines), 2)
        self.check_line(lines[0])
        self.assertEqual(lines[0]["item"], 'a "quoted" item')
        self.assertEqual(lines[0]["seconds"], 12.346)
        self.assertEqual(lines[0]["run"], lines[1]["run"])
        self.assertEqual(lines[0]["ts"], lines[1]["ts"])

    def test_off_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "timings.jsonl"
            old = os.environ.get(report.ENV_LOG)
            os.environ[report.ENV_LOG] = "off"
            try:
                report.Writer("x").add("s", "stage", "i", 1.0)
            finally:
                if old is None:
                    del os.environ[report.ENV_LOG]
                else:
                    os.environ[report.ENV_LOG] = old
            self.assertFalse(log.exists())

    def test_a_big_log_is_rotated_and_still_read_whole(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "timings.jsonl"
            log.write_text(json.dumps(entry("r01", "a.gd", 1.0)) + " " * report.MAX_BYTES + "\n")
            report.Writer("x", log).add("s", "stage", "i", 1.0)
            self.assertTrue(Path(str(log) + ".1").exists())
            runs = [e["run"] for e in report.read_log(log)]
        self.assertEqual(runs[0], "r01")
        self.assertEqual(len(runs), 2)

    def test_the_shell_writer_writes_the_same_fields(self) -> None:
        bash = shutil.which("bash")
        self.assertIsNotNone(bash, "ci/*.sh need bash")
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "reports" / "timings.jsonl"
            env = dict(os.environ, WANE_TIMING_LOG=str(log))
            env.pop("WANE_TIMING_TOOL", None)
            env.pop("WANE_TIMING_RUN", None)
            script = (
                ". ci/timing.sh; timing_init ci/perf.sh; "
                'timing_log perf bench "a \\"b\\".gd" "release" 12.5; '
                'timing_log native build template_debug "linux cache" '
                '"$(timing_since "$(timing_now)")"'
            )
            done = subprocess.run(
                [bash, "-c", script], cwd=ROOT, env=env, capture_output=True, text=True, check=False
            )
            self.assertEqual(done.returncode, 0, done.stderr)
            lines = [json.loads(x) for x in log.read_text(encoding="utf-8").splitlines()]
        self.assertEqual(len(lines), 2)
        for line in lines:
            self.check_line(line)
        self.assertEqual(lines[0]["tool"], "ci/perf.sh")
        self.assertEqual(lines[0]["item"], 'a "b".gd')
        self.assertEqual(lines[0]["seconds"], 12.5)
        self.assertEqual(lines[1]["variant"], "linux cache")
        self.assertLess(lines[1]["seconds"], 1.0)
        self.assertEqual(lines[0]["run"], lines[1]["run"])

    def test_the_shell_writer_honours_off_and_the_tool_and_run_the_caller_set(self) -> None:
        bash = shutil.which("bash")
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "timings.jsonl"
            env = dict(os.environ, WANE_TIMING_TOOL="ci/unit.sh", WANE_TIMING_RUN="shared-1")
            env["WANE_TIMING_LOG"] = str(log)
            script = ". ci/timing.sh; timing_init ci/test.sh; timing_log unit stage unit '' 3"
            subprocess.run([bash, "-c", script], cwd=ROOT, env=env, check=True)
            line = json.loads(log.read_text(encoding="utf-8"))
            self.assertEqual((line["tool"], line["run"]), ("ci/unit.sh", "shared-1"))
            log.unlink()
            env["WANE_TIMING_LOG"] = "off"
            subprocess.run([bash, "-c", script], cwd=ROOT, env=env, check=True)
            self.assertFalse(log.exists())


if __name__ == "__main__":
    unittest.main()
