# tests/

| Folder | What | Runner |
| --- | --- | --- |
| `unit/` | gdUnit4 suites for the core and tools | `tools/ci/run_tests.gd --stage unit` |
| `replay/` | Replay fixtures: an input script and the expected state at named frames (BUILD.md section 13) | `tools/ci/run_tests.gd --stage fixtures` |
| `perf/` | The stress room benchmark (Phase 1 task 8) | `ci/perf.sh` |
| `screenshot/` | Screenshot regression (Phase 2) | |

Run everything: `ci/test.sh` (or `godot --headless --path . --script tools/ci/run_tests.gd`).
