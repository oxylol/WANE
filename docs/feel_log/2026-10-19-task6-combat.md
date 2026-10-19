# 2026-10-19: Phase 1 task 6, the Taper's hits, Flame, Kindling, parry, spells and hit feedback

- Author: Claude
- BUILD.md section and table row: section 6, every table (the Taper, Flame, Kindling, Parry, Spells, Hit feedback, Enemy-side rules); section 5, Pogo ("on hitting an enemy"); section 15, Combat (every line Phase 1 can check) and Graphics and feel, "Screen shake at default 50% never moves the frame more than 3 units".
- Fixture(s): `tests/replay/combat/` (24 fixtures: the Taper's frames and Flame on the dummy, the chain's rising weight, a dash out of hitstop, the parry window's first and last frame and the frame before it, the red swing, the player hit's knockback and invulnerability, the kill ember, the pogo off an enemy, Kindle's reach, Flame and cancel, Mend's heal, its loss and its chain, Radiance at Blaze and below it, the Charged strike and its hold, White's dash, a hazard's heart, death); `tests/unit/core/combat/` (the rules that need a loop: ten parries in a row, the window frame by frame, White's tenth hit, Blaze's trail and burst, the cone's rectangles, Mend's conditions, the dash through a swing, the knockback ended by an action, a kill on the landing tick); `tests/unit/game/test_combat_presentation.gd`.
- Contact sheet: `docs/feel_log/2026-10-19-task6-combat.png`, filmed by `tools/replay/film.gd --overlay on` through the game's own views (room, enemies, combat's objects and hit feedback, player, HUD, camera). Each frame is half the screen with the world magnified twice around Ash; the HUD (hearts, the Flame bar, Kindling) is top left and the F3 text below it.
  - The overlay's combat colours: violet, each enemy's box with its state, health and poise; white or red, filled, a live swing; orange, filled, a strike or Kindle's cone; dark orange, Blaze's trails; the kill ember an orange square.
  - Rows:
    1. the chain, every frame from 8: side 2 lands on frame 9 (2 f of hitstop: frames 10 and 11 hold), side 3 starts on 14 and lands on 17 with 4 f of hitstop and the dummy's poise breaking (it slumps, "stagger");
    2. the parry, every frame from 50: the press on 46 is in the window, the swing lands on 53, the flash shows the frame through it, the dummy staggers and both hold 12 frames;
    3. the player hit, every other frame from 51: the swing lands on 53, the vignette pulses, Ash holds 8 frames and is pushed 60 u away from 62 to 73, "invulnerable" throughout;
    4. the kill, every other frame: side 1 kills the 10 hp dummy on frame 2 and its ember flies to Ash, arriving on 18 (the Flame bar's flash);
    5. Kindle, every frame from 1: the cone's three widening rectangles from frame 4 reach the dummy 170 u away;
    6. the pogo off the dummy, every frame: the bounce on frame 2, 2 f of hitstop, then the rise;
    7. Radiance at Blaze, every frame from 2: the burst on frame 6 (the flash and the ring), the dummy pushed away;
    8. the Charged strike, every frame from 29: the hold let go on 31, "charged" from 31, its box on 34 with 6 f of hitstop and the dummy staggered;
    9. Mend, every sixth frame: the green channel bar rising beside Ash, the heart back on frame 49;
    10. the red swing, every third frame from 29: the red outline and rising bar of its telegraph, then the hit on 53 a press in the window did not parry.

## Change

First implementation of combat. One number was tuned on the contact sheet:

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| `flash_alpha` (`content/feedback.tres`) | 1.0 (first value, never committed) | 0.55 | opacity |

The values BUILD.md does not give are set here for the first time (docs/adr/0013 says why each rule is what it is):

| Number | Value | Unit | Where |
| --- | --- | --- | --- |
| A kill's ember: Flame granted on arrival, flight time | 11, 16 | Flame, frames | `content/combat/combat.tres` |
| Blaze's trail damage (each strike's trail burns an enemy once) | 4 | damage | same |
| A Blaze finisher's burst: radius, damage | 96, 8 | units, damage | same |
| The finisher's launch on light enemies | 600 | u/s up | same |
| How fast an enemy's knockback bleeds off | 2400 | u/s² | same |
| The player hit's knockback: frames the stick's sideways push is held off | 12 | frames | same |
| What a hazard costs | 1 | heart | same |
| Kindle's cone: sections, near and far width | 3, 40, 96 | -, units | `content/wicks/ash/kit.tres` |
| Kindle's burn: length, period, damage | 90, 15, 2 | frames, frames, damage | same |
| Radiance's recovery | 12 | frames | same |
| The training dummy: size, health, poise, swing (telegraph, active, recovery, reach), respawn | 32 x 64, 200, 30, (24, 4, 20, 64 x 48), 60 | units, -, -, frames and units, frames | `content/enemies/dummy.tres`, `core/enemies/training_dummy.gd` |
| The red vignette when the player is hit | 20 | frames | `content/feedback.tres` |

## Why

- **The flash.** BUILD.md asks for a "full-screen white flash 1 f" on a parry; at full opacity that one frame was solid white on the contact sheet, and the parried swing, the dummy's stagger and Ash all vanished on the very frame the parry is read. At 0.55 the flash is unmistakable and the frame shows through it. The accessibility setting still scales it to 0 (section 15, "with flashes set to 0").
- **The kill ember** flies in 16 frames, inside section 15's 20, on a smoothstep toward wherever the player is, so it can never miss; 11 Flame is a Taper hit's worth.
- **The knockback.** 300 u/s is 5 u a tick. As a plain velocity the stick overrode it on the next tick and a hit read as nothing; held for 12 frames after the 8 f of hitstop it carries Ash 60 u away, a clear "you were hit", and any action (a dash, a jump, a strike, a toss) ends it at once, so no input waits on it (CLAUDE.md rule 3).
- **Hazards cost a heart.** A spike that only sends you back makes the pogo pits of techs 3 and 4 free to fail.
- **Kindle's cone** is three rectangles (CLAUDE.md rule 8) widening 40, 68, 96 u along its 180 u: wide enough at the far end to read as a cone and to reach a dummy 170 u away, and no wider than the Taper's box near Ash.
- **The burn** (2 every 15 f for 90 f, 12 in all) is a third of Kindle's hit again: the "ignites" reads, and Kindle stays a single strong hit.
- **The dummy** is the Taper's test bench: 200 health takes a dozen chains to kill, so the chain, the finisher's knockback and the poise break (30: three 10-damage hits) can be practised on it; its swing telegraphs 24 frames (over section 6's 20) and reaches 64 u from its centre: Ash striking from the far edge of the Taper's reach (68 u from Ash's centre, up to 84 u between their centres) stands outside it, and Ash standing close does not, so spacing matters even against the dummy.

## How it plays now

- The Taper's box is live on frame 3 from a neutral press, every time; on the dummy, side 1, side 2 and side 3 land 2, 2 and 4 frames of hitstop and the third breaks its poise (`side1_hits_dummy_once`, `chain_rising_weight`).
- A press made during hitstop fires on the first free frame: a dash pressed in side 1's hitstop comes out on side 1's frame 4 (`dash_out_of_hitstop`).
- A parry is an attack press in the 8 frames that end on the swing's landing, in any direction; the frame before is a hit (`parry_window_*`); ten parries in a row succeed (`test_a_parry_succeeds_ten_times_in_a_row`). A red swing is never parried.
- A hit on Ash freezes Ash 8 frames, pushes Ash 60 u away over the next 12 and gives 20 frames of invulnerability; the red vignette pulses and the shake runs along the hit.
- A kill's ember reaches Ash 16 frames later and the Flame bar flashes.
- Kindle reaches 180 u; Mend heals after 50 frames held still and loses the Flame if let go; Radiance pushes every enemy away at Blaze; holding attack 24 frames and letting go strikes Charged.
- F3 shows each enemy's box with its state, health, poise and how many frames until its swing lands, the swing's box (white, or red for unparryable), Kindle's cone and the fire trails, and a line of hearts, Flame, Kindling, spell, hitstop and knockback.

## What the contact sheet shows, and what it does not

Checked against BUILD.md section 6 and section 10's readability rules, frame by frame:
- Every number on the sheet matches its row: the hitstop counts in the F3 text, the frames boxes are live, the dummy's health after each hit (side 2 to 180, side 3 to 164, the Charged strike from 190 to 154).
- The parry frame reads through the flash (tuned for that, above). The player-hit frame is unmistakable: the vignette, the hearts, the shake and the knockback all fire on it.
- The white and red telegraphs differ by an outline and a raised bar in their colour (and, since the review pass, by shape: the red cue's bar is saw-toothed and its outline jagged, row 10; the sheet is filmed with every review fix), so they read with flashes at 0. The dummy's health bar was red and sat where the telegraph's bar rises; it is now tan, so red only ever means "unparryable".
- Grey boxes cannot show weight. The chain's rising weight is only in its numbers here (2, 2 and 4 frames of hitstop, the finisher's shake): the art pass (smears, the slash arc) and the sound pass carry it. The checklist line stays partial until then.
- The camera's focus dot (yellow) often sits inside the dummy on these sheets; it is the overlay's camera mark, not a hit spark.

## Review pass: presentation findings (same day)

A reviewer who had not seen the work found presentation defects. Each was fixed with a test that fails without the fix (`tests/unit/game/test_feedback_budget.gd`, `test_combat_presentation.gd`, `test_hud_and_enemy_view.gd`, `test_sim_driver_slow_motion.gd`). The sheet `docs/feel_log/2026-10-19-task6-presentation-review.png` is filmed with the fixes (F3 on, world magnified): row 1 the chain's finisher from frame 14, row 2 the red swing every third frame from 32, row 3 the parry from frame 49.

| What | Before | After |
| --- | --- | --- |
| Finisher feedback in the VFX budget | the hit's spark took the cell; the slash arc and the burst were refused (kept: the spark alone, refused 2) | one hit is one group in the budget: spark, arc and burst all draw (row 1, frames 17 to 21: the grey arc, the orange burst ring and the sparks); the Charged hit's burst and the stagger burst too |
| A burn beside a Taper hit | the burn's spark (same priority) could take the cell and the Taper's was refused | burns rank below the Taper's and spells' (`VfxBudget.BURN`), in either event order |
| Radiance's ring | drawn by the combat view, outside the budget, on top of the budget's own burst | a `RING` effect in the budget, grouped with the burst, 18 ticks and 640 u from `content/feedback.tres`; the burst and ring outrank a spark in their cell |
| Full-screen flash, chromatic split | drawn straight from counters | admitted by the budget: one bright screen effect per 3 ticks (`vfx_screen_frames`); the overlay draws what it admitted |
| Effects' first frame | aged once before the first draw (a 6 tick spark drew on 5 ticks, from age 1) | the feedback ages the budget first: drawn from age 0, whole lifetime (spark 6, burst 9, smear 5) |
| Flash setting | below 50% the 1 tick flashes vanished (`roundi(1 * scale)`) | 1 tick at any setting above 0, the setting scales the opacity (the split's too); 0 draws nothing |
| The enemy's hit flash | a literal 2 in `enemy_view.gd`, ignoring the tuning and the setting | `enemy_flash_frames` blended to white by the setting; at 0% a cyan outline instead of a flash |
| Parry slow motion | the 6 slow ticks ran inside the 12 f of hitstop, where nothing moves | the driver holds the slow until the player's freeze ends: slowed ticks are the six after the freeze (`test_the_parrys_slow_ticks_are_ticks_where_things_move`) |
| Telegraph sound | on the telegraph's first tick: 24 f before the hit (26 if struck) | on the core's cue: exactly 20 ticks before the swing lands, for 11 strike times against both swings, `landing - cue == 20` every time |
| The red cue's shape | the same bar and outline as white, only the colour differed | a saw-toothed bar and a jagged outline (row 2), white stays plain; the cue stays through the landing frame (last frame of the parry window) and the live swing keeps its colour and outline |
| Spark tint | the tier after the hit (the 8th hit, Ember damage, showed orange) | the tier the hit's damage used (carried in the hit event) |
| F3 | "lands in N" ignored the enemy's hitstop; a corpse drew a full hurtbox; the label sat under the rising bar | N counts hitstop (`Enemy.ticks_to_landing`); a dead enemy is a dim outline labelled dead; the label is drawn above the bar's highest point |
| HUD Flame bar | flashed 11 ticks, not the 12 of its constant | flashes 12 ticks, counting the tick of the gain |

New numbers, all in `content/feedback.tres`: `vfx_screen_frames` 3 (the cell rule's window, applied to the screen), `radiance_ring_frames` 18 and `radiance_ring_radius_u` 640 (were literals in the combat view). Nothing in the simulation changed; no golden hash moved.

What the new sheet does not show: the flash and the chromatic split (not in the filmed frames except the parry flash on row 3, frame 53, which reads through at 0.55), the 0.5x slow motion (a driver timing, checked by test, not by a still), and the sounds. Listen for: the telegraph cue 20 frames before a swing lands, and a parry's slow motion starting after the freeze.

## Review pass: core findings (same day)

The same review's core findings, each pinned by a fixture in `tests/replay/combat/` that fails on the code before the fix. Golden hashes moved (`Simulation.VERSION` 6).

| Finding | Before | After |
| --- | --- | --- |
| H1: damage that is not a hit | a burn tick, a Blaze trail or the AoE set the enemy's knockback to 0: at Blaze and White every strike lost its knockback (side 1 left the dummy where it stood) | it takes health and poise only (`blaze_strike_keeps_knockback`, `burn_tick_keeps_knockback`) |
| H2: Blaze trails of two strikes | took turns and burned the enemy every tick: a two-hit chain dealt 94 damage instead of 34 | each strike's trails burn each enemy once (`blaze_chain_trails_burn_once`) |
| H3: Radiance's burst | lost if any action fired on its burst frame, the 66 Flame spent | the burst is decided at its frame and lands whatever else fires (`radiance_bursts_with_a_dash_on_its_burst_frame`) |
| H4: one press, many parries | one attack press parried every white swing landing during the parry's 12 f hitstop | a parry spends every press in the ring; a press made during the hitstop is a fresh one (`one_press_parries_once`) |
| H5: corpses | frozen where they died, hanging in the air; the respawned dummy leapt with its stored launch | a corpse carries its knockback and falls; the dummy comes back at its marker at rest (`corpse_carries_momentum`, `corpse_falls_and_respawns_at_its_marker`) |
| H6: leaving Mend | the frame Mend ended ignored the stick: no turn, no run, a jump out with no sideways speed | the stick acts on that frame (`mend_let_go_turns_and_runs_at_once`, `mend_ended_by_a_jump_keeps_the_stick`) |
| M1: a spell during the hit's knockback | did not end it; Mend channelled while sliding 64 u | a spell ends it, and Ash stops where Mend starts (`a_spell_ends_the_hit_knockback`, `mend_ends_the_hit_knockback`) |
| M2: a spell pressed during Mend | ignored, then dropped | it ends the channel and casts (`a_spell_ends_mend`) |
| M4: a Charged strike that waits its turn | went the way the stick pointed when it started | goes the way it was let go (`charged_strike_goes_the_way_it_was_let_go`) |
| M6: a spell pressed with too little Flame | ended the dash on its frame 6, cutting its distance and invulnerability | a fizzle leaves the dash alone (`a_fizzle_leaves_the_dash_alone`) |
| M7: Kindle over the room's origin | hit dead enemies again, for another ember, Flame and Kindling each time | the dead are skipped in every hit loop (`kindle_never_hits_a_corpse`) |
| L1: a re-press while attack is held | kept the Charged strike's hold | a press starts a new hold (`a_repress_breaks_the_charge_hold`) |
| L2: content validation | accepted a parry window the input ring cannot hold | the window must be 1 to 9 frames, the cue 1 to the shortest telegraph |
| The telegraph cue (presentation M4's core half) | none: the sound keyed off the telegraph's first tick | `SimEvents.TELEGRAPH_CUE`, sent the tick the swing lands in exactly 20 ticks, hitstop or not (`telegraph_cue_twenty_before_the_hit`, `telegraph_cue_keeps_its_word_through_hitstop`, `telegraph_cue_waits_for_hitstop_before_it`) |
| A kill by a burn (presentation M1) | no kill hitstop, though the presentation shook for the kill | the Kill row's 3 f of hitstop on both (`a_kill_by_burn_stops_time`) |

Two findings were checked and kept as designed, for the director: M3 (a spell pressed early in a strike ages out of its 8 f buffer, as a jump pressed early in a dash does) and M5 (the 20 f of invulnerability counts after the hit's 8 f of hitstop: BUILD.md now says so). See ADR-0013.

**Speed.** Combat made every simulation tick about 35% slower, even in rooms with no enemy (the fixture suite went from 7.6 s to 10.3 s on the same 328 fixtures, over its 10 s budget). Profiled: each input-buffer query cost about 4 us (an assert formatting its message on every call, and a scan of the ring), and combat added several per tick; the Charged strike was looked up by name every tick. The ring now keeps a mask of every button pressed in it, so a query for a button with no press answers at once, the player looks its Charged and down strikes up once, and Kindle's and the pogo's checks skip a room with no enemy. A tick of a movement fixture went from 87 to 68 us (57 before combat). The suite's own costs came down too: a player probe built a table of all 45 values (two of them hitbox queries) to return one, and the content digest asked each resource for its whole property list on every simulation built; a probe now computes only its value, and each script's variable names are listed once (the digest's bytes are unchanged). The suite runs 378 fixtures in 7.9 to 8.3 s. The state hashes of every fixture are identical before and after.

## Open questions for the director

- Play the sandbox's dummies (the first stands, the second swings white every second, the third red): does the chain feel like three rising impacts with grey boxes and placeholder sounds? The weight is in the numbers (2, 2, 4 frames of hitstop, the finisher's shake); the art and sound pass will carry most of it.
- The 12-frame knockback after a hit, and whether a hazard should cost a heart.
- The Charged strike asks for a hold you let go of; a release that waits 8 frames for the strike layer to be free. Does the release feel late?
- Mend stands Ash still for 50 frames. Should a walk interrupt it rather than be ignored?
- The kill ember's 11 Flame.
