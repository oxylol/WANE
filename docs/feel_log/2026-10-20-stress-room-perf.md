# 2026-10-20: Task 8, the stress room and the CPU budget

- Author: Claude
- BUILD.md section and table row: section 13, Testing and CI (Performance) and Frame budget ("Input + simulation step 3.0 ms")
- Fixture(s): `tests/replay/perf/stress_pin.fixture` (pinned in the suite), `tests/perf/stress_run.fixture` (timed by `ci/perf.sh`)
- Contact sheet: none. Nothing a player sees or feels changed; this entry records measurements (docs/adr/0020).

## Change

No feel number changed. Every committed fixture's state hash is the same as before the task (only the content fingerprint of the 144 fixtures that use `content/enemies/dummy.tres` moved: it gained `patrol_speed_ups` 120 u/s and `patrol_drop_u` 16 u, used only by a dummy marked `patrol=1`, which no zone room is).

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Stress room, input + step, p50 | 8.03 | 3.89 | ms |
| Stress room, input + step, p99 (gate 3.00) | 13.40 | 9.00 | ms |
| Stress room, worst tick (gate 20.00) | 26.39 | 20.26 | ms |
| Zone 1 loop x5 (17,920 ticks), worst tick (gate 20.00) | 0.76 | 1.01 | ms |
| Mean tick, the 200 dummies' share | 7.3 | 3.7 | ms |
| Blaze trails, mean | 0.96 | 0.19 | ms |
| State hash tick (p99 of its stage) | 1.48 | 0.97 | ms |

Measured on this container with nothing else running (load average 0.8), best of 3 whole runs per tick; headless GDScript.

## Why

The CPU half of section 13's budget cannot be judged without a crowd that moves: Phase 1's dummies stand, and a standing dummy costs a fifth of a walking one. So dummies walk, a room holds 200 of them, and Ash sweeps it with the 39-proc Votive set while striking, dashing, pogoing and casting. The profile found the sweep (walks and ground re-reads: 7.3 of 9.3 ms), Blaze trails, and the proc path. `FlatWalk` answers the commonest sweep (a body on a flat floor) without sweeping it, checked tick for tick against the sweep. The gate is still not met: the median tick is 3.9 ms, and a tick with a proc burst is 9 to 20 ms.

## How it plays now

Nothing changes in play. In the stress room Ash meets about 150 walkers and 67 swingers; `ci/perf.sh --verbose` lists the slowest ticks (all of them 300 to 500 proc ticks: one Kindle cone or Radiance burst on a dozen dummies, each hit raising 39 procs).

## Open questions for the director

- Port `CollisionWorld` and the proc path to C++ (the GDScript stays as the reference), or change the design (a proc budget per tick; enemies far from Ash sleeping)? 40 procs from one hit is 1.3 ms; an area hit on a dense crowd is 16 ms.
- A GPU runner (RTX 4060-class and a Steam Deck) for the 16.0 / 15.0 ms frame (PROGRESS.md, Blocked 2).
- To look at: nothing yet; to run: `ci/perf.sh --verbose`.
