# 2026-10-19: Zone 1 room 9, Reverse pogo

- Author: Claude
- BUILD.md section and table row: section 5, "The twelve core tech interactions" 9 (Reverse pogo); Pogo ("Horizontal speed fully preserved"); docs/adr/0010 "Reverse pogo"; docs/adr/0014 (doors)
- Fixture(s): `tests/replay/zone1/09_reverse_pogo.fixture` (teaching route, 220 frames, west arrival to the east door), `09_reverse_pogo_strike_88`/`_93` (the window's edges), `09_reverse_pogo_without_dash`, `09_note_plain_jump_crosses` (the not-gated decision), `09_control_forward_pogo.fixture`, `09_control_hop_lands_in_front.fixture`
- Contact sheet: `docs/feel_log/2026-10-19-zone1-reverse-pogo.png` (room 9's row: ticks 72 to 204 every 12, zoom 2, F3 overlay on: the run-up and dash with the invulnerable tag, the short hop, the strike and bounce above the guard, the fall behind it facing it, the walk to the east door strip, then the track of the whole route)

## Change

First implementation of the room; no tuned number changed.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| (none) | stub room | room `zone1/09_reverse_pogo`, 60 x 34 tiles, guard at x 1056 to 1088 | tiles, u |

## Why

The room gives the dash its runway (x 74 to 762 is 79 ticks of running, 294 u before the guard, the distance `tech09_reverse_pogo` dashes from) and a landing run behind the guard (landing at x 1170, the east strip at 1856). The guard is the pogo block of `tests/replay/rooms/shield.room` (32 x 64 u, the dummy's size) with an `entity guard` marker (`faces=west`) that nothing simulates; it is passive, so the first encounter is safe. The route takes 215 ticks (3.6 s). The sheet shows Ash still flying forward while facing back at the bounce, and landing 82 u behind the guard's east face facing it.

The tech cannot be the only way across (a 64 u guard in the open is jumped by anyone, and a door cannot ask which way Ash faces); a run and one jump lands on the guard and leaves by the east door (`09_note_plain_jump_crosses`). Decision (ADR-0010 "Reverse pogo", BUILD.md s5 tech 9): the room teaches the tech and does not gate it until the shielded enemy exists; the header comment says what the tech buys: Ash behind the guard, facing the one side its shield cannot cover.

## How it plays now

Run, dash at the guard, short-hop, back and down with the strike on any of ticks 88 to 93 (dash+9 to dash+14, 6 ticks; `09_reverse_pogo_strike_88` and `_93` pin the edges), land behind it facing it, walk on. Controls: the same route with the stick straight down lands facing away; a running hop with no dash that strikes early (tick 107) falls back in front, against the guard's west face. A running hop struck late (jump 108, strike 115 or 116) also lands behind it: `09_reverse_pogo_without_dash`.

## Open questions for the director

- Settled in the room 9 review: the reverse pogo from a run is real physics, not a bug (Ash is already over the block when the strike goes out; the bounce keeps the speed it has left). ADR-0010 and the control's doc are corrected, and `09_reverse_pogo_without_dash` pins it. Still for the director: is a 2-tick no-dash window an acceptable second way, or should the bounce keep less speed? Left as is (BUILD.md says fully preserved).
- Play the room and judge whether the 294 u dash distance reads as obvious; the camera lead may hide the guard until late.
