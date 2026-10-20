# 2026-10-20: Task 8, the stress room and the CPU budget

- Author: Claude
- BUILD.md section and table row: section 13, Testing and CI (Performance) and Frame budget ("Input + simulation step 3.0 ms")
- Fixture(s): `tests/replay/perf/stress_pin.fixture` (pinned in the suite), `tests/perf/stress_run.fixture` (timed by `ci/perf.sh`)
- Contact sheet: `docs/feel_log/2026-10-19-task8-stress.png` (part B: the stress run at Pitch, ticks 468 to 472, a 45-proc burst; top row the game's view, bottom row the F3 overlay). Nothing a player feels changed; this entry records measurements and a judgement (docs/adr/0020).

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

## Part B: the presentation, measured and looked at

`tools/bench/frame_bench.gd` plays the same run through the game's real scene (`game/main.tscn`: views, camera, hit feedback, VFX budget, voices, HUD) under the Phase 1 stand-in Pitch lighting (`game/lighting/`: ember `PointLight2D` 420 u, soft shadows, 50 merged occluder polygons and 16 box occluders in the stress room, ambient 0.15). Headless (dummy renderer, our script cost), best of 3 passes, 3720 counted frames:

| Stage, ms | p50 | p99 | max | Gate |
| --- | --- | --- | --- | --- |
| Simulation step | 4.01 | 8.96 | 20.70 | 3.0 p99 (stress_bench; not met, above) |
| Views capture a tick | 1.59 | 2.62 | 4.26 | |
| Views `_process`, `_draw`, engine | 0.90 | 1.36 | 1.75 | |
| **Presentation script** (frame less step) | 2.57 | 3.64 | 5.44 | **5.0 p99** (sprites 2.0 + VFX 2.0 + audio and UI 1.0): met |
| Whole frame | 6.68 | 12.49 | 25.68 | GPU runner |

Windowed (X11, llvmpipe software rendering, 1 pass, recorded not gated): frame p50 37.2, p99 53.9, max 79.5 ms; 146 draw calls in the busiest frame. That is the rasteriser, not a figure for a GPU. The VFX budget over the run refused 6,543 effects and displaced 12 (at most 16 alive of 256). Voices, windowed: at the 86 burst ticks (39 to 60 procs) at most 22 of 24 in use, median 8; at the 135 crowd hits 24 of 24, median 11; 114 dropped and 128 stolen in the run (headless the dummy audio driver never ends a stream, so those counts are not real).

What the sheet shows (checklist: "With 30 Votives active, the screen stays readable: the player and every enemy telegraph are visible"): at tick 470 a 45-proc burst lands with five white and five red enemies mid-telegraph or mid-swing in view. At Pitch, Ash is a bright yellow box in his own ember light and is found at once; every telegraph (white bar and outline, the red wavy outline, the live swing box) is drawn unshaded and keeps full brightness near and far; enemies beyond the ember are dark silhouettes, which is the intent of Pitch; the burst's own marks are few. I judge the line met for Phase 1 grey boxes and the stand-in light, and it is re-judged with the Phase 2 art and lighting. One defect found on the sheet and fixed: the F3 overlay printed a label for each of the 200 dummies, a wall of overlapping text; an idle enemy now carries its label only within 240 u of Ash.

## How it plays now

Nothing changes in play. In the stress room Ash meets about 150 walkers and 67 swingers; `ci/perf.sh --verbose` lists the slowest ticks (all of them 300 to 500 proc ticks: one Kindle cone or Radiance burst on a dozen dummies, each hit raising 39 procs).

## Open questions for the director

- Port `CollisionWorld` and the proc path to C++ (the GDScript stays as the reference), or change the design (a proc budget per tick; enemies far from Ash sleeping)? 40 procs from one hit is 1.3 ms; an area hit on a dense crowd is 16 ms.
- A GPU runner (RTX 4060-class and a Steam Deck) for the 16.0 / 15.0 ms frame (PROGRESS.md, Blocked 2).
- To look at: `docs/feel_log/2026-10-19-task8-stress.png`; to run: `ci/perf.sh --verbose` (both benches); `-- --lighting=pitch` on the game for Pitch.
