# 2026-10-20: Landing squash and apex stretch on the grey-box player

- Author: Claude
- BUILD.md section and table row: section 5, Landing ("0 f of lag; a 3 f squash animation that does not block input"); section 10, Animation ("squash on landing (3 f, 110% wide) and stretch at jump apex (2 f, 94% wide) from vertical velocity"); section 15, "Landing squash and jump stretch are visible and do not block any input"
- Fixture(s): `tests/replay/movement/jump_full.fixture` (apex at tick 24, landing at tick 45, 990 u/s impact), `jump_ceiling_bump.fixture` (a head bump is no apex); tests `tests/unit/game/test_player_squash.gd`
- Contact sheet: `docs/feel_log/2026-10-20-squash-stretch.png` (zoom 8, one tick a tile, feet anchored)

## Change

First implementation; nothing in the core moved (no golden changed, `Simulation.VERSION` the same). The drawn player (`game/player/player_view.gd`) now scales about the middle of its feet, from the core's `land` event and from the rise ending. Every number is in `content/player_view.tres`.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Landing squash width | none | 110 (height 1/1.10: area kept) | percent |
| Landing squash length | none | 3 | ticks |
| Impact for no squash / full squash | none | 300 / 800 (smoothly between) | u/s |
| Apex stretch width | none | 94 (height 1/0.94) | percent |
| Apex stretch length | none | 2 | ticks |
| Rise speed for a full stretch | none | 900 (the jump's take-off speed) | u/s |

## Why

The line was reported partial and was nothing: the view drew a fixed rectangle. The squash starts on the tick of the land event, at its full amount, and eases out along a smoothstep over the 3 ticks (a hard impact, then a settle); the stretch swells and fades along a sine over its 2 ticks, so it is at its deepest on the tick after the apex. The landing impact is the event's payload (the vertical speed on touch-down) so a step off a lip (under 300 u/s) is no squash, and a full jump's landing (990 u/s) is the doc's 110%. The stretch is scaled by the rise's peak speed, so an air jump or a wall kick stretches less. A head bump on a ceiling ends the rise but is not an apex and does not stretch (the test fails without that guard). `box_at` stays the true box that the camera, the lighting follow and the F3 overlay read; only `drawn_box_at` is scaled, and the test replays a fixture with and without the view and compares the state hash.

The sheet: row 1 shows the stretch at ticks 23 to 27 (18 u wide against 20 u at tick 25), row 2 the landing (the box wide and low on tick 45, 2/3 of it on 46, 1/3 on 47, gone on 48). Judged against the doc: the landing reads at once; the stretch is 2 u narrower and 3 u taller, which is the doc's 94%, and reads only as a flicker at 1x. The doc's number rules; the Phase 2 rig will carry it with a smear and the ink line.

## How it plays now

Jump, and on the way down land: the little figure squashes for three ticks and nothing waits for it: input is read by the core the same tick, the squash only scales the drawing.

## Open questions for the director

Is 94% at the apex enough to feel, or should the apex stretch wait for the rig, where it can be drawn as a shape and not a rectangle? Left as the doc has it.
