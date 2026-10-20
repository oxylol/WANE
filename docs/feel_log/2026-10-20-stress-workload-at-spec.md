# 2026-10-20: The stress room's workload at the spec, and what the CPU budget looks like with the native sweep

- Author: Claude
- BUILD.md section and table row: section 13, Testing and CI (Performance: "a stress room (200 enemies, 40 procs, Pitch lighting)", "With 40 procs firing, the screen must still be readable") and Frame budget ("Input + simulation step 3.0 ms")
- Fixture(s): `tests/replay/perf/stress_pin.fixture` (re-blessed), `tests/replay/perf/storm_pin.fixture` (the old pin, same hash), `tests/replay/procs/stress_taper_spell_starts_no_chain.fixture`, `tests/perf/stress_run.fixture` and `tests/perf/storm_run.fixture` (timed by `ci/perf.sh`)
- Contact sheet: none. Nothing a player feels changed: the Votive sets are test content and `core/` gained a read-only accessor (`ProcApi.tick()`). `docs/feel_log/2026-10-19-task8-stress.png` (a 45-proc burst at Pitch) is the readability sheet and still describes the gated burst (39 procs, 45 with the inert rolls).

## Change

No feel number changed. The gate (`sim_p99_us` 3,000, `sim_max_us` 20,000, zone 20,000) is not touched. What changed is the workload the gate is measured on, which was 13 times the spec.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Most procs on one tick of the gated run | 525 (the storm) | 88 (45 at the first swing) | procs |
| Procs a Taper hit starts (any number of dummies in the swing) | 39 each dummy | 39 once per 3 ticks | procs |
| Procs a spell tick starts | a sure chain, 39 | none (it rolls, inert) | procs |
| Procs over the 3840 ticks | about 24,800 | 9,825 | procs |
| `min_procs`, `min_hits` (scenario guards, not gates) | 12,000, 14,000 | 8,000, 9,000 | count |
| Stress input + step p50 / p99 / worst, GDScript sweep, the storm | 3.89 / 9.00 / 20.26 | 5.05 / 11.22 / 22.23 (1800 ticks, this machine today) | ms |
| Stress input + step p50 / p99 / worst, GDScript sweep, the spec's workload | not measured | 5.14 / 7.68 / 11.21 | ms |
| Stress input + step p50 / p99 / worst, native sweep, the spec's workload | not measured | 2.68 / 5.06 / 8.09 (gate 3.00 / 20.00) | ms |
| Stress input + step p50 / p99 / worst, native sweep, the storm | 2.01 / 7.04 / n.a. (ADR-0022, 3840 ticks) | 2.79 / 9.36 / 19.46 (1800 ticks) | ms |
| Zone 1 loop x5, worst tick, GDScript / native | 1.01 (feel log of this morning) | 1.61 / 0.95 (gate 20) | ms |
| Presentation script p99, GDScript / native | 3.64 (the storm) | 4.82 / 4.49 (gate 5.00) | ms |
| Cost of a proc (storm, ticks of 100 procs or more) | 30 | 34 | us |

Measured on this container (4 cores) idle (load average 0.3 to 0.9 when each run started), best of 3 whole runs per tick, `template_debug` native library, headless.

## Why

The perf gate was red on a workload the spec does not describe. "40 procs" is one hit's burst. The stress Votive set fired a sure 3 + 9 + 27 chain on every proc event from every source, so a swing that landed on ten bunched dummies raised ten chains (a tick of 552 procs, 10 finisher hits and a charged hit), and a Kindle cone or Radiance burst did the same. The feel log of this morning blamed the spells; with the spells switched off the worst tick was still 552 procs, so the area of a finisher on a bunched crowd is the larger cause. A real Votive has a chance, a coefficient per source (Kindle 0.5, Radiance 0.2) and, when it is strong, an internal cooldown. So the gated set starts one chain per Taper hit or pogo with a 3-tick cooldown (the Votive keeps the tick of its last chain in its counter; `ProcApi.tick()` is new for that), and ignores spell ticks. The storm is kept as its own run, measured and reported with the cost of a proc, never gated: it answers a Phase 2 design question, not the CI.

With the native sweep the median tick fell from 5.14 to 2.68 ms and the worst from 11.2 to 8.1 ms, so the worst-tick gate (20 ms) is met by a wide margin. The p99 is 5.06 ms against 3.00, so the gate fails and the `perf-stress` job keeps `continue-on-error` (expiry 2026-12-31). The stages (`tools/bench/stage_bench.gd`, native, p50 / p99 ms): the 200 enemies' steps 1.95 / 2.19, combat 0.62 / 2.90, the player 0.10 / 0.20, the state hash 0.00 / 1.17 (every 60th tick). The 200 enemies' steps are 72% of the median tick, 9.8 us each, so even a free proc path would leave a median tick of 2.7 ms and 0.3 ms for a burst. What remains is, in order: the enemies' step in C++, the proc path (34 us a proc), combat's hit resolution (0.6 ms a tick), the hash tick.

## How it plays now

Nothing changes in play. The gated run: Ash meets about 150 walkers and 67 swingers; each swing starts one chain, so the screen has at most about 45 procs' marks a burst, as BUILD.md asks. `stress_taper_spell_starts_no_chain` shows a Kindle burn tick rolling three procs that do nothing; `test_stress_sets.gd` shows the cooldown.

## Open questions for the director

- Proc storms in late runs (Phase 2's Votives): a Votive that chains on every event, three of them stacked, costs 34 us a proc, and a swing on a bunched crowd is 300 to 550 procs: 10 to 17 ms in one tick on this machine even with the native sweep. Do the Votives get internal cooldowns or a per-tick proc budget (a design rule the doc should state), or does the engine take the cost (proc path in C++)? The storm run in `ci/perf.sh` shows the cost whichever way.
- The next C++ step: the enemies' step (1.95 ms a tick) or hit resolution first? The profile says the enemies' step.
- To run: `ci/perf.sh --only stress` (gated run plus the storm), `godot --headless --path . --script tools/bench/stage_bench.gd` (the stages; `-- --storm` for the storm).
