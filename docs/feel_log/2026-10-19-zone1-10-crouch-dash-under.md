# 2026-10-19: Zone 1 room 10, Crouch-dash under (grey box)

- Author: Claude
- BUILD.md section and table row: section 5, "The twelve core tech interactions" row 10 ("Crouch-dash under: crouch, then dash, keeps the 28-tall hitbox. Taught by a low gap"); section 5 Ground "Crouch: Height 44 -> 28"; docs/adr/0010 (Crouch-dash, Low gaps)
- Fixture(s): `tests/replay/zone1/10_crouch_dash_under.fixture` (the teaching route), controls `10_standing_dash_stops_at_the_gap`, `10_wall_stops_the_full_kit`, `10_one_toss_skips_one_gap`
- Contact sheet: `docs/feel_log/2026-10-19-zone1-10-crouch-dash-under.png` (one row, the teaching route, 12 frames every 14 ticks from tick 30; F3 overlay on)

## Change

First implementation of the room, no tuning number changed. The room `content/rooms/zone1/10_crouch_dash_under.room` replaces its stub.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| (none changed) | - | - | - |

## Why

Tech 10 is taught by a low gap. The room is 60 x 34 tiles, floor top at y 960, a solid ceiling over a 576 u hall. Two walls run from floor to ceiling, each with a 32 u gap in the bottom row:

- Gap A, x 448..512 (64 long): the safe first encounter, floor on both sides, nothing that hurts. A dash started from anywhere between the door and the face gets through.
- Gap B, x 960..1088 (128 long): the real one. It leaves onto a 4-tile landing, then a 5-tile pit (x 1216..1376) that a plain run-jump clears (about 190 u of reach), then floor to the east door.

Numbers measured on the fixtures: a crouch-dash is 180 u in 9 frames plus 3 carry frames at 10 u, 210 u plus a short slide. From the face of B (x 950) the body is standing again at about x 1100. A dash started at x 880 or later still gets out (an 80 u, 9 frame window); from x 860 it ends inside B at x 1087.5, crouched and unable to move, and needs the second dash after the 24 frame ground cooldown. B is 128 long, under the ADR-0010 level rule (one crouch-dash, about 210 u).

Why the tech is needed. The gaps are 32 u and the standing body 44 (the standing dash stops at the face, x 950, `10_standing_dash_stops_at_the_gap`); a hop in a low gap never crawls (ADR-0010); nothing goes over or under (`10_wall_stops_the_full_kit`: dash-jump, air jump, up-forward air dash and wall-kicks end at the ceiling with x never past 950). The one other way is the Ember Toss (tech 11): the ember flies through a 32 u gap and the teleport crouches the player in beyond it (`tech11_teleport_crouches_into_low_gap`). So the room is not the only-way for a player who has the toss, and is built so that it cannot be skipped: there are two gaps in a row and the toss has a 12 s (720 f) cooldown, so one toss skips one gap (`10_one_toss_skips_one_gap`: thrown from x 300 it goes over A, B still stops the player at x 950 with the cooldown running). A patient player can wait 720 frames for a second toss; the crouch-dash has a 24 frame cooldown and risks nothing, so it is clearly the best way. A toss thrown from B's own face ends at x 1350, over the pit; the 6 invulnerable frames after the teleport cover the landing and an air jump gets the player out (traced), so B can be skipped with the toss by a skilled player, once.

The contact sheet shows the route: the run to the first pillar, the dash into its low lane, the second pillar, the dash, the pit (dark red) and the door. At 4x with the overlay on the player is small against the whole room (the camera shows the room's width), so the sheet proves the order of events rather than the pose; the fixture's `height=28` expectations inside both gaps are the proof of the hitbox.

## How it plays now

A skilled player crosses in about 3 s (the teaching route crosses the east door at tick 178): run, down-forward and dash at A, run, down-forward and dash at B, jump the pit, run. `10_crouch_dash_under` pins `height=28` and `state=dash` inside each gap, no wall hit, no hazard, and the door crossing into room 11 at x 74.

## Open questions for the director

- Play B from a dead run: is the 80 u (9 frame) window to start the crouch-dash before the face generous enough, or should B be shortened to 3 tiles (a window of about 110 u)?
- The toss alternative (above): fine as an advanced shortcut, or should the room close it (it cannot be closed with geometry alone: the ember is a point at chest height and the gap is open at that height)?
- Run time is short (3 s, the low end of the 3 to 8 s aim); a stand-in dummy encounter is not needed for this tech, so I left it.
