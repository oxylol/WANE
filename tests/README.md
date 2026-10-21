# tests/

| Folder | What | Runner |
| --- | --- | --- |
| `unit/` | gdUnit4 suites for the core and tools, run in up to four processes at once (below) | `tools/ci/run_tests.gd --stage unit` |
| `replay/` | Replay fixtures: an input script and the expected state at named frames (BUILD.md section 13) | `tools/ci/run_tests.gd --stage fixtures` |
| `perf/` | The stress room (200 dummies, 150 walking, 39-proc Votive set) and its 3840-tick run, timed against `content/perf/budget.tres` (docs/adr/0020) | `ci/perf.sh` |
| `screenshot/` | Screenshot regression (Phase 2) | |

Run everything: `ci/test.sh` (or `godot --headless --path . --script tools/ci/run_tests.gd`).

## The unit stage runs in several processes

`tools/ci/unit_runner.gd` splits the suites under `tests/unit/` over up to four gdUnit4 processes at
once, one per processor (`--unit-processes N` after `ci/test.sh`, or `UNIT_PROCESSES=N ci/unit.sh`,
sets the number; 1 is one process, as the stage once ran). Each process is a `GdUnitCmdTool` run of its
own with its own report folder (`reports/unit/<k>/report_1/`, CI uploads them on a failure); the stage
watches them all, stops them at the error or time limit, and merges their answers: the same
`unit PASS 854 cases 86.1 s` line, the same failure blocks. The split is made from the timing log
(longest suite first onto the process with the least so far, using each suite's median time over its
last three logged runs; a suite not yet in the log costs its file size at the rate of those that are),
so it adapts as suites change. `python3 tools/ci/timing_report.py` shows how even the last run's
processes were.

A stage that runs things at once must not pass by omission: a process that exits non-zero (a failed
case, a crash, a kill), exits 0 without printing gdUnit4's summary, or is still running at the time
limit fails the stage, and so does a suite handed to a process that its `results.xml` does not list.

What a suite in this folder must know:

- Suites that write files other suites read (the room editor's suites, which save scratch rooms
  under `tests/replay/rooms/ed_scratch/` that `test_room_document` and the editor panel read back)
  say so with a line `# unit-group: room-scratch` under `extends`; suites with the same group name
  always run in one process. `tests/unit/tools/test_unit_shards.gd` fails for a suite that touches the
  scratch rooms without it.
- A file a suite writes needs a name no other suite uses (`user://test_driver_session.wrp`, not
  `user://tmp.dat`). gdUnit4 clears `user://tmp` after every suite, so do not rely on its temp helpers
  for anything another process could be using (none of the suites do).
- A new suite is found without being listed: any script under `tests/unit/` that extends
  `GdUnitTestSuite` (directly or through a base class) and has a `func test...`. The test above holds
  this to gdUnit4's own scanner.

Finding your way around the repo (where the loop, fixtures, probes and tunables live, and every command): `docs/CODEMAP.md`.

## For agents: quiet runs

A full run prints hundreds of lines (gdUnit4's per-test lines with colour codes, engine noise).
Read the quiet one instead; CI keeps the full logs.

- `ci/test.sh --quiet` (the same as `godot --headless --path . --script tools/ci/run_tests.gd -- --quiet`,
  without the import step): one line per stage, then the closing marker and, on a green run, one
  line of timing (below, "Timing log").

  ```
  compile PASS 154 scripts 3.9 s
  content PASS 11 resources, 13 rooms 0.0 s
  fixtures PASS 386 fixtures 3.6 s
  unit PASS 854 cases 86.1 s
  ALL STAGES PASSED (104.9 s)
  timing: slowest suites test_camera_rig.gd 40.4 s, test_native_sweep.gd 35.3 s, test_debug_boxes.gd 27.4 s; no regression
  ```

  A stage that fails says `FAIL` and what failed under its line, ANSI stripped and at most 15
  lines each (at most 12 failures per stage, then a count): a script that does not compile with
  the engine's error, a content problem, a fixture with its failing expectations, a unit case as
  `suite > case` with its failure message and location. The run ends `FAILED STAGES: <names>`
  and exits 1. `--stage <name>` picks stages as before.
- `ci/unit.sh [--quiet] <res:// path>...` runs only the named gdUnit4 suites (a `.gd` file or a
  folder; `tests/unit/core/test_rng.gd` works too): the compile stage first, so a script that does
  not compile is reported with its error instead of hanging the run, then gdUnit4 with the flags
  `run_tests.gd` uses, under a time limit (`UNIT_TIME_LIMIT`, default 300 s). Quiet, a green run is
  the single line `unit PASS 19 cases 2.3 s`. Exit status is 1 on any failure, error, timeout, a
  path with no suites, or a compile error.
- Replay fixtures: `godot --headless --path . --script tools/replay/check.gd -- <fixture>...`
  prints `pass` or `FAIL` plus the failing expectations per fixture; it is already terse.

The extraction is `tools/ci/quiet_report.gd`, tested on recorded gdUnit4 output in
`tests/unit/tools/test_quiet_report.gd` (samples in `tests/unit/tools/samples/`). Under `--quiet`
every report line goes to stdout, so `2>/dev/null` drops the engine's own noise.

## Timing log: what takes time

Every run records what it measured, one JSON line per item, in `reports/timings.jsonl`
(git-ignored; `WANE_TIMING_LOG=<path>` writes elsewhere, `WANE_TIMING_LOG=off` writes nothing; the
file moves to `timings.jsonl.1` at 8 MiB and the report reads both). Who writes:

| Tool | Items |
| --- | --- |
| `ci/test.sh`, `ci/unit.sh` (`tools/ci/run_tests.gd`, `ci/timing.sh`) | `import`, each stage, each unit suite and case (gdUnit4's `results.xml`), each unit process (how evenly the split went), each fixture, the whole run |
| `ci/perf.sh` | each bench script |
| `ci/build_native.sh` | each target, as `built`, `cache` or `up-to-date` |
| `tools/ci/gd_coverage.py` | the instrumented run (its inner stages are not logged: it is slow on purpose) |
| `tools/replay/film.gd` | each fixture filmed, with the options as the variant |

Only green runs are logged (a run that fails stops early and would teach the report that the
suite got faster). A case under 0.05 s and a fixture under 0.02 s are left out (their suite and
stage lines hold the time). The fields are `ts run commit tool stage kind item variant seconds
processors load`: `load` is the 1-minute load average when the run started, so that a slow line on a
busy machine can be told from a slow item; `variant` keeps series apart that must not be compared
(`native=on` and `native=off`, `release`, `built` and `cache`).

`python3 tools/ci/timing_report.py [--top N] [--run ID] [--markdown]` prints, from the log:

- the slowest stages, suites, cases and fixtures (ten of each) with the latest time and the
  median of the (up to) ten runs before it;
- every item more than 25% and 0.1 s slower than that median (`REGRESSION`, with the load of
  that run and of the median beside it; the second condition keeps a case from "regressing" from
  7 ms to 9 ms), and every new item among the slowest (`NEW`);
- the total: the latest run of each tool, stage by stage, and the time all logged runs took.

`ci/test.sh --quiet` ends a green run with one more line, from the same log:
`timing: slowest suites test_camera_rig.gd 113.0 s, test_debug_boxes.gd 66.0 s, ...; no regression`
(or the slowest three of what that run measured when it ran no suites, and the regressions,
three at most, with the rest counted). CI appends the full report to the job summary and uploads
the log (`timings` artifact). The report only reads: it always exits 0, and a regression is for a
person to look at, not a gate. Delete `reports/timings.jsonl` to start the history over.
Tests: `python3 tools/ci/test_timing_report.py` and `tests/unit/tools/test_timing_log.gd`.
