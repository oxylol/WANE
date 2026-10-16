# WANE: progress

- **Phase:** 1, feel in grey boxes (BUILD.md section 14; CLAUDE.md kickoff order)
- **Status:** in progress
- **Engine:** Godot 4.7.2-stable (ADR-0001)

## Kickoff order

| # | Task | Status |
| --- | --- | --- |
| 0 | Repo skeleton, `.godot-version`, CI, gdUnit4, lint, requirements, PROGRESS, ADR and feel-log templates, LICENSES | done |
| 1 | Core loop: fixed-step driver, `InputFrame` and ring buffer, split-stream RNG, state hash every 60 ticks, replay recorder and player | done (eight review rounds; the last found nothing) |
| 2 | Physics sweep: AABB, slopes to 45 degrees, one-way platforms, corner correction | in progress: redesigned after its first review (ADR-0008) |
| 3 | Ash: ground, jump, dash, wall, pogo; one fixture per table row and per tech interaction | not started |
| 4 | Camera | not started |
| 5 | F3 debug overlay and frame-stepper | not started |
| 6 | Taper, Flame, Kindling, parry, spells, hit feedback, training dummy with poise | not started |
| 7 | Room editor plugin and grey-box zone 1 (12 rooms, 12 tech interactions in order) | not started |
| 8 | Stress room (200 enemies, 40 procs, Pitch lighting) and perf benchmark in CI | not started |
| 9 | Immaculate Checklist pass, Phase 1 report | not started |

## Next

Task 2: the physics sweep, reworked after review (validated slope geometry, exact swept walking, crest landings, drop-through beside walls), then Ash's movement (task 3, whose fixtures are being written alongside).

## Immaculate Checklist (BUILD.md section 15)

Applicability to Phase 1 is decided per line. "No" lines depend on systems that are not in the Phase 1 kickoff order (final art, audio, enemies from later zones, the Wane Clock, the Vigil) and are carried to the phase that builds them. "Partial" lines are checked against Phase 1's grey-box stand-ins now and re-checked when the real system lands.

| Line | Applies in Phase 1 | Status |
| --- | --- | --- |
| *Movement* | | |
| Jump pressed 8 frames before landing fires on the landing frame | yes | in progress: the input ring serves an 8-frame-old press (task 1); the landing jump comes with Ash (task 3) |
| Jump pressed 6 frames after walking off a ledge still jumps | yes | not started |
| Tap jump and full jump differ by at least 3 tiles; release feels like a decision | yes | not started |
| Turning around never produces a dead frame; sprite flips on the input frame | yes (the grey box's facing marker flips) | not started |
| Dash from standstill and at full run reach the same distance | yes | not started |
| Dash-jump keeps 100% of dash speed and clears the zone 1 room 7 gap every time | yes, with a numbering decision: the grey-box zone teaches the tech in order, so its dash-jump reference gap is in room 2; ADR at task 7 | not started |
| Pogo keeps full horizontal speed; 10-bounce chain across the zone 1 spike pit at 4 bounces/s | yes | not started |
| Pogo resets air dash; pogo, dash, pogo crosses the hidden-room gap | yes | not started |
| Wall-kick climbs a single wall without feeling stuck | yes | not started |
| Landing on a 1-pixel ledge edge lands; nudge invisible | yes | not started |
| Head bumping a ceiling corner by under 6 units slides around it | yes | not started |
| Camera never shows the player within 80 units of the screen edge | yes | not started |
| 60-second movement-only loop through zone 1 playable with eyes on the character | yes (the director plays it) | not started |
| *Combat* | | |
| Attack comes out on frame 3 from a neutral press, every time, including during hitstop | yes | not started |
| Dash cancels an attack on frame 4 and never eats the next attack input | yes | not started |
| 3-hit chain against a Tallowman reads as three impacts with rising weight | partial: a grey-box heavy dummy stands in for the Tallowman | not started |
| Parry succeeds on the 8-frame window against the Snuffed Knight 10 times in a row | partial: a grey-box knight dummy. BUILD.md gives only the rules (telegraph of at least 20 f, parryable sweep, unparryable red overhead), so its timings are new content values with a feel-log entry | not started |
| Unparryable red distinguishable from parryable white at Pitch with flashes at 0 | partial: shape and outline cues on grey boxes; re-checked with Phase 2 lighting and art | not started |
| Taking a hit is never confusing | yes | not started |
| Hitstop never causes a dropped input; buffered inputs fire on the first free frame | yes | in progress: the ring merges hitstop frames and keeps every press (task 1, unit-tested); hitstop itself comes with combat (task 6) |
| With 30 Votives active the screen stays readable | partial: the stress room's grey-box procs | not started |
| Kindling White reached by a skilled tester in zone 2, feels earned | no: zone 2 does not exist in Phase 1 | carried |
| A kill releases an ember that reaches the player within 20 frames; Flame reacts | yes | not started |
| *Graphics and feel* | | |
| 60 fps in the stress room on the Deck profile with lighting on | partial: Phase 1 lights the stress room with Godot's 2D lights; the real lighting pass is Phase 2 task 1, and the gate needs Deck-class hardware (see Blocked) | not started |
| No frame-time spike above 20 ms in a 5-minute zone 1 run | partial: the 12-room grey-box zone, not the final 60-room zone | not started |
| At Pitch the ember reveals a Clinger 30 frames before it drops | no: neither the Clinger nor the ember light exists in Phase 1 | carried |
| Every enemy identifiable by silhouette at 64 px | no: art is Phase 2 | carried |
| Every attack has a smear frame | no: animation is Phase 2 | carried |
| Landing squash and jump stretch visible and never block input | partial: grey-box squash and stretch driven by the core's timings | not started |
| Ember flicker visible on nearby normal-mapped surfaces | no: normal maps are Phase 2 | carried |
| Screen shake at default 50% never moves the frame more than 3 units | yes | not started |
| Any boss-fight frame could be the store page | no: art is Phase 2 | carried |
| *Audio* (all five lines) | no: audio is Phase 2 task 4 | carried |
| *Run tension* | | |
| Greedy 20-minute zone 1 noticeably harder than a 6-minute one | no: the Wane Clock's spawn scaling is not in the Phase 1 kickoff order | carried |
| Vigil radius readable; kills refill it | no: the Vigil is not in Phase 1 | carried |
| Dark thresholds distinguishable by sight | no: needs the Phase 2 lighting pass | carried |
| Run beatable with the starting kit on Wane | no: needs a full run | carried |
| Seeded replay reproduces bit-for-bit on Windows, Linux and Deck | partial: every fixture and grey-box zone replay on Linux, Windows and macOS CI; a full run and the Deck come later | not started |
| *Process* | | |
| Every tuning change this milestone is in the feel log | yes | not started |
| Every new system has an ADR | yes | not started |
| F3 overlay shows hitboxes, state, frame counter and input history | yes | not started |
| CI is green: unit, replay, perf, screenshot, style gate, lint | yes for unit, replay, perf and lint; screenshot and style gate have no assets until Phase 2 | not started |

## CI gates from BUILD.md section 13 not on the checklist

| Gate | Status |
| --- | --- |
| Core coverage of at least 85% | green: `tools/ci/gd_coverage.py` instruments a scratch copy of the project (GDScript has no coverage tooling); core is at 95.2% and CI gates at 85% |
| Export for Windows, Linux, macOS and Deck on every merge, booting to the Hearth | carried: no export presets yet and the Hearth is not in Phase 1; the export job lands with the first presets |
| Credits and legal screen listing Godot's third-party licenses (docs/LICENSES.md) | carried to the Phase 2 UI work |

## Feature flags with expiry

None.

## Blocked

1. **BUILD.md section 14's roadmap body and section 13's architecture diagram did not survive the export to Markdown** (`docs/BUILD.md` lines 692 and 777 read "[embedded content: ...]"). The Phase 1 gate sentence and the per-phase contents are therefore unknown; Phase 1 follows CLAUDE.md's kickoff order meanwhile. **Director: please paste the roadmap table (phases, gates, months) and the architecture diagram's text.**
2. **The perf gate needs hardware we do not have in CI.** BUILD.md: "a stress room ... on a GPU runner", "60 fps ... on reference PC settings, 15.0 ms on the Deck profile". GitHub-hosted runners have no GPU. Task 8 builds the benchmark and runs it on what exists (software rendering here, the CPU budget everywhere); the GPU numbers need a self-hosted runner on the reference PC (RTX 4060-class) and a Steam Deck. **Director: can you provide either?**

## For the director

Nothing to play yet.
