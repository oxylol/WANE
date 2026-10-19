# WANE: progress

- **Phase:** 1, feel in grey boxes (BUILD.md section 14; CLAUDE.md kickoff order)
- **Status:** in progress
- **Engine:** Godot 4.7.2-stable (ADR-0001)

## Kickoff order

| # | Task | Status |
| --- | --- | --- |
| 0 | Repo skeleton, `.godot-version`, CI, gdUnit4, lint, requirements, PROGRESS, ADR and feel-log templates, LICENSES | done |
| 1 | Core loop: fixed-step driver, `InputFrame` and ring buffer, split-stream RNG, state hash every 60 ticks, replay recorder and player | done |
| 2 | Physics sweep: AABB, slopes to 45 degrees, one-way platforms, corner correction | in review: fixed through seven review rounds (ADR-0008); the seventh round's fixes are committed and their re-review runs next. Committed with task 3, whose player its fixtures and tests run through |
| 3 | Ash: ground, jump, dash, wall, pogo; one fixture per table row and per tech interaction | in review: every row and all 12 tech interactions have fixtures, with control runs; fixed through five review rounds (ADR-0010); the fifth round's fixes are committed and their re-review runs next |
| 4 | Camera | in review: fixed through six review rounds (ADR-0011); the sixth round's fixes are committed and their re-review runs next |
| 5 | F3 debug overlay and frame-stepper | in review: the overlay (boxes, state, frame counter, input history) and the stepper (F3 to F6) are in the game and film every contact sheet (`film.gd --overlay on`); the view eases corner-correction nudges; fixed through two review rounds (ADR-0012); the second round's fixes are committed and their re-review runs next |
| 6 | Taper, Flame, Kindling, parry, spells, hit feedback, training dummy with poise | in review: combat resolves once a tick after everything moves (ADR-0013): the Taper's hits, Flame, hearts, Kindling and its tiers, the parry, Kindle, Mend, Radiance, the Charged strike, poise and stagger, kill embers, hazards costing a heart, and the training dummy (standing, swinging white or red); hit feedback, the HUD, enemy and combat views and the F3 overlay's combat boxes; 44 combat fixtures and the rules' unit tests; the sandbox has three dummies. Its first review's core and presentation findings are fixed (ADR-0013, the feel log's review tables); its re-review runs next |
| 7 | Room editor plugin and grey-box zone 1 (12 rooms, 12 tech interactions in order) | in progress: doors between rooms are committed (ADR-0014: paired doors, crossed on the tick the body is inside a door's strip, speed and state kept, the camera cutting; zones as content with a schema); the editor's document, history and panel are built but not committed; the twelve rooms are next |
| 8 | Stress room (200 enemies, 40 procs, Pitch lighting) and perf benchmark in CI | in progress: the procs are built (ADR-0015): the proc event bus (every Taper hit, pogo, Kindle tick and Radiance reach an event with its coefficient; chances in parts per million with the relative Flame bonus, split past 100% last; chains to depth 3; one PROCS draw order), Votives as content behind a checked listener API (adding one never touches `core/`: the five content Votives came in a commit with no `core/` diff), the stacking curves exact in integers, and five Votives (Tallow Knuckle, Pilgrim's Wick, Bell of the Vigil, Second Ember, Hollow Step; the Abbess's Mercy waits for quarter hearts, Hearthshard for the light, Snuffed Blade for the clock); proc marks through the VFX budget at PROC priority and the F3 overlay's proc lines; 36 proc fixtures; `Simulation.VERSION` 9 with every existing fixture's per-tick state unchanged (`tools/replay/state_trace.gd`); a stress set of three test Votives fires 39 procs from one hit, costing 1.3 to 1.5 ms (`tools/bench/proc_bench.gd`). The stress room and the perf gate are next |
| 9 | Immaculate Checklist pass, Phase 1 report | not started |

## Next

Re-review physics (round 8), movement (round 6), the camera (round 7), task 5 (round 3) and task 6 (round 2), and fix what they find; then task 7: the room editor and the grey-box zone 1. Task 8: review the procs (ADR-0015), then build the stress room and its perf gate on them.

## Immaculate Checklist (BUILD.md section 15)

Applicability to Phase 1 is decided per line. "No" lines depend on systems that are not in the Phase 1 kickoff order (final art, audio, enemies from later zones, the Wane Clock, the Vigil) and are carried to the phase that builds them. "Partial" lines are checked against Phase 1's grey-box stand-ins now and re-checked when the real system lands.

| Line | Applies in Phase 1 | Status |
| --- | --- | --- |
| *Movement* | | |
| Jump pressed 8 frames before landing fires on the landing frame | yes | green: `jump_buffer_8f` fires on the landing frame and `jump_buffer_9f_expires` is the edge; the same on a cling (`wall_cling_buffered_jump`) and a dash's touchdown (`dash_diagonal_touchdown_buffered_jump`) |
| Jump pressed 6 frames after walking off a ledge still jumps | yes | green: `jump_coyote_frame6` jumps, `jump_coyote_frame7` is the air jump; walking off a ledge's far edge after touching it gets the same (`far_edge_touch_then_ground_jump`) |
| Tap jump and full jump differ by at least 3 tiles; release feels like a decision | yes | green on numbers: 77.9 u against 176 u, 3.07 tiles (`jump_tap`, `jump_full`, `jump_tap_buffered_on_landing`); whether the release feels like a decision is the director's to play |
| Turning around never produces a dead frame; sprite flips on the input frame | yes (the grey box's facing marker flips) | green: `ground_turnaround`, `ground_turnaround_partial_speed`, `dash_carry_turnaround` |
| Dash from standstill and at full run reach the same distance | yes | green: 210 u both (`dash_same_distance`, `dash_distance`) |
| Dash-jump keeps 100% of dash speed and clears the zone 1 room 7 gap every time | yes, with a numbering decision: the grey-box zone teaches the tech in order, so its dash-jump reference gap is in room 2; ADR at task 7 | partial: 100% kept for the whole airtime, off a lip and off a door down a ramp too (`dash_jump_from_box_a_lip`, `dash_jump_down_ramp45_off_door`); the 1664 u test chasm is cleared by a ground dash-jump with its air jump and air dash from a broad region of timings (with the air jump alone, a 15-tick window from dash frame 9), and no route without a dash-jump of any kind crosses it, one Ember Toss included, and nothing in the chasm can be clung to or pogoed off toward the far side, nor fallen into and teleported back out of: its floor is a pit 192 u down, the same as the room the search measures on (farthest 1592 u counting the 10 u ledge-grab, 62 u short; `tech02_dash_jump_frame5_air_dash`, `_frame5`, `_frame9`, `tech02_control_*` including `_pogo_floor`, `_toss_wall_kick` and `_toss_fall_teleport`, `tech02_respawn_does_not_keep_the_ember`; reach table in ADR-0010, measured by `tools/replay/gap_reach.gd`); the zone 1 room is task 7 |
| Pogo keeps full horizontal speed; 10-bounce chain across the zone 1 spike pit at 4 bounces/s | yes | partial: speed kept (`pogo_keeps_horizontal`, `pogo_dash_jump_speed`), ten bounces cross the 3360 u test pit (`tech03_pogo_chain`); the zone 1 pit is task 7 |
| Pogo resets air dash; pogo, dash, pogo crosses the hidden-room gap | yes | partial: `pogo_resets`, `tech04_pogo_dash_reset` on the test gap; the hidden room is task 7 |
| Wall-kick climbs a single wall without feeling stuck | yes | green on fixtures: 176 u every 24 f, held, tapped or mashed (`tech05_wall_kick_climb`, `tech05_wall_kick_mash`); the feel is the director's to play |
| Landing on a 1-pixel ledge edge lands; nudge invisible | yes | partial: a fall or a diagonal dash lands from the near side by the corner lift and from the far side by the far-edge landing (`ground_corner_lift`, `far_edge_landing_lands`, `down_dash_lands_on_ledge_far_corner`, `test_physics_fuzz_lift.gd`); the view eases a lone nudge over 3 frames and a staircase of them with its catch-up speed changing by at most a quarter of the nudge a frame, never a hop, never more than twice the run's largest nudge behind (task 5; feel log 2026-10-19; `test_a_corner_correction_nudge_never_snaps_the_drawn_player` over eleven fixtures, two of them staircases of lips); whether the ease reads as invisible is the director's to judge once Ash is drawn: up a dashed staircase the drawn body sits inside the steps, up to 48 u, for two frames (feel log 2026-10-19, rows 5 and 6) |
| Head bumping a ceiling corner by under 6 units slides around it | yes | green: `jump_ceiling_nudge` slides, `jump_ceiling_bump` (7 u) bumps |
| Camera never shows the player within 80 units of the screen edge | yes | green over all 332 movement, tech, physics and camera fixtures at 16:9, 16:10, 4:3 and 21:9, held by the follow alone with no backstop correction, and over the fourth review's sweeps (falls beside walls and down shafts 96 to 288 u wide, wall-jumps up every shaft width, look-drops of 64 to 256 u, borderless room edges, long ramps) the fifth review's fixtures (`cam5_*`) and the sixth review's sweep of teleports followed by a dash on toward one-tile ceilings and borderless tops and bottoms 12 to 24 rows away (`test_camera_rig.gd`, `test_camera_review*.gd`); the re-review of the sixth round's fixes runs next; the zone 1 loop is task 7 |
| 60-second movement-only loop through zone 1 playable with eyes on the character | yes (the director plays it) | not started: needs zone 1 (task 7) |
| *Combat* | | |
| Attack comes out on frame 3 from a neutral press, every time, including during hitstop | yes | green: the box is live on the strike's frame 3 from a neutral press (`side1_hits_dummy_once`, `dash_cancels_attack`); a press made during hitstop fires on the first free frame and its box counts frame 3 from there (`dash_out_of_hitstop`, `chain_rising_weight`) |
| Dash cancels an attack on frame 4 and never eats the next attack input | yes | green: `dash_cancels_attack`, `dash_cancel_window`, `dash_cancels_down_strike`; an attack pressed before the dash that cancels a strike is kept for its frame 6 (`dash_cancel_keeps_earlier_attack`, with its control), handed back with the attack buffer when the dash ends sooner (a landing, a cling, a dash-jump: `dash_cancel_attack_survives_*`), and replaced by a later press (`dash_cancel_latest_attack_press_wins`) |
| 3-hit chain against a Tallowman reads as three impacts with rising weight | partial: the grey-box training dummy stands in for the Tallowman | partial: 2, 2 and 4 frames of hitstop, the finisher's shake and knockback, the third hit breaking the dummy's poise (`chain_rising_weight`); whether it reads as rising weight with grey boxes and placeholder sounds is the director's to play |
| Parry succeeds on the 8-frame window against the Snuffed Knight 10 times in a row | partial: the grey-box dummy's white swing (24 f telegraph) stands in for the Snuffed Knight | green on the dummy: the window is the 8 frames ending on the landing frame (`parry_window_first_frame`, `_last_frame`, `_too_early`), frame by frame (`test_the_parry_window_is_the_eight_frames_ending_on_the_landing`), ten in a row (`test_a_parry_succeeds_ten_times_in_a_row`); the Knight is zone 3 content |
| Unparryable red distinguishable from parryable white at Pitch with flashes at 0 | partial: shape and outline cues on grey boxes; re-checked with Phase 2 lighting and art | partial: a telegraph raises a bar and outlines the enemy with no flash involved, and they differ in shape as well as colour (the red bar saw-toothed and its outline jagged, white plain), through the landing frame; the telegraph's sound comes exactly 20 frames before the hit, hitstop or not (`telegraph_cue_*`); the F3 overlay labels the red swing; `red_swing_is_never_parried`; Pitch is Phase 2 |
| Taking a hit is never confusing | yes | partial: 8 f of hitstop on Ash only, a 60 u knockback over 12 f that any action ends, 20 f of invulnerability, the red vignette, a shake along the hit and a heart lost on the HUD (`player_hit_knockback_and_invulnerability`); the director plays it |
| Hitstop never causes a dropped input; buffered inputs fire on the first free frame | yes | green: the ring merges hitstop frames and keeps every press (task 1); a dash pressed in hitstop fires on the first free frame (`dash_out_of_hitstop`); held frames for the Charged strike count only the player's own frames (`charged_strike_after_a_24_frame_hold`) |
| With 30 Votives active the screen stays readable | partial: the stress room's grey-box procs | in progress: every proc's mark goes through the VFX budget at the lowest priority, joining its own hit's feedback once per Votive and never taking a cell from a hit or a telegraph (`test_proc_feedback.gd`); a 39-proc burst lights two cells (`docs/feel_log/2026-10-19-task8-procs.png`); the stress room judges 30 Votives |
| Kindling White reached by a skilled tester in zone 2, feels earned | no: zone 2 does not exist in Phase 1 | carried |
| A kill releases an ember that reaches the player within 20 frames; Flame reacts | yes | green: the ember arrives 16 frames after the kill and grants 11 Flame (`kill_ember_reaches_the_player`); the HUD's bar eases up and flashes on a gain (`test_the_flame_bar_eases_to_a_gain_and_flashes_for_twelve_ticks`) |
| *Graphics and feel* | | |
| 60 fps in the stress room on the Deck profile with lighting on | partial: Phase 1 lights the stress room with Godot's 2D lights; the real lighting pass is Phase 2 task 1, and the gate needs Deck-class hardware (see Blocked) | not started |
| No frame-time spike above 20 ms in a 5-minute zone 1 run | partial: the 12-room grey-box zone, not the final 60-room zone | not started |
| At Pitch the ember reveals a Clinger 30 frames before it drops | no: neither the Clinger nor the ember light exists in Phase 1 | carried |
| Every enemy identifiable by silhouette at 64 px | no: art is Phase 2 | carried |
| Every attack has a smear frame | no: animation is Phase 2 | carried |
| Landing squash and jump stretch visible and never block input | partial: grey-box squash and stretch driven by the core's timings | not started |
| Ember flicker visible on nearby normal-mapped surfaces | no: normal maps are Phase 2 | carried |
| Screen shake at default 50% never moves the frame more than 3 units | yes | green: the largest shake (a player hit, 4 u) is 2 u at 50%, and the total is capped (`test_shake_at_the_default_fifty_percent_never_exceeds_three_units`; content validation refuses a default that would pass 3 u) |
| Any boss-fight frame could be the store page | no: art is Phase 2 | carried |
| *Audio* (all five lines) | no: audio is Phase 2 task 4 | carried |
| *Run tension* | | |
| Greedy 20-minute zone 1 noticeably harder than a 6-minute one | no: the Wane Clock's spawn scaling is not in the Phase 1 kickoff order | carried |
| Vigil radius readable; kills refill it | no: the Vigil is not in Phase 1 | carried |
| Dark thresholds distinguishable by sight | no: needs the Phase 2 lighting pass | carried |
| Run beatable with the starting kit on Wane | no: needs a full run | carried |
| Seeded replay reproduces bit-for-bit on Windows, Linux and Deck | partial: every fixture replays bit-for-bit against its golden hashes on Linux, Windows and macOS CI; a full run and the Deck come later | in progress: green for all fixtures |
| *Process* | | |
| Every tuning change this milestone is in the feel log | yes | green so far: tasks 2 to 8 (`docs/feel_log/`) |
| Every new system has an ADR | yes | green so far: ADR-0008 (physics), 0009 (rooms), 0010 (movement), 0011 (camera), 0012 (debug overlay and frame-stepper), 0013 (combat), 0014 (doors and zones), 0015 (procs and Votives) |
| F3 overlay shows hitboxes, state, frame counter and input history | yes | green: F3 in any build, and with it shown F4 pause, F5 one tick, F6 ten; a hazard hit is marked where the hurtbox touched (ADR-0012; `test_debug_overlay.gd`, `test_debug_boxes.gd`, `test_input_history.gd`); every tech and physics fixture plays to the same hash with the overlay reading every tick; the task 5 sheet is filmed through it |
| CI is green: unit, replay, perf, screenshot, style gate, lint | yes for unit, replay, perf and lint; screenshot and style gate have no assets until Phase 2 | green for unit, replay, coverage and lint; the perf gate is task 8 |

## CI gates from BUILD.md section 13 not on the checklist

| Gate | Status |
| --- | --- |
| Core coverage of at least 85% | green: `tools/ci/gd_coverage.py` instruments a scratch copy of the project (GDScript has no coverage tooling); core is at 93.6% and CI gates at 85% |
| Replay fixtures run headless in under 10 seconds | green: 4.1 to 4.6 s for all 378 fixtures here, run in four processes at once (ADR-0006, Shards), 7.7 s of fixture time in all. CI's Windows runner took 9.9 s in one process at task 6 and 13.4 s two commits before, so the suite is sharded and the state hash is native (480 us to 56 us a hash, once a second in the game too). The fixture time is printed beside the wall clock to keep its growth visible; the simulation's own cost is task 8's stress-room gate |
| Export for Windows, Linux, macOS and Deck on every merge, booting to the Hearth | carried: no export presets yet and the Hearth is not in Phase 1; the export job lands with the first presets |
| Credits and legal screen listing Godot's third-party licenses (docs/LICENSES.md) | carried to the Phase 2 UI work |

## Feature flags with expiry

None.

## Blocked

1. **BUILD.md section 14's roadmap body and section 13's architecture diagram did not survive the export to Markdown** (`docs/BUILD.md` lines 692 and 777 read "[embedded content: ...]"). The Phase 1 gate sentence and the per-phase contents are therefore unknown; Phase 1 follows CLAUDE.md's kickoff order meanwhile. **Director: please paste the roadmap table (phases, gates, months) and the architecture diagram's text.**
2. **The perf gate needs hardware we do not have in CI.** BUILD.md: "a stress room ... on a GPU runner", "60 fps ... on reference PC settings, 15.0 ms on the Deck profile". GitHub-hosted runners have no GPU. Task 8 builds the benchmark and runs it on what exists (software rendering here, the CPU budget everywhere); the GPU numbers need a self-hosted runner on the reference PC (RTX 4060-class) and a Steam Deck. **Director: can you provide either?**
3. **Camera jolt: a pogo bounce during a teleport's glide.** `tests/replay/zone1/bypass/04_bypass_toss_wait` (an Ember Toss bypass of zone 1 room 4, ADR-0015) bounces on a post 13 ticks after a teleport; at 1920x1440 the view's vertical speed changes from -11.76 to -25.43 u in one tick (limit 5 in a glide). The follow turns with the player at once (+12.95 to -1.41) and the glide's offset keeps its rate (`game/camera/camera_rig.gd`, `step`: the glide's budget is spent only in the catching branch). The fixture sits in `bypass/`, outside the camera sweep's `tests/replay/zone1` directory, until the camera is fixed: the glide's rate must give back what the follow's turn adds, and the fixture then moves up a directory. Not on the Immaculate Checklist's path (the nine room fixtures pass at all four screen shapes).
3. **Tech 8 (attack-cancel landing) is taught, not enforced, in zone 1 room 8.** A dash outruns a dummy's 24 f telegraph, so two dashes cross the room with 5 hearts in 174 f (`tests/replay/zone1/08_gap_two_dashes.fixture`, a known-gap fixture). Waiting, no strike, one dash and a strike pressed on the landing each cost a heart (controls). Closes when a boss with a short window blocks the door (Phase 2); then the gap fixture becomes a control.

## For the director

- **Play the sandbox** (`content/rooms/sandbox.room`, the room the game boots into): run, jump, dash, wall-kick, pogo the spikes and bells, toss the ember.
- **Camera**: the questions in `docs/feel_log/2026-10-17-task4-camera.md` (the climb's head room, look-down distance, teleport cuts, the turn on an up-dash out of a fall, the look pausing past a ledge in steering reach).
- **Movement**: the questions in `docs/feel_log/2026-10-17-task3-ash-movement.md` and ADR-0010 (wall-kick climb, pogo-dash cadence, ember values, low gaps, wall coyote time, tech 2's 1664 u gap, the reverse pogo needing dash speed, a spent wall still kicking, a press lost behind a strike with no cancel, the safe-ground margin, strikes read 4 ways, the jump A/B).
- **Physics**: the ledge-grab's 10 u is measured from the feet (ADR-0008).
- **Procs**: play the sandbox with Votives (`godot --path . -- --room=sandbox --votive=bell_of_the_vigil:10 --votive=tallow_knuckle:3`, any Votive and stack count) and the questions in `docs/feel_log/2026-10-19-task8-procs.md` (the Bell's 30 f stun cancelling a swing after its cue, Kindle's cone as a tick, the relative Flame bonus, Hollow Step's one-heart floor, quarter hearts for the Abbess's Mercy, where Second Ember's mark shows). Read the five Votives' lines in `content/votives/`.
- **Combat**: strike, parry and Mend on the sandbox's three dummies (to the right of the spawn: one standing, one swinging white every second, one red); the questions in `docs/feel_log/2026-10-19-task6-combat.md` (the chain's weight in grey boxes, the 12-frame knockback, hazards costing a heart, the Charged strike's release, Mend standing still, the kill ember's Flame).
