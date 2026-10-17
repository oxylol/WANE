# 2026-10-17: Phase 1 task 3, Ash's movement and the twelve tech interactions

- Author: Claude
- BUILD.md section and table row: section 5, every table (Ground, Jump, Dash, Wall, Pogo), the twelve core tech interactions and the feel rules; section 6, the Taper's cancel column and Ember Toss
- Fixture(s): `tests/replay/movement/` (one or more per table row) and `tests/replay/tech/` (one or more per tech interaction, with control runs that show the tech is needed), including one per finding of the first and second reviews
- Contact sheet: `docs/feel_log/2026-10-17-task3-ash-movement.png`, one panel per tech (1 to 12), drawn by `tools/replay/play.gd`.
  - `tools/replay/contact_sheet.gd` renders on the CPU, so it works headless.
  - The F3 overlay (task 5) will add hitboxes and the input history to these sheets.
  - Colours: ground blue, air yellow, dash magenta, wall green; event frames white with their frame number; the ember orange; a burned wax wall outlined.

## Change

Five BUILD.md numbers were tuned, one entry each:
- `2026-10-17-jump-velocity.md`: 1020 to 900 u/s;
- `2026-10-17-jump-release.md`: 2.5x to 4.5x;
- `2026-10-17-wall-jump-velocity.md`: 900 to 794 u/s up;
- `2026-10-17-wall-kick-velocity.md`: 1020 to 900 u/s up;
- `2026-10-17-pogo-bounce.md`: 900 to 794 u/s.

A sixth, the pogo chain window, was tuned from frame 6 to 14 and then reverted to 6 after the first review (`2026-10-17-pogo-chain-window.md`). BUILD.md section 5 carries every tuned number.

The rules BUILD.md leaves open are decided in ADR-0010. These values are set for the first time; none is in BUILD.md:

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Wall-jump reach (how far from a wall a falling player can still wall-jump) | none | 3 | units |
| Wall coyote time (after letting go of a cling) | none | 6 | frames |
| Wall-kick direction lock | none | 1 | frames |
| Dash, attack and toss buffers (the jump's is BUILD.md's 8 f) | the jump's | 8 each | frames |
| Hurtbox inset from the collider, sides / top / feet | none | 3 / 8 / 2 | units |
| Ember flight before it stops in the air | none | 40 | frames |
| Ember wait for the teleport once stopped | none | 120 | frames |
| Teleport fit reach around the ember | 16 (vertical only) | 24 (any direction) | units |
| Tech 2 test chasm | 768 | 1664 | units |
| Stick direction for a dash or the toss | each axis past 64 of 127 | 8 equal 45-degree sectors, read on the frame of the press | |
| Stick direction for a strike | each axis past 64 of 127, then the dash's 8 sectors | 4 equal 90-degree sectors (a diagonal is up or down), read on the frame of the press | |
| Safe ground: the same flat floor beyond the collider on each side | none | 16 | units |

## Why

- **Wall-jump reach.** It lets a jump pressed just as the player falls past a wall's edge still wall-jump; at 3 u it never reaches across a gap.
- **Wall coyote time.** A player who pushes away from a cling and presses jump a moment late meant a wall-jump. In 3 frames, air control has already carried them more than 3 u from the wall, so the reach alone turned the press into the air jump (the first review). 6 frames is the ground's coyote time.
- **Kick lock.** One frame of lock carries the kick clear of the wall before the stick (held toward it) brings the player back for the next kick (tech 5).
- **Buffers.** The dash, attack and toss used the jump's buffer setting. Each is now its own value in content, all BUILD.md's 8 frames.
- **Hurtbox insets.** They make the hurtbox smaller than the sprite (CLAUDE.md rule 8): a spike grazed by a boot tip or a hair's width at the side does not hurt.
- **Ember times.** 40 frames is 400 u: a gorge of up to about 12 tiles can be crossed with a throw (tech 11). 120 frames is long enough to land and press again without hurrying.
- **Teleport reach.** The ember stops 1 sub-pixel short of whatever it hits, so the body centred on it overlaps that surface. Fitting it needs half the body's width beside a wall (10 u) and half its height on a floor or under a ceiling (22 u). The old 16 u vertical nudge failed silently on walls and floors, the usual places an ember stops. 24 u covers both with a margin.
- **Tech 2 chasm.** The first search covered only routes that start with a run and found nothing crossing more than 1024 u, so the chasm was 1152 u. The second review found a route without a dash-jump that crosses it: a ground dash runs flat past the edge, and a coyote jump on a carry-over frame keeps the carry's 10 u/f for the whole airtime; the chasm became 1600 u. The third review found that route's air jump fell on the air dash's frame 9 (an air dash-jump, which keeps 20 u/f), and that the Ember Toss, which costs no Flame, carries a crossing further. `tools/replay/gap_reach.gd` now searches routes with no dash-jump of any kind, with and without one toss (reach past the edge at the ledge's height):
  - no dash-jump: 1201 u from a run, 1323 u from a ground dash and a carry-frame jump;
  - no dash-jump and one toss (thrown up-right after the air dash, the teleport 30 ticks later): 1590 u, which a random multi-start search and a perturbation search around it did not beat;
  - an air dash-jump without the ground one: 1539 u;
  - a plain ground dash-jump: 1029 u; with its air jump up to 1809 u; with the air dash too, up to 2223 u.

  At 1600 u the toss route fell short by less than a unit. At 1664 u (52 tiles) a crossing needs 1654 u, 64 u past the toss route (`tech02_control_carry_toss` falls), and a ground dash-jump clears it: with its air jump alone in a 15-tick window from dash frame 9 (2 ticks from frame 5, at the edge), and with the air dash as well from anywhere in a broad region (`tech02_dash_jump_frame5_air_dash`: every air jump and air dash within 6 ticks lands). A gap the plain dash-jump alone clears (about 1040 u) cannot teach it: the air jump, the air dash and the toss carry any route further.
- **Stick directions.** A buffered press fired with the stick as it was when the press fired, so a down-strike tapped just after a bounce and released came out as a side strike, and the second pogo was lost (the second review's High). Each press now keeps the stick of its own frame, read in 8 equal sectors; before, each axis was read against the threshold on its own, which left the diagonals 29.5 degrees of the circle.
- **Rules from the first review** (ADR-0010):
  - every way of arriving on the ground is a landing, with its resources, event and buffered actions;
  - a landing drops speed above run speed, so bunny-hopping cannot keep a dash-jump's 20 u/f;
  - air reversal is air control, not the ground turnaround;
  - kicks are fixed and restore nothing, and only the first cling since the floor, a wall-jump or a pogo restores the air jump and dash, so mashing climbs no faster than timed kicks;
  - the apex hang is centred on the apex;
  - a missed pogo never locks the jump;
  - a toss press during the throw's startup is used up;
  - side strikes from a wall go away from it;
  - drop-through needs the stick straight down;
  - a dash in coyote time with the ground cooldown running is the air dash at once;
  - the dash cooldown clears on landing and on wall-cling.
- **Rules from the second review** (ADR-0010):
  - a toss pressed with a jump or a dash teleports first, and the jump or dash goes from where the player arrives;
  - a buffered tap jump fired on landing peaks at 77.9 u like any tap (it peaked 10 u lower);
  - a bounce and a hazard on the same frame is a bounce;
  - down-forward and dash on the ground is a crouch-dash, not a standing dash that stops at the gap's face;
  - a toss from a cling goes away from the wall;
  - wall coyote time is 6 frames counted as the ground's is (it ran out a frame early);
  - down and a buffered jump onto a one-way drops through it;
  - a diagonal air dash that touches down fires a buffered jump that frame;
  - a missed pogo that lands gives way to a ground strike pressed after it;
  - a Kindle dash ignites only the wax ahead of it;
  - a teleport into a 32 u gap arrives crouched instead of failing, and a failed teleport costs 0.37 ms instead of 5.07 ms;
  - a jump under a flush ceiling waits in its buffer instead of firing a jump that cannot rise.
- **Rules from the third review** (ADR-0010):
  - a hazard respawn puts the ember out (its cooldown runs on). Left out, the teleport back out to it, with the air jump and dash the respawn had restored, crossed tech 2's chasm with no dash-jump (`tech02_respawn_does_not_keep_the_ember`);
  - the pogo bounce uses up a jump pressed during the down-strike. The press used to fire on the tick after the bounce as the air jump the bounce had just restored: the tap's early release cut the bounce to 62 u (124 u without it) and spent the jump (`pogo_bounce_uses_up_jump_pressed_in_strike`);
  - safe ground needs the same flat floor 16 u beyond the collider on each side. Walking off an edge into spikes respawned Ash with the collider overhanging the edge by 19 u, and the stick still held walked straight back in: a loop every 23 frames (`hazard_respawn_stays_off_the_lip`). 16 u (half a tile) keeps a respawn at least 26 u from an edge, four ticks of running before the box leaves it, and still counts a two-tile platform (64 u) as safe; a whole tile would need three tiles (84 u);
  - strikes read the stick in 4 equal sectors, a d-pad diagonal going up or down: in the dash's 8 sectors a stick 23.6 degrees above level while running was an up-strike that whiffed over an enemy ahead (`strike_stick_a_little_up_is_side`, `strike_stick_up_diagonal`, `strike_air_down_diagonal_pogo`);
  - a jump on any dash's frames 5 to 9 is a dash-jump, the air dash's included, so tech 2's controls (each an air dash-jump) are relabelled and the no-dash-jump routes measured again (below);
  - side 3 keeps BUILD.md's 3 f startup, with armor through it (task 6 builds the armor), so the table and the feel rule agree;
  - a strike pressed during a strike with no cancel into it ages out of its 8 f buffer, as a jump does: added to that director question.

## How it plays now

Every movement row and all twelve tech interactions have fixtures that pass:
- a jump buffered 8 frames before landing fires on the landing frame; one 9 frames early has expired;
- a jump 6 frames after walking off a ledge is a ground jump, 7 frames after is the air jump;
- a tap jump and a full jump differ by 3.07 tiles;
- the apex hang is two rising frames, the apex and one falling frame;
- a dash from standstill and one at full run travel the same 210 u;
- a dash into the floor lands with no lag, and the air jump and air dash are back on that frame;
- a dash-jump keeps 20 u/f through its airtime and, with its air jump and air dash, clears a 1664 u chasm that nothing without a dash-jump crosses, the Ember Toss included;
- ten plain pogo bounces cross a 3360 u spike pit at full run speed. The pogo-dash rhythm crosses it at 4 bounces a second, and pogo, down-dash, pogo works;
- a well is climbed by kicks at each apex, 176 u every 24 frames, or by mashing at the same rate;
- a crouch-dash slides under a 32 u gap a standing dash cannot enter;
- an ember thrown mid-dash carries the player across a gorge after landing. An ember on a wall, a floor or a ceiling is always reachable, and one in a crawl-height gap brings the player in crouched;
- a strike, dash or toss goes the way the stick pointed when it was pressed, even if it fires frames later from the buffer: a dash or toss 8 ways, a strike 4 ways;
- a hazard sends Ash back at least 26 u from any edge, and puts out a thrown ember;
- a jump pressed in the down-strike is answered by the bounce, not spent as the air jump after it.
- a reverse pogo off a short-hop dash-jump strikes an enemy-sized block's head while Ash, turned to face it, still flies forward, and lands Ash behind it facing its back; any strike in a 6-tick window works.

## Open questions for the director

- **Wall-kick climb.** Play the well climb (panel 5): one fixed kick per apex, the button held or tapped.
- **Pogo-dash cadence.** Play the pogo-dash chain (panel 4) and `docs/feel_log/fixtures/pogo_skim_window6.fixture`. The skim can bounce faster than "about 4 bounces per second" (pogo chain window entry).
- **Ember values.** The ember's 40 and 120 frames and the 24 u fit reach are new; they set how wide a gorge can be and where a teleport may land.
- **Low gaps.** A crouch-dash that stops inside a gap longer than one crouch-dash leaves the player stuck until the dash cooldown ends (`tech10_crouch_dash_long_gap`). The proposed level rule is at most one crouch-dash long. A crouched crawl is the alternative.
- **Wall coyote time** of 6 frames: does a late wall-jump feel fair, and does it ever fire when you meant the air jump?
- **Tech 2's gap** is 1664 u, because the air jump, the air dash and the Ember Toss extend every route; a gap one plain dash-jump wide (about 1040 u) can be crossed without it. With the air jump alone the dash-jump's window is narrow (15 ticks from dash frame 9, 2 from frame 5); with the air dash too it is broad. Is a crossing that wants all three right for the room that teaches the dash-jump?
- **Reverse pogo** (panel 9). It needs a dash's speed: turning back bleeds a run's 9 u/f within 8 frames (air control), leaving at most 36 u, too little to clear an enemy after striking its head. Is a dash-jump the intended way in, or should the down-strike keep the speed it started with when Ash turns?
- **From the second review, behaviour rather than bugs:** a spent wall still kicks (the 3 u reach), so the 90 f slide does not limit a kick climb; the slide budget carries to the opposite wall when kicking across; the dash's invulnerability crosses spike strips up to 140 u; a coyote dash ignores the stick's vertical; a jump pressed early in side 2, side 3 or the up-strike ages out before they end; and an A/B of the jump at 1020 u/s with gravity about 2956 u/s^2 (same 176 u height, rising in 0.35 s instead of 0.375 s).
