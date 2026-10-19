# WANE: progress

- **Phase:** 1, feel in grey boxes (BUILD.md section 14; CLAUDE.md kickoff order)
- **Status:** in progress
- **Engine:** Godot 4.7.2-stable (ADR-0001)

## Kickoff order

| # | Task | Status |
| --- | --- | --- |
| 0 | Repo skeleton, `.godot-version`, CI, gdUnit4, lint, requirements, PROGRESS, ADR and feel-log templates, LICENSES | done |
| 1 | Core loop: fixed-step driver, `InputFrame` and ring buffer, split-stream RNG, state hash every 60 ticks, replay recorder and player | done |
| 2 | Physics sweep: AABB, slopes to 45 degrees, one-way platforms, corner correction | in review: fixed through six review rounds (ADR-0008); the sixth round's fixes are committed and their re-review runs next. Committed with task 3, whose player its fixtures and tests run through |
| 3 | Ash: ground, jump, dash, wall, pogo; one fixture per table row and per tech interaction | in review: every row and all 12 tech interactions have fixtures, with control runs; fixed through four review rounds (ADR-0010); the fourth round's fixes are committed and their re-review runs next |
| 4 | Camera | in review: fixed through five review rounds (ADR-0011); the fifth round's fixes are committed and their re-review runs next |
| 5 | F3 debug overlay and frame-stepper | in progress, not yet committed: overlay, boxes, input history and stepper built and unit-tested (ADR-0012); wiring into the game and the filmed contact sheet remain |
| 6 | Taper, Flame, Kindling, parry, spells, hit feedback, training dummy with poise | in progress: the Taper's strikes and the pogo are committed with task 3; Flame, hearts, Kindling, the dummy, hit feedback and slow motion are built and unit-tested but not yet integrated or committed |
| 7 | Room editor plugin and grey-box zone 1 (12 rooms, 12 tech interactions in order) | in progress: the room format (ADR-0009) is committed; the editor's document, history and panel are built but not committed; zone 1 is not built |
| 8 | Stress room (200 enemies, 40 procs, Pitch lighting) and perf benchmark in CI | not started (the physics bench exists: ADR-0008) |
| 9 | Immaculate Checklist pass, Phase 1 report | not started |

## Next

Task 5: commit the F3 overlay and the frame-stepper with their first review's fixes; re-review physics (round 7), movement (round 5), the camera (round 6) and task 5 (round 2) and fix what they find; then task 6's integration.

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
| Dash-jump keeps 100% of dash speed and clears the zone 1 room 7 gap every time | yes, with a numbering decision: the grey-box zone teaches the tech in order, so its dash-jump reference gap is in room 2; ADR at task 7 | partial: 100% kept for the whole airtime, off a lip and off a door down a ramp too (`dash_jump_from_box_a_lip`, `dash_jump_down_ramp45_off_door`); the 1664 u test chasm is cleared by a ground dash-jump with its air jump and air dash from a broad region of timings (with the air jump alone, a 15-tick window from dash frame 9), and no route without a dash-jump of any kind crosses it, one Ember Toss included, and nothing in the 1504 u deep chasm can be clung to or pogoed off toward the far side (farthest 1595 u counting the 10 u ledge-grab, 59 u short; `tech02_dash_jump_frame5_air_dash`, `_frame5`, `_frame9`, `tech02_control_*` including `_pogo_floor` and `_toss_wall_kick`, `tech02_respawn_does_not_keep_the_ember`; reach table in ADR-0010, measured by `tools/replay/gap_reach.gd`); the zone 1 room is task 7 |
| Pogo keeps full horizontal speed; 10-bounce chain across the zone 1 spike pit at 4 bounces/s | yes | partial: speed kept (`pogo_keeps_horizontal`, `pogo_dash_jump_speed`), ten bounces cross the 3360 u test pit (`tech03_pogo_chain`); the zone 1 pit is task 7 |
| Pogo resets air dash; pogo, dash, pogo crosses the hidden-room gap | yes | partial: `pogo_resets`, `tech04_pogo_dash_reset` on the test gap; the hidden room is task 7 |
| Wall-kick climbs a single wall without feeling stuck | yes | green on fixtures: 176 u every 24 f, held, tapped or mashed (`tech05_wall_kick_climb`, `tech05_wall_kick_mash`); the feel is the director's to play |
| Landing on a 1-pixel ledge edge lands; nudge invisible | yes | partial: a fall or a diagonal dash lands from the near side by the corner lift and from the far side by the far-edge landing (`ground_corner_lift`, `far_edge_landing_lands`, `down_dash_lands_on_ledge_far_corner`, `test_physics_fuzz_lift.gd`); every nudge is recorded for the view to ease, but nothing eases it before task 5, so a step on a slope still shows as a snap of up to 18 u |
| Head bumping a ceiling corner by under 6 units slides around it | yes | green: `jump_ceiling_nudge` slides, `jump_ceiling_bump` (7 u) bumps |
| Camera never shows the player within 80 units of the screen edge | yes | green over all 305 movement, tech, physics and camera fixtures at 16:9, 16:10, 4:3 and 21:9, held by the follow alone with no backstop correction, and over the fourth review's sweeps (falls beside walls and down shafts 96 to 288 u wide, wall-jumps up every shaft width, look-drops of 64 to 256 u, borderless room edges, long ramps) and the fifth review's fixtures (`cam5_*`) (`test_camera_rig.gd`, `test_camera_review*.gd`); the re-review of the fifth round's fixes runs next; the zone 1 loop is task 7 |
| 60-second movement-only loop through zone 1 playable with eyes on the character | yes (the director plays it) | not started: needs zone 1 (task 7) |
| *Combat* | | |
| Attack comes out on frame 3 from a neutral press, every time, including during hitstop | yes | partial: the strike box is live on frame 3 from a neutral press (`dash_cancels_attack`); hitstop is task 6 |
| Dash cancels an attack on frame 4 and never eats the next attack input | yes | green: `dash_cancels_attack`, `dash_cancel_window`, `dash_cancels_down_strike`; an attack pressed before the dash that cancels a strike is kept for its frame 6 (`dash_cancel_keeps_earlier_attack`, with its control) |
| 3-hit chain against a Tallowman reads as three impacts with rising weight | partial: a grey-box heavy dummy stands in for the Tallowman | not started (task 6) |
| Parry succeeds on the 8-frame window against the Snuffed Knight 10 times in a row | partial: a grey-box knight dummy; its timings are new content values with a feel-log entry | not started (task 6) |
| Unparryable red distinguishable from parryable white at Pitch with flashes at 0 | partial: shape and outline cues on grey boxes; re-checked with Phase 2 lighting and art | not started (task 6) |
| Taking a hit is never confusing | yes | not started (task 6) |
| Hitstop never causes a dropped input; buffered inputs fire on the first free frame | yes | in progress: the ring merges hitstop frames and keeps every press (task 1, unit-tested); hitstop itself comes with task 6 |
| With 30 Votives active the screen stays readable | partial: the stress room's grey-box procs | not started |
| Kindling White reached by a skilled tester in zone 2, feels earned | no: zone 2 does not exist in Phase 1 | carried |
| A kill releases an ember that reaches the player within 20 frames; Flame reacts | yes | not started (task 6) |
| *Graphics and feel* | | |
| 60 fps in the stress room on the Deck profile with lighting on | partial: Phase 1 lights the stress room with Godot's 2D lights; the real lighting pass is Phase 2 task 1, and the gate needs Deck-class hardware (see Blocked) | not started |
| No frame-time spike above 20 ms in a 5-minute zone 1 run | partial: the 12-room grey-box zone, not the final 60-room zone | not started |
| At Pitch the ember reveals a Clinger 30 frames before it drops | no: neither the Clinger nor the ember light exists in Phase 1 | carried |
| Every enemy identifiable by silhouette at 64 px | no: art is Phase 2 | carried |
| Every attack has a smear frame | no: animation is Phase 2 | carried |
| Landing squash and jump stretch visible and never block input | partial: grey-box squash and stretch driven by the core's timings | not started |
| Ember flicker visible on nearby normal-mapped surfaces | no: normal maps are Phase 2 | carried |
| Screen shake at default 50% never moves the frame more than 3 units | yes | not started (task 6) |
| Any boss-fight frame could be the store page | no: art is Phase 2 | carried |
| *Audio* (all five lines) | no: audio is Phase 2 task 4 | carried |
| *Run tension* | | |
| Greedy 20-minute zone 1 noticeably harder than a 6-minute one | no: the Wane Clock's spawn scaling is not in the Phase 1 kickoff order | carried |
| Vigil radius readable; kills refill it | no: the Vigil is not in Phase 1 | carried |
| Dark thresholds distinguishable by sight | no: needs the Phase 2 lighting pass | carried |
| Run beatable with the starting kit on Wane | no: needs a full run | carried |
| Seeded replay reproduces bit-for-bit on Windows, Linux and Deck | partial: every fixture replays bit-for-bit against its golden hashes on Linux, Windows and macOS CI; a full run and the Deck come later | in progress: green for all fixtures |
| *Process* | | |
| Every tuning change this milestone is in the feel log | yes | green so far: tasks 2 to 4 (`docs/feel_log/`) |
| Every new system has an ADR | yes | green so far: ADR-0008 (physics), 0009 (rooms), 0010 (movement), 0011 (camera) |
| F3 overlay shows hitboxes, state, frame counter and input history | yes | in progress (task 5) |
| CI is green: unit, replay, perf, screenshot, style gate, lint | yes for unit, replay, perf and lint; screenshot and style gate have no assets until Phase 2 | green for unit, replay, coverage and lint; the perf gate is task 8 |

## CI gates from BUILD.md section 13 not on the checklist

| Gate | Status |
| --- | --- |
| Core coverage of at least 85% | green: `tools/ci/gd_coverage.py` instruments a scratch copy of the project (GDScript has no coverage tooling); core is at 93.6% and CI gates at 85% |
| Replay fixtures run headless in under 10 seconds | green: the fixture stage takes about 7.5 s for all 307 fixtures here (building a simulation costs 1.4 ms: ADR-0006) |
| Export for Windows, Linux, macOS and Deck on every merge, booting to the Hearth | carried: no export presets yet and the Hearth is not in Phase 1; the export job lands with the first presets |
| Credits and legal screen listing Godot's third-party licenses (docs/LICENSES.md) | carried to the Phase 2 UI work |

## Feature flags with expiry

None.

## Blocked

1. **BUILD.md section 14's roadmap body and section 13's architecture diagram did not survive the export to Markdown** (`docs/BUILD.md` lines 692 and 777 read "[embedded content: ...]"). The Phase 1 gate sentence and the per-phase contents are therefore unknown; Phase 1 follows CLAUDE.md's kickoff order meanwhile. **Director: please paste the roadmap table (phases, gates, months) and the architecture diagram's text.**
2. **The perf gate needs hardware we do not have in CI.** BUILD.md: "a stress room ... on a GPU runner", "60 fps ... on reference PC settings, 15.0 ms on the Deck profile". GitHub-hosted runners have no GPU. Task 8 builds the benchmark and runs it on what exists (software rendering here, the CPU budget everywhere); the GPU numbers need a self-hosted runner on the reference PC (RTX 4060-class) and a Steam Deck. **Director: can you provide either?**

## For the director

- **Play the sandbox** (`content/rooms/sandbox.room`, the room the game boots into): run, jump, dash, wall-kick, pogo the spikes and bells, toss the ember.
- **Camera**: the questions in `docs/feel_log/2026-10-17-task4-camera.md` (the climb's head room, look-down distance, teleport cuts, the turn on an up-dash out of a fall, the look pausing past a ledge in steering reach).
- **Movement**: the questions in `docs/feel_log/2026-10-17-task3-ash-movement.md` and ADR-0010 (wall-kick climb, pogo-dash cadence, ember values, low gaps, wall coyote time, tech 2's 1664 u gap, the reverse pogo needing dash speed, a spent wall still kicking, a press lost behind a strike with no cancel, the safe-ground margin, strikes read 4 ways, the jump A/B).
- **Physics**: the ledge-grab's 10 u is measured from the feet (ADR-0008).
