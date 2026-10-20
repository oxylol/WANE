# ADR-0019: Zone 1's grey box gates the techs a room can gate and teaches the rest

- Status: Accepted
- Date: 2026-10-19
- BUILD.md sections: 5 (the twelve core tech interactions, "taught by the world, never by a tutorial pop-up"; "Taught by" means the cheapest route, not the only one), 3 (hidden rooms), 6 (Ember Toss 12 s cooldown), 15 (Movement checklist)
- Checklist lines: "Dash-jump keeps 100% of dash speed and clears the reference gap in zone 1 room 7"; "Pogo keeps full horizontal speed; a 10-bounce chain across the zone 1 spike pit is possible at 4 bounces per second"; "Pogo resets air dash; pogo, dash, pogo crosses the reference hidden-room gap"

## Summary

- Gated by controls (the only way across): rooms 02 dash-jump, 03 pogo, 07 coyote dash, 10 crouch-dash, 11 Ember-toss cancel, 12 Kindle-dash (see Decision 1).
- Gated except for a known cost: room 06 (no dash, no crossing, but a toss per crossing is not modelled) and room 05 (kicks beat the no-kick control; wall-jump plus up-dash is faster).
- Taught as the best way, not gated, because Phase 1 cannot: 01 dash-slash, 08 attack-cancel landing, 09 reverse pogo (see Decision 2).
- Room 04 (hidden alcove) is reachable by the Ember Toss waited out on a spike post: 2516 ticks against 7.5 s for pogo-dash (ADR-0016); the reward is no progress gate.
- Later content gates them: the boss with the short window (08), the shielded enemy (09), Snuffed in the pit (03), Snuffed beside wax (12); 01 has no gate yet (see Decision 3).
- The checklist's "zone 1 room 7" dash-jump gap is room 02 here; room 07 is the coyote dash (see Decision 4).
- The pogo pit needs at least 10 bounces (best chain 2.3 a second); the plain teaching chain does 20 at 4.6 a second (see Decision 5).
- Director questions are listed at the end (see Consequences).

## Context

BUILD.md section 5 says every tech is "taught by the world, never by a tutorial pop-up" and, after the review rounds, that "taught by" means the room makes the tech the cheapest route and a control fixture proves what single-use alternatives cannot do (ADR-0016). Twelve grey-box rooms in `content/rooms/zone1/` were reviewed one by one by fresh reviewers who tried to skip each tech. Several found routes that bypass the tech; fixers closed what geometry could close and wrote the rest into the room headers, the feel logs (`docs/feel_log/2026-10-19-zone1-*` and `*-room-*`) and `PROGRESS.md`. This ADR records the outcome room by room so the next phase knows which rooms to revisit when the missing content exists. The doc's older wording ("only a route with X crosses") was true of only some rooms.

## Decision

1. **Gated, proved by control fixtures.** Each control is a fixture in `tests/replay/zone1/` that spends every resource except the tech and fails to cross.
   - Room 02: the chasm is 1664 u, 62 u past the farthest route without a dash-jump (`tools/replay/gap_reach.gd`, held equal to `tests/replay/rooms/chasm.room` by `test_gap_reach_room.gd`).
   - Room 03: the farthest route without a pogo ends 672 u into a 5184 u tunnel (`03_control_no_pogo`); a ceiling 64 u above the spikes forbids arcing over. Nine bounces of the best chain end 329 u short (`zone1_03_control_nine_bounces`), ten cross.
   - Room 07: chasm B has its lip at x 1604. A dash read on the last floor tick (93 or 94) crosses a lip at 1590 or nearer; a coyote dash crosses 1622 at the best phase and 1604 with 6 to 10 plans per phase. The first version put the lip 14 u too near and a plain ground dash on tick 94 crossed (review H); the control now dashes on the correct tick. This is a search, not a proof.
   - Room 10: the gaps are 32 u under a 44 u body and run floor to ceiling; a standing dash stops at the face, crouching alone slides 13.5 u. A toss skips one gap, there are two, and the toss is on a 12 s cooldown, so the second needs a crouch-dash or a 720 tick wait. That last is the cost, not a closure.
   - Room 11: the chasm is 2400 u and needs a reach past 2390 u; dash-jump with every resource reaches 2243 u, with one toss thrown mid-air-dash 2505 u (ADR-0017). Proven by hand on `test/longchasm`, not on the real room.
   - Room 12: the wax screens run floor to ceiling and the pit below the door has spikes; without the Kindle Votive both hold (`12_no_kindle_screen_holds`, `12_no_kindle_door_holds`).
   - Room 06: without the dash the farthest crossing meets the far wall 69 u too low (`06_control_no_dash_crossing`); one toss carries a no-dash crossing to band 1 and the landing trick to band 2 (`06_control_no_dash_toss`, 74 u short of band 3). A toss waited out on a band between crossings is not modelled (ADR-0016).
   - Room 05: the no-kick control (`05_control_no_kick`) tops out 128 u short, but a wall-jump plus up-dash cycle climbs the same well 85 ticks sooner (`05_wall_jump_dash_cycle`). The kick is the plain way, not the only one.
2. **Taught, not gated, because Phase 1 cannot gate it.**
   - Room 01 dash-slash: the corridor dummies are solid so a run or a dash stops at the first; the dash-slash chain takes 358 ticks, running slashes 434 (a 72 tick margin, about 7 ticks per dummy). Dash alone and run alone never cross (`zone1_01_control_dash_only`, `zone1_01_control_run`), but plain slashing does, so the tech is the best way, not the only one. Weak enemies that cannot be out-slashed arrive with zone 1's real enemies.
   - Room 08 attack-cancel landing: the ambushing unparryable swing costs a heart for every plain alternative (no strike, a strike on or after the landing, waiting, one dash), but two dashes outrun a 24 f telegraph and cross with 5 hearts in 174 f against the teaching route's 210 (`08_gap_two_dashes`, a known-gap fixture).
   - Room 09 reverse pogo: a run and one jump clears the 64 u guard (`09_note_plain_jump_crosses`); any jump high enough to strike its head clears it, so no geometry gates the strike, and a no-dash reverse pogo also works (2 ticks of window against the dash route's 6). The dash is the forgiving way in (ADR-0010).
   - Room 04 hidden alcove: reachable with the Ember Toss waited out on a spike post (`04_bypass_toss_wait`, 2516 ticks), with no air dash after the approach. Pogo-dash takes 7.5 s. ADR-0016 holds the reasoning.
3. **What later content gates.** The boss with the short window closes room 08's gap (its door cannot be crossed by two dashes; the gap fixture becomes a control). The shielded enemy closes room 09 (the unshielded back is the reason for the tech; the room changes when it exists). Snuffed in the pit makes room 03 a pogo line of enemies as written in BUILD.md; Snuffed beside wax does the same for room 12's Kindle-dash. Room 01 is gated when a pack of weak enemies that a plain attacker cannot clear in the corridor's time exists; nothing in Phase 1 does. The hidden room of room 04 is not a progress gate (its reward is a Lantern-tier Votive or note, ADR-0016 Decision 3), so its bypass needs no later closure.
4. **The reference dash-jump gap is room 02.** Checklist line "clears the reference gap in zone 1 room 7" was written when the list was ordered differently; in this grey box room 02 holds the dash-jump gap and room 07 is the coyote dash. The checklist line is satisfied by room 02 (`tools/replay/gap_reach.gd` on `test/longchasm`, `zone1_02_*` fixtures). BUILD.md keeps the wording; `PROGRESS.md` maps it.
5. **The pogo pit against "10 bounces at 4 per second".** The best non-plain chain needs 10 bounces and does 2.3 a second (a stride of 26 frames spending the air dash and air jump on each); a search over strides of 22 to 32 frames found none better. The plain teaching chain does one down-strike per fall, a bounce every 13 frames or 4.6 a second, and takes 20 bounces (44 at run speed). So the checklist line holds as a count (at least 10 across the pit, 20 for the plain chain) and a rate (4.6 a second with the plain chain), not as one chain doing both. The pit was widened to 6208 u wide to make the count real.
6. **Headers are honest.** Every room header says which of these it is, names its controls and bypass fixtures, and says what is not modelled. A claim of "the only way" appears only where a control backs it.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Gate every tech with geometry no matter what | Rooms 01, 08 and 09 cannot be gated by static geometry and dummies: a dash outruns a telegraph, a jump over a 64 u guard clears it, a corridor of dummies is crossed by plain slashes. Tuning them to fake it makes them timing tests that no longer teach. |
| Add core rules to close bypasses (pause the toss cooldown off the ground, change the wall-jump restore) | Changes BUILD.md section 6 and the wall-jump row, and would break rooms 05 and 06 (ADR-0016). Not a room-design problem. |
| Tutorial pop-ups for the techs that cannot be gated | Forbidden by BUILD.md section 5. |
| Cut rooms 01, 08 and 09 until the content exists | The twelve-room sequence is the Phase 1 gate; each room still teaches the tech as the cheapest or most forgiving route and carries its control fixtures. |

## Feel reason

Movement: a tech that is the cheapest route and sometimes the only one is learned by feel, not by instruction. A room that falsely claimed to require a tech would punish players who found a legitimate faster line; one that is honest lets them. The rooms with a heart at stake (08) or a long fall (03, 07, 11) keep the stakes, so the tech is still the answer worth reaching for.

## Consequences

- When the boss (08), the shielded enemy (09), Snuffed (03, 12) and the weak-enemy pack (01) exist, revisit those rooms, turn the known-gap fixtures into controls, and update their headers.
- Known-gap and bypass fixtures (`08_gap_two_dashes`, `09_note_plain_jump_crosses`, `04_bypass_toss_wait`, `05_wall_jump_dash_cycle`) record costs; a change that closes or widens one is seen. The 10-bounce bound and the coyote lip rest on searches, not proofs.
- Director questions the fixers raised:
  1. Accept "taught, not enforced" for rooms 01, 08, 09, 04 until the content exists, or add a core rule? (Room 08's two-dash gap; the toss wait in room 04; room 05's wall-jump cycle.)
  2. Reverse pogo without a dash works because a bounce keeps full horizontal speed (BUILD.md); keep that as a second way or make the bounce keep less?
  3. Room 11: reset the toss cooldown on send-back, or show a HUD readout sooner, since a toss spent in the dip or on a failed throw locks the chasm for 12 s? Does "teleport after landing" in BUILD.md tech 11 mean the literal reading, or the mid-air teleport the room teaches (ADR-0017)?
  4. Room 03: is the checklist's 10 bounces at 4 a second satisfied by a count and a rate on different chains? Is the 72 tick margin in room 01 enough?
  5. Room 07: the window is narrow (6 to 10 plans per phase at the lip); play it. The Ember Toss is unsearched there.
  6. Room 10: the landing after a second dash is 51 u short of the pit (5 to 6 ticks of held run); lengthen? A toss from B's face at tick 12 crouches Ash into the wall again, easy to mistime.
  7. Solid dummies and the ambush `trigger` are core options; `Simulation.VERSION` was not bumped, since no existing behaviour changed. Bump and re-bless the goldens?
  8. Reviewer sign-off: some fixers could not spawn a fresh reviewer; rooms 10 and 11 were not re-reviewed independently.
