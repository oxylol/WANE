# 2026-10-17: Jump velocity, 1020 to 900 u/s

- Author: Claude
- BUILD.md section and table row: section 5, Jump, "Jump velocity: 1020 u/s; Full hold reaches 5.5 tiles (176 u)"
- Fixture(s): `tests/replay/movement/jump_full.fixture`
- Contact sheet: `docs/feel_log/2026-10-17-jump-velocity.png`. Panel 1 is 1020 u/s, panel 2 is 900 u/s, and panel 3 plots both heights over time (1020 blue, 900 orange)

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Jump velocity | 1020 | 900 | u/s |

## Why

The row contradicts itself. At 1020 u/s, with the table's own 2400 u/s² rise gravity and its 0.6x apex hang, a full hold peaks at 225 u (7 tiles), not the 176 u (5.5 tiles) the note promises. Every room in the game is built around the jump's height (BUILD.md section 9 measures gaps and ledges in jump heights), so the 5.5 tiles is the number to keep, and the velocity follows from it: 900 u/s peaks at exactly 176.0 u with the same gravity and hang (panel 3).

## How it plays now

A full jump clears 5.5 tiles and takes 45 frames from take-off to landing on flat ground. The double jump stays at 85% of this velocity (765 u/s).

## Open questions for the director

Play `jump_full` and say whether 5.5 tiles reads right for Ash's body (44 u tall, so the jump is four bodies high).
