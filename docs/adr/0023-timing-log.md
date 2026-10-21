# ADR-0023: Log what every run measures, and report what got slower

- Status: Accepted
- Date: 2026-10-20
- BUILD.md sections: 13 (Testing and CI)
- Checklist lines: Process, "CI is green" (the gate must stay fast enough to run dozens of times a day)

## Summary

- Every run of `ci/test.sh`, `ci/unit.sh`, `ci/perf.sh`, `ci/build_native.sh`, `tools/ci/gd_coverage.py` and `tools/replay/film.gd` appends one JSON line per measured item to `reports/timings.jsonl` (see Log).
- Items: stages, unit suites and cases (from gdUnit4's `results.xml`), fixtures (from `FixtureRunner`), benches, native builds, the coverage run, filmed fixtures (see Writers).
- A line is `ts run commit tool stage kind item variant seconds processors load`; `load` is the 1-minute average when the run started (see Log).
- `tools/ci/timing_report.py` prints the slowest stages, suites, cases and fixtures, each against the median of its last 10 runs (see Report).
- A regression is more than 25% and 0.1 s slower than that median; a new item among the slowest is marked NEW (see Report).
- `ci/test.sh --quiet` ends with one line: the slowest three suites and any regression (see Quiet line).
- CI appends the report to the job summary and uploads the log (see CI).
- Only green runs are logged; the instrumented coverage run logs one line of its own (see Log).

## Context

BUILD.md section 13 sets the budgets that are gated (the fixture suite in 10 s, the stress room's p99) and says nothing about the rest of the gate, which is where the time goes: the unit stage took 460 s of a 470 s `ci/test.sh` on the 4-processor development container, 88 suites and 808 cases, two suites of which (the camera sweep and the overlay sweep) took 113 s and 66 s. Agents run the gate dozens of times a day and nobody could say which part had got slower, or by how much, without running it twice. The director asked for something that checks and logs what takes time and improves the slowest parts.

## Decision

**Log.** One line of JSON per measured item in `reports/timings.jsonl` (git-ignored, so one history per worktree; `WANE_TIMING_LOG=<path>` moves it, `=off` silences it). All lines of one invocation share `ts`, `run`, `commit`, `processors` and `load`. `kind` is one of `stage`, `suite`, `case`, `fixture`, `bench`, `build`, `coverage`, `film`, `total` (a whole `ci/test.sh` run). `variant` separates series that must not be compared: `native=on|off|auto` for the Godot-side lines, `release` for a bench on the release library, `built`, `cache` or `up-to-date` for a native build, the film options for a film. A case under 0.05 s and a fixture under 0.02 s are not logged (`TimingLog.FLOORS`): their suite and stage lines hold the time, and 1,200 lines of milliseconds per run would bury the 20 that matter. A run that fails is not logged (it stops early, and its numbers would only teach the report that the suite got faster). The instrumented coverage run is slow on purpose: `run_tests.gd --no-time-budget` logs nothing and `gd_coverage.py` logs the whole run as one line. The file is moved to `timings.jsonl.1` at 8 MiB; the report reads both.

**Writers.** Three writers, one format: `tools/ci/timing_log.gd` (`TimingLog`; `run_tests.gd`, `film.gd`), `ci/timing.sh` (sourced by the shell scripts; plain `printf`, no Python needed) and `tools/ci/timing_report.py` (`Writer`; `gd_coverage.py`). Logging never fails a run. `ci/unit.sh` sets `WANE_TIMING_TOOL` so that its lines say so; `ci/test.sh` exports `WANE_TIMING_RUN` so that the shell's lines (import, whole run) and Godot's share one run id. `tools/ci/unit_report.gd` reads the suites and cases from the newest `report_N/results.xml`.

**Report.** For each item the latest sample is compared with the median of the up to 10 samples before it (the latest does not count in its own baseline; an outlier run does not move a median). More than 25% slower and at least 0.1 s slower is a regression, listed by the seconds lost (a minute lost comes before a case that went from 70 to 240 ms), with the load of that run beside the median's load so that a slow line on a busy machine can be told from a slow item; the quiet line ends with the load at the start of the run for the same reason. An item is new when its only samples are from the latest run to log its kind and an earlier run logged that kind; new items among the slowest ten are marked NEW. The total is the latest run of each tool, stage by stage, and the sum of every logged run. The report only reads and always exits 0: a timing is information, never a gate (the 10 s fixture budget and the perf gates stay what they were).

**Quiet line.** After a green `ci/test.sh --quiet` the run prints `timing: slowest suites a 41.2 s, b 22.0 s, c 20.0 s; no regression` (the slowest three fixtures or stages when the run had no suites; up to three regressions, then a count). `ci/unit.sh --quiet` drops it: its output stays the single unit line.

**CI.** The `test`, `perf`, `perf-stress` and `determinism` jobs append `timing_report.py --markdown` to `$GITHUB_STEP_SUMMARY` and upload `reports/timings.jsonl` (artifact `timings-<job>`). The `test`, `perf` and `perf-stress` jobs restore `reports/timings.jsonl` from the Actions cache (the newest of the job and OS) and save it again, so that a run has history to compare with. `ci.yml`'s lint job runs `tools/ci/test_timing_report.py`.

**Reports folder.** The unit stage used to delete all of `reports/` before every run, which would have deleted the log and the perf reports with it; it now clears and uses `reports/unit/` only (gdUnit4 writes `reports/unit/report_N/`).

## Alternatives considered

| Option | Why not |
| --- | --- |
| Scrape timings out of the console output | The output is quiet by design and the gdUnit4 text does not carry case times; `results.xml` and `FixtureRunner` already hold them exactly. |
| A SQLite or CSV file | A line of JSON is appendable by `printf` from a shell script with nothing installed, survives a torn write (the reader skips the line) and is greppable. |
| Fail the gate on a regression | Wall times on a shared 4-processor container (other agents run at the same time) move by a third without the code changing. A report that fails would be switched off within a week; this one shows the load beside the number. |
| Log every case and fixture | 1,200 lines a run; the milliseconds drown the report and the file. |

## Feel reason

None directly. A gate an agent can run in two minutes is run more often, so the movement and combat fixtures are checked more often against the feel.

## Consequences

- The history is per worktree; deleting `reports/timings.jsonl` starts it over.
- Suites are timed by gdUnit4 inside the process that ran them; the parallel unit stage (ADR-0006, Unit shards) balances processes by these times.
- A new tool that wants to log uses one of the three writers; a new `kind` needs a section in `timing_report.py`'s `SECTIONS`.
