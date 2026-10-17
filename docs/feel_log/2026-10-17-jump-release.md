# 2026-10-17: Jump release gravity, 2.5x to 4.5x

- Author: Claude
- BUILD.md section and table row: section 5, Jump, "Min jump (tap): 2.2 tiles (70 u); Released after 4 f applies a 2.5x gravity multiplier until apex"; section 15, "Tap jump and full jump differ by at least 3 tiles; the release feels like a decision, not a cut"
- Fixture(s): `tests/replay/movement/jump_tap.fixture`, `tests/replay/movement/jump_variable_height.fixture`
- Contact sheet: `docs/feel_log/2026-10-17-jump-release.png`. Panel 1 is a tap at 2.5x, panel 2 a tap at 4.5x, and panel 3 a full jump; panel 4 plots all three (2.5x blue, 4.5x orange, full green)

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Gravity multiplier after an early release | 2500 | 4500 | per-mille of rise gravity |

## Why

With the 900 u/s jump (previous entry), a tap at 2.5x peaks at 100 u. That is only 76 u (2.4 tiles) under the full jump, which breaks the checklist's "at least 3 tiles". The table's 70 u tap would need about 8x, and at 8x the rise stops within three frames of the release: the cut the checklist forbids. At 4.5x the tap peaks at 77.9 u (2.4 tiles), 98 u (3.07 tiles) under the full jump, and still decelerates over five frames (panel 4). Every frame held between the minimum 4 and the apex adds height (`jump_variable_height`: 10 frames held peaks at 128 to 131 u).

## How it plays now

A tap is a short, quick hop with a soft top. The full jump is clearly a different move, and holding for anything in between gives a height in between.

## Open questions for the director

Tap jump, then full jump, on the flat room: does the release feel like a decision? The table's 2.2-tile tap was not kept (2.4 tiles instead); if 70 u matters more than the soft top, the multiplier must rise to about 8x.
