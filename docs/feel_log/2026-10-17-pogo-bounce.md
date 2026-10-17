# 2026-10-17: Pogo bounce velocity, 900 to 794 u/s

- Author: Claude
- BUILD.md section and table row: section 5, Pogo, "Bounce velocity: 900 u/s; Slightly under a jump"
- Fixture(s): `tests/replay/movement/pogo_bounce.fixture`, `tests/replay/tech/tech03_pogo_chain.fixture`
- Contact sheet: `docs/feel_log/2026-10-17-pogo-bounce.png`. Panel 1 is 900 u/s, panel 2 is 794 u/s, and panel 3 plots both (900 blue, 794 orange)

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Pogo bounce velocity | 900 | 794 | u/s |

## Why

The note says "slightly under a jump", and BUILD.md had it at 88% of the jump (900 against 1020). With the jump at 900 u/s, a 900 u/s bounce would equal the jump. 794 u/s keeps the 88%.

## How it plays now

A bounce rises 125 u (measured on `pogo_bounce`; the bounce gets no apex hang, which is for a held jump). A plain pogo chain over a level spike pit runs at one bounce every 36 to 37 frames at full run speed (`tech03_pogo_chain`: ten bounces across a 3360 u pit).

## Open questions for the director

None.
