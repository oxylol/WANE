# 2026-10-19: Zone 1 room 7, Coyote dash

- Author: Claude
- BUILD.md section and table row: section 5, "The twelve core tech interactions" 7 ("Coyote dash: dash off a ledge within coyote time keeps ground cooldown rules. Taught by a cliff"); section 5 Dash ("Cooldown: 24 f on ground"; coyote time 6 f); docs/adr/0010 (Dash: a coyote dash is a ground dash and leaves the air dash), docs/adr/0014 (doors and zones), docs/adr/0009 (room format).
- Fixture(s): `tests/replay/zone1/07_coyote_dash.fixture` (the teaching route, 160 frames to the east door), `07_control_ground_dash.fixture` (the same route with the first dash on tick 94, the last tick on the floor), `07_control_standing_start.fixture` (a standing start on the island, the same dash on its last grounded tick), `07_control_late_dash.fixture`.
- Contact sheet: `docs/feel_log/2026-10-19-zone1-07-coyote-dash.png`, filmed with the F3 overlay at 1.5x, ticks 94, 104, 114, 124, 134. Top row `z1_07_coyote_dash`: Ash walks off chasm B's edge on tick 94, the coyote dash (tick 97) takes her flat under the roof over the red pit, the air dash follows, and by tick 134 she stands on the far ledge past the lip box ("no-cling"). Bottom row `z1_07_control_ground_dash`: the same inputs with the first dash on tick 94, a ground dash from the last grounded x, and by tick 134 she has fallen onto the hazard (the red flash). Both rows show the dash from the same place; what differs is the 9 u the coyote dash starts further along.

## Review fix (movement review: tech skippable)

The first version of this room was wrong: its control dashed on tick 93 and called it "the last frame on the ground", but the floor ends under Ash during tick 94 (she is grounded when that tick's input is read, so a dash read on 94 is an ordinary ground dash: `air_frames=0`, `air_dashes=1`, `dash_cooldown=24` after it, the same resource state as a coyote dash). Her coyote window is ticks 95 to 100; a dash on 101 is the air dash. A ground dash on 94 starts 9 u further along than the one on 93, and the lip was set 14 u past the 93 route's reach, so the dash on 94 crossed the chasm with no coyote time (and so did a standing start on the island: the run's phase moves the last grounded x by up to 9 u, and the author had searched one phase only).

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Chasm B width (edge x 992 to lip) | 592 | 612 (lip box x 1604 to 1632, floor from 1632) | u |
| Control: first dash | tick 93 (not the last on the floor) | tick 94 (the last one) | tick |

How it was measured: `tools/replay/coyote_scan.gd` (new) holds right from a spawn on the island and presses a first dash on every tick from 4 before the floor ends to the sixth airborne tick, a second dash 12 to 20 ticks later (right, or up-right) or none, and a jump 12 to 36 ticks after the first (held), over all nine phases of the run's 9 u step (the spawns 770 to 778), on the room itself with the lip moved. A plan crosses when it stands on the far ledge. (The reach of gap_reach.gd, the farthest tick-end x on a chasm with no far side, understates what crosses: a 20 u dash meets the far face between ticks.) Results (phase 772 is the best for both kinds; spawn 74's run is that phase):

| Lip (x) | Chasm | First dash on the floor (to tick 94) | Coyote dash (ticks 95 to 100) |
| --- | --- | --- | --- |
| 1584 (before) | 592 u | 1 plan crosses (phase 772: dash on tick 94, air dash +17, jump +25); also phases 770, 771, 776 to 778 at 1586 | 40 of 1446 plans |
| 1590 | 598 u | 1 plan at phases 771 and 772 | not scanned |
| 1594 | 602 u | none, all phases | not scanned |
| 1604 (after) | 612 u | none, all nine phases, with the up-right second dash and 4 ticks before the last grounded one (2285 plans per phase); none from 61 standing-start spawns (x 800 to 860, 29402 plans) | 6 to 10 of 1446 plans at each phase (e.g. dash on tick 97 or 98, air dash +17, jump +25) |
| 1616 to 1622 | 624 to 630 u | not scanned | 5 and 2 plans (phase 772); none at 1628 |

The lip at 1604 is 14 u past the farthest lip a ground-first route crosses and about 18 u short of the farthest a coyote route does. The air dash (a first dash on the eighth airborne tick and later) crosses with none (3 phases, 1371 plans each). Before the fix `07_control_ground_dash` (now on tick 94) and `07_control_standing_start` both crossed to the east door and failed (checked on the old lip); with the lip at 1604 they fall into the pit.

## Change

First implementation of room `zone1/07_coyote_dash` (the stub is replaced); no tuning number changed. Room numbers (not tunables of the sim): roof 44 u over the floor, trench A 192 u wide and 32 u deep, chasm B 612 u wide (592 u in the first version, see the review fix) with a pit row 32 u under the floor.

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Room 07 | 60 x 20 empty stub | 60 x 34: trench A, island, chasm B under a 44 u roof | tiles |

## Why

Tech 7 has to be taught by a cliff. A coyote dash differs from a dash pressed at the edge only by the frames of running past the edge before the dash (up to 9 u each), so the room is built so that every route over the chasm is dashes (flat, under a roof exactly as low as the standing body) and the pit's far ledge is placed between the two reaches. The placement is measured on the room itself (see the review fix above for the method and numbers): the lip sits between the farthest a dash read on the floor crosses and the farthest a coyote dash does. (The first version measured one phase of the run on a copy of the chasm with no far side, and a ground dash on tick 94 crossed it.) The contact sheet shows the dash flat at pit level with the roof just above the collider: it reads as a cliff and a tunnel, grey box only.

## How it plays now

- Trench A (safe): a dash at its edge crosses it; walking in is a 32 u drop and one jump out (checked by hand in a scratch fixture).
- Chasm B: walk off the edge, dash within the first 6 airborne ticks (95 to 100), air dash 16 to 17 frames later, air jump about 24 to 25 frames after the first dash on the air dash's last frames: lands on the far ledge (`z1_07_coyote_dash`: coyote dash on frame 97 with `air_frames=3 dash_cooldown=24 air_dashes=1`, the air dash on 114 with `air_dashes=0`, the door crossing on frame 160, never a hazard).
- The same inputs with the first dash on tick 94, the last on the floor, fall into the pit (`z1_07_control_ground_dash`), and so does a standing start from the island with the dash on its last grounded tick (`z1_07_control_standing_start`); with the first dash on the eighth airborne frame (an air dash, coyote time over) they fall too (`z1_07_control_late_dash`).

## Open questions for the director

- The room is the only way for every route searched (a grid over spawn phase, first dash, second dash, jump; 14 u at the lip), but it is not proven: a search is not a proof, and the Ember Toss was tried once (a throw from the edge stopped about 90 u out) and not searched. The margin is narrow by nature (the coyote dash's gain is a few ticks of running, 9 u each). Play it; if anything else crosses, move the lip box (x 1604) farther out (the coyote route still crosses to about 1620).
- The window is tight (a handful of timings per first-dash frame). Is it a fair "tech for real", or should the lip come in and the control be the dash on tick 94 alone (the window between the two reaches is 32 u at most)?
