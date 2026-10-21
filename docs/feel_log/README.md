# Feel log

Every tuning change to a movement or combat number is recorded here with the before, the after and the why (CLAUDE.md, "Feel: how to tune"; BUILD.md section 13). One file per change or task: `YYYY-MM-DD-<task>.md`, with the matching frame-stepped contact sheet `YYYY-MM-DD-<task>.png` beside it. Start from `TEMPLATE.md`.

The tuned values become the spec: when a number changes here, the same commit changes it in `content/` and in `docs/BUILD.md`.

## Index

| Date | Entry | Summary |
| --- | --- | --- |
| 2026-10-16 | [task 1: core loop](2026-10-16-task1-core-loop.md) | Input buffer (8 f of history), latest-press rule, hitstop-safe input, replays |
| 2026-10-17 | [task 2: physics](2026-10-17-task2-physics.md) | The AABB sweep: slopes to 45 degrees, one-way platforms, corner correction (steps up and down lips, on ramps too), ledge-grab, far-edge landings; five review rounds |
| 2026-10-17 | [jump velocity](2026-10-17-jump-velocity.md) | 1020 to 900 u/s: the full jump reaches BUILD.md's 176 u |
| 2026-10-17 | [jump release](2026-10-17-jump-release.md) | Release multiplier 2.5x to 4.5x: a tap is 3 tiles under a full jump |
| 2026-10-17 | [wall-jump velocity](2026-10-17-wall-jump-velocity.md) | 900 to 794 u/s up, kept at 88% of the jump |
| 2026-10-17 | [wall-kick velocity](2026-10-17-wall-kick-velocity.md) | 1020 to 900 u/s up, equal to the jump |
| 2026-10-17 | [pogo bounce](2026-10-17-pogo-bounce.md) | 900 to 794 u/s, slightly under a jump |
| 2026-10-17 | [pogo chain window](2026-10-17-pogo-chain-window.md) | Frame 6 to 14, reverted to 6; the pogo-dash cadence is a director question |
| 2026-10-17 | [task 3: Ash's movement](2026-10-17-task3-ash-movement.md) | Every row and tech interaction; first-time values (wall coyote, buffers, ember, teleport reach, safe-ground margin, strike sectors); three review rounds |
| 2026-10-17 | [task 4: camera](2026-10-17-task4-camera.md) | Rest height, dead zone, lead, looks (fall, look-down, up-dash), room bounds, teleport glide; first-time values; four review rounds |
| 2026-10-17 | [task 5: F3 overlay](2026-10-17-task5-debug-overlay.md) | The overlay, the frame-stepper and the frame-stepped contact sheet (`film.gd --overlay on --zoom`) |
| 2026-10-17 | [corner-correction ease](2026-10-17-nudge-ease.md) | The drawn player eases onto a nudge over 6 frames, tuned to 3: no hop, no sinking |
| 2026-10-19 | [task 6: combat](2026-10-19-task6-combat.md) | The Taper's hits, Flame, Kindling, the parry, Kindle, Mend, Radiance, the Charged strike, hit feedback and the training dummy; first-time values; the parry flash's opacity 1.0 to 0.55 |
| 2026-10-19 | [corner-correction ease on runs](2026-10-19-nudge-ease-runs.md) | The cap moves from the gap to the catch-up speed's change: no hitch up a staircase of lips, at the cost of lag up a dashed one |
| 2026-10-19 | [task 7: zone 1 rooms 4 to 6](2026-10-19-zone1-b.md) | The pogo-dash tower to a hidden alcove, the kick-climb well, the wall-jump-dash shaft; each sized against the Ember Toss's landing trick; a wall-jump and up-dash cycle out-climbs kicks (director question) |
| 2026-10-19 | [task 7: room editor](2026-10-19-task7-room-editor.md) | The plugin: every tile kind, boxes, the dummy's properties, doors drawn, moved, resized and paired, resize, the loader's problems live, Play |
| 2026-10-19 | [task 7: zone 1 rooms 1 to 3](2026-10-19-zone1-a.md) | The dash-slash corridor of solid dummies, the dash-jump ditch and island, the pogo-chain spike tunnel; each beside the strongest single-use control |
| 2026-10-19 | [task 7: zone 1 room 7](2026-10-19-zone1-07-coyote-dash.md) | Room 7: a trench and a chasm taught by the coyote ticks and the air dash kept in hand; first implementation, no tuned number changed |
| 2026-10-19 | [task 7: zone 1 room 8](2026-10-19-zone1-08.md) | Three drops, two ambusher dummies tied to Ash's position; the strike pressed 4 f before the landing wins, the one on the landing loses |
| 2026-10-19 | [task 7: zone 1 room 9](2026-10-19-zone1-reverse-pogo.md) | Room 9: the reverse pogo; first implementation, no tuned number changed |
| 2026-10-19 | [task 7: zone 1 room 10](2026-10-19-zone1-10-crouch-dash-under.md) | Room 10: the crouch-dash under a low roof; first implementation and a review pass on the far half's layout |
| 2026-10-19 | [task 7: zone 1 room 11](2026-10-19-zone1-11-ember-toss-cancel.md) | Room 11: the Ember-toss cancel over a long chasm (ADR-0017); first implementation, no tuned number changed |
| 2026-10-19 | [task 7: zone 1 room 12](2026-10-19-zone1-room12.md) | Room 12: the Kindle-dash through a wax screen and a wax door over a chasm; first implementation, no tuned number changed |
| 2026-10-19 | [task 7: zone 1 whole](2026-10-19-merge-zone1.md) | The rooms re-timed on the fixed engine (rooms 1 and 8), and the 60-second loop through all twelve rooms: 3584 ticks |
| 2026-10-20 | [Phase 2 task 1: the art build](2026-10-20-artbuild.md) | `tools/artbuild/`: SVG parts to exact distance-field sheets, normal and emissive maps and metadata; the probe and a test prop; byte-identical builds; first implementation, no tuned number changed |
| 2026-10-20 | [Phase 2 task 1: ink and gouache shaders](2026-10-20-ink-gouache-shaders.md) | The ink line, two-value gouache, rim, brush, grain and emissive as canvas shaders on the ADR-0023 channel layout; brush_noise 0.10 to 0.05 |
| 2026-10-20 | [Phase 2 task 1: the lighting pass](2026-10-20-lighting-pass.md) | The ember, soft shadows from the room's distance field, ambient times the Dark, emissives and bloom replace the Phase 1 stand-in |
| 2026-10-20 | [Phase 2 task 1: the art pipeline made whole](2026-10-20-art-pipeline.md) | The three builders merged; the three-size review in the lit test room; per-action cells, pages and the blade tip; one boil rate (`boil_hz` 12, now in one file) |
| 2026-10-19 | [camera review 7](2026-10-19-camera-review7.md) | Camera review 7: fall away, death cut, charge hold, shake margin, glide exit |
| 2026-10-19 | [engine merge](2026-10-19-merge-engine.md) | The engine work merged: core review 2, physics 8, camera 7, presentation, procs |
| 2026-10-19 | [physics review 8](2026-10-19-physics-r8.md) | Physics review 8: lips met down a ramp, lids over hazards |
| 2026-10-19 | [presentation review 3](2026-10-19-presentation-review-3.md) | Presentation review 3 (task 5 round 3, task 6 round 2) |
| 2026-10-19 | [core fixes, review round 3](2026-10-19-rr3-core-fixes.md) | Movement review 6 and task 6 core review 2: the core fixes |
| 2026-10-19 | [task 7: doors](2026-10-19-task7-doors.md) | Task 7: doors between rooms |
| 2026-10-19 | [task 8: procs and Votives](2026-10-19-task8-procs.md) | Task 8: the proc event bus and the first Votives |
| 2026-10-20 | [Phase 2 task 1: design and spike](2026-10-20-art-pipeline-spike.md) | Phase 2 task 1: the art pipeline designed (ADR-0023) and its risky parts spiked |
| 2026-10-20 | [camera glide jolt](2026-10-20-camera-glide-jolt.md) | The camera jolt from a bounce during a teleport's glide (ADR-0011) |
| 2026-10-20 | [parry window in ticks](2026-10-20-parry-window-ticks.md) | The parry window is 8 ticks when the press connects; dash-jump audit notes |
| 2026-10-20 | [presentation audit fixes](2026-10-20-presentation-audit-fixes.md) | Audit fixes: the door spike, tunables in content, effects through the VFX budget, the stress sheet |
| 2026-10-20 | [squash and stretch](2026-10-20-squash-stretch.md) | Landing squash and apex stretch on the grey-box player, drawn only |
| 2026-10-20 | [task 8: stress room and CPU budget](2026-10-20-stress-room-perf.md) | Task 8: the stress room and the CPU budget |
| 2026-10-20 | [stress workload at the spec](2026-10-20-stress-workload-at-spec.md) | The stress room's workload at the spec, with the native sweep |
| 2026-10-20 | [stress gate closed](2026-10-20-stress-gate-closed.md) | The stress room's simulation gate closed: p99 5.01 to 2.67 ms |
| 2026-10-20 | [room 03: the 4-a-second pit](2026-10-20-room03-pit.md) | Room 03: the pit a 10-bounce chain at 4 a second crosses |
| 2026-10-20 | [room 03: open pit](2026-10-20-room03-open-pit.md) | Room 03 rebuilt for the director: an open pit for the main route, the 4-a-second tunnel optional |
| 2026-10-20 | [grey-box box colours](2026-10-20-box-colours.md) | Grey-box solid boxes coloured by function (wax, bell, smooth, plain) |
| 2026-10-21 | [Phase 2 task 1: first review fixed](2026-10-21-art-pipeline-fixes.md) | Phase 2 task 1: the first review's findings fixed (form lighting, halos, the smear ribbon, the painted backdrop; ADR-0026) |
| 2026-10-21 | [Phase 2 task 1: review 2, shaders and lighting](2026-10-21-review2-shaders.md) | Phase 2 task 1, second review: the shaders and the lighting (bloom in u, the hue-keeping shoulder, all four shadow channels pinned) |
| 2026-10-21 | [Phase 2 task 1: review 2, art build](2026-10-21-review2-artbuild.md) | Phase 2 task 1, second review: the art build (a whole-root --check, strict sources, the review lights eyes as eyes) |
| 2026-10-21 | [Phase 2 task 1: review 2, integration](2026-10-21-review2-integration.md) | Phase 2 task 1, second review: the grey boxes judged lit, pogo-able surfaces emissive, the room shot lit |
