# 2026-10-17: Wall-jump up velocity, 900 to 794 u/s

- Author: Claude
- BUILD.md section and table row: section 5, Wall, "Wall-jump: 900 u/s up, 480 u/s away; 5 f of locked direction, then full control"
- Fixture(s): `tests/replay/movement/wall_jump.fixture`, `tests/replay/movement/wall_jump_resets.fixture`
- Contact sheet: `docs/feel_log/2026-10-17-wall-jump-velocity.png`. Panel 1 is 900 u/s, panel 2 is 794 u/s, and panel 3 plots both (900 blue, 794 orange)

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Wall-jump velocity up | 900 | 794 | u/s |

## Why

BUILD.md sets the wall-jump below the ground jump (900 against 1020: 88%). The ground jump came down to 900 u/s to keep its 5.5-tile height (jump velocity entry). Left at 900, the wall-jump would equal the ground jump and climb a shaft faster than intended. 794 u/s keeps BUILD.md's ratio (900 / 1020 x 900). The 480 u/s away and the 5-frame lock are unchanged.

## How it plays now

A wall-jump held to its apex rises 138 u (measured on `wall_jump`), under the ground jump's 176 u, as BUILD.md's ratio intended.

## Open questions for the director

None.
