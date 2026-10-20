# 2026-10-21: The stress room's simulation gate is closed (p99 5.01 to 2.67 ms)

- Author: Claude
- BUILD.md section and table row: section 13, Frame budget ("Input + simulation step 3.0 ms") and Testing and CI (Performance: "a stress room (200 enemies, 40 procs, Pitch lighting)"); section 13, Architecture ("C++ via GDExtension for the physics sweep, hitbox resolution ... once profiling demands it")
- Fixture(s): `tests/replay/combat/batch_mix_runs.fixture` (new, blessed on the reference loop), `tests/replay/perf/stress_pin.fixture` and every other golden unchanged; timed by `tests/perf/stress_run.fixture` through `ci/perf.sh --only stress` and `tools/bench/stage_bench.gd`
- Contact sheet: none. Nothing a player feels changed: no feel number moved, every golden hash is the same with `WANE_NATIVE=off` and on, and the new code answers exactly what the old loops answered (`tests/unit/core/enemies/test_enemy_batch.gd`, `tests/unit/core/combat/test_native_cells.gd`).

## Change

No feel number changed. The gate (`sim_p99_us` 3,000, `sim_max_us` 20,000, zone 20,000) is not touched. What changed is how much of the 3.0 ms the stress room's tick needs.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Stress input + step p50 / p99 / worst (debug native library, the spec's workload) | 2.74 / 5.18 / 7.96 (stage bench) and 2.62 / 5.01 / 7.64 (gate bench, ADR-0020 Decision 15) | 1.22 / 2.67 / 3.89 (gate bench; gate 3.00 / 20.00) | ms |
| The same with the release native library | not measured | 1.21 / 2.64 / 4.16 | ms |
| The 200 enemies' steps, p50 / p99 | 1.99 / 2.23 | 0.77 / 0.90 | ms |
| Native calls a tick for the enemies (`walk`, `floor_top_in`, `refresh_ground`) | 307 | 1 batch and about 30 single calls for the enemies that take the full step | calls |
| Combat, p50 / p99; on a tick with procs | 0.61 / 2.98; 2.30 | 0.33 / 1.74; 1.34 | ms |
| One proc of the 39-proc chain | 34 | about 22 | us |
| The state hash tick (whole `state_hash`, tick 700) | 918 | 754 | us |
| The proc storm, p99 / worst (not gated) | 8.81 / 19.84 (ADR-0020 Decision 15, 1800 ticks) | 5.15 / 9.86 | ms |

## Why

The 200 enemies took 72% of the median tick. A counter on the native calls showed that the brief's "300 `set_box` calls a tick" were really 307 calls of `walk`, `floor_top_in` and `refresh_ground` (no `set_box`: no box changes in the stress room), 3 us each, so the fix was fewer calls, not a smaller mirror: a walker's step is one call (`patrol_walk`), and the plain ticks of the whole room are one (`EnemyBatch`, `patrol_many`). Combat's remaining cost was GDScript doing 200 calls where it needed 200 comparisons, a Blaze burst that looped over the room for every enemy a finisher hit, and the cells for the procs' questions; those became comparisons, the query cells, and `WaneCells`. The rest of the table is arithmetic on a profile, in `docs/adr/0020-stress-room-and-perf-gate.md` Decision 17, one step at a time.

## How it plays now

The same. A run is a seed and its inputs and every state hash along the stress run and the 532 fixtures is unchanged. What the player gets is headroom: a room of 200 enemies and a 39-proc chain on every Taper hit now costs 2.67 ms of the 3.0 ms the simulation is allowed, and a hit that bunches a crowd (the storm: every proc event chaining, 300 to 550 procs in one tick) costs a 10 ms tick instead of 20.

## Open questions for the director

- The p99 has 0.33 ms (11%) of margin on this machine and the CI runner is slower; the `perf-stress` job is blocking from this change. If it turns red on the runner, the cells' native build (150 us of GDScript filling 200 centres) and the proc dispatch (22 us a proc) are next, then the plain walkers' state native (only that cuts the 0.78 ms the enemies still take).
- The proc storm is still ungated (p99 5.15 ms, worst 9.86): decide for Phase 2 whether a Votive that chains on every proc event is a design the engine pays for or one the Votives carry a cooldown against (PROGRESS.md, For the director).
