# WANE: progress

- **Phase:** 1, feel in grey boxes (BUILD.md section 14; CLAUDE.md kickoff order). All ten kickoff tasks are built and merged; the Immaculate Checklist pass is done and its report is drafted below ("Phase 1 report"). **Not claimed signed off:** it waits on the director (play, and the questions under "For the director"), and CI has not yet run on this tree. Phase 2 does not start before that.
- **Status:** Phase 1 report ready for review
- **Engine:** Godot 4.7.2-stable (ADR-0001); `Simulation.VERSION` 12; golden hashes blessed once at 12 (545 fixtures, 805 unit cases, 252 scripts, all passing on this container)

## Kickoff order

| # | Task | Status |
| --- | --- | --- |
| 0 | Repo skeleton, `.godot-version`, CI, gdUnit4, lint, requirements, PROGRESS, ADR and feel-log templates, LICENSES | done |
| 1 | Core loop: fixed-step driver, `InputFrame` and ring buffer, split-stream RNG, state hash every 60 ticks, replay recorder and player | done |
| 2 | Physics sweep: AABB, slopes to 45 degrees, one-way platforms, corner correction | done: green through eight review rounds (ADR-0008; `2026-10-19-physics-r8.md`); the sweep runs in C++ with the GDScript reference kept and tested against it (ADR-0022) |
| 3 | Ash: ground, jump, dash, wall, pogo; one fixture per table row and per tech interaction | done: every row and all 12 tech interactions have fixtures with controls; six movement rounds (ADR-0010); the parry window fix and the dash-jump audit notes after them (`2026-10-20-parry-window-ticks.md`) |
| 4 | Camera | done: seven review rounds and the glide-jolt fix (ADR-0011); no tuned number changed after round 6; the bypass fixture is in the camera sweep |
| 5 | F3 debug overlay and frame-stepper | done: F3 to F6 in any build, films every contact sheet; three review rounds (ADR-0012) |
| 6 | Taper, Flame, Kindling, parry, spells, hit feedback, training dummy with poise | done: ADR-0013; two review rounds; the parry window is exactly the 8 ticks ending on the landing tick, hitstop or not; the one tuned number is `flash_alpha` 1.0 to 0.55 |
| 7 | Room editor plugin and grey-box zone 1 (12 rooms, 12 tech interactions in order) | done: the editor (ADR-0018) and twelve rooms with route and control fixtures (ADR-0016, 0017, 0019); `zone1_loop` is 3461 ticks (57.7 s); room 03 was rebuilt on 2026-10-20 so ten bounces at four a second cross it. Two techs are taught, not gated: 8 and 9 (Blocked 3). The director plays the loop |
| 8 | Stress room (200 enemies, 40 procs, Pitch lighting) and perf benchmark in CI | done on the CPU side (ADR-0015, 0020, 0021, 0022): five Votives and the proc bus; `perf/stress` with 200 dummies; the gated step p99 2.67 ms against 3.0 (best of 3), presentation script p99 4.4 ms against 5.0, a door gate at 2.0 ms; the GPU frame gate is blocked on hardware (Blocked 2) |
| 9 | Immaculate Checklist pass, Phase 1 report | done as a pass: an independent audit of all 83 checklist lines and 30 defects, its fixes landed (room 03, squash and stretch, the parry window, the camera jolt, door lighting, the fixture suite's speed, tunables to content, effects through the VFX budget, docs); the report is below. Per-task re-review sign-offs for the last rounds of tasks 2 to 6 are not recorded; the audit stood in for them, and the director should know that |

## Next

1. The director reads "Phase 1 report", plays the sandbox and `zone1_loop`, and answers "For the director". Phase 2 waits for that.
2. First CI run on this tree: the Windows jobs (10 s fixture budget on the native path) and the blocking `perf-stress` job (margin 11% on the best of 3). If either is red, the suite is made faster or the cells and proc dispatch go native, never a gate lowered.
3. Phase 2 opens with the ink-line and gouache shaders and the lighting pass (CLAUDE.md), which replace the stand-in lighting and let the carried checklist lines be judged.
4. Owed small items: a short ADR for the HUD; before and after rows for the non-feel tunables; re-judge the 30 Votives lit with Phase 2 art.

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
| Dash-jump keeps 100% of dash speed and clears the zone 1 room 7 gap every time | yes, with a numbering decision: the grey-box zone teaches the tech in order, so its dash-jump reference gap is in room 2; ADR at task 7 | green: 100% kept for the whole airtime, off a lip and off a door down a ramp too (`dash_jump_from_box_a_lip`, `dash_jump_down_ramp45_off_door`); the 1664 u test chasm is cleared by a ground dash-jump with its air jump and air dash from a broad region of timings (with the air jump alone, a 15-tick window from dash frame 9), and no route without a dash-jump of any kind crosses it, one Ember Toss included, and nothing in the chasm can be clung to or pogoed off toward the far side, nor fallen into and teleported back out of: its floor is a pit 192 u down, the same as the room the search measures on (farthest 1592 u counting the 10 u ledge-grab, 62 u short; `tech02_dash_jump_frame5_air_dash`, `_frame5`, `_frame9`, `tech02_control_*` including `_pogo_floor`, `_toss_wall_kick` and `_toss_fall_teleport`, `tech02_respawn_does_not_keep_the_ember`; reach table in ADR-0010, measured by `tools/replay/gap_reach.gd`); zone 1's room 02 is the reference gap (ADR-0019 Decision 4; BUILD.md section 15 keeps "room 7" and carries a note); a neutral stick sheds the speed over about 22 frames (ADR-0010; feel log `2026-10-20-parry-window-ticks.md`: the director may want it carried) |
| Pogo keeps full horizontal speed; 10-bounce chain across the zone 1 spike pit at 4 bounces/s | yes | green on the fixtures, the rate is the director's to play: speed kept (`pogo_keeps_horizontal`, `pogo_dash_jump_speed`), ten bounces cross the 3360 u test pit (`tech03_pogo_chain`); the zone 1 pit (room 03) is 3008 u: ten bounces at 4.0 a second, 20 u/f kept, cross it (`zone1_03_pogo_chain_route`) and nine fall 133 u short (`zone1_03_control_nine_bounces`); the plain 4.6-a-second chain needs 11, the slow air-dash chain 6; a slow opening link (an air jump in the opener) lets nine cross (`zone1_03_route_slow_opener`), so the line is "ten are possible", not "fewer than ten fall short" (ADR-0019 Decision 5, rebuilt 2026-10-20) |
| Pogo resets air dash; pogo, dash, pogo crosses the hidden-room gap | yes | green: `pogo_resets`, `tech04_pogo_dash_reset` on the test gap, and zone 1's room 04 alcove route (`tests/replay/zone1`, ADR-0016) |
| Wall-kick climbs a single wall without feeling stuck | yes | green on fixtures: 176 u every 24 f, held, tapped or mashed (`tech05_wall_kick_climb`, `tech05_wall_kick_mash`); the feel is the director's to play |
| Landing on a 1-pixel ledge edge lands; nudge invisible | yes | partial: a fall or a diagonal dash lands from the near side by the corner lift and from the far side by the far-edge landing (`ground_corner_lift`, `far_edge_landing_lands`, `down_dash_lands_on_ledge_far_corner`, `test_physics_fuzz_lift.gd`); the view eases a lone nudge over 3 frames and a staircase of them with its catch-up speed changing by at most a quarter of the nudge a frame, never a hop, never more than twice the run's largest nudge behind (task 5; feel log 2026-10-19; `test_a_corner_correction_nudge_never_snaps_the_drawn_player` over eleven fixtures, two of them staircases of lips); whether the ease reads as invisible is the director's to judge once Ash is drawn: up a dashed staircase the drawn body sits inside the steps, up to 48 u, for two frames (feel log 2026-10-19, rows 5 and 6) |
| Head bumping a ceiling corner by under 6 units slides around it | yes | green: `jump_ceiling_nudge` slides, `jump_ceiling_bump` (7 u) bumps |
| Camera never shows the player within 80 units of the screen edge | yes | green over all movement, tech, physics and camera fixtures at 16:9, 16:10, 4:3 and 21:9, held by the follow alone with no backstop correction, and over the fourth review's sweeps (falls beside walls and down shafts 96 to 288 u wide, wall-jumps up every shaft width, look-drops of 64 to 256 u, borderless room edges, long ramps) the fifth review's fixtures (`cam5_*`) and the sixth review's sweep of teleports followed by a dash on toward one-tile ceilings and borderless tops and bottoms 12 to 24 rows away (`test_camera_rig.gd`, `test_camera_review*.gd`); and over all twelve zone 1 rooms' route fixtures at the four shapes; the glide-jolt fix closed the one open camera finding (the bypass fixture is in the camera sweep) |
| 60-second movement-only loop through zone 1 playable with eyes on the character | yes (the director plays it) | built, awaiting the director: `tests/replay/zone1/zone1_loop.fixture`, 3461 ticks (57.7 s) from room 1's west arrival through all twelve teaching routes and back into room 1. It is the movement loop as the rooms teach it, not a stripped one: it carries the Kindle Votive and presses attack 48 times (the pogo down-strikes and dash-slashes), and takes no hit and loses no heart. The director plays it for the eyes-on-the-character part |
| *Combat* | | |
| Attack comes out on frame 3 from a neutral press, every time, including during hitstop | yes | green: the box is live on the strike's frame 3 from a neutral press (`side1_hits_dummy_once`, `dash_cancels_attack`); a press made during hitstop fires on the first free frame and its box counts frame 3 from there (`dash_out_of_hitstop`, `chain_rising_weight`) |
| Dash cancels an attack on frame 4 and never eats the next attack input | yes | green: `dash_cancels_attack`, `dash_cancel_window`, `dash_cancels_down_strike`; an attack pressed before the dash that cancels a strike is kept for its frame 6 (`dash_cancel_keeps_earlier_attack`, with its control), handed back with the attack buffer when the dash ends sooner (a landing, a cling, a dash-jump: `dash_cancel_attack_survives_*`), and replaced by a later press (`dash_cancel_latest_attack_press_wins`) |
| 3-hit chain against a Tallowman reads as three impacts with rising weight | partial: the grey-box training dummy stands in for the Tallowman | partial: 2, 2 and 4 frames of hitstop, the finisher's shake and knockback, the third hit breaking the dummy's poise (`chain_rising_weight`); whether it reads as rising weight with grey boxes and placeholder sounds is the director's to play |
| Parry succeeds on the 8-frame window against the Snuffed Knight 10 times in a row | partial: the grey-box dummy's white swing (24 f telegraph) stands in for the Snuffed Knight | green on the dummy: the window is the 8 frames ending on the landing frame (`parry_window_first_frame`, `_last_frame`, `_too_early` turned away, and `parry_window_connecting_*` pressing at the dummy, where hitstop once made it 10; docs/adr/0013), frame by frame (`test_the_parry_window_is_the_eight_frames_ending_on_the_landing`), ten in a row (`test_a_parry_succeeds_ten_times_in_a_row`); the Knight is zone 3 content |
| Unparryable red distinguishable from parryable white at Pitch with flashes at 0 | partial: shape and outline cues on grey boxes; re-checked with Phase 2 lighting and art | partial: a telegraph raises a bar and outlines the enemy with no flash involved, and they differ in shape as well as colour (the red bar saw-toothed and its outline jagged, white plain), through the landing frame; the telegraph's sound comes exactly 20 frames before the hit, hitstop or not (`telegraph_cue_*`); the F3 overlay labels the red swing; `red_swing_is_never_parried`; Pitch is Phase 2 |
| Taking a hit is never confusing | yes | partial: 8 f of hitstop on Ash only, a 60 u knockback over 12 f that any action ends, 20 free frames of invulnerability (hits and hazards alike), the red vignette, a shake along the hit and a heart lost on the HUD (`player_hit_knockback_and_invulnerability`); the director plays it |
| Hitstop never causes a dropped input; buffered inputs fire on the first free frame | yes | green: the ring merges hitstop frames and keeps every press (task 1); a dash pressed in hitstop fires on the first free frame (`dash_out_of_hitstop`); held frames for the Charged strike count only the player's own frames (`charged_strike_after_a_24_frame_hold`) |
| With 30 Votives active the screen stays readable | partial: the stress room's grey-box procs, judged lit at Pitch | met for Phase 1 as tested: the stress Votive set (three test Votives, `test_stress_taper_a/b/c`, one 39-proc chain per Taper hit), not 30 distinct Votives (five real ones exist; the rest are Phase 2 content) (`docs/feel_log/2026-10-19-task8-stress.png`: a 45-proc burst, Ash and every white and red telegraph visible; re-judged with Phase 2 art). Every proc's mark goes through the VFX budget at the lowest priority, joining its own hit's feedback once per Votive and never taking a cell from a hit or a telegraph (`test_proc_feedback.gd`); a 39-proc burst lights two cells (`docs/feel_log/2026-10-19-task8-procs.png`); the stress room judges 30 Votives |
| Kindling White reached by a skilled tester in zone 2, feels earned | no: zone 2 does not exist in Phase 1 | carried |
| A kill releases an ember that reaches the player within 20 frames; Flame reacts | yes | green: the ember arrives 16 frames after the kill and grants 11 Flame (`kill_ember_reaches_the_player`); the HUD's bar eases up and flashes on a gain (`test_the_flame_bar_eases_to_a_gain_and_flashes_for_twelve_ticks`) |
| *Graphics and feel* | | |
| 60 fps in the stress room on the Deck profile with lighting on | partial: the Phase 1 stand-in lighting is on in the stress room; the frame gate needs Deck-class hardware (Blocked 2); the CPU budget is gated in CI: presentation script 3.8 to 4.1 ms p99 against 5.0, read directly from the views' own `_process` and `_draw` and the tick capture (met, ADR-0020 Decision 18), simulation step p99 2.67 ms against 3.0 on the spec's workload, least of 3 runs per tick (met, ADR-0020 Decision 17); **single runs read higher and are reported beside the gate, not gated: the step's p99 3.2 to 4.1 ms and the presentation's 5.4 to 6.2 ms in the audit's runs on a shared core, over their 3.0 and 5.0 sub-budgets, with the sum (about 9 to 10 ms) inside 16.0**; whether a single run should be a second gate on the reference PC is the director's question | partial: CPU half measured and met on the gated figure; GPU half blocked |
| No frame-time spike above 20 ms in a 5-minute zone 1 run | partial: the 12-room grey-box zone, not the final 60-room zone | simulation side met: zone 1 loop x6 played as one continuous simulation, 20,766 ticks (5.8 minutes; six passes since room 3 shortened the loop to 3461 ticks, five would be 4.8), worst tick 0.84 ms native, 1.61 GDScript measured before the change (the route holds for three passes; Ash is hurt and dies in the later passes, when Kindling reaches White: ADR-0020 Decision 14); presentation side met in the stress room: worst frame's script time 5.44 ms (gate 20 ms); the stress room's worst simulation tick, 7.64 ms native on the spec's workload (11.2 ms GDScript), is met too (`ci/perf.sh`, ADR-0020 Decision 15; the proc storm's worst, 19.8 ms then, is reported, not gated); a door crossing at Pitch costs 0.08 to 0.38 ms since the occluders are prebuilt per room (it cost 4 to 17 ms before), gated at 2.0 ms by `tools/bench/door_bench.gd` (ADR-0020 Decision 19); the simulation-side loop includes passes where Ash dies at Kindling White (ADR-0020 Decision 14), so three passes are clean play |
| At Pitch the ember reveals a Clinger 30 frames before it drops | no: neither the Clinger nor the ember light exists in Phase 1 | carried |
| Every enemy identifiable by silhouette at 64 px | no: art is Phase 2 | carried |
| Every attack has a smear frame | no: animation is Phase 2 | carried |
| Landing squash and jump stretch visible and never block input | yes (grey box): `PlayerView` squashes 110% wide for 3 ticks on the core's land event (scaled by impact speed) and stretches to 94% wide for 2 ticks at the apex, feet anchored, drawn only; numbers in `content/player_view.tres`; `tests/unit/game/test_player_squash.gd`; sheet `docs/feel_log/2026-10-20-squash-stretch.png`, entry `docs/feel_log/2026-10-20-squash-stretch.md` (the stretch is 2 u narrower on a 20 u box: director to judge) | green for the grey box; the rig, smears and ink line are Phase 2 |
| Ember flicker visible on nearby normal-mapped surfaces | no: normal maps are Phase 2 | carried |
| Screen shake at default 50% never moves the frame more than 3 units | yes | green: the largest shake (a player hit, 4 u) is 2 u at 50%, and the total is capped (`test_shake_at_the_default_fifty_percent_never_exceeds_three_units`; content validation refuses a default that would pass 3 u) |
| Any boss-fight frame could be the store page | no: art is Phase 2 | carried |
| *Audio* (all five lines) | no: audio is Phase 2 task 4 | carried |
| *Run tension* | | |
| Greedy 20-minute zone 1 noticeably harder than a 6-minute one | no: the Wane Clock's spawn scaling is not in the Phase 1 kickoff order | carried |
| Vigil radius readable; kills refill it | no: the Vigil is not in Phase 1 | carried |
| Dark thresholds distinguishable by sight | no: needs the Phase 2 lighting pass | carried |
| Run beatable with the starting kit on Wane | no: needs a full run | carried |
| Seeded replay reproduces bit-for-bit on Windows, Linux and Deck | partial: every fixture replays bit-for-bit against its golden hashes on Linux, Windows and macOS CI; a full run and the Deck come later | green in the audit's fuzz: random inputs, GDScript against native, 300 per-second hashes equal and replays verify bit-for-bit (2.6 KB a minute, the spec says about 2); the Deck and a full run do not exist yet; the five real Votives were not fuzzed |
| *Process* | | |
| Every tuning change this milestone is in the feel log | yes | green so far: tasks 2 to 8 and the audit fixes (`docs/feel_log/`); the non-feel tunables (the join band, spike inset, safe-ground margin, Ember Toss speed and cooldown, hazard invulnerability) are recorded in ADR-0008, 0010 and 0013 and the task 3 entry in prose, with no before and after table: carried |
| Every new system has an ADR | yes | green so far: ADR-0008 (physics), 0009 (rooms), 0010 (movement), 0011 (camera), 0012 (debug overlay and frame-stepper), 0013 (combat), 0014 (doors and zones), 0015 (procs and Votives), 0016 (tech rooms teach, they do not gate), 0017 (ember toss cancel over a chasm), 0018 (room editor install), 0019 (zone 1 grey box), 0020 (stress room and perf gate; its Decisions 10 to 13 hold the lighting stand-in), 0021 and 0022 (native extension and sweep); the HUD is folded into ADR-0013, a short ADR of its own is owed |
| F3 overlay shows hitboxes, state, frame counter and input history | yes | green: F3 in any build, and with it shown F4 pause, F5 one tick, F6 ten; a hazard hit is marked where the hurtbox touched (ADR-0012; `test_debug_overlay.gd`, `test_debug_boxes.gd`, `test_input_history.gd`); every tech and physics fixture plays to the same hash with the overlay reading every tick; the task 5 sheet is filmed through it |
| CI is green: unit, replay, perf, screenshot, style gate, lint | yes for unit, replay, perf and lint; screenshot and style gate have no assets until Phase 2 | green on this container for compile, content, replay (545 fixtures) and unit (805 cases), coverage and lint, and `ci/perf.sh` passes (stress p99 2.67 ms against 3.0, ADR-0020 Decision 17; door gate; frame bench). At 4bd4b79 both Windows jobs were red on the 10 s fixture budget (10.5 s release library, 14.1 s debug); the suite was then made faster without checking less (ADR-0006, Suite speed), and CI run 24 on 12c9af3 passed every job, Windows included |

## CI gates from BUILD.md section 13 not on the checklist

| Gate | Status |
| --- | --- |
| Core coverage of at least 85% | green: `tools/ci/gd_coverage.py` instruments a scratch copy of the project (GDScript has no coverage tooling); core is at 96.3% (the audit's run) and CI gates at 85% |
| Replay fixtures run headless in under 10 seconds | green here, unproven on CI's runners: 545 fixtures in 4.8 s on this 4-core container with the native path, none failing, every golden hash equal on Linux, Windows and macOS. With the GDScript reference path they took 14.2 s (Linux) and 16.6 s (Windows) on CI's 2-processor runners, 8 to 13 s on the 4-core container. The director decided (2026-10-20, ADR-0006 Budget): the 10 s holds the shipped configuration, the native path on; the reference run proves the hashes and is not timed. after the speed work (ADR-0006, Suite speed) CI's native-path time on Windows (10.5 s at 4bd4b79) is the next number to read; if it misses 10 s, the suite is made faster, never the budget larger |
| Export for Windows, Linux, macOS and Deck on every merge, booting to the Hearth | carried: no export presets yet and the Hearth is not in Phase 1; the export job lands with the first presets |
| Credits and legal screen listing Godot's third-party licenses (docs/LICENSES.md) | carried to the Phase 2 UI work |

## Feature flags with expiry

- None open. The `perf-stress` CI job's `continue-on-error` (expiry 2026-12-31) was removed when the stress gate was met (ADR-0020 Decision 17); the job and `perf` are both blocking.

## Blocked

1. **BUILD.md section 14's roadmap body and section 13's architecture diagram did not survive the export to Markdown** (`docs/BUILD.md` lines 692 and 777 read "[embedded content: ...]"). The Phase 1 gate sentence and the per-phase contents are therefore unknown; Phase 1 followed CLAUDE.md's kickoff order. **Director: please paste the roadmap table (phases, gates, months) and the architecture diagram's text.**
2. **The frame gate needs hardware we do not have in CI.** BUILD.md: "a stress room ... on a GPU runner", "60 fps ... on reference PC settings, 15.0 ms on the Deck profile". GitHub-hosted runners have no GPU. The CPU budget is gated (`ci/perf.sh`); the GPU numbers need a self-hosted runner on the reference PC (RTX 4060-class) and a Steam Deck. **Director: can you provide either, or may the line close on the PC plus the CPU numbers?**
3. **Tech 8 (attack-cancel landing) is taught, not enforced, in zone 1 room 8** (and tech 9, ADR-0016). A dash outruns a dummy's 24 f telegraph (`tests/replay/zone1/08_gap_two_dashes.fixture`, a known-gap fixture). Closes when a boss with a short window blocks the door (Phase 2); then the gap fixture becomes a control.

(The old Blocked 3, the camera jolt on a pogo during a teleport glide, is closed: `2026-10-20-camera-glide-jolt.md`.)

## For the director

What to play (Windows or Linux with a display; `godot --path .` boots the sandbox; add `-- --lighting=pitch` for the Pitch stand-in; F3 shows the overlay, F4 pauses, F5 steps one tick, F6 ten):

- **Movement.** Tap and hold jumps (is the release a decision or a cut? holds of 1 to 4 f are identical); the wall-kick climb in room 05 (held, tapped, mashed: any sticking, any press that does nothing?); a dash-jump with the jump pressed with the dash, or on its 2nd to 4th frame (it comes out up to 4 frames late: if that feels late the lever is `dash_jump_first`); releasing the stick on a dash-jump sheds the speed over about 22 frames (carry it?); lips and staircases (does the 3-frame ease of a corner nudge read as invisible? up a dashed staircase the body sits inside the steps for two frames); the ramp crest in `test/ramp45_crest_lip` (a 5 u step eased: step or bump?).
- **Camera.** The questions in `docs/feel_log/2026-10-17-task4-camera.md`; a wall-jump off a long fall (the view should settle then follow the fall down); a death far from the spawn (the cut is instant, the fade is not built); toss up room 4's post column and bounce on the next post (no kick); a door at a run and at a dash (is a cut right, or a few frames of fade?).
- **Combat.** Strike, parry and Mend on the sandbox's three dummies (one standing, one white swing every second, one red). Look and feel for: three rising impacts in the chain (2, 2 and 4 f of hitstop); the 12 f knockback; the side 1 recoil (8 f at 60 u/s, perhaps too small: `recoil_frames`); whether an armored hit should skip hitstop; the Charged strike's release (late?); Mend standing still 50 f (should a walk interrupt it?); the kill ember's 11 Flame; take a hit, a hazard and the red swing with the overlay off and say what hit you; red and white at Pitch with flashes at 0 (shape cues only). Listen for the heal against the parry chime and Radiance's bloom (grey-box tones; real audio is Phase 2).
- **Zone 1 (rooms 1 to 12) and `zone1_loop`.** Does 60 s read as flow, and does your eye ever leave Ash for the HUD? Questions from the room reviews: accept "teach, not gate" for tech 8 and 9 (ADR-0016), or add a core rule? Room 03: a pit that needs ten bounces with an air jump in each (the plain chain takes eleven): right to teach the pogo chain, or should the header ask the plain one? Is the air jump 5 f after each bounce natural? Room 07's coyote-dash window is tight (fair?). Room 08: is the 2 f gap a boss's "short window"? Room 10: is the 111 u (12 f) window generous, and is the toss shortcut fine? Room 11: is a throw timed to the air dash with a teleport on the last tick too hard for a teaching room, and is "land, then teleport" wanted literally (it needs an island)? The Ember Toss's 12 s cooldown is not refilled by a pit send-back. Room 12: is 146 u from the door generous for a first air use? Kicks are not the best way up a wall (a wall-jump plus up-dash climbs 263 u every 25 ticks against 176 u every 24): keep, or change the toss and the wall-jump's restores? The Ember Toss's landing trick sets room heights (rooms 4 and 5 are 76 and 78 tiles tall): is that the toss you want? Room 6 teaches wall-jump, dash, air jump, cling: the rhythm you want? Room 9: a reverse pogo works without a dash in a 2-tick window (kept, BUILD.md says speed is preserved). Room 4's Votive alcove draws as an empty recess until pickups exist. Enemies reset when a room is left: should a room remember its dead?
- **Squash and stretch.** Land from a long fall mashing jump and dash: it never delays an action (the tests say so; judge the look). Is 94% at the apex enough to feel, or should the stretch wait for the rig?
- **Procs.** `godot --path . -- --room=sandbox --votive=bell_of_the_vigil:10 --votive=tallow_knuckle:3`: the Bell's 30 f stun cancelling a swing after its cue (fair?); Kindle's cone as a tick; the Flame tier bonus as relative; Hollow Step's one-heart floor; quarter hearts for the Abbess's Mercy (hearts with quarters?); where Second Ember's diamond shows (on the bounce or on Ash?). Hearthshard and the Snuffed Blade are deferred (they need the Phase 2 light and the Dark's clock).
- **Stress.** `docs/feel_log/2026-10-19-task8-stress.png` and `2026-10-20-stress-readable.png`: can you find Ash mid-burst at Pitch? `ci/perf.sh --verbose` to run both benches.
- **Room editor.** Open the editor and press Play on a zone 1 room: only the headless parts were checked. Is the door workflow natural (the second door saves only after the first), or is a "make the partner door" button worth having?

Decisions waiting on you:

1. Roadmap and architecture diagram text (Blocked 1).
2. A GPU runner and a Deck, or close the frame line on the PC plus CPU numbers (Blocked 2).
3. A single-run gate: single runs of the step and the presentation read over their sub-budgets (see the report); gate the median or the single run on the reference PC, keeping the best of 3 only for shared CI?
4. Proc storms: a Votive that chains on every proc event, from every source, costs about 22 us a proc and a swing on a bunched crowd is 300 to 550 procs (5 to 10 ms in one tick). Do the Votives carry internal cooldowns or the engine a per-tick proc budget (and BUILD.md section 6 says so), or does the engine pay (proc path in C++)? The storm stays in the bench.
5. The stress workload's minimums (12,000 to 8,000 procs, 14,000 to 9,000 hits) were the lead's decision, recorded in ADR-0020 Decision 15: guards that the run did its work, not cost gates. Say if you want it otherwise.
6. `Simulation.VERSION` was bumped per commit (9, 10, 11) and golden hashes were re-blessed once at 12: collapse to one per release?
7. Content hash covers a Votive's tooltip text, so a wording change forces a re-bless: should it cover display text at all? The listener boundary check is regex-based, not a token check.
8. The typeface for the shipped UI (open licenses only, `docs/LICENSES.md`).
9. The parry window: decided and built as exactly 8 world ticks (hitstop does not stretch it); say if you wanted the other reading.
10. The re-reviews of the last rounds of tasks 2 to 6 are not signed off by a reviewer subagent; the checklist audit stood in. Accept, or have them run?

## Phase 1 report

**What the player can now do, see and hear.** Ash runs, jumps (tap to 77.9 u, full to 176 u: 3.07 tiles), dashes 210 u from standstill or at a run, wall-clings and kicks up a wall, pogoes off spikes and bells, and tosses the ember and teleports to it, every action buffered 8 frames, with coyote time, corner correction and the whole of the section 5 tech list: all twelve tech interactions work and each has a room that teaches it. Ash fights with the Taper: three-hit chains with rising hitstop, a dash cancel on frame 4 that never eats the next press, a Charged strike, an 8-frame parry window, Kindle, Mend, Radiance, hearts, Flame and Kindling, poise and stagger, and kill embers that fly back and feed Ash. Ash can carry five Votives whose procs stack by exact curves. The camera leads, never takes control in combat and never lets Ash within 80 u of the screen edge; Ash squashes on landing and stretches at the apex. Everything is grey boxes and placeholder tones, by design: Phase 1 is feel. Twelve grey-box rooms of zone 1 can be crossed in a 57.7 second loop; a stress room of 200 enemies runs at Pitch under a stand-in ember light. A run is a seed and an input stream; every fixture replays bit-for-bit on Linux, Windows and macOS, and the F3 overlay and frame stepper show every box, state and input.

**What Phase 1 built.** The fixed 60 Hz integer core and replay system (task 1); the physics sweep, in C++ with the GDScript reference (2); Ash (3); the camera (4); the overlay and stepper (5); combat (6); the room editor, doors and zone 1 (7); the proc bus, Votives and the stress room with its CI gates (8); 545 replay fixtures, 805 unit cases and 22 ADRs.

**The Immaculate Checklist.** Green = verified by a fixture or a gate; partial = met against a Phase 1 stand-in (named); carried = depends on a later phase; director-only = the machine has done its half and a person must judge.

| Line | State |
| --- | --- |
| Jump buffered 8 f before landing fires on landing | green |
| Jump 6 f after a ledge still jumps | green |
| Tap and full jump differ by at least 3 tiles | green on numbers (3.07 tiles); the release is director-only |
| Turning never has a dead frame | green |
| Dash from standstill and at run reach the same distance | green (210 u) |
| Dash-jump keeps 100% and clears the reference gap | green; the gap is zone 1 room 02, not "room 7" (ADR-0019 Decision 4, noted in BUILD.md) |
| Pogo keeps speed; ten bounces at four a second cross the pit | green on fixtures (room 03, 3008 u); the rate is director-only |
| Pogo resets air dash; pogo, dash, pogo crosses the hidden-room gap | green |
| Wall-kick climbs without feeling stuck | green on fixtures; the feel is director-only |
| A 1-pixel ledge lands; the nudge is invisible | partial: landing green, the eased view tested; invisibility needs Ash drawn (Phase 2) |
| Ceiling corner under 6 u slides | green |
| Camera never within 80 u of the edge | green |
| 60 s loop through zone 1, eyes on the character | director-only: built (3461 ticks; it strikes and carries Kindle, no hit taken) |
| Attack on frame 3, even in hitstop | green |
| Dash cancels on frame 4, never eats the next attack | green |
| Three-hit chain reads as rising weight | partial: the dummy stands in for the Tallowman; the feel is director-only |
| Parry on the 8-frame window ten in a row | partial: green on the dummy (exactly 8 ticks, ten in a row); the Snuffed Knight is zone 3 |
| Red distinguishable from white at Pitch, flashes 0 | partial: shape and outline cues in grey boxes; re-checked with Phase 2 light and art |
| Taking a hit is never confusing | partial: all cues built; director-only |
| Hitstop never drops an input | green |
| 30 Votives, screen readable | partial: tested with the stress Votive set (39 procs per Taper hit), not 30 real Votives (five exist); re-judged in Phase 2 |
| Kindling White in zone 2 feels earned | carried (zone 2) |
| A kill's ember reaches the player in 20 f | green (16 f) |
| 60 fps in the stress room, Deck profile, lit | partial: CPU half met on the gated figure; the GPU half is blocked on hardware |
| No spike over 20 ms in a 5-minute zone 1 run | partial: simulation, presentation and door sides met on the grey box; the 60-room zone and a windowed GPU run are not |
| Clinger revealed by the ember at Pitch | carried (Phase 2) |
| Every enemy identifiable at 64 px | carried (Phase 2 art) |
| Every attack has a smear frame | carried (Phase 2 animator) |
| Landing squash and jump stretch, never blocking input | green for the grey box (3 f at 110% wide, 2 f at 94%); the rig is Phase 2 |
| Ember flicker on normal-mapped surfaces | carried (Phase 2 lighting) |
| Screen shake at 50% never over 3 u | green (largest is 2 u) |
| A boss-fight frame could be the store page | carried (Phase 2 and 3) |
| Audio (five lines) | carried (Phase 2 task 4) |
| Greedy 20-minute run harder than 6-minute | carried (the Wane Clock) |
| Vigil radius readable | carried |
| Dark thresholds distinguishable | carried (Phase 2 lighting) |
| Run beatable with the starting kit | carried (a full run) |
| Seeded replay bit-for-bit on Windows, Linux, Deck | partial: green on Linux, Windows and macOS CI and in the audit's fuzz; the Deck and a full run do not exist |
| Every tuning change in the feel log | green; the non-feel tunables have prose, not tables (carried) |
| Every new system has an ADR | green; the HUD has a section in ADR-0013 and is owed its own short ADR |
| F3 shows hitboxes, state, frames, input history | green |
| CI green: unit, replay, perf, screenshot, style gate, lint | green: every job of run 24 (Linux, Windows and macOS, native path off and on, both perf gates, release libraries); this merge's run is checked before review; screenshot and style gate have no assets until Phase 2 |

Of 42 rows (the five audio lines are one): 21 green, 9 partial with a named stand-in, 11 carried, 1 director-only (the 60-second loop); several green and partial rows also keep a director-only half, listed under "For the director".

**The numbers that matter.**

| | Value |
| --- | --- |
| Tap jump / full jump | 77.9 u / 176 u (3.07 tiles) |
| Dash | 210 u from standstill and at run; dash-jump keeps 100% of the speed |
| Pogo, ten bounces | cross room 03's 3008 u pit at 4 a second, 20 u/f kept |
| Wall-kick climb | 176 u every 24 f |
| Combat | strike box live on frame 3; dash cancel frame 4; parry window 8 ticks; chain hitstop 2, 2, 4 f; hit: 8 f hitstop on Ash, 60 u knockback over 12 f, 20 free frames; kill ember in 16 f |
| Shake | at most 2 u at 50% (cap 3 u) |
| Simulation step, spec workload (200 enemies, 39-proc chain per Taper hit) | gated figure (least of 3 runs per tick): p99 2.67 to 2.88 ms (gate 3.0), worst 3.9 to 4.2 ms (gate 20). Single runs, reported beside it and not gated: p99 3.2 to 4.7 ms. CI's runner passes the gate too |
| Presentation script time at Pitch | gated: p99 3.9 to 4.4 ms (gate 5.0), worst 7.2 to 13.6 ms. Single passes: p99 5.4 to 7.0 ms |
| Door crossing at Pitch | 0.08 to 0.38 ms (gate 2.0; it was 4 to 17) |
| Zone 1 loop x6 on one simulation (5.8 min) | worst tick 0.84 ms (gate 20) |
| Proc storm (a chain on every event; not gated) | p99 5.2 ms, worst 9.9 ms; about 22 us a proc |
| Fixture suite | 545 fixtures in 4.8 to 5.0 s on this 4-core container, native path (budget 10 s; 9.8 s on the GDScript reference, not timed); CI's Windows runners now meet the 10 s too (run 24); unit 805 cases |
| Core coverage | 96.4% (gate 85%) |

**Contact sheets to look at** (`docs/feel_log/`, each is a frame-stepped sheet with the F3 overlay):

- Movement and tech: `2026-10-17-task3-ash-movement.png`, `2026-10-17-pogo-chain-window.png`, `2026-10-17-jump-release.png`, `2026-10-19-zone1-reverse-pogo.png`.
- Physics and nudges: `2026-10-17-task2-physics.png`, `2026-10-19-nudge-ease-runs.png`.
- Combat: `2026-10-19-task6-combat.png`, `2026-10-20-parry-window-ticks.png`, `2026-10-19-rr3-core-fixes.png`.
- Camera: `2026-10-17-task4-camera.png`, `2026-10-19-camera-review7-fall-away.png`, `2026-10-20-camera-glide-jolt.png`.
- Doors: `2026-10-19-task7-doors.png`; the room editor: `2026-10-19-task7-room-editor.png`.
- Zone 1 by room group: `2026-10-19-zone1-a.png` (rooms 1 to 3), `2026-10-20-room03-pit.png` (room 03 rebuilt), `2026-10-19-zone1-b.png` (rooms 4 to 6), `2026-10-19-zone1-07-coyote-dash.png`, `2026-10-19-zone1-08.png`, `2026-10-19-zone1-reverse-pogo.png` (9), `2026-10-19-zone1-10-crouch-dash-under.png`, `2026-10-19-zone1-11-ember-toss-cancel.png`, `2026-10-19-zone1-room12.png`.
- Procs: `2026-10-19-task8-procs.png`, `2026-10-19-task8-procs-counters.png`.
- Stress at Pitch: `2026-10-19-task8-stress.png`, `2026-10-20-stress-readable.png`.
- Squash and stretch: `2026-10-20-squash-stretch.png`.

**What is not done, and why.**

- All art, audio, the real enemies, the Wane Clock, the Vigil, the Dark's thresholds and the Hearth: Phase 2 and later by the kickoff order; 15 checklist lines wait on them.
- The GPU frame gate and the Deck: no hardware in CI (Blocked 2). The CPU half is gated.
- Tech 8 and 9 are taught, not gated (Blocked 3, ADR-0016): the core has nothing that can block a door yet.
- Export presets and the credits screen: carried to the first Phase 2 export (the Hearth does not exist).
- Hearthshard and the Snuffed Blade Votives: need the Phase 2 light and the Dark.
- Every Phase 1 change was reviewed by a fresh reviewer at least once and its high and medium findings fixed; the checklist audit was the final pass. Physics went through eight review rounds and still found edge cases each time, so the director's play is the real sign-off.
- The roadmap and architecture diagram are missing from BUILD.md (Blocked 1).

**Decisions the director made.** The 10 s fixture budget holds the shipped configuration, the native path on; the GDScript reference run proves hashes and is not timed (2026-10-20, ADR-0006). Wall time, not CPU time, decides the budget.

**Decisions waiting on the director.** The ten under "For the director". The ones that block Phase 2 planning are 1, 2 and 4; the rest can be answered while playing.
