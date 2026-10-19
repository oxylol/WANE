# 2026-10-19: Zone 1 room 10, Crouch-dash under (grey box)

- Author: Claude
- BUILD.md section and table row: section 5, "The twelve core tech interactions" row 10 ("Crouch-dash under: crouch, then dash, keeps the 28-tall hitbox. Taught by a low gap"); section 5 Ground "Crouch: Height 44 -> 28"; docs/adr/0010 (Crouch-dash, Low gaps)
- Fixtures: the teaching route `tests/replay/zone1/10_crouch_dash_under.fixture`; controls `10_standing_dash_stops_at_the_gap`, `10_wall_stops_the_full_kit`, `10_crouch_alone_does_not_enter_b`, `10_dash_then_crouch_then_jump_stops_in_a`, `10_one_toss_skips_one_gap`, `10_toss_from_the_face_skips_b`, `10_toss_from_the_face_late_lands_on_the_rim`; the windows `10_dash_from_the_door_stops_short_of_a`, `10_dash_window_a_edge`, `10_dash_window_edge`, `10_dash_window_missed`; the recovery `10_stranded_second_dash_lands`
- Contact sheet: `docs/feel_log/2026-10-19-zone1-10-crouch-dash-under.png`, panels 1 to 4 (play.gd, a box every 2 ticks, magenta = dash, blue = ground): gap A at its window edge (x 295), gap B at its window edge (x 839), B one unit short (x 838, stranded, the box 0.5 u under the wall), the stranded recovery (second dash at tick 40); panel 5 the teaching route at a box every 8 ticks. The earlier single 6272 px strip showed the order of events but not the pose; these panels show the 28 tall box under the 32 tall gap

## Change

First implementation of the room, then a review pass that changed the layout of the far half.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Gap B length (x 960..) | 128 (to 1088) | 96 (to 1056) | u |
| Landing after B | 128 (1088..1216) | 288 (1056..1344) | u |
| Pit | x 1216..1376 | x 1344..1504 | u |
| Crouch-dash start window for B (before the face, x 950) | 70 (x 880 or later; measured: x 870 is stranded) | 111 (x 839 or later) | u |

No tuning number in `content/` changed; this is room geometry.

## Why

Tech 10 is taught by a low gap. The room is 60 x 34 tiles, floor top at y 960, a solid ceiling over a 576 u hall. Two walls run from floor to ceiling, each with a 32 u gap in the bottom row: A, x 448..512 (64 long), the safe first encounter, floor on both sides; B, x 960..1056 (96 long), then a 9-tile landing, then a 5-tile pit (x 1344..1504) that a plain run-jump clears (about 190 u of reach), then floor to the east door.

A crouch-dash is 227.5 u from start to rest (180 u of dash, 3 carry frames, the slide; traced). The crouched box cannot move, so a dash that ends with the box (20 wide) still under the wall column leaves the player stuck until the 24 frame cooldown allows a second dash.

Review findings, and what changed:

- A stranded player's documented recovery (a second dash) ran off the 128 u landing into the pit and killed them (spawn 870: x 1217 still in dash at the pit's edge). The landing is now 288 u: from the worst stranded spot (x 1065.5) the second dash ends at 1293 at the latest, 51 u short of the pit (`10_stranded_second_dash_lands`, from x 830).
- The window was misreported: the old notes said a dash from x 880 got out, but x 870 ended 0.5 u under the column, stuck. B is now 96 long and the window is measured and pinned both sides of its edge: x 839 gets out (`10_dash_window_edge`), x 838 is stuck at 1065.5 (`10_dash_window_missed`). The window is 111 u before the face, up from 70. This answers last time's open question (B at 3 tiles).
- Gap A: a dash from the west door does not cross it (the body stands up before the face and walks to it, `10_dash_from_the_door_stops_short_of_a`). A needs a start at x 295 or later (up to the face at 438: 143 u, `10_dash_window_a_edge`); the teaching route runs to x 438 first.
- No fixture covered crouching without a dash. Now `10_crouch_alone_does_not_enter_b` (the stick down at B's face slides 13.5 u into the gap, never past x 1000) and `10_dash_then_crouch_then_jump_stops_in_a` (a dash, the stick down, a jump with the stick held: x never past 520, A's exit is 522) pin the margin against a later crouch-deceleration change.
- The Ember Toss from B's face: the ember flies 10 u a tick and 400 u in all. A re-press while it is past the wall (tick 24, x 1160) lands on the landing and skips B (`10_toss_from_the_face_skips_b`); a re-press from the very early frames puts Ash crouched inside the gap, stuck again (x 1040 at tick 12). Left to fly its whole 400 u the ember stops at x 1350, 6 u past the pit's edge, and Ash stands on the 4 u of floor at its rim, alive (`10_toss_from_the_face_late_lands_on_the_rim`). The old note that Ash arrives in the pit was wrong. So one toss skips one gap, B included, as designed (`10_one_toss_skips_one_gap`: from x 300, over A; B then stops the player at x 950).

Why the tech is needed: the gaps are 32 u and the standing body 44 (`10_standing_dash_stops_at_the_gap`); a hop in a low gap never crawls (ADR-0010); nothing goes over or under (`10_wall_stops_the_full_kit`); crouching alone slides at most 13.5 u into B. The toss (tech 11) is the one other way, once per 12 s (720 f).

## How it plays now

A skilled player crosses in about 3 s (the teaching route crosses the east door at tick 182): run to A's face, down-forward and dash, run, down-forward and dash at B, jump the pit from the landing's end, run. `10_crouch_dash_under` pins `height=28` and `state=dash` inside each gap, no wall hit, no hazard, and the door crossing into room 11 at x 74.

## Open questions for the director

- Play B from a dead run: is the 111 u (about 12 frame) window generous, and is the stuck state (a dash that falls short, then a second dash 24 frames later) a fair cost for missing it?
- The toss alternative: fine as an advanced shortcut? It cannot be closed with geometry alone: the ember is a point at chest height and the gap is open at that height.
- Run time is short (3 s, the low end of the 3 to 8 s aim); a stand-in dummy encounter is not needed for this tech, so I left it.
