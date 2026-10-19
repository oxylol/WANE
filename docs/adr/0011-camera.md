# ADR-0011: Rest the camera on support heights, look ahead only as far as the ground, never outrun the player, and keep its bounds inside the margin

- Status: Accepted (revised after the second, third and fourth camera reviews)
- Date: 2026-10-17
- BUILD.md sections:
  - 5, feel rules: "The camera never fights the player. 60 u horizontal lead in the facing direction, dead zone of 40×30 u, vertical catches up at 0.08 lerp; look-down on crouch hold. Cutscenes may take the camera; combat never does."
  - 12, default pad: "look-down (hold stick down)".
  - 13, presentation: "the camera"; "Rendering interpolates between the last two simulation states".
- Checklist lines: Movement, "The camera never shows the player within 80 units of the screen edge during normal play". Also CLAUDE.md rule 9: "The camera never takes control during combat. Lead, dead zone and lerp values come from `content/camera.tres`".

## Context

BUILD.md gives the camera four numbers and a principle. Followed literally, the numbers fight the player in four places, measured on the camera fixtures (`tests/replay/camera/`) before the rules below existed:
- **Every jump bobs the view.** A 0.08 lerp on the player's height moves the view about 135 u during two full jumps on flat ground.
- **A fall outruns the view.** At terminal velocity (25 u a tick) the lerp lags 327 u, leaving 191 u of view below the feet: 7.6 ticks of warning.
- **A plain look-ahead overshoots the landing.** With a fall lead added, the view kept moving down 80 u after the player landed, then came back 260 u.
- **Landing on a ledge jolts the view.** A lerp toward a support 160 u higher starts the camera at 11.6 u a tick in a single tick.

The first review of this camera then found where the first fixes still failed:
- Room borders thinner than the margin made the margin backstop drive the view rigidly.
- A ledge entering the ground probe mid-fall collapsed the look-ahead in one tick (24.7 u per tick per tick).
- A teleport after the ember had lingered (up to 1586 u) snapped and whipped the view, and drew Ash off-screen between ticks.
- A crouch-dash and a crawl under a low ceiling triggered look-down.
- A double jump left the view 80 u high.
- The dead zone ate 15 u of every look.

The second review found the rest:
- A cut teleport left Ash exactly on the 80 u margin, so moving on the way the teleport went needed the backstop (up to 20 ticks of it).
- When a fast fall stopped or turned (an up-dash, an air jump, a cling, a side dash), the view kept falling for up to 11 ticks and then swung back: 309 u of view motion against Ash in the worst case. The fall look shrank at only 16 u a tick, and the 3 u per tick per tick limit held the view's downward speed.
- The ground probe's three samples missed narrow ground between them (a one-tile platform far below: the look went 164 u past the ground the player landed on), and braked for ledges only passed.
- Crouched strikes in a fight triggered look-down, against CLAUDE.md rule 9.
- Dithering, and strikes turning Ash both ways, swung the lead, so the view moved further than the player.
- An up-dash showed 119 u above the head, about six ticks of the dash.
- A double jump left the view 15 u high (the dead zone holding where the rest window had left it).
- The probe ran `move_y` on the live world: presentation writing the core, even if only scratch fields.

The third review found five more, each from a case no fixture covered:
- A teleport that left Ash just outside the margin glided from the old view, which starts at rest; a dash or an up-dash straight after it reached the margin before the glide got going (the backstop for up to 7 ticks, the view jumping 16.8 u per tick per tick). At 4:3 an existing fixture did the same.
- The ground probe assumed the fall kept its speed across, so a ledge Ash steered onto late in a fast fall appeared a few ticks before the landing: the view overshot it, stopped dead, and drifted back up 180 u with Ash standing still.
- Leaving the ground ended a look-down at once, so dropping through a one-way or walking off into the space just looked at swung the view up 34 to 50 u against Ash before it followed.
- Wall-jumping across a narrow shaft in a room wider than the view committed the lead on every 108 u crossing, adding its swing to Ash's speed: the world swayed sideways three times a second.
- The eased bounds only approached a room's edge, so a room with no border tiles (the grid's edge is solid) left Ash 0.2 u inside the margin.

The fourth review found that three of the third round's fixes had been tuned to the one fixture that showed each bug, and broke a little way from it:
- The steering envelope counted any wall inside it as ground (`floor_top_in` stands a span already reaching into a wall on it at once). A fall along a wall had no look at all (Ash rode 0.78 of the way down the view and the backstop moved the view on the last three ticks), a fall down a 128 u shaft looked 250 u ahead instead of 500, and a ledge behind a wall counted as a landing.
- The look-drop fix clamped the look to near ground in one tick while the view already showed past it: dropping 64 u after a look swung the view 69 u up against Ash.
- The quadratic ease reached a room's edge, but the vertical follow (the lerp and the acceleration limit) reached the ease 13 to 20 u late: falling onto, or climbing into, a room edge with no border tile needed the backstop.
- In shafts wider than 140 u each crossing still committed the lead (at 120 u, or after 20 ticks in the widest), and the world swayed again.
- Climbing out of a shaft and running off the top, the rest height kept easing up after the climb it lagged: the view rose 54 u while Ash fell.
- On a long 45-degree ramp the rest rose at 8 u a tick while Ash climbed at 9, so the view fell behind until the 256 u window stopped it.
- The commit distance was a literal (twice the lead) in code.

All of those are now fixtures in `tests/replay/camera/` (the second review's 48, the third's 9 and the fourth's 14 among them) or sweeps in `test_camera_review_round4.gd`.

BUILD.md leaves open:
- how far look-down goes, and when;
- how fast the lead swings;
- what happens on a teleport, a hazard respawn and at a room's edge;
- whether the horizontal follow is smoothed.

The camera is presentation (`game/camera/`), so it may use floats. It is still stepped once per simulation tick, so it behaves the same at any frame rate and every rule can be tested against every replay fixture.

## Decision

`CameraRig` is stepped once per tick with a `CameraSubject` read from the simulation. `GameCamera` places the view between the last two ticks at the driver's interpolation factor. Every value lives in `content/camera.tres`.

**Horizontal: rigid, by design.**
- The focus is the player's centre plus a 60 u lead in the facing direction.
- Inside the 40 u dead zone the player moves freely. Beyond it the view moves with the player exactly, so Ash holds still on screen at speed: about 990 u visible ahead of a dash.
- The view's speed across changes only when the player's does, or by the lead's swing of 4 u a tick when Ash turns. The swing is never faster than the player's own motion the other way, so a strike backward in the air (Ash turns while the jump still carries forward) never pulls the view back.
- The lead follows a turn only once Ash has gone the lead's whole swing (`lead_commit_u`, 120 u) the new way, or kept facing it for 20 ticks. Turning back and forth in place or striking both ways in a fight leaves the lead and the view where they are: a dither never moves the view further than Ash moves. A turn after a run moves the view 80 u relative to Ash (the lead's 120 u less what the dead zone takes on each side).
- **No turn commits between touching a wall and next standing on the ground**, unless Ash gets 400 u (`lead_wall_release_u`) from the last wall touched. A cling faces Ash away from the wall it holds, so a climb up a shaft turns at every wall without choosing a way to go; whatever the shaft's width up to 400 u, the view sways only as far as the dead zone lets it and never faster than Ash. The first version committed after the dead zone's width (40 u), which every shaft crossing passed; the second after 120 u, which every crossing of a shaft wider than 140 u passed. The release came with the fifth review (L1): a wall-jump away and a 1220 u drift across an open room kept the lead pointing back at the wall for 136 ticks.
- Smoothing the horizontal follow would let the player slide across the screen whenever they change speed. BUILD.md gives a dead zone and no horizontal lerp, and holding the player still is what "never fights" means across.

**Vertical: the rest height.**
- The view rests on the feet at the last place the player stood, clung to a wall, kicked or wall-jumped off one, or bounced off a pogo.
- **Up**: walking up continuous ground (a ramp, a step) carries the rest height with Ash at once, as a fall carries it down. Landing on a higher support eases the rest up to it at 8 u a tick, so landing on a ledge never jolts the view, and a wall-kick climb's 176 u steps become a steady 6.5 to 7.8 u a tick from the fourth kick (`cam_shaft_climb`, its presses on the climb's 24-tick period). A climb broken by a slide (a press that found no wall spends the air jump, and Ash slides a tick or two before the next kick: `cam6_climb_after_slide`) is taken up again from the next kick without the view ever stopping or sinking; its speed swings between 3 and 8.5 u a tick for three kicks while it catches up within its acceleration, then settles into the steady band (sixth review, L1). The easing pauses only while Ash falls away from the support, the feet at or below it (walking off the top of a climb the view lagged). On a hop's way down toward it the ease carries on, so hops in place on a ledge leave the view exactly where it is without them (sixth review, M2: the ease paused on every hop's way down and the view froze for 10 ticks at a time).
- **Down**: it follows the feet down at once (a fall, a step down, a wall slide).
- **In the air**: it is raised with the feet once they are more than 256 u above it, and lowered with them again as they come back down. A full jump or a wall-kick (176 u) never moves the view; a double jump moves it about 16 u, and back on the ground it returns to where it was (the dead zone re-centres once the window has let go, rather than holding the view half its height off).
- The 30 u dead zone holds the view still for small changes of the rest height. Beyond it the view catches up at BUILD.md's 0.08 lerp.
- **Never outrunning the player.** The view's vertical speed changes by at most 3 u per tick in a tick, with one exception: a view moving faster than the player now moves the same way (the player landed, clung, bounced, or turned with an up-dash or an air jump) may at once slow to the player's own speed. It turns with the player at once only when the player turned, from moving the view's way the tick before; otherwise it may stop at once and no more. A jump out of a held look-down used to snap the view from sinking into the look at 0.8 to 1.9 u a tick to rising at 14 to 15 u a tick on the takeoff tick, though Ash had been standing still (fifth review, M1, `cam_look_then_jump` and `cam5_look_then_jump_drift`); it now stops and then rises by the limit, 3 u a tick each tick. The view then finishes the look's return after the landing, as a look let go while standing does (55 u in the 4-tile shaft). And while Ash falls unsupported at or below the last support the view never rises, even while it is still catching up from below (a climb it lagged, then a walk off the top): it stops at once instead, which is the same exception (a view moving against the player slows at once to nothing). Above the last support (the way down of a hop toward it or onto higher ground: a hop in place, a staircase, a ramp's crest) the view carries on as it was, easing up to the support: the hop does not move it. Stopping it dead at every apex was a 3 Hz stutter up a staircase (fifth review, M1); only letting its rise shrink there still took it to 0.2 u a tick at every hop and froze it while Ash hopped on a ledge it was easing up to (sixth review, M2). Out of a held look-down the view no longer freezes while Ash falls back to the floor and drifts on after the landing: 10 u is left to go after it (55 u before). The mirror holds too: while Ash rises unsupported the view never sinks, even while it is still catching up with a fall it lagged. An air jump just above the floor at the end of a fall used to leave the view sinking 90 u against Ash's rise (fifth review, H2). So a fall that stops never carries the view on: across all fixtures, the view moves against the player's vertical motion for less than a tile in any stretch while the player moves faster than a wall slide, the way down of a hop above the last support aside (BUILD.md: the ease pauses only "while the player falls away from it"). A jump or a kick, which the view lags anyway, loosens nothing, so a climb still rises steadily. On screen the player's motion stays smooth; the world turns as sharply as the player did.

**Three looks, added after the dead zone, so each moves the view exactly as far as it says:**
- **Look-down**: 200 u, at 8 u a tick, once the player has asked for 20 ticks.
  - Asking means standing crouched on the ground with the stick straight down, not dashing, striking or casting. A crouch-dash, a crawl under a low ceiling and crouched strikes or spells in a fight (Radiance is cast with the stick held down) are not requests (CLAUDE.md rule 9).
  - Leaving the ground upward (a jump) ends the look at once: the view turns back to the player rather than finishing the look while they rise. Dropping or walking off into the space looked at, the two looks together shrink no faster than the view's anchor goes down with Ash, so the view never turns up against the drop, however near the ground below; what is left of the look eases out once Ash stands again. Ending it at once swung the view up 34 to 50 u; clamping it to the near ground (the third round) swung it up 69 u on a 64 u drop. Now it rises by nothing on drops of 64 to 256 u.
  - The view follows the look at the vertical lerp: 155 u down 50 ticks into the hold, 196 u at 80. Ash then sits on the view's upper third.
  - The look is bounded by the room like the rest of the view: crouched on a room's floor, it moves the view only as far as the room's edge allows (20 u in the camera test room).
  - Once the look has been asked for its whole delay it stays wanted until Ash stands up, lets the stick go or does anything else on the ground (a dash): then it eases out, and asking again waits the whole 20 ticks. A crouched strike or spell with the stick held down holds the look where it is (it neither grows nor eases out, and neither ever starts one: BUILD.md, "never during a strike"). Strikes 15 to 40 ticks apart used to shrink the look by 8 u a tick through each 14-tick strike and bring it back with no delay on the first crouched tick after, so the view swung 32 u down and 35 u up every strike while Ash stood and fought (sixth review, H1).
  - In the air a look still showing carries on if Ash lands asking for it, and holds on the landing tick (not yet a crouch). Down held through a drop and the landing used to ease the look out and back in, the view rising 90 u and sinking 116 u with no change of input (fifth review, H3).
- **Falls**: below the last support (or the rest height, when that is higher), the view looks 20 ticks of fall ahead, the look growing at up to 16 u a tick and dropped the moment the fall ends. It used to start only below the eased rest height, which lags a climb, so a drop over the top of a wall fell 250 u with no look (fifth review, M4).
  - It never reaches past the ground the fall will land on. `CameraSubject` follows the player's path over the next 20 ticks (the horizontal speed kept, the Wick's gravity, a wall stopping the horizontal travel) and checks each tick's step as one box spanning all of it, so ground between ticks is never missed and ledges the path passes above are not counted. It reads the world through read-only queries (`CollisionQueries.floor_top_in`, `region_blocked`): the camera never writes the core.
  - The camera cannot know the stick's future, so each tick's box is widened on each side by how far air control could still carry Ash that way by then: accelerating at the air acceleration until the speed that way reaches run speed, counted as the player moves (the speed changes before each tick's move, so the sum a + 2a + ...; the fifth review found a·k²/2 short by up to 11 u), plus the 10 u ledge-grab, and a ledge top up to the ledge-grab above the feet in the widened part counts as ground: steering into its side lifts Ash onto it (fifth review, H1). A wall holds the path's horizontal travel up only while it is there: Ash keeps the speed while the stick holds that way, so the path carries on past a wall that ends. The widening stops at the first wall tile or solid box at Ash's height there (slopes do not stop it: Ash can come down onto one), so a wall beside the fall is never ground and a ledge behind a wall never counts; a fall along a wall, a cling let go, or a fall down a shaft of any width looks as far ahead as one in the open. A ledge Ash could still steer onto counts as the landing. Steering onto one late now lands with the view's centre above the feet and the view never comes back up. The price, by design: falling past a ledge within steering reach shortens the look until it is passed, and the look grows back after (`cam_fall_past_ledge`).
  - At terminal velocity Ash's centre sits 0.32 to 0.40 of the way down the view, with 630 to 715 u (0.42 to 0.48 s of fall) below the feet.
  - The camera arrives at the landing with the player, and the look is gone on the landing tick.
- **Up-dashes**: dashing up, the view looks 120 u ahead of the dash, at 16 u a tick. An up-dash out of a jump and an air jump now shows at least 161 u above the head (eight ticks of the dash; 119 u before).
**Room edges.**
- The view's centre stays within the room grown by the 80 u margin, so the player can stand against a one-tile wall without the margin having to push.
- It eases into those bounds over the last 160 u of its travel instead of stopping dead, on both axes, and reaches them: within the ease the view moves at a share of the focus's speed that falls linearly to nothing, so a player against a room's outermost edge (a room with no border tiles) is exactly the margin from the view's edge. The first version eased exponentially and never quite arrived. A room smaller than the view, grown, is centred.
- Vertically the bounds are grown a tile and a half further (`edge_slack_u`, 48 u). Across, the follow is rigid and arrives with the player; vertically it eases (the lerp and the acceleration limit), so a fall onto an edge with no border tile below, or a climb into one above (a room's opening onto the next), reached the eased bound 13 to 20 u after Ash reached the margin. The slack is where the vertical follow eases in. 32 u covered falls and jumps, but not a jump, the air jump and an up-dash into a top edge from a platform 16 or 17 rows below it (fifth review, M2).
- The view beyond the room is drawn as solid.

**The margin.**
- The player's box is never nearer than 80 u to the view's edge.
- The follow and the bounds are built never to need the backstop. `follow_misses` counts every tick it moves the view, and the tests require none on every fixture.

**Teleport and respawn.**
- After an Ember Toss teleport the follow restarts at the player. The view glides there from where it was with a smootherstep, which starts and ends with no speed and no acceleration relative to the follow.
- The glide lasts 24 ticks, or longer to keep its peak at 32 u a tick.
- On an axis where the old view would leave the player nearer its edge than 160 u (`glide_cut_u`: the margin plus 80 u; a teleport after the ember lingered can reach 1500 u), the view cuts all the way to where the follow puts it, with no interpolation across the cut, and the other axis glides. A glide starts at rest and the follow trails a sudden move by up to the dead zone and its acceleration's lag (an up-dash gains about 90 u on the view before the view reaches its speed), so the cut has to leave room for moving on at once. Cutting only as far as the margin allows (the first version) left Ash on the margin; cutting only inside the margin (the second) left a band just outside it where a dash or an up-dash on needed the backstop. A sweep over every distance of run, dash, up-dash and jump after a teleport, at 16:9 and 4:3, needs it on no tick.
- **A glide yields to the margin across.** Where the room's bound holds the follow itself with the player within `glide_cut_u` of the view's edge (an edge with no border tile), any glide inward would carry the player past the margin, so that axis cuts. And while a glide runs, a player who outruns it toward the view's edge across takes the view along, as the rigid follow across would: a teleport then a dash toward a borderless edge needed the backstop for up to 18 ticks (fifth review, M3).
- **A glide finishes early when the player presses on vertically.** Vertically the follow eases, so yielding to the margin would shove the view at the player's speed. Instead, once the player comes nearer than `glide_cut_u` to the edge the view is gliding toward (a dash, an up-dash or a fall on, the way the view has yet to go), the rest of the glide's vertical offset is closed as fast as the glide's acceleration allows (`glide_accel_milli_u`, 5 u per tick per tick, less what the follow's own speed changed that tick; at most the glide's peak) and met at rest, braking with the 2 u the follow can never take. A ceiling or a borderless top holds the follow still, and the glide's offset held the view behind it while an up-dash carried Ash 180 u on: the backstop for up to 7 ticks and the view's speed jumping 10 to 19 u a tick; the bottom twin did the same (sixth review, M1). A sweep over ceilings, borderless tops and borderless bottoms 12 to 24 rows away, toss waits of 20 to 52 ticks and a dash on at once or after a jump, at every screen shape, needs the backstop on no tick and changes the view's speed by at most 5 u a tick.
- **A view that was moving stops with the teleport.** The second review asked for the glide to start from the view's own speed. Any smooth stop from a fall's 25 u a tick carries the view on another 60 to 100 u the way it was going before it turns toward where the player went, and the teleport is itself a jump the player chose; so the view's own motion stops with it, and the glide starts from rest.
- A hazard respawn cuts, and the presentation will cover it with a fade (task 6).
**Screen shape.** `GameCamera` zooms so the planned 1920 × 1080 u view fits the screen, and tells the rig the size it really shows. A 16:10 screen sees 1920 × 1200 u and the bounds use that; the tests play every fixture at 16:9, 16:10, 4:3 and 21:9 (2520 × 1080).

**No combat control.** Nothing here reacts to attacks or enemies (CLAUDE.md rule 9). Screen shake (task 6) offsets the drawn view, never the rig.

## Alternatives considered

| Option | Why not |
| --- | --- |
| BUILD.md literally: lerp the player's height | Every jump bobs the view by about 135 u; a terminal fall leaves 7.6 ticks of warning |
| Platform snap without a window (Super Mario World) | A double jump (280 u) and a jump, air jump and up-dash (550 u) carry the player toward the top with the view still at the ground |
| A rest window of 192 u, just over a jump | With the fixed wall-kick (ADR-0010) the rest height still lags the last kick at each apex; 192 u then set the window off mid-climb and the view's speed swung between 5.7 and 8.1 u a tick |
| A fall lead with no ground limit, or a probe under the player only | The view sinks past the landing and comes back; a ledge drifted onto mid-fall collapses the look in one tick |
| Lerp the rest height straight to a new support | 11.6 u a tick in a single tick on landing; a climb pumps the view with every kick |
| A velocity-based upward lead for climbs | It pumps with each kick and sinks back when the climb ends. The climb already shows 214 u (29 ticks) above the head on average, 153 u at the least: about what a terminal fall shows below |
| Smooth the horizontal follow | The player would slide across the screen with every change of speed; BUILD.md gives a dead zone and no horizontal lerp |
| Clamp to the room exactly | With a one-tile border the margin then drives the view rigidly at every wall; the room grown by the margin removes the conflict |
| Lerp or cut on every teleport | A lerp whips at 57 u a tick from rest; a cut loses where Ash went. Glide, and cut only what the margin cannot hold |
| A glide that starts from the view's own speed (second review) | A smooth stop from 25 u a tick carries the view 60 to 100 u further from where the player went before it turns |
| An absolute 3 u per tick per tick limit on the view's vertical speed | When a fall stops or turns, the view carries on against the player for up to 11 ticks and swings back (309 u of motion against Ash) |
| Widening the limit by the player's own change of speed (the second review's suggestion) | A kick's sudden upward speed loosens it too, and a climb pumps; only slowing toward the player's own speed needs the exception |
| Ease the lead swing, or delay it a fixed time | Dithering at any period longer than the delay still swings it; committing on distance travelled (or a long hold) follows real turns and ignores turning in place |
| Commit the lead after the dead zone's width (40 u) | Every crossing of a narrow shaft commits it, and the lead's swing adds to Ash's speed: the world sways three times a second during a vertical climb |
| A ground probe along the fall's current path only | A ledge steered onto late appears ticks before the landing: the view overshoots it and comes back 180 u (third review) |
| Predict the path with the stick's current direction | Steering that starts late is still seen late; only the envelope of what air control can reach keeps the look above every possible landing |
| Cut a teleport only when the old view leaves the player inside the margin | A teleport just outside it glides from rest and a dash on reaches the margin first (third review) |
| Let a glide yield to the margin vertically, as it does across (sixth review's first suggestion) | The backstop's count goes, its jolt stays: the margin pushes the view at the up-dash's 20 u a tick from 4 |
| Ease a look-down out during a strike and let it come straight back after (fifth round) | The view pumped 32 u down and 35 u up with every strike 15 to 40 ticks apart; held still through the strike, the look moves nothing |
| Sample the ground under the player and at two points along the fall | Narrow ground between the samples is missed, and ledges only passed above brake the look |
| Widen the steering envelope without regard to walls (third round) | `floor_top_in` stands a span reaching into a wall on it: a fall along a wall or down a shaft loses its look, and a ledge behind a wall counts (fourth review) |
| Clamp the look-down to the near ground when Ash drops (third round) | The view already shows past the ground: it swings up 69 u against a 64 u drop |
| Commit the lead at 120 u in a shaft | Every crossing of a shaft wider than 140 u passes it; the widest also pass 20 ticks. Only the wall contact tells a climb from a turn |
| Lerp an unbounded vertical follow and clamp its output (the fourth review's suggestion) | It clamps the view's speed at the bound, a jolt; growing the vertical bounds by the follow's own lag keeps every rule |
| Ease the rest up a ramp at 8 u a tick | Ash climbs a 45-degree ramp at 9: the view falls behind for the whole climb |

## Feel reason

Movement is the first pillar. The camera's job is to show the next decision early enough to make it, measured in time, not distance:
- 0.45 s below a terminal fall;
- about half a second above a wall-kick climb;
- 990 u ahead of a dash.

It must never move the world when the player did not ask it to. A jump that bobs the screen makes every jump on flat ground feel like it is fighting the floor.

## Consequences

- `tests/unit/game/test_camera_rig.gd` checks each rule, `test_camera_review.gd` each finding of the second review, `test_camera_review_round3.gd` each of the third (including a sweep of teleports followed at once by a run, a dash, an up-dash or a jump), `test_camera_review_round4.gd` each of the fourth, as sweeps over the dimension each bug lives in: falls 0 to 200 u from a wall, falls and wall-jump climbs in shafts 96 to 288 u wide, look-drops of 64 to 256 u, and borderless edges, at all four screen shapes; and `test_camera_review_round5.gd` each of the fifth, on the review's own fixtures (`tests/replay/camera/cam5_*`): reversing onto a ledge and a notch after a fall, an air jump just above the floor, a look-down held through a drop, a staircase, a jump into a borderless top, a teleport near a borderless side, a drop over a climbed wall and a long drift after a wall-jump. They play every movement, tech, physics and camera fixture (307) through the camera at 16:9, 16:10, 4:3 and 21:9, report every fixture that breaks a rule, and require:
  - the 80 u margin held by the follow alone (no backstop corrections at all);
  - no motion against the player across, and never outrunning the player across by more than the lead's swing;
  - vertical speed changes within 3 u per tick per tick (5 inside a glide), or toward the player's own speed when the view outran it;
  - under a tile of vertical motion against the player in any stretch while the player is in the air (not standing, clinging or bouncing). The second round counted only ticks the player moved faster than a wall slide, which hid a look that swung up as Ash dropped into it.

  Each of the second and third reviews' fixes was switched off in turn (reading the stick alone for look-down, a one-tick probe, the margin alone for the cut, the probe without steering): the tests fail. Every round-4 test fails on the third round's camera.
- `tools/replay/film.gd` films fixtures through the real views, with the margin, the dead zone and the focus drawn over them and the player's track across the screen. It is the camera's contact sheet.
- Revisit:
  - when rooms start using vistas (BUILD.md section 10: "the camera pulls back"), which will add a per-room zoom;
  - when screen shake and the hit-stop zoom arrive (task 6);
  - when room transitions arrive (task 7), which cut like a respawn.
