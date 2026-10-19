# tests/

| Folder | What | Runner |
| --- | --- | --- |
| `unit/` | gdUnit4 suites for the core and tools | `tools/ci/run_tests.gd --stage unit` |
| `replay/` | Replay fixtures: an input script and the expected state at named frames (BUILD.md section 13) | `tools/ci/run_tests.gd --stage fixtures` |
| `perf/` | The stress room benchmark (Phase 1 task 8) | `ci/perf.sh` |
| `screenshot/` | Screenshot regression (Phase 2) | |

Run everything: `ci/test.sh` (or `godot --headless --path . --script tools/ci/run_tests.gd`).

Finding your way around the repo (where the loop, fixtures, probes and tunables live, and every command): `docs/CODEMAP.md`.

## For agents: quiet runs

A full run prints hundreds of lines (gdUnit4's per-test lines with colour codes, engine noise).
Read the quiet one instead; CI keeps the full logs.

- `ci/test.sh --quiet` (the same as `godot --headless --path . --script tools/ci/run_tests.gd -- --quiet`,
  without the import step): one line per stage, then the closing marker.

  ```
  compile PASS 154 scripts 3.9 s
  content PASS 11 resources, 13 rooms 0.0 s
  fixtures PASS 386 fixtures 3.6 s
  unit PASS 487 cases 252.3 s
  ALL STAGES PASSED (259.8 s)
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
