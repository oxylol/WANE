# 2026-10-19: Movement review 6 and task 6 core review 2, core fixes

- Author: Claude
- BUILD.md section and table row: section 5 (feel rules: "No move has more than 2 frames of startup unless it has armor"; Pogo, "chains are infinite with rhythm"; landing and wall rules), section 6 (Taper side 1 "player recoils 60 u/s", Charged, Kindle "cancelable from f 8", Player hit "any action ends it", "20 f of invulnerability after the hitstop"); docs/adr/0010, docs/adr/0013.
- Fixture(s): 22 in all (20 from the first pass, 2 from the follow-up review F1 and F2) in `tests/replay/combat/` and `tests/replay/movement/` (each fails on the code before the fix), rooms `dummy_swing_behind` and `dummy_swing_wall`; `tests/unit/core/combat/test_training_dummy.gd`.
- Contact sheet: `docs/feel_log/2026-10-19-rr3-core-fixes.png`: `side1_recoil_moves_the_player` filmed from frame 2, every second frame with the F3 overlay: Ash (cyan) stands still through the hitstop, then is carried away from the dummy; before, the gap never opened.

## Change

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| `recoil_frames` (new, `content/combat/combat.tres`) | none (a speed erased on the first free tick) | 8 | frames |
| `armor_frames` (new, side 3 and Charged, `taper.tres`) | none | 3 | frames |
| Player hit invulnerability, free frames covered | 19 | 20 (counter set to 21 on the hit tick) | frames |
| `DummyDef.respawn_frames`, `swing_period` (moved from literals in core) | 60, 90 in code | 60, 90 in `content/enemies/dummy.tres` | frames |

## Why

Thirteen confirmed findings. Fixed at the root, each pinned by a fixture:
- Pogo (movement H1): a hold whose press began an up- or down-strike never arms the Charged strike (`charge_broken`), so holding attack through a pogo chain no longer eats the next pogo. Rule recorded in ADR-0013. `pogo_chain_window` now expects no Charged strike through frame 49.
- Armor (H2): side 3 and the Charged strike keep going through a hit on their 3 startup frames: hearts, Kindling and hitstop are paid, there is no knockback and no interrupt. Content refuses a startup over 2 f without armor.
- Knockback (movement M1, core H1): `PlayerCombat.after_actions` runs again after the move, so a jump, dash or strike fired by a landing or a cling ends the knockback.
- Landing jump then dash (M2): the dash takes the jump's first rise before it starts; the `jump_fresh` flag is cleared wherever the rise is replaced, so it no longer skips a later tick of gravity.
- Wall (M3): Charged and Kindle on the tick of reaching a wall go away from it (`PlayerWall.met`). Probe keys `spell_dir_x` and `spell_dir_y` added.
- Kindle hold (movement L1, core M1): a buffered jump at a landing or cling waits out Kindle frames 1 to 7.
- Recoil (core H2): a push carried for 8 f after the hitstop, on top of the run, ended by a dash, cling, hit, Mend, death or send-back. 8 u in all.
- Invulnerability (core H3): covers 20 free frames, 28 world ticks from the hit.
- Mend (core M2): a press up to 8 f before a landing starts on the landing frame.
- Death and hazard (core M3): break an attack hold; the Charged strike needs a fresh press.
- Dummy numbers (core L2): moved into a `DummyDef` content resource.

## How it plays now

Holding attack through pogos keeps the chain; a hit on a finisher's startup does not lose it; a buffered landing jump after a hit steers at once; side 1 pushes Ash off the dummy by 8 u. A death by an enemy's hit sends `SimEvents.DEATH` (after `PLAYER_HIT`, in combat's resolve): x and y are where the player died (sub-pixels, before the send-back), value 0. Presentation can read it with no core change.

Committed fixtures whose path moved (per-tick probe values compared before and after; every expectation still met unless listed):
- Side 1's recoil moves Ash after a side 1 hit (x and vx): `blaze_chain_trails_burn_once`, `blaze_strike_keeps_knockback`, `burn_tick_keeps_knockback`, `chain_rising_weight`, `charged_strike_after_a_24_frame_hold`, `charged_strike_needs_the_whole_hold`, `corpse_carries_momentum`, `corpse_falls_and_respawns_at_its_marker`, `dash_out_of_hitstop`, `door_enemies_belong_to_their_room`, `door_kill_ember_in_flight_reaches_ash`, `kill_ember_reaches_the_player`, `kindle_never_hits_a_corpse`, `side1_hits_dummy_once`.
- The recoil carried Ash out of the dummy's swing reach, so the fixture's player starts 12 u closer (`spawn 212 544`; intent unchanged): `telegraph_cue_keeps_its_word_through_hitstop`, `telegraph_cue_waits_for_hitstop_before_it`.
- The invulnerability counter reads 21 on the hit tick (the probe `invuln_frames` only): `a_spell_ends_the_hit_knockback`, `mend_ends_the_hit_knockback`, `one_press_parries_once`, `parry_window_too_early`, `red_swing_is_never_parried`, `telegraph_cue_twenty_before_the_hit`, `player_hit_knockback_and_invulnerability` (expectation now 21, and the 20-frame window is pinned by `invulnerability_covers_twenty_free_frames`).
- `pogo_chain_window`: no Charged strike from frame 41 (the old path fired one from the pogo hold).

`Simulation.VERSION` 8 to 9, golden hashes re-blessed: the state hash gained the recoil and `charge_broken`, and the content hash the new fields.

## Open questions for the director

- Side 1's recoil is only 8 u (60 u/s for 8 f). Play the training dummy at close range: if it should read stronger, raise `recoil_frames` or the strike's recoil.
- Armor on a hit: the hit still freezes Ash for 8 f but does not push him; decide whether an armored hit should skip the hitstop as well.
- Follow-up review (F1, F2): `Simulation.VERSION` 10; 15 existing fixtures' hashes moved (the hazard's invulnerability is hashed) and were re-blessed with the 2 new ones; no expectation changed.
