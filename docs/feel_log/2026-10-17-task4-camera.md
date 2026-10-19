# 2026-10-17: Phase 1 task 4, the camera

- Author: Claude
- BUILD.md section and table row:
  - section 5 feel rules: "The camera never fights the player. 60 u horizontal lead in the facing direction, dead zone of 40×30 u, vertical catches up at 0.08 lerp; look-down on crouch hold";
  - section 12: "look-down (hold stick down)";
  - section 15: "The camera never shows the player within 80 units of the screen edge during normal play".
- Fixture(s): `tests/replay/camera/` (the first review's 20, the second's 48, the third's 9, the fourth's 14, the fifth's 12 and the sixth's 6 among them, many with rooms of their own). `tests/unit/game/test_camera_rig.gd`, `test_camera_review.gd`, `test_camera_review_round3.gd` to `test_camera_review_round6.gd` play every movement, tech, physics and camera fixture (332) through the camera at 16:9, 16:10, 4:3 and 21:9; the round-4 suite sweeps wall distances, shaft widths and drop depths.
- Contact sheet: `docs/feel_log/2026-10-17-task4-camera.png`, filmed by `tools/replay/film.gd` through the game's own views.
  - Each row is one fixture, a frame every few ticks.
  - Drawn over each frame: red is the 80 u margin, green the dead zone around the point the follow holds to, the yellow dot the focus (that point plus the looks), and a white ring round Ash, who is small at sheet scale. Frames are a quarter of the 1920 x 1080 view (the third review found a sixth too small to read).
  - Each row ends with the player's track across the screen: blue for across the view, orange for down it.
  - Rows:
    1. run, turn, run back, and a backward strike in the air;
    2. jumps and a running double jump;
    3. onto a 160 u ledge, then a 320 u one;
    4. look-down on a ledge;
    5. a 1600 u fall;
    6. a 15-kick wall climb;
    7. a long teleport to a lingering ember, then running on the way it went (the cut axis);
    8. jumps under a one-tile ceiling and on a one-tile floor;
    9. running into a room's one-tile wall;
    10. reversing onto a ledge mid-fall;
    11. crouched strikes every 10 frames (no look-down);
    12. a hazard respawn;
    13. a fall of 40 ticks, then an up-dash (the view turns with Ash);
    14. a run off a shelf onto a one-tile platform far below;
    15. turning back and forth every 10 frames;
    16. a jump, an air jump and an up-dash;
    17. a teleport that leaves Ash just outside the margin, then an up-dash at once (the axis cuts);
    18. steering onto a ledge late in a fast fall (the view never passes it or comes back up);
    19. looking down over a platform's end, then walking off into the drop (the view keeps going down);
    20. wall-jumping up a narrow shaft in a room wider than the view (the lead does not swing);
    21. a cling to a tall wall let go: the fall along the wall looks as far ahead as one in the open, Ash on the view's upper third;
    22. a look-down from a one-way, then a drop onto a floor 64 u below (the view never turns up);
    23. a fall onto the grid's own bottom edge, no border tile (the view arrives with Ash, inside the margin);
    24. wall-jumping across a 192 u shaft (the view holds across: the blue track only ripples);
    25. climbing out of a 128 u shaft and running off the top (the view stops rising the tick Ash falls);
    26. running up a 2240 u 45-degree ramp (Ash keeps one place in the view).

## Change

BUILD.md's four numbers are kept: the 60 u lead, the 40×30 u dead zone, the 0.08 lerp and the 80 u margin. These are new, none of them in BUILD.md, and all live in `content/camera.tres`:

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Lead swing when Ash turns | none | 4 | u per tick |
| Look-down delay, distance, speed | none | 20, 200, 8 | ticks, u, u per tick |
| Rest window (rise before a jump moves the view) | none | 256 | u |
| Rest rise speed (easing up to a higher support; continuous ground carries the rest at once) | none | 8 | u per tick |
| Vertical acceleration limit | none | 3 | u per tick per tick |
| Fall look-ahead, and how fast it grows | none | 20, 16 | ticks of fall, u per tick |
| Ground probe below a fall | none | the fall's own path, 20 ticks ahead (the first round's 1024 u straight down is gone) | ticks |
| Lead commits to a turn after (never between a wall contact and the next landing) | none | 120 travelled (`lead_commit_u`), or 20 | u, ticks |
| ... unless that far from the last wall touched (`lead_wall_release_u`) | none | 400 | u |
| Up-dash look | none | 120 | u |
| Teleport glide length, and its peak speed | none | 24, 32 | ticks, u per tick |
| A glide's acceleration, finishing early when Ash presses on vertically (`glide_accel_milli_u`) | none | 5 (sixth review) | u per tick per tick |
| A teleport cuts an axis on which the old view leaves Ash nearer its edge than | none | 160 | u |
| Room-edge ease | none | 160 | u |
| Vertical bounds grown past the margin (`edge_slack_u`) | none | 32, then 48 (fifth review) | u |

BUILD.md section 5's camera rule now names these behaviours.

## Why

ADR-0011 has the full reasoning. Every "before" below was measured on the fixtures.

- **The rest height and its 256 u window.**
  - Before: a plain 0.08 lerp on the player's height bobs the view about 135 u over two jumps on flat ground.
  - After: no jump moves the view (row 2: the orange track traces whole jump arcs while the view holds), and a double jump moves it about 16 u before it settles back.
  - 256 u covers a jump's or a kick's 176 u rise, plus how far the rest height lags a wall climb. At 192 u the window went off at each apex of the climb, and the view's speed swung between 5.7 and 8.1 u a tick.
- **8 u a tick up to a higher support.**
  - Before: a lerp straight to a 160 u ledge started the view at 11.6 u a tick in one tick. Now it starts at under 1 u a tick (row 3).
  - The climb's 176 u steps become a steady 6.6 to 8.2 u a tick (row 6). 8 is just above the climb's average of 7.33 u a tick.
  - Walking up continuous ground carries the rest at once (fourth review): Ash climbs a 45-degree ramp at 9 u a tick, so easing at 8 let the view fall behind for the whole climb (the top gap shrank from 334 to 181 u on a 2240 u ramp). Now Ash keeps one place in the view (row 26; the top gap holds within 1 u).
  - The easing pauses while Ash falls away from the support, and the view never rises while Ash falls (fourth review): climbing out of a shaft and running off the top, the view used to keep easing up after the climb it lagged, 54 u against Ash (row 25).
- **The 3 u per tick per tick limit, and never outrunning the player.** Nothing jolts the view on its own. But the limit alone held the view's speed when a fast fall stopped or turned: the view carried on for up to 11 ticks against Ash and swung back (309 u against Ash after a fall and an air jump; the second review). Now a view moving faster than the player the same way may slow at once to the player's own speed, or turn with them: against-the-player motion fell to 28 u for that fall, 1 u for a fall into an up-dash (row 13), and under a tile in any stretch across all 237 fixtures. On screen Ash's motion stays smooth; the world turns as sharply as Ash did. A kick, which the view lags anyway, loosens nothing, so the climb (row 6) is as steady as before.
- **The fall look-ahead of 20 ticks, never past the ground.**
  - Before: the lerp alone left 191 u below the feet at terminal velocity. Now 630 to 715 u, or 0.42 to 0.48 s of fall, shows below the feet, with Ash's centre 0.32 to 0.40 of the way down the view (row 5).
  - The ground is found along the fall's own path, each tick's step checked as one box: a one-tile platform far below is seen all the way down (row 14), where the old three samples missed it and the look went 164 u past it. Ledges the path passes above no longer brake the look.
  - The look ends the tick the fall does (a landing, a cling, a bounce, a jump or a dash out of it).
  - The steering envelope stops at walls (fourth review). It used to count any wall inside it as ground, so a fall along a wall had no look at all (Ash 0.78 of the way down the view, the backstop on the last three ticks) and a 128 u shaft looked 250 u ahead. Now every fall 0 to 200 u from a wall, a cling let go (row 21) and a fall down any shaft from 96 to 288 u looks the full 500 u ahead, as in the open, and a ledge behind a wall is not ground.
  - The probe now also counts any ledge Ash could still steer onto with air control (third review): the camera cannot know the stick's future. Steering onto a ledge late in a fast fall used to land with the view past it, stopped dead, then drifting 180 u back up with Ash standing still; now it lands with the view's centre above the feet and never comes back up (row 18). Falling past a ledge within steering reach shortens the look until it is passed (`cam_fall_past_ledge`).
- **16 u a tick of growth.** At 20, a fall crossing the rest height already fast changed the view's speed by 3.03 u per tick in one tick.
- **Look-down: 200 u after 20 ticks, added after the dead zone.** It moves the view exactly 200 u and back exactly (before, the dead zone ate 15 u of it).
  - 200 u puts Ash on the upper third and shows 22 tiles below the feet instead of 16.
  - Only an actual request (crouched on the ground, stick straight down, not dashing, not striking) counts, so a crouch-dash, a crawl under a low ceiling and crouched strikes in a fight (row 11) never look down.
  - A jump ends a look at once. A drop or a walk off into the space looked at keeps the looks together from shrinking faster than Ash takes the view down; what is left eases out once Ash stands (fourth review). Ending it at once swung the view up 34 to 50 u against Ash; the third round's clamp to the near ground swung it up 69 u on a 64 u drop. Now it rises by nothing on drops of 64 to 256 u (rows 19 and 22).
  - The view follows the look at the vertical lerp: 155 u down 50 ticks into the hold, 196 u at 80. On a room's floor it looks only as far as the room's edge allows.
- **Room bounds grown by the margin, eased over 160 u.**
  - Before: against a one-tile wall the margin had to push the view rigidly (36 corrections in two jumps under a one-tile ceiling), and the view stopped dead at every room edge.
  - Now the margin is never needed (rows 8 and 9), and the view slows into an edge instead of stopping.
  - The ease now reaches the bound (third review): it used to approach it exponentially, so in a room whose edge is the grid's own (no border tiles) Ash stood 0.2 u inside the margin on every tick.
  - **32 u of vertical slack** (fourth review). The vertical follow eases, so a fall onto a borderless bottom edge or a climb into a borderless top reached the bound 13 to 20 u after Ash reached the margin, and the backstop moved the view (13 u a tick in one tick). A tile more lets the follow ease in and arrive with Ash (row 23). Across, the follow is rigid and needs none.
  - **48 u** (fifth review, M2). A jump, the air jump and an up-dash into a borderless top from a platform 16 or 17 rows below it reached the margin first: the window held the view still until the climb was 256 u up, and the up-dash outran the ease. 40 u did not clear that sweep (18 of 6144 runs, 16:9 and 21:9 only); 48 u clears it.
- **Lead swing of 4 u a tick, committed after 120 u or 20 ticks.** A turn after a run moves the view 80 u relative to Ash (the lead's 120 u less what the dead zone takes) and never against the player (row 1). Turning back and forth in place used to swing the lead each time, so the view moved further than Ash (156 u against 136 u); now it follows only a turn Ash commits to, and never moves more than Ash does (row 15).
  - The commit distance was the dead zone's width (40 u) until the third review: every 108 u crossing of a narrow shaft committed it and added the swing to Ash's speed, so the world swayed sideways three times a second during a climb. At the lead's whole swing (120 u) a 108 u crossing never commits it (row 20). A turn-and-run commits a few ticks later and the view still swings its 80 u.
  - The fourth review found shafts wider than 140 u still swaying (5 to 9 swings across 140 ticks, the view up to 4 u a tick faster than Ash). No distance tells a shaft crossing from a turn; a wall does. No turn commits between touching a wall and next landing, so across a shaft of any width the view moves no faster than Ash (row 24; swept from 96 to 288 u). The 120 u is `lead_commit_u` in `content/camera.tres`, no longer twice the lead in code.
  - **400 u from the wall** (fifth review, L1). With no turn committing until the next landing, a wall-jump away and a 1220 u drift across an open room kept the lead pointing back at the wall for 136 ticks: 880 u visible ahead of Ash instead of 1000. Past 400 u from the last wall touched, a turn commits again. 400 u is wider than any shaft the climbs use (96 to 288 u), so a climb still never swings the lead.
- **An up-dash look of 120 u.** An up-dash out of a jump and an air jump showed 119 u above the head, six ticks of the dash; now at least 161 u (row 16).
- **A double jump returns.** Back on the ground the view comes back to where it was, instead of resting the dead zone's half-height (15 u) above it.
- **Teleport glide of 24 ticks at up to 32 u a tick.**
  - Before: a lerp glide started at 57 u a tick, and a long teleport snapped the view 444 u then whipped it at 97 u a tick.
  - Now the glide starts and ends at rest. A long one cuts the axis the margin cannot hold all the way to where the follow puts it, and glides the other (row 7); nothing is interpolated across the cut. Cutting only as far as the margin allowed left Ash on the margin, and running on needed the backstop for 3 to 20 ticks.
  - **160 u** (third review): a teleport that left Ash just outside the margin glided from rest, and a dash or up-dash straight after it reached the margin before the glide moved (the backstop for up to 7 ticks, the view jumping 16.8 u per tick per tick). An axis now cuts whenever the old view would leave Ash nearer its edge than 160 u: the margin plus 80 u, about what an up-dash gains on the view while the view gets up to its speed. A sweep of run, dash, up-dash and jump after a teleport, at every distance and at 16:9 and 4:3, needs the backstop on no tick (row 17).
  - A view that was moving stops with the teleport. The second review asked for the glide to start from the view's own speed; any smooth stop from a fall's 25 u a tick carries the view another 60 to 100 u away from where Ash went (ADR-0011).
- **A hazard respawn cuts** (row 12). Task 6's fade will cover it.

## Sixth review (2026-10-19)

Contact sheet: `docs/feel_log/2026-10-19-camera-review-6.png`, drawn as the main sheet. Rows: (1) a held look-down, then crouched strikes every 30 ticks with the stick still down; (2) a toss up toward a one-tile ceiling 18 rows above, the teleport, and an up-dash at once; (3) hops in place on the 320 u ledge while the view still eases up to it; (4) the shaft climb broken by a slide, then taken up again. I looked at each row: in (1) the look holds at 200 u through every strike and the view only settles on down; in (2) the view rises into the ceiling with Ash inside the red margin on every frame; in (3) the ledge sinks steadily through the hops; in (4) Ash's track down the view scallops with the kicks and never reaches the shaded margin.

| Finding | Before | After |
| --- | --- | --- |
| H1: crouched strikes with the stick held down pumped a held look | The look shrank 8 u a tick through each 14-tick strike and came back on the first crouched tick after it: the view swung 32 u down and 35 u up every strike, Ash standing still | A crouched strike holds the look where it is; standing up, letting the stick go or a dash ends it and asking again waits the whole 20 ticks. The view never turns in strikes 15 to 40 ticks apart, and strikes fewer than 20 free ticks apart never start a look |
| M1: a teleport up under a ceiling or a borderless top, then an up-dash | The glide's offset held the view behind a follow the edge held still: the backstop for 4 to 7 ticks, the view's speed jumping 10 to 19 u a tick (2 ticks for the bottom twin) | Once Ash comes within 160 u of the edge the view glides toward, the glide finishes as fast as 5 u a tick a tick allows and meets the follow at rest: no backstop in a sweep of 10 rooms, 9 toss waits and two onward moves at every screen shape; Ash stays 115 u or more from the edge in the reviewer's cases |
| M2: hops stopped the view's ease up to a higher support | The view froze 10 ticks on each hop's way down onto the ledge it was easing up to; up review 5's staircase the rise fell to 0.2 u a tick at every hop; out of the look-down the view froze while Ash fell back, then drifted 55 u up while Ash stood | The ease pauses only while Ash falls away from the support, the feet at or below it. Hops on the ledge leave the view exactly as it is without them; the staircase's rise only gathers pace; 10 u is left after the drift fixture's landing |
| L1: the climb's steady window was moved to fit a slide | `cam_shaft_climb` pressed every 23 ticks against the climb's 24, so one press spent the air jump and Ash slid; the test skipped the three kicks after | `cam_shaft_climb` presses every 24 ticks and climbs steadily (6.5 to 7.8 u a tick) from the fourth kick, as before. The old timing is `cam6_climb_after_slide`, tested for what a slide does: from the next kick the view rises at 3 to 8.5 u a tick, never stopping, and settles in three kicks |

Why the glide does not simply yield to the margin vertically, as it does across: the vertical follow eases, so the margin would push the view at the up-dash's 20 u a tick from 4, the same jolt the backstop gave, only uncounted.

## How it plays now

The tests play all 332 movement, tech, physics and camera fixtures through the camera at 16:9, 16:10, 4:3 and 21:9. On every tick of every one:
- the player is at least 80 u from the edge without the margin ever having to move the view;
- the view never moves against the player across, and never outruns them by more than the lead's swing;
- its vertical speed never changes by more than 3 u per tick in a tick (5 inside a teleport's glide), except to slow to the player's own speed when it outran them;
- it moves against the player's vertical motion for less than a tile in any stretch while the player is in the air (the second round only counted ticks the player moved faster than a wall slide, which hid the look-down's swing on a drop).

## Open questions for the director

- **The wall-kick climb (row 6).** Ash rides in the upper part of the view while climbing: 214 u on average (never under 153 u), or 29 ticks of climbing, shows above the head. Is that enough to read the wall's end?
- **Look-down (row 4).** 200 u, the view getting there about a second into the hold. Far enough? Hold crouch at the edge of a long drop in the sandbox.
- **Teleport glides (rows 7 and 17).** A teleport cuts an axis on which the old view would leave Ash within 160 u of its edge and glides the other. Would you rather it cut outright? Pressing on vertically toward the edge the view glides toward now makes the glide finish early (sixth review sheet, row 2): watch a toss up under a ceiling and an up-dash at once in the sandbox, and say whether the view's catch-up reads as smooth.
- **Ledges within steering reach (row 18).** Falling past one shortens the fall's look until it is passed. Is that pause in the look-ahead noticeable?
- **A fall that stops (row 13).** The view now turns with Ash at once. The world turning that sharply (up to 40 u per tick in a tick at an up-dash out of a fast fall) is the price of never carrying on against Ash. Does it read as the camera keeping up, or as a jolt? The same goes for walking off the top of a climb the view lagged (row 25): the view stops rising, from up to 5 u a tick, the tick Ash starts to fall.
- **Room tops and bottoms (row 23).** The view may show a tile more beyond a room's top and bottom than beyond its sides, drawn solid. Is that noticeable at a room's floor?
- **Horizontal follow.** It is rigid: Ash holds still on screen at speed. BUILD.md gives no horizontal smoothing, and this keeps it that way.
- **Playing it.** The game boots into `content/rooms/sandbox.room`.
