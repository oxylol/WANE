# ADR-0010: How Ash's state machine reads BUILD.md's movement tables

- Status: Accepted (revised after the first, second and third task-3 reviews)
- Date: 2026-10-17
- BUILD.md sections: 5 (all movement tables, the twelve tech interactions, the feel rules), 6 (the Taper's cancel column, Ember Toss)
- Checklist lines: every Movement line; Combat "Dash cancels an attack on frame 4 and the cancel never eats the next attack input"

## Summary

- `core/fsm/player.gd` runs locomotion and a strike layer side by side, the Ember Toss beside both; the toss acts before dash and jump (see Structure).
- Stick threshold 64 of 127; dash and toss read 8 sectors, strikes 4; a buffered press keeps its press-time stick; buffers are 8 f (see Reading the stick).
- Landing by any route restores air jump and dash, clears the ground dash cooldown, caps speed at run speed; air keeps dash speed (see Landing, Air momentum).
- Ground: turnaround keeps 60% speed; crouch needs the stick straight down. Jump: apex hang 4 f at 0.6x, release cut from frame 4, coyote (see Ground, Jump).
- Dash: 20 u/f for 9 f then 3 f at 50%, invulnerable frames 1 to 7, 24 f ground cooldown, one air dash per airtime, dash-jump on frames 5 to 9 (see Dash).
- Wall: cling slides 3 u/f up to 90 f; the first cling since a landing restores jump and dash; wall coyote 6 f; wall-jump 5 f lock, kick 1 f (see Wall).
- A dash cancels a strike from its table frame and keeps an earlier attack press (`Player.queued_attack_left`); strikes turn at once (see Cancels, Strikes).
- Pogo: down-strike box 36 x 24 u live on frames 3 to 9; the bounce keeps horizontal speed, restores jump and dash, and beats a hazard that frame (see Pogo).
- Hazards send back to safe ground (`safe_ground_margin_u` 16 u), 20 f invulnerable; Ember Toss: 600 u/s, 12 s cooldown, fit 24 u (see Hazards, Ember Toss).
- Tech 2's chasm is 1664 u (a crossing needs 1654 u of reach; no-dash-jump routes reach 1592 u); see also Reverse pogo, Kindle-dash and the director questions.

## Context

BUILD.md section 5 gives numbers, not rules for how they combine. Several rows also conflict, with each other or with the checklist:
- the jump row's numbers do not reach its own heights;
- the pogo chain window's note names a cadence its number does not set;
- "dash cancels any attack" against the down-strike's "anything on bounce";
- "Down-dash on ground = nothing" against tech 10's crouch-dash.

The feel log has one entry per number tuned. This ADR records the rules. The second review found a buffered press firing in the wrong direction, a tech 2 gap that could be crossed without the dash-jump, and a dozen edges. The third found an ember that outlived a hazard respawn and crossed tech 2's chasm, a jump pressed in the down-strike that halved the bounce, respawns on a ledge's lip, strikes read in the dash's 8 sectors, and tech 2's controls being air dash-jumps. Each has a fixture under `tests/replay/movement/` or `tests/replay/tech/`, and the rules below include the fixes.

## Decision

**Structure.** `core/fsm/player.gd` runs locomotion (ground, air, dash, wall) and a strike layer (the Taper) side by side. The Ember Toss (`ember_toss.gd`) runs beside both and never cancels either: that is what makes tech 11 possible. `player_contacts.gd` holds what the world does to the player after its move (pogo bounces, hazards, the hurtbox, safe ground, the Kindle dash-through). `player_wall.gd` holds the wall's rules (the cling, the kick and the wall-jump, letting go with wall coyote time, and which wall a press means), and `player_strikes.gd` which strike a press starts, the chain and its cancels. Each tick, in this order:
1. timers;
2. strike advance;
3. facing;
4. crouch;
5. toss;
6. dash;
7. jump;
8. strike;
9. move;
10. after-move: wall-cling, then the pogo, then hazards only if there was no bounce;
11. ember.

The toss goes before the dash and the jump: a teleport pressed on the same frame as a jump or a dash moves the player first, and the jump or dash goes from where the player arrives. The other way round, the jump or dash fired, spent its resource, and the teleport then cancelled it (`tech11_toss_teleport_and_jump_same_frame`, `_air_dash_`, `_ground_dash_`).

Input is read before the move and acted on the same tick (BUILD.md feel rule 1). Every button press is buffered for its own tunable number of frames, all 8 (the jump, dash and attack buffers in `movement.tres`, the toss buffer in `kit.tres`), and the latest press wins (ADR-0004).

**Reading the stick** (`core/fsm/player_input.gd`).
- Running, crouching and the wall read each axis on its own, past the stick threshold (64 of 127).
- What goes somewhere 8 ways (a dash, the toss) reads an 8-way direction in equal 45-degree sectors: diagonal when the shorter axis is at least tan(22.5 degrees) of the longer. Each axis held to the threshold on its own would leave the diagonals 29.5 degrees of the circle against 60.5 for the straight directions.
- A strike reads a 4-way direction in equal 90-degree sectors (the Taper is "4-directional", BUILD.md section 4): up or down when the vertical axis is at least as long as the horizontal, so a d-pad diagonal is up or down. Read through the dash's 8 sectors, up and down took 135 degrees each and the side strike 45: a stick 23.6 degrees above level while running was an up-strike that whiffed over an enemy ahead (third review, M4; `strike_stick_a_little_up_is_side`, `strike_stick_up_diagonal`, `strike_air_down_diagonal_pogo`). A side strike still turns to the side the stick leans, read 8 ways, so a d-pad's down-forward on the ground (no down-strike there) turns Ash and strikes forward.
- A buffered press goes the way the stick pointed on the frame it was pressed, not wherever it points when the press fires. Down and attack tapped together just after a bounce, with the stick then let go, is still a down-strike when it fires on the chain window's frame 6 (`pogo_buffered_down_strike_stick_released`); the same holds for a strike buffered into a dash and a buffered air dash.

**Landing.** Arriving on the ground by any route counts as a landing:
- a fall, a wall slide, a straight-down air dash, a diagonal air dash that touches down and runs on along the floor, an ember teleport onto ground, and a hazard respawn.

The landing does three things:
- it restores the air jump and air dash, clears the ground dash cooldown (BUILD.md Dash: "Cooldown: 24 f on ground, resets on landing or wall-cling") and makes the next wall-cling fresh;
- it lowers horizontal speed above run speed to run speed on the landing frame, before a buffered jump fires: the air keeps a dash-jump's or a pogo's speed, but bunny-hopping cannot carry a dash-jump on forever ("the ground slows back to run speed");
- a jump, dash or attack pressed within its buffer before landing starts on the landing frame. A jump or attack counts the landing frame as its frame 1. A dash counts it as frame 0, so its nine moving frames and its invulnerability start on the next tick, just as a landing jump first rises on the next tick.
  - **A dash on the tick after a landing jump.** A jump fired on the landing has not risen yet (`jump_fresh`: its first rise comes on the next tick). A dash taken on that tick first takes the rise, as a dash the tick after a jump pressed on the ground does, then starts from there: every jump rises. Anything else that replaces the rise (a teleport, a bounce, a landing, a send-back) clears the flag, so it never skips the gravity of a later fall (movement review 6, M2: the dash ate the jump, and the stale flag skipped a tick of the fall after it).
  - **A jump held back by a spell.** A landing's or a cling's buffered jump waits out Kindle's frames 1 to 7 as a jump on the ground does (ADR-0013; movement review 6, L1).
  - A jump started on the landing frame (or on a cling frame) counts its frames from its first airborne move, as a jump from the ground does, so a buffered tap jump peaks at the same 77.9 u as any tap (`jump_tap_buffered_on_landing`).
  - A buffered jump with the stick straight down onto a one-way drops through it, as on the ground.
  - A diagonal air dash that touches down fires a buffered jump on the touch-down frame, if the dash has reached its jump frames (a dash-jump, as from any dash).
  - A down-strike that missed and reached the ground gives way to a ground strike pressed after it lands, as it gives way to the jump.

A straight-down air dash that reaches the floor cannot go on, so it ends there: a landing with no lag (BUILD.md "Landing: 0 f of lag").

**Ground.**
- **Turnaround** (BUILD.md "2 f, keeps 60% speed"): on the input frame, speed flips to 60% in the new direction, and the remaining 40% is recovered over the next 2 frames; facing flips on the input frame. There is never a dead frame. The turnaround is a ground rule; it counts down and never lingers into air control.
- **Crouch** needs the stick straight down; down-diagonal still walks, so an analog stick a little low never freezes the player. The crouched box cannot move ("cannot move") and stands up as soon as there is headroom.
- **Crouched in the air.** The crouched box ignores the stick in the air too; it keeps only the speed it had, which air deceleration bleeds off. A body stays crouched in the air only under a ceiling too low to stand: anywhere else it stands up at once. So this rule only stops a hop-crawl in a low gap. A hop there would otherwise reach run speed by air control; the collision allows it, so this is a player rule (`tech10_jump_in_low_gap`).
- **Crouch-dash** keeps the 28 u box for the whole dash (tech 10). A ground dash with the stick anywhere down, straight down or down-forward, is a crouch-dash, going the way the stick points or, straight down, the way Ash faces. Only the straight-down stick used to count, so the natural input (down-forward and dash) stood the player up and stopped the dash at the gap's face (`tech10_crouch_dash_down_forward`). "Down-dash on ground = nothing for others" means no special move: it is the ordinary horizontal ground dash, crouched.
- **Down and jump** drops through a one-way only with the stick straight down, as crouch does, and only where one-ways alone hold the player up (ADR-0008).
- **Low gaps** (director question): crouched, the player cannot move, so a crouch-dash that stops inside a gap longer than one crouch-dash strands the player until the ground cooldown allows a second one. Level-design rule: a crouch-only gap is at most one crouch-dash long (about 210 u).

**Jump.**
- The take-off frame has no gravity.
- A release before frame 4 still rises at normal gravity until frame 4, then at the release multiplier until the apex.
- The apex hang is 4 frames of 0.6x gravity centred on the apex, while the button is held. It starts on the rising frame that puts the apex nearest the hang's middle: the first frame whose upward speed is within the hang's speed band plus half a frame of full gravity. For the full jump that is two rising frames, the frame the apex falls in, and one falling frame.
- **Coyote** time counts frames since walking off a ledge, never after a jump or a drop-through; a body placed in the air has none.
- The **landing jump buffer** fires on the landing frame.
- **Every jump rises.** With a ceiling flush on the head there is no room to rise, so the press waits in its buffer (stepping out from under the ceiling fires it) instead of firing a jump that never leaves the floor and spends the air jump (`test_a_jump_under_a_flush_ceiling_never_leaves_the_floor`). Down and jump on a one-way needs no room above.

**Air momentum and air control.**
- Above run speed, the air keeps the extra speed while the stick holds that way. That covers:
  - a dash-jump's dash speed (BUILD.md "keeps 100% dash speed", for the whole jump);
  - a pogo's preserved speed;
  - the dash carry-over.
- Released, normal air deceleration takes over.
- Reversed in the air, it is ordinary air control (BUILD.md "Air control: 0 to max in 8 f", 288 sub-pixels a frame), not the ground turnaround. Facing still turns on the input frame. A dash-jump reversed in the air bleeds its speed over about 18 frames.

**Dash.**
- 20 u/f for 9 frames, then 3 frames at 50%; invulnerable on frames 1 to 7.
- The 24-frame cooldown applies to ground dashes only. It clears on landing and on wall-cling. The air dash is one per airtime, restored by:
  - landing;
  - the first wall-cling since a landing, wall-jump or pogo;
  - a wall-jump;
  - a pogo.
- Reversing the stick during the carry-over ends the carry-over at once and turns the player (BUILD.md s15 "Turning around never produces a dead frame").
- **Coyote dash** (tech 7): a dash within coyote time is a ground dash. It is horizontal (ground dashes are horizontal), uses the ground cooldown, and leaves the air dash for later. If the ground cooldown is still running, the press is the air dash at once; with no air dash left, it is refused rather than held to fire late.
- **Cancels**:
  - A strike's "dash from f N" column is the first frame the dash may cancel it. The down-strike, whose row lists only "anything on bounce", takes section 5's general "dash cancels any attack after frame 4", so a mistimed pogo can be escaped.
  - A cancelled strike ends like a finished one: the chain carries on for its 20 frames, so slash, dash, slash keeps the three-hit rhythm.
  - The cancel spends only the dash press; an attack pressed before it stays buffered and fires on the dash's frame 6 (checklist: "never eats the next attack input"). However old that press is: the dash takes it over (`Player.queued_attack_left`, with the stick it was pressed with), so it fires on frame 6 even when frame 6 is more than the 8-frame buffer after the press. An attack pressed on side 1's frame 2 and a dash on its frame 6 used to lose the attack (fourth review, L1; `dash_cancel_keeps_earlier_attack`).
    - A dash that ends before its frame 6 (a straight-down dash reaching the floor, an air dash clinging to a wall, a dash-jump, a teleport) hands the press back: from the frame the dash ends it waits the attack buffer (8 f), as a press made then would, and fires on the first free frame: the landing frame, the frame after the cling (away from the wall), the dash-jump's own frame. It used to be dropped with the dash, which ate the dash-slash-jump rhythm's second strike (fifth review, H2; `dash_cancel_attack_survives_down_dash_landing`, `_cling`, `_dash_jump`).
    - A press made after the take-over replaces it: the buffer keeps the latest press, with its own stick (fifth review, M3: a forward slash, a dash, then an up-slash came out as the stale forward slash; `dash_cancel_latest_attack_press_wins`).
- **Dash-jump**: a jump on frames 5 to 9 of any dash keeps 100% of the dash's horizontal speed. That includes the air dash: an air jump on its frames 5 to 9 is an air dash-jump and keeps its 20 u/f (BUILD.md's row names no kind of dash; the third review found tech 2's controls were air dash-jumps).
- **On the ground** a level dash walks: it follows slopes up and down and steps up the corner lift (8 u), as running does (ADR-0008). A level air dash walks too once it has touched down; before, it swept as if airborne and stopped dead at the first ramp row it met.
- **Into a wall**: an air dash that meets a clingable wall the stick holds toward, while not rising, clings at once instead of grinding out its frames (tech 6).

**Wall.**
- **The cling.**
  - A cling starts only while falling or level, holding toward a clingable wall, and the player faces away from the wall.
  - It slides at 3 u/f for up to 90 frames of time on the wall, then lets go and cannot cling again until a landing, a wall-jump or a pogo.
- **Fresh and later clings.**
  - The first cling since a landing, a wall-jump or a pogo restores the air jump and air dash (BUILD.md "resets on wall-cling") and starts a fresh slide.
  - Later clings restore nothing and continue the slide where it stopped. That covers re-gripping after letting go, and the cling at the top of each kick of a climb.
  - Every cling clears the ground dash cooldown.
- **Leaving a cling.**
  - Holding down never clings, a d-pad diagonal included: pressing down drops off at once, and no cling starts while down is held (BUILD.md "Pressing down drops instantly"). A down-diagonal into a wall used to cling for a tick, flipping the sprite twice and restoring the air jump and dash (fourth review, L3; `down_diagonal_toward_wall_never_clings`).
  - A jump pressed before a cling fires on the cling frame, as one pressed before landing does.
  - Letting go without jumping (stick released or pushed away, or sliding off the wall's end) starts 6 frames of **wall coyote time** (`wall_coyote_frames`), in which a jump still pushes off that wall. It is counted as the ground's coyote time is: a jump on the 6th frame after letting go still pushes off, one on the 7th is the air jump (`wall_coyote_frame6`, `wall_coyote_expires`). It used to run out a frame early.
- **Wall-jump or wall-kick**: holding away is a wall-jump (5-frame lock); anything else is a kick (1-frame lock).
  - A wall-jump restores the air jump and air dash (BUILD.md "Resets double jump and air dash").
  - A kick restores nothing: its row lists no reset.
  - A kick is a fixed kick, like the pogo's bounce: no early-release cut and no apex hang. Each kick rises the same height however the button is pressed.
- **Reach.** A wall-jump or kick needs one of:
  - a cling;
  - the wall coyote time;
  - a fall within 3 u of a wall (`wall_jump_reach_u`; the reach covers a player who falls past a wall without holding toward it, the coyote time a player who lets go of one).

  A press while rising beside a wall is an air jump instead.
- **A press on the tick the player reaches a wall** is a press on the wall (`PlayerWall.met`): the tick whose move clings to a clingable wall the stick holds toward, a fall's (`Player._after_move`) or an air dash's (`Player._move_dash`). The cling starts after the tick's move, so such presses used to be read with air rules (fourth review, M5):
  - a jump spent the air jump a tick before it could kick; now it waits in the buffer for the cling this very tick and kicks off it (`jump_on_cling_frame_kicks`);
  - a dash went into the wall, moved nowhere and spent the air dash; now it goes away from the wall, as from a cling (`dash_on_cling_frame_goes_away`);
  - a side strike turned Ash toward the wall and put its box inside the wall for 14 frames; now it goes away (`strike_on_cling_frame_goes_away`);
  - a throw went into the wall and spent the cooldown; now it goes away (`toss_on_cling_frame_goes_away`).
  - The tick is found by trying the move on a copy of the body with the tick's own speeds and gravity (`Player.air_velocity_ahead` puts back the jump state the gravity reads), so it is exactly the tick the cling comes. The fourth review's version counted a wall within the 3 u reach plus the tick's travel, which said yes a tick early (11.5 u from the wall at run speed, the move leaving 2.5 u) and on a landing tick beside a short step: a dash went 180 u the wrong way, a kindle-dash missed the wax, an up-left dash onto a step went up-right, a strike toward the step faced the open floor, and a jump waited a frame and fired as a kick (fifth review, M4 and L6; `dash_two_ticks_before_wall_goes_toward_it`, `tech12_kindle_dash_into_wax_from_air`, `dash_on_landing_tick_beside_step`, `strike_on_landing_tick_beside_step`, `jump_two_ticks_before_wall_is_not_late`). Asking it changes nothing (`test_wall_prediction.gd` plays the wall, dash and jump fixtures and checks the state hash around every question).
  - An air dash meeting the wall is covered too: a jump pressed on that tick (dash frames 5 to 9) used to fire an air dash-jump up the face with the air jump left, and kick with it spent; now it waits for the cling and kicks either way (fifth review, M5; `jump_on_dash_cling_frame_kicks`, `_air_jump_spent`).
  - With the Kindle Votive a dash toward a wax wall goes into it, from a cling to the wax too, and burns through (tech 12: "dash through a wax wall ... to ignite it"); without the Votive wax is a wall like any other (`tech12_kindle_dash_from_wax_cling_burns_through`, `tech12_dash_from_wax_cling_without_kindle_goes_away`).
- **Climbing** (tech 5): a climb is one full kick per apex. Mashing jump buffers each press into the next apex's cling, and kicks restore no air jump to spend between them. So mashing and timed kicks climb at the same rate, about 176 u every 24 frames, and mashing still climbs (`tech05_wall_kick_climb`, `tech05_wall_kick_mash`).
- **Ledge-grab**: holding toward a wall in the air raises the corner correction from 8 u to 10 u, measured from the feet (ADR-0008, director question).

**Strikes.**
- **Jumping.** A strike blocks the jump unless:
  - its row lists a jump cancel (Side 1: "jump any frame"); or
  - it is the air-only down-strike and the player is on the ground, so a missed pogo never locks the jump after landing.

  The up-strike's "air attack any frame" is a cancel into another air strike, not a jump, and not into itself: an up press every 3 frames restarted it each time, a fresh box every third frame (fourth review, M6; `up_strike_never_cancels_itself`).
- **Landing** never interrupts a strike (tech 8).
- **Turning.** Side strikes turn the player instantly and do not slow a run (BUILD.md section 6). On a wall they go away from it: the stick holds toward the wall to keep the cling.
- **Side 3's startup.** BUILD.md's Taper table gives the finisher 3 frames of startup, and its feel rules say "no move has more than 2 frames of startup unless it has armor". The table stands, and the finisher gets armor through its startup: a hit on those frames does not interrupt it (task 6, which adds hits to the player, builds it; third review, L7). Built in the task 6 reviews: `AttackDef.armor_frames` (3 on side 3 and the Charged strike), docs/adr/0013, The player hit. Spells (section 6's spell table, 3 to 6 frames) are not moves in that rule's sense: each is a deliberate cast with its own startup in its own table.

**Pogo.**
- The down-strike's 36 x 24 u box is live on its frames 3 to 9.
- **The bounce.**
  - It replaces the vertical speed with the bounce velocity: a fixed bounce, with no apex hang and no early-release cut.
  - It keeps the horizontal speed, restores the air jump and the air dash, and makes the next cling fresh.
  - It ends the strike at once ("anything on bounce").
- The next down-strike may start on frame 6 after the bounce (BUILD.md). A press on frames 1 to 5 waits in the buffer, and keeps the direction it was pressed with.
- **A bounce and a hazard on the same frame** is a bounce: the pogo is checked first, and the hazard only if there was no bounce. The pogo box reaching the spikes as the hurtbox does would otherwise send the player back to safe ground in the middle of the tech the spikes teach (`pogo_beats_hazard_same_frame`; benefit of the doubt, BUILD.md section 5).
- The bounce event is placed at the centre of the pogo box, where it hit.
- **The bounce answers a jump pressed during the down-strike.** The strike blocks the jump, so a press in its frames waits in the buffer; it used to fire on the tick after the bounce as the air jump the bounce had just restored, cutting the bounce to half its height (a tap's early release) and spending the jump. The bounce now uses that press up (`pogo_bounce_uses_up_jump_pressed_in_strike`, against `pogo_bounce_control`; third review, M2). A press after the bounce jumps as usual.
- **Cadence.** The fastest chain, pogo, dash, pogo, can skim at a bounce every 8 to 11 frames. BUILD.md's note gives "about 4 bounces per second at its fastest", which a 15-frame rhythm meets (`tech04_pogo_dash_reset`). A later window (frame 14) was tried and reverted: it did not stop the skim, and it blocked pogo, down-dash, pogo (feel log 2026-10-17-pogo-chain-window, director question).

**Reverse pogo** (tech 9). "Pogo while moving backward" is a pogo while moving the opposite way to the way Ash faces.
- Facing turns on the input frame, and in the air the speed is air control's, so Ash can turn to face an enemy while still flying past it. The bounce keeps that speed (BUILD.md "Horizontal speed fully preserved"), so Ash sails over and lands behind the enemy facing its back (`tech09_reverse_pogo`; struck without turning, `tech09_control_forward_pogo` lands facing away).
- Turning back bleeds the forward speed at air control's rate (BUILD.md "0 to max in 8 f"), so from a run (9 u/f) at most 36 u of forward travel is left: not enough to clear an enemy-sized (32 u) target when the strike catches its head from in front, as a hop struck early does (`zone1_09_control_hop_lands_in_front`).
- **Corrected (room 9 review).** The earlier claim here, that a search found no reverse pogo from a run, was wrong, and so was "it takes a dash's speed". A running jump clears a 64 u enemy by 21 u (the jump's apex is 85 u), so Ash can already be over its head when the back-and-down strike goes out; the strike then catches the head from above with 7.9 u/f of forward speed left, the bounce keeps it (BUILD.md "Horizontal speed fully preserved") and Ash lands behind the enemy facing it (`zone1_09_reverse_pogo_without_dash`: jump on 108 from x 1032, strike on 115). That is a legitimate reverse pogo, not a bug: the speed at the strike is air control's, the bounce is the doc's. It is the narrow way, 2 strike ticks for a given jump tick (jump 108: 115 and 116), where the dash route is the forgiving one.
- The dash route: a short-hop dash-jump at the enemy, with the strike on any of 6 ticks, dash+9 to dash+14 (`zone1_09_reverse_pogo_strike_88` and `_93` are its edges, with the dash on 79 and the jump on 85; the same window as `tech09_reverse_pogo`). The dash-jump holds 20 u/f until the turn, so the strike can go out 35 u before the guard's head (tick 91, x 1021) and the bounce at 16.6 u/f still carries Ash far past the block. Zone 1's tech 9 room gives the player room to dash at the guard (`zone1/09_reverse_pogo`, 294 u of runway); the dash is the way the room is built for, not a requirement.
- **Taught, not gated (decision, room 9 review).** The shielded enemy's shield is what makes the tech necessary, and Phase 1 has no combat that blocks a strike. With a 64 u stand-in, every jump that can strike its head also clears it, so no geometry and no door can require the tech or ask which way Ash faces: a run and one jump crosses the room (`zone1_09_note_plain_jump_crosses`). Room 9 therefore teaches the tech and does not gate it; the gate arrives with the shielded enemy (Phase 2, zone 1), when the room and that fixture change. BUILD.md section 5 tech 9 says so.
- The first fixture for this tech drifted over a bell facing the way it moved, so it never moved backward (the second review).

**Hazards.**
- A hazard (spikes, or a pit) touching the hurtbox sends the player back to the last safe ground with 20 frames of invulnerability. Safe ground is a flat, non-one-way floor with no hazard within a tile, the same flat floor running under the whole collider and 16 u beyond it on each side (`safe_ground_margin_u` in `kit.tres`, not in BUILD.md); until the player first stands on safe ground, the spawn point is used. Standing there again restores the airtime's resources.
  - The margin keeps a respawn off a ledge's lip: safe ground used to be any flat floor the box touched, so walking off an edge into spikes respawned Ash with the collider overhanging the edge by 19 u, and the stick that walked off carried Ash straight back in on the next tick, a loop every 23 frames (third review, M3; `hazard_respawn_stays_off_the_lip`). A platform narrower than 52 u is never safe ground: a respawn goes back to the last one wide enough.
  - An ember thrown before the hazard goes out with the send-back (the throw's cooldown runs on). Left out, a teleport to it undid the send-back with the air jump and dash the respawn had restored, and crossed tech 2's chasm with no dash-jump (third review, H1; `toss_ember_goes_out_on_hazard_respawn`, `tech02_respawn_does_not_keep_the_ember`).
  - A stick held through the send-back is ignored until it is let go or turned (`Player.stick_hold_x`). The margin alone only stretched the loop: holding right walked Ash back off the edge 8 frames after the respawn, inside the invulnerability, and beside floor spikes the send-back came every 20 frames (fourth review, M1; `hazard_loop_stick_held_pit`, `_floor_spikes`).
  - Nothing of the wall or a turn carries through it either: a wall-jump's direction lock used to keep Ash facing the old way for two frames after the send-back (fifth review, L7; `turn_after_hazard_in_wall_jump_lock`).
  - A pit (`~`, ADR-0008 decision 1) is a hazard filling its whole tile, with nothing to pogo off.
  - Every press still buffered is used up by the send-back, so a jump or dash pressed over the pit never fires at the safe ground (fourth review, M2; `hazard_respawn_drops_stale_jump`, `_dash`).
  - Safe ground must last and have room to stand: never on a box the game can take away (wax, `SolidBox.fragile`), whose burning made an endless send-back to open air over spikes (M3; `safe_ground_never_on_wax`), and never where a standing body does not fit, such as a crawl gap a standing Ash was put back into, 12 u into its ceiling (M4; `safe_ground_never_in_crawl_gap`).
- The hurtbox is the collider inset 3 u at the sides, 8 u at the top and 2 u at the feet (CLAUDE.md rule 8).
- The dash's invulnerable frames also ignore hazards.

**Ember Toss** (BUILD.md section 6).
- **The throw.**
  - A press throws the ember in the stick's 8-way direction on the frame it was pressed (facing when neutral). From a wall cling it goes away from the wall, as side strikes and dashes do; thrown into the wall, it stopped 9 u from the player and spent the cooldown (`tech11_toss_from_cling_goes_away`).
  - Thrown on the tick the player reaches a wall it goes away from it too (see Wall).
  - So are the Charged strike and Kindle (ADR-0013): let go of or cast on the tick the fall clings, they go away from the wall (`PlayerStrikes._try_charged`, `PlayerSpells._cast`; movement review 6, M3).
  - It is out at the player's centre on the throw's frame 4 and flies 600 u/s until a wall, a floor or a ceiling, or for 40 frames, then waits 120 frames. "3 f startup" counts as the Taper's does: frames 1 to 3 wind up, so the ember appeared a frame early until the fourth review (L2).
  - A press during the 3-frame startup does nothing (it is used up), so a double press cannot teleport the moment the ember appears.
- **The teleport.**
  - A press while the ember is out moves the body to the nearest spot around the ember where it fits, within 24 u (`toss_fit_reach_u`).
  - The search tries straight-line offsets first: an ember on a wall needs half the body's width (10 u), one on a floor or ceiling half its height (22 u). Then it tries every other offset in the square, nearest first, in a fixed order.
  - It tries the standing body first and then the crouched one, so an ember in a 32 u gap teleports the player in crouched (`tech11_teleport_crouches_into_low_gap`); it used to fail silently there.
  - The search marks, row by row, which offsets are blocked (one bit mask per row, from the tiles and solids near the ember) and takes the first free one in the same order: the same answer as trying every offset, which `test_the_masked_fit_search_finds_what_trying_every_offset_finds` checks, but a failed teleport costs 0.37 ms where trying all 2401 offsets cost 5.07 ms against the 3.0 ms tick budget. The offsets' order is built once per reach and cached.
  - The player gets 6 frames of invulnerability. Arriving on the ground is a landing.
- The 12 s cooldown starts at the throw. The 40, 120 and 24 are not in BUILD.md and are flagged for the director.
- A hazard respawn puts the ember out (see Hazards); the cooldown runs on.

**Kindle-dash** (tech 12, with the Kindle Votive): wax solids in the dash's path ignite and stop blocking, and passing through restores the air jump (BUILD.md "dash-through"). The path is the box the dash sweeps this tick, reaching one sub-pixel further only on the sides it moves toward: wax touched at the start of a dash into it ignites, wax the dash leaves behind does not (`tech12_kindle_dash_away_does_not_ignite`).

**Tech 2's gap.** "A gap exactly one dash-jump wide" must not be crossable without a dash-jump. A jump on frames 5 to 9 of any dash is a dash-jump, the air dash's included (see Dash). The first version of this rule searched only routes that start with a run and set the gap at 1152 u. The second review found a route it missed: a ground dash runs flat past the edge (a ground dash does not fall), and a coyote jump on one of its carry-over frames keeps the carry's 10 u/f for the whole airtime. The third found that the routes then labelled "without a dash-jump" fired their air jump on the air dash's frame 9, an air dash-jump, and that the Ember Toss (0 Flame: BUILD.md section 6) carries a crossing further: no Flame gate keeps it out of the room. `tools/replay/gap_reach.gd` searches every route, coarse and then tick by tick around the best plan, and a toss route from its route's best plan, the throw, the teleport, the air jump and the air dash in turn until nothing improves; on a chasm with no far side. The reach is how far past the edge the body's centre gets with the feet no lower than the ledge-grab (10 u) below the ledge's height: meeting the far face there, the grab lifts the body on (fourth review, H1). The test chasm's floor is a pit 192 u below the ledges and its far face is smooth above it, so nothing in it can be clung to, pogoed off or climbed toward the far side, nothing can fall far and come back up on a teleport, and only a route that reaches the ledge from the air crosses. (The fourth review's chasm was 1504 u deep with no hazard: the fifth found a toss route that threw the ember up-right late, let the body fall over 900 u while the ember flew to the ceiling, then teleported up to it and glided onto the far ledge, 119 u past its face. The search ran on a room with spikes 192 u down, which cut that plan short: the measuring room was not the fixtures' room (H1). Both now have the same pit, and `tests/unit/tools/test_gap_reach_room.gd` keeps `test/longchasm`, the chasm's near half with no far side, the same as `test/chasm`.)

| Route | Reach past the edge |
| --- | --- |
| No dash-jump of any kind: a run, a full jump at the last coyote frame, the air jump, the air dash | 1201 u |
| ... and one Ember Toss (straight ahead, after the air dash; the teleport 43 ticks later) | 1488 u |
| No dash-jump of any kind: a ground dash, a carry-frame jump, the air jump, the air dash | 1333 u |
| ... and one Ember Toss (up-right, after the air dash; the teleport 29 ticks later, the tick before the fall would reach the pit) | 1592 u |
| A plain ground dash-jump, nothing else | 1029 u |
| A ground dash, a carry-frame jump, the air dash and an air dash-jump (the air jump on its frame 9; third review, before the grab was counted) | 1539 u |
| A ground dash-jump and its air jump | up to 1809 u |
| A ground dash-jump, its air jump and the air dash | up to 2243 u |

The third review's random multi-start search and a perturbation search around the toss route's best plan found nothing farther than that route (1590 u then, before the grab was counted). A gap the plain dash-jump alone clears is crossed by any route with the air jump, the air dash or the toss, so the dash-jump cannot be needed on its own. The test chasm is 1664 u (52 tiles): a crossing needs a reach past 1654 u (the gap less half the body's width), 62 u more than the farthest route without a dash-jump, the toss included (`tech02_control_carry_toss`, `tech02_control_carry_jump` and `tech02_control_all_resources` fall; `tech02_control_pogo_floor` and `tech02_control_toss_wall_kick` find nothing in the chasm to use; `tech02_control_toss_fall_teleport`, the fifth review's route, falls into the pit before its teleport). A ground dash-jump clears it with its air jump alone in a 15-tick window from dash frame 9 and a 2-tick window from frame 5 (`tech02_dash_jump_frame9`, `_frame5`), and with the air dash as well from anywhere in a broad region: every air jump and air dash within 6 ticks of `tech02_dash_jump_frame5_air_dash`'s lands. At 1600 u (the second review's width) the toss route fell short of crossing by less than a unit. Task 7's zone-1 room 7 must keep that width, or close the toss's or the air dash's extra reach some other way and be searched again.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Air control while crouched in the air | Mashing jump in any low gap crawls through it at run speed, which makes "Crouch: cannot move" meaningless there and tech 10's crouch-dash unnecessary |
| Wall-jump from any wall contact | Mashing climbs a single wall at jump speed, which the wall-kick tech (a deliberate apex rhythm) is meant to teach |
| Kicks restore the air jump, and so does every cling | Mashing alternates kicks and air jumps and climbs faster than timed kicks (the first review measured 9.7 u/f against 7.5) |
| Kicks with the jump's early-release cut | Short taps cut each kick and kick again sooner: tapping climbs fastest, and holding the button, the obvious way to kick, is the slowest |
| Keep the down-strike uncancellable (the Taper row alone) | A mistimed pogo over spikes would be a guaranteed hit with no input that helps; section 5's general cancel rule says otherwise |
| Air momentum decays to run speed | The dash-jump would lose its speed mid-jump, against "keeps 100% dash speed"; pogo chains would slow |
| Keep speed above run speed through a landing | A buffered landing jump carries a dash-jump's 20 u/f forever (the first review's bunny-hop): the fastest movement in the game would be free |
| The ground turnaround in the air | A dash-jump flips from 20 u/f forward to 5.4 u/f back in one frame, against "Air control: 0 to max in 8 f" |
| Chain window at frame 14 | Did not change the skim's height (only its cadence); blocked pogo, down-dash, pogo; dropped presses on bounce frames 1 to 5; narrows a cancel window (CLAUDE.md prefers wider ones) |
| Teleport nudges only vertically, up to 16 u | An ember stopped on a wall or a floor (the usual case) fails silently |

## Feel reason

Every row here follows BUILD.md's feel rules: never a dead frame, no input waits for an animation, buffers that remember the latest press, and landings with no lag. Where the tables conflict, the checklist's player-facing promise wins: 3 tiles between tap and full jump, a wall climbed "without feeling stuck", and a dash that never eats the next attack.

## Consequences

- Every row and tech has a fixture under `tests/replay/movement/` and `tests/replay/tech/`, including one per finding of the first, second and third task-3 reviews.
- The contact sheet draws no strike or pogo boxes (third review, L8): the F3 overlay (task 5) draws them, and `film.gd --overlay on` films them.
- `tests/unit/core/fsm/test_player_state.gd` checks that every field of the player and the ember toss is in the state hash.
- The fourth review's fixes moved 30 committed fixtures' paths (each fixture played tick by tick against the code before them), every one by a rule above and every one still meeting its expectations: the ember out on the throw's frame 4, so a teleport lands up to 10 u short of where it did (five tech-11 and fourteen camera teleport fixtures; 25 u in `cam_fall_toss_teleport`); a stick held through a hazard send-back ignored (`cam_hazard`, and the three spike-chasm fixtures, now on `spike_chasm.room`); a jump pressed on the tick of reaching a wall kicking off it on the cling instead of spending the air jump (`cam_shaft_climb`, `cam_noceiling_climb`: the air jump comes later in each climb); and tech 2's controls falling into the deeper chasm. `Simulation.VERSION` went to 4 with the re-bless (ADR-0006): the state hash also gained the stick hold and the dash's queued attack.
- The fifth review's fixes moved only tech 2's six chasm fixtures' paths (each fixture played tick by tick against the code before them): their falls now end in the pit and the send-back, and `tech02_control_carry_toss` and `_toss_wall_kick` take the search's new best plan. Every other fixture's path is unchanged; the state hash gained the queued press's countdown, so `Simulation.VERSION` went to 5 with the re-bless.
- Director questions:
  - the ledge-grab measurement;
  - the pogo cadence: a faster pogo-dash skim than "about 4 a second";
  - the ember's flight, linger and fit-reach values;
  - the low-gap rule;
  - the wall coyote time;
  - a spent wall still kicks: once the 90 f slide is used up the player cannot cling, but a fall within the 3 u reach still kicks off the wall at every apex, so the slide budget does not limit a kick climb (`wall_spent_still_kicks`);
  - the slide budget carries over from one wall to the opposite one when the player kicks across rather than wall-jumping (`wall_cling_budget_carries_to_other_wall`);
  - the dash's invulnerable frames ignore spikes, so a strip of spikes up to 140 u wide can be dashed across;
  - a coyote dash is a ground dash and ignores the stick's vertical direction;
  - side 2, side 3 and the up-strike have no jump cancel (BUILD.md section 6), so a jump pressed in their first frames ages out of its 8-frame buffer before they end (14 to 20 frames) and is lost; a buffer that waits for the strike to end is the alternative. The same holds for a strike pressed during a strike with no cancel into it: in the air, a down-strike pressed on side 1's frame 3 waits for side 1's 14 frames, outlives its buffer and never comes out (third review, L6). Side 1 into up or down, and side 2 or 3 into anything off the chain, behave this way;
  - the reverse pogo from a run needs the strike over the target's head (a 2-tick window); the dash route's window is 6 ticks. Neither is required in Phase 1, see "Taught, not gated" under Reverse pogo;
  - the jump: 900 u/s with BUILD.md's gravity rises in 0.375 s; the reviewer suggests an A/B against 1020 u/s with gravity about 2956 u/s^2, which keeps the 176 u height and rises in 0.35 s;
  - a jump tapped on the tick after a bounce is the air jump, released at once: the bounce's rise is cut to about half, and the air jump spent (fourth review, L4). A press on the bounce frame or before is used up by the bounce; one after it jumps, as an air jump always does. A tap one tick late reads as wanting a higher bounce; the alternative is a few ticks after a bounce in which a jump press adds to the bounce instead of cutting it;
  - after a hazard send-back, a stick held through it is ignored until let go or turned: no loop back into the hazard, at the cost of standing still when the player meant to walk on.
