# 2026-10-19: Presentation review 3 (task 5 round 3, task 6 round 2)

- Author: Claude
- BUILD.md section and table row: section 5, Corner correction; section 6, Hit feedback (Parry, Finisher); section 10, VFX language; section 12, Photosensitivity and the HUD table; section 11, "no sound repeats identically"
- Fixture(s): `tests/replay/presentation/walk_down_lip_stairs`, `dash_down_lip_stairs`, `walk_up_stairs9`; `tests/replay/combat/death_far_from_the_spawn`, `blaze_finisher_burst`, `two_parries_in_a_slow`, `five_parries_in_a_second`
- Contact sheet: none new. Every change here is in how the simulation is drawn, heard or overlaid; `core/` is untouched, `Simulation.VERSION` is unchanged and no committed fixture's per-tick state moved (the fixtures stage and the golden hashes are green), so there is nothing to compare frame by frame.

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| `nudge_lag_percent` (`content/player_view.tres`) | 200 | 250 | % of the run's nudge |
| `screen_flash_max` in `screen_flash_window_frames` (new) | none (one per 3 ticks, up to 20 a second) | 3 in 60 | flashes in ticks |
| `vfx_spark_frames`, `vfx_burst_frames`, `vfx_smear_frames` (were literals in `vfx_budget.gd`) | 6, 9, 5 | 6, 9, 5 | ticks |
| `hud_gain_flash_frames`, `hud_ghost_flame_per_tick` (were literals in `hud.gd`) | 12; the fill eased at 4 | 12; the fill is the true value, the ghost closes at 4 | ticks; Flame a tick |
| `split_offset_px`, `split_alpha`, `vignette_depth`, `vignette_alpha` (were literals in `feedback_overlay.gd`) | 6, 0.18, 0.12, 0.5 | 6, 0.18, 0.12, 0.5 | px, opacity, share of the short side, opacity |
| `hit_pitch_spread` renamed `sound_pitch_spread`; every sound plays with it | 0.03 on hits only | 0.03 on every sound | share |
| Sound variants | hit 3, others 1 | hit `spark_variants` (3 to 5), others 3 | variants |

No other number moved: the new tunables carry the values that were literals.

## Why

Findings and what was done, in the order of the review files.

**Task 5 round 3**
- **H1 (stairs).** A speed that may change by a quarter of the nudge a tick, from rest, up a stair taken a lip a tick, lets the gap grow n, 1.75n, 2.25n, 2.5n and stop (braking holds the speed at n). The cap of 200 forced the excess through at once: the drawn speed changed by 4 u where 2 u is allowed (frame 19 of the walked-down stair), then held 16 u off the treads. Measured now on the walked-down `test/lip_stairs`: gaps 8, 14, 18, 20, 20, 20, 20, no jolt anywhere. The cap is 250, the number at which the quarter-nudge limit never has to give way on any shipped staircase. The cost is honest and now written down: an 8 u stair taken a lip a tick is drawn 20 u behind the collider for its length, and dashed down three lips a tick it reaches 46 u for three ticks (more than Ash is tall). The alternative the review proposed (follow the stair's climb rate and ease only the deviation) has the same start-up lag, since the drawn speed cannot reach the stair's rate any faster than the quarter limit; it only hides the offset after, at the price of a terrain model in a view. It is left for the Phase 2 rig, where planted feet are the animation's job. BUILD.md section 5, ADR-0012 and the old feel log claim that the speed limit "never jolts" are corrected: it never jolts up to the cap, and the cap is where the shipped content stops.
- **M1 (parry).** A parry staggers the enemy and clears its attack on the tick the swing lands, so the parried swing's box was never drawn. `DebugBoxes.Memory` remembers each telegraphing enemy's swing box after every tick; a PARRY event now draws a contact mark and the remembered box in white, "parried". The enemy's label says "PARRY WINDOW OPEN" while a press would parry (ticks to landing within `parry_window_frames`).
- **M2 (death).** A death by an enemy's hit sends Ash to the spawn in one tick, like a hazard, but only HAZARD cut the drawn player: at 144 Hz Ash slid 1150 px across the room. `SimEvents.DEATH` now cuts, and the overlay draws the hurtbox that took the lethal hit ("lethal hit") and the contact point of every hit on the player ("hit"). The camera's half of the same slide (`CameraSubject.respawned` is HAZARD only, a one-tick whip-pan) is in `game/camera/` and left to the camera's owner; it needs the same one-word change.
- **M3 (burst).** The Blaze finisher's burst and burns were invisible to the tool that verifies the checklist. The overlay draws the burst (the bounding square of the 96 u circle, labelled), a "burn" mark on each burned enemy, and "burning N" in the label. The burst stays a circle: the shape is the ADR's decision (the distance between centres), and the rectangle question is core, not presentation (left for the core's owner; BUILD.md says only "a small AoE").
- **L1.** Every enemy label is lifted above the health and poise bars (the cue lifts it further while it shows).
- **L2.** Resuming with F4 dropped no phase, so the first frame drew up to 0.6 of a tick backward at 144 Hz. Resuming now owes nothing: a tick is stepped at once and the frame draws forward.
- **L3.** The overlay collected 200 enemies' boxes on every display frame and scanned all pairs for repeated labels (5.5 ms). Boxes are cached per simulation, tick and view; the down-strike's pogo box that equals its strike box is labelled once where it is collected, so there is nothing to scan.
- **L4.** The overlay-purity test plays every fixture directory. Measured on a loaded machine: reading on every tick of all 390 fixtures took 3 min 18 s, so `combat`, `doors`, `presentation`, `tech` and `physics` are read on every tick (the state hashed on every tick in the first three, where task 6's reads are exercised), the rest every tenth tick and at the end; 41 s in all. Every fixture's end hash is compared.

**Task 6 round 2**
- **H1 (Harding).** Five parries 4 ticks apart drew five 0.55 white flashes in 17 ticks. A rolling window now caps bright full-screen effects at 3 in any 60 ticks whatever the priority (a second at 60 Hz; slow motion only stretches it). A refused flash leaves the parry's burst, shake and sound, and the enemy's outline cue. `five_parries_in_a_second` plays it: 5 parries, 3 flashes. The luminance of a flash frame was not re-measured; the cap is what keeps it under the rule's count.
- **M1 (slow in a freeze).** A running slow is moved to the held slot when a hitstop starts and runs after it: the second parry's flash is drawn one frame, and no slowed tick is a frozen one (`two_parries_in_a_slow`: parries on 53 and 68; before, three of the first parry's slow ticks were spent frozen). A chain of parries shows 3 slowed ticks, the freeze, then 6.
- **M2 (Flame bar).** The fill is the Flame the simulation holds, at once (the review's trace: bar 76, held 0, on the tick a spell fizzled). The ghost trails a spend (dim, above the fill) and leads a gain (bright), closing at the tuned rate; marks at the spells' costs make "can I cast" readable from the bar.
- **M3 (trails over the enemy).** The combat view now draws below the enemies, and the enemies' cues are a child layer above the VFX budget; the trails no longer cover the cue or the hit flash. The grey-box trail alpha is unchanged (it stacks under the body now).
- **L1.** At the cap, an arriving kill ember pulses the bar (the HUD takes the tick's events).
- **L2.** The HUD's flash follows the flash setting (scaled; an outline at 0).
- **L3.** Displacing a hit removes its whole group.
- **L4.** The synth has hit sounds for every `spark_variants` the tuning allows (3 to 5), and validation refuses more.
- **L5.** Every sound plays with +-3% pitch and has 3 variants; Mend's heal and Radiance have sounds of their own (a low rising pair, a broad bloom with a sub), so the parry's chime means a parry. They are still grey-box synthesis: the final sounds are Phase 2's.
- **L6.** The literals in the table above moved to `content/feedback.tres` with validation.
- **L7.** The player-facing HUD drew text with Godot's embedded font, which docs/LICENSES.md allows for the F3 overlay only. The HUD now draws no text (the Kindling tier is four pips). No other font is in the repository (`assets/fonts/` is empty). Proposal for Phase 2, not done: one OFL-1.1 face (Atkinson Hyperlegible, or Inter) vendored from its upstream release with an ADR and a LICENSES.md row, plus a dyslexia-friendly second face for the section 12 option. I did not download anything.
- **L8.** The enemy's overlay box is a 1 px line, so the 3 px white cue outline around the same rectangle shows as white on the F3 sheets. The cue bar greyed by the F3 text panel in zoomed film is the panel's shade, not the cue.
- **L9.** The finisher's slash arc is centred on the player with the reach to the struck enemy as radius, swept through the strike direction.
- **L10.** The budget's header no longer claims what did not exist. The cue layer is a child of the enemy view at z 1, above the budget (z 0), with the F3 overlay at z 100; `TELEGRAPH_PRIORITY` stays in the enum for the Phase 2 proc layer.

## How it plays now

A stair taken a lip a tick is climbed or descended at a steady speed with no speed change past a quarter of the nudge. Parrying five swings in a second flashes the screen three times and bursts five. A chain of parries has its freeze, then its slow. The Flame bar never shows Flame Ash does not have. The F3 overlay shows the parry, the lethal hit, the burst and the burn on the tick they happen. Every sound varies.

## Open questions for the director

- Look at: a parry chain in the stress of five swings (`five_parries_in_a_second`, with flashes at 100% and at 0%); the Flame bar through a spend and a gain; a walk down `test/lip_stairs` (Ash trails the treads by 20 u for ten ticks: is that acceptable until the Phase 2 rig plants the feet?).
- Listen for: the heal against the parry chime (Mend, then a parry), and Radiance's bloom; they are grey-box tones.
- Decide: the typeface for the shipped UI (see L7). Camera: `CameraSubject.respawned` for DEATH (camera's owner).
