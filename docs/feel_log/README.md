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
| 2026-10-19 | [task 7: room editor](2026-10-19-task7-room-editor.md) | The plugin: every tile kind, boxes, the dummy's properties, doors drawn, moved, resized and paired, resize, the loader's problems live, Play |
