# 2026-10-19: Zone 1 room 7, Coyote dash

- Author: Claude
- BUILD.md section and table row: section 5, "The twelve core tech interactions" 7 ("Coyote dash: dash off a ledge within coyote time keeps ground cooldown rules. Taught by a cliff"); section 5 Dash ("Cooldown: 24 f on ground"; coyote time 6 f); docs/adr/0010 (Dash: a coyote dash is a ground dash and leaves the air dash), docs/adr/0014 (doors and zones), docs/adr/0009 (room format).
- Fixture(s): `tests/replay/zone1/07_coyote_dash.fixture` (the teaching route, 160 frames to the east door), `07_control_ground_dash.fixture`, `07_control_late_dash.fixture`.
- Contact sheet: `docs/feel_log/2026-10-19-zone1-07-coyote-dash.png`, filmed with the F3 overlay, frames 92 to 125 every third frame: Ash walks off chasm B's edge (frame 94), dashes on frame 97 (the fourth airborne frame, flat under the 44 u roof, over the red pit), and the air dash follows.

## Change

First implementation of room `zone1/07_coyote_dash` (the stub is replaced); no tuning number changed. Room numbers (not tunables of the sim): roof 44 u over the floor, trench A 192 u wide and 32 u deep, chasm B 592 u wide with a pit row 32 u under the floor.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Room 07 | 60 x 20 empty stub | 60 x 34: trench A, island, chasm B under a 44 u roof | tiles |

## Why

Tech 7 has to be taught by a cliff. A coyote dash differs from a dash pressed at the edge only by the frames of running past the edge before the dash (up to 9 u each), so the room is built so that every route over the chasm is dashes (flat, under a roof exactly as low as the standing body) and the pit's far ledge is placed between the two reaches. Measured on a copy of chasm B with no far side (random-restart hill climb, three seeds of 20 starts): first dash on the ground, 569 u past the edge at best; first dash in coyote time, 596 u; the ledge at 592 u needs more than 582. In the room itself (second dash 11 to 23 and air jump 16 to 31 frames after the first, 208 timings per first-dash frame): first dash on frames 84 to 93 crosses with none of them, frames 94 to 100 (airborne frames 1 to 7) cross with one to six. The contact sheet shows the dash flat at pit level with the roof just above the collider: it reads as a cliff and a tunnel, grey box only.

## How it plays now

- Trench A (safe): a dash at its edge crosses it; walking in is a 32 u drop and one jump out (checked by hand in a scratch fixture).
- Chasm B: walk off the edge, dash within the first airborne frames, air dash 14 to 17 frames later, air jump about 25 frames after the first dash on the air dash's last frames: lands on the far ledge (`z1_07_coyote_dash`: coyote dash on frame 97 with `air_frames=3 dash_cooldown=24 air_dashes=1`, the air dash on 114 with `air_dashes=0`, the door crossing on frame 160, never a hazard).
- The same inputs with the first dash on the last grounded frame fall into the pit (`z1_07_control_ground_dash`); with the first dash on the eighth airborne frame (an air dash, coyote time over) they fall too (`z1_07_control_late_dash`).

## Open questions for the director

- The room is the only way for every route I searched, by 14 u and one frame at the lip, but it is not proven: a hill climb is not a proof, and the Ember Toss was tried once (a throw from the edge stopped about 90 u out) and not searched. The margin is narrow by nature (the coyote dash's gain is a few frames of running). Play it; if anything else crosses, move the far-ledge box (x 1584) closer to 580.
- The window is tight (a handful of timings per first-dash frame). Is it a fair "tech for real", or should the gap come down and the control be the one-frame-earlier dash alone?
