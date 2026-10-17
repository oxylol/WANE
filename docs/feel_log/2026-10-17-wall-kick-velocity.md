# 2026-10-17: Wall-kick up velocity, 1020 to 900 u/s

- Author: Claude
- BUILD.md section and table row: section 5, Wall, "Wall-kick (neutral): Jump without holding away: 1020 u/s up, 240 u/s away; Lets the player climb a single wall"; section 15, "Wall-kick climbs a single wall without feeling stuck"
- Fixture(s): `tests/replay/movement/wall_kick.fixture`, `tests/replay/tech/tech05_wall_kick_climb.fixture`, `tests/replay/tech/tech05_wall_kick_mash.fixture`
- Contact sheet: `docs/feel_log/2026-10-17-wall-kick-velocity.png`. Panel 1 is the well climb at 1020 u/s, panel 2 at 900 u/s, and panel 3 plots the height of both climbs over time (1020 blue, 900 orange)

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Wall-kick velocity up | 1020 | 900 | u/s |

## Why

BUILD.md gives the kick the ground jump's velocity (1020 = 1020), so that a kick climbs a jump's height. The ground jump is now 900 u/s, so the kick follows it. At 1020 a kick would out-jump the ground jump by 49 u and climb the 672 u well in fewer kicks than its layout teaches.

## How it plays now

Each kick climbs about 176 u, one every 24 frames when pressed at the apex: the well (672 u) takes three kicks to clear its top (`tech05_wall_kick_climb`). A kick is a fixed kick, like the pogo's bounce (no early-release cut and no apex hang), and restores nothing (ADR-0010, after the first task-3 review found mashing climbed faster than timed kicks). Mashing jump 3 frames on and 3 off climbs at the same rate: each press waits in the buffer for the next apex (`tech05_wall_kick_mash`). It is never stuck.

## Open questions for the director

Climb the well both ways, timed at the apex and mashing.
