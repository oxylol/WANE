# ADR-0020: Gate the CPU budget on a stress room of walking dummies, and answer flat floors without the sweep

- Status: Accepted (the budget is not met: see Decision 8 and the director question)
- Date: 2026-10-20
- BUILD.md sections:
  - 13, Testing and CI: "Performance | a stress room (200 enemies, 40 procs, Pitch lighting) on a GPU runner | 60 fps with 99th-percentile frame time <= 16.0 ms on reference PC settings, <= 15.0 ms on the Deck profile";
  - 13, Frame budget: "Input + simulation step 3.0 ms; Sprite and animation submit 2.0; Lighting pass 3.0; VFX 2.0; Post 1.0; Audio and UI 1.0; Headroom 4.6" (16.6 ms);
  - 13, Determinism and replays (the golden hashes of every fixture stay what they were).
- CLAUDE.md: kickoff 8 ("The stress room (200 enemies, 40 procs, Pitch lighting) and the perf benchmark in CI"), rule 6 (the gate's numbers are content), "Lowering a gate threshold" is prohibited, "C++ GDExtension only for profiled hot paths, and a GDScript reference implementation is kept and tested against it".
- Checklist lines (BUILD.md section 15): "The game holds 60 fps in the stress room on the Deck profile with the lighting pass on" (CPU half measured, not met); "No frame-time spike above 20 ms in a 5-minute zone 1 run" (simulation side met: 1.0 ms); "With 30 Votives active, the screen stays readable" (presentation, not a CPU matter; see Decision 9).

## Summary

- The stress room `perf/stress` (`tests/perf/rooms/stress.room`) holds 200 training dummies, 151 of them walking and 67 swinging (27 red), over flats, both ramps, two tiers of one-way platforms, curbs and hung solid boxes (see Decision 1).
- A dummy walks with the marker `patrol=1` (turns at walls and ledges; `fall=1` walks off); speed 120 u/s and ledge depth 16 u are in `content/enemies/dummy.tres` (see Decision 2).
- `tests/perf/stress_run.fixture` (3840 ticks, the stress Votive set: 39 procs a Taper hit) is timed by `tools/bench/stress_bench.gd`; its first 60 ticks are the blessed fixture `stress_pin` (see Decision 3).
- Gate: p99 of input plus `Simulation.step` <= 3.0 ms, worst tick <= 20 ms, zone 1 loop x5 worst tick <= 20 ms; all in `content/perf/budget.tres`; each tick's time is the least of 3 runs (see Decision 4).
- `ci/perf.sh` runs it; the `perf` job in `ci.yml` uploads `reports/perf.txt` (see Decision 5).
- `FlatWalk` answers `walk()` and `refresh_ground()` for a body on a flat tile floor without the sweep; the sweep stays the reference and a differential test plays both (see Decision 6).
- Measured on this machine, best of 3: p50 8.03 to 3.89 ms, p99 13.40 to 9.00 ms, worst 26.4 to 20.3 ms; the gate (3.0 ms p99) is not met and GDScript cannot meet it (see Decisions 7 and 8).
- Remaining cost: ramps and plateaus (35 us a step), 30 us per proc (a 40-proc burst 1.3 ms; an AoE hit on a crowd 500 procs, 16 ms), 3 ms of baseline: a C++ decision for the lead (see Decision 8).

## Context

Phase 1 task 8 needs a stress room and a perf gate. BUILD.md gates a frame on a GPU runner; CI has none (PROGRESS.md, Blocked 2) and no lighting pass exists before Phase 2, so what can be gated now is the simulation's share of the frame: "Input + simulation step 3.0 ms". ADR-0008 measured the sweep for 200 bodies at 2 to 4.5 ms alone and said task 8 would profile the stress room and, if the sweep was still the hot path, port `CollisionWorld` to C++ with this GDScript as the reference. ADR-0015 measured a 39-proc burst at 1.3 ms. Phase 1 had only standing dummies; zone enemies move.

## Decision

1. **The stress room.** 128 x 30 tiles. The ground is flats and ramps (45-degree up and down 2 to 4 tiles, 1:2 up and down 2 to 3 tiles, ten stretches in all); nine one-way platforms 6 tiles up and seven 11 up; six 8 u curbs on the floor (a wall to a walking dummy, a step to Ash); ten solid boxes hung between the tiers. 100 dummies on the ground (70 walking), 50 on the lower tier (40 walking, 10 falling), 30 on the upper (24, 6), 20 on the hung boxes (16, 6). 67 of the 200 swing: 40 white (parryable) and 27 red. `tools/perf/make_stress.py` writes the room and the run (seeded, deterministic); the files are the source. Room ids `perf/<name>` resolve to `tests/perf/rooms/` (`RoomData.PERF_ROOT`). Pitch lighting is not in the room: there is no lighting pass in Phase 1.
2. **Walking dummies.** `entity dummy ... patrol=1 [fall=1] [facing=-1|1]`. A walking dummy turns when `walk` reports a wall, and turns at a ledge when no floor lies within `patrol_drop_u` (16) of its feet under the leading edge after the step, unless `fall=1`. It stands for a swing (facing the player as it starts) and walks on after. On the ground it uses `walk`, in the air `move_x` and gravity. Its state hash gains `patrol_dir` only when it is not 0, so a standing dummy hashes as it always did. The content hash of `dummy.tres` moved (two new fields), so the content fingerprint of 144 fixtures was re-blessed; none of their state hashes changed. A walker skips the ground re-read after its own `walk` (`Enemy.settled`): `walk` leaves `on_ground` as a re-read would (checked on the whole run: it differs only in the tile kind and slope flag named at the join of a ramp and its plateau, which enemies never read).
3. **The scenario and its pin.** `stress_run.fixture` holds the stress Votive set (`test_stress_arc_a/b/c`, ADR-0015) at 1 stack each, so a Taper hit raises 40 events and fires 39 procs, and Ash sweeps the room east and west in passes of 330 ticks, in a seeded order of strikes, three-strike chains, dashes, hops with a down-strike pogo, Kindle casts and up-strikes (about 24,800 procs, 26,000 hits, 160 kills, one death). A 3840-tick fixture costs more than the fixture suite's 10 s budget allows, so the run lives in `tests/perf/` and the first 60 ticks (two bursts, a walker turning at a ledge, one falling, Ash's vitals) are `tests/replay/perf/stress_pin.fixture`, blessed with the others. The bench checks that the run did what it is for (`min_procs` 12,000, `min_hits` 14,000, `min_kills` 80, `min_walkers` 100) and that three runs end on the same hash.
4. **The bench.** `tools/bench/stress_bench.gd` times `fixture.input_frame(i)` plus `Simulation.step` with `Time.get_ticks_usec`, after 120 warm-up ticks, for 3 whole runs, and keeps for each tick the least time (the work of a tick is fixed by the replay; this machine's vCPU is descheduled for 1 to 100 ms inside a single dummy's step now and then, and one run's max is that noise). It prints p50, p99 (nearest rank) and max, the 8 slowest ticks with procs, hits, kills and flags (hash tick, door, death, hurt, cast), and the zone 1 loop played 5 times through (17,920 ticks, the checklist's spike line). Gates: `sim_p99_us` 3000, `sim_max_us` 20000, `zone_max_us` 20000 (content, `content/perf/budget.tres`; `validate()` also holds section 13's seven frame-budget stages to 16.6 ms). Exit 1 over any, and on a stress run that did too little.
5. **CI.** `ci/perf.sh` imports, runs the bench under a time limit (900 s) and requires the marker `PERF GATE PASSED`; `--verbose` adds the slowest ticks; the report goes to `reports/perf.txt`. The `perf` job runs it on `ubuntu-24.04` and uploads the report. The ubuntu runner is slower than the reference PC, so a pass there is conservative. **The job fails today** (Decision 8): no threshold was lowered.
6. **`FlatWalk`.** A body whose feet are on a tile boundary, standing on a floor of one tile kind (wall, smooth or one-way), with only empty tiles in the rows its box fills and no solid box that could matter near, walks level: the sweep's result for a step is `x + dx`, ground true, ground tile that kind, slope false. The run of such columns around the body (at most 8 columns past it each way, a column clear of any solid box in height) is found once and kept on the `Body` (`run_*`, not state, never hashed or copied), good under a token that changes when `TileGrid.revision` or `SolidBox.revision` (position setters, global) or the solid count changes. It serves `walk()` and `refresh_ground()` when no move has narrowed the solid list (`_narrowed`), and `CollisionWorld.flat_ahead` tells a walker the floor goes on. The sweep is untouched and stays the reference (`use_flat_walk = false`); `tests/unit/core/physics/test_flat_walk.gd` plays both worlds with the same random moves on 120 random worlds (flat ground with steps, blocks, hazards, platforms and moving solid boxes; random soup with slopes) and demands every body field and return value agree after every move; run at 1500 worlds each it also agrees. Every committed fixture's state hash is unchanged with it on, and so are the 64 hashes of the whole stress run with it off.
7. **Other changes that moved no result.** `Combat._trails` asks the query cells (`EnemyCells.touching`, a superset by centre and reach, then the exact test in the room's order) from `CELL_QUERY_MIN` (24) enemies up and leaves the cells built for the procs (the stress run's 64 hashes are the same with the threshold out of reach; `test_combat_trails.gd`). `StateHasher.add_ints` lets `Enemy.hash_into` add its fields in two calls. The measurements:

   | Stage, us a tick (mean) | Before | After |
   | --- | --- | --- |
   | Player step | 150 | 112 |
   | Walking dummies (151) | 6302 | 3019 |
   | Standing dummies (49) | 997 | 637 |
   | Effects age, strike, Kindle, Radiance, pogo | 335 | 242 |
   | Blaze trails | 963 | 192 |
   | Procs (a burst of 39: 1.3 ms) | 208 | 185 |
   | Enemy swings, door, input ring | 174 | 144 |
   | State hash (60th tick: p99) | 29 (1481) | 18 (966) |
   | Whole tick, mean | 9267 | 4641 |

   `tools/bench/stress_bench.gd`, best of 3 runs (a different crowd path after the walkers' ledge rule moved a sub-pixel, so the two runs are alike, not the same):

   | | p50 | p99 | worst | zone 1 loop x5 worst |
   | --- | --- | --- | --- | --- |
   | Before (commit `3b36da0`) | 8.03 ms | 13.40 ms | 26.39 ms | 0.76 ms |
   | After | 3.89 ms | 9.00 ms | 20.26 ms | 1.01 ms |
   | Gate | | 3.00 ms | 20.00 ms | 20.00 ms |

   Run `ci/perf.sh --verbose` for the slowest ticks: all eight are 300 to 500 procs ticks (one Kindle or Radiance hit on a dozen of the crowd raises a dozen proc events, each firing 39).
8. **Where GDScript stops, and why.** What is left after this ADR, per tick: 3.0 ms for the dummies (89 walkers in a flat run cost 9.6 us a step, 41 on flat floor outside a run and 18 on ramps cost 34 to 35 us, a stander 6 to 25 us), 0.5 ms of other effects, swings and Ash, 0.2 ms of trails, and procs at 30 us each (`proc_bench`: 9.5 us the nearest-enemy query, 4.6 us the hit, the rest the listener call, the event and the three Votives' rolls). The p99 tick is a proc tick: 40 procs cost 1.3 ms on top of a 3.9 ms median; an area hit on the crowd costs 15 ms. The 3.0 ms gate needs the median near 1.5 ms and a burst near 1.3 ms: 2.6 times the baseline cut, in a language that spends 0.3 to 1 us on every call. The hot paths for a C++ port, in order: `CollisionWorld` (`walk`, `move_x`, `move_y`, `refresh_ground`, 3.6 ms for the 200 bodies; its reference stays, with `FlatWalk`), the proc path (`ProcBus.resolve` and `_fire`, the listener call through `ProcApi`, `Combat.nearest_enemy`, `_damage`; BUILD.md names "hitbox resolution" for C++ already), `Combat._trails`/`_strike` box tests, `state_hash`. Ramps would also need their own flat-run rule in GDScript (three fifths of the dummies cost 9 us a step, the rest, on a ramp or a short plateau, 34).
9. **Not gated here.** The lighting pass, sprite submit, VFX and post stages and the 16.0/15.0 ms frame are GPU matters (Blocked 2); `PerfBudget` carries them so the report names them. "With 30 Votives active, the screen stays readable" is a presentation check against `game/vfx` and the VFX budget manager (ADR-0015 Decision 5), judged on a contact sheet with a display, not a CPU number; this task has no display.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Lower the gate until it passes, or run the job report-only | CLAUDE.md prohibits lowering a gate threshold; a red job with its numbers is the honest state until the lead decides |
| Put the 3840-tick run in `tests/replay/` | It would take most of the fixture suite's 10 s budget; the 60-tick pin keeps the scenario bit-exact in the suite and the bench keeps the long run |
| A time-sliced "sleeping" enemy (far enemies skip their step) | Would cut the stress room's cost sharply, but it changes behaviour and is a design decision for the lead, not a port |
| One run, take the 99th percentile as measured | This machine adds 1 to 100 ms to single ticks at random; the p99 and the worst tick would measure the noise |
| A bitmap of solid-box columns in `FlatWalk` | It counted a hung box high above a walker as an obstacle; the run now compares heights |
| Port `CollisionWorld` to C++ in this task | CLAUDE.md allows it only for profiled hot paths and the lead decides (the task's own rule) |

## Feel reason

None changed: no feel number moved and every committed state hash is the same. A walking dummy changes nothing the player feels in the 12 zone rooms (none has `patrol`). The room is for load, not for play.

## Consequences

- `ci/perf.sh` fails until the lead decides (Decision 8). It is the first number, not a regression: the next change to `core/` can be judged against 3.89 / 9.00 / 20.26 ms.
- Anything that writes a `SolidBox` edge goes through its setters (they bump `SolidBox.revision`); anything that edits a grid after a world is built goes through `TileGrid.set_tile` or `resize`. Swapping the world's solid list for another of the same length with unchanged boxes is not detected.
- A C++ port of the sweep must match the reference and `FlatWalk`'s answers; `test_flat_walk.gd` is its template. `Enemy.settled` and the walker's rules are new behaviour of a new kind of dummy, not a change to anything blessed.
- `Simulation.VERSION` is unchanged (11). The one golden this ADR re-blessed is `stress_pin`, added in the same task.
- Director question: (1) C++ for `CollisionWorld` and the proc path, or a design change (a proc budget per tick, sleeping enemies)? A 500-proc tick is 16 ms in GDScript whatever else is done; "40 procs" is one hit, an AoE on a dense crowd is twelve. (2) The runner for the GPU half (PROGRESS.md, Blocked 2).
