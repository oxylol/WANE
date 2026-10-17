# 2026-10-17: Phase 1 task 2, the physics sweep

- Author: Claude
- BUILD.md section and table row: s5 Ground ("Slope handling: up to 45 degrees, speed unchanged; no sliding on slopes", "Corner correction: horizontal 8 u nudge over ledge corners; vertical 6 u nudge around ceiling corners", "Crouch: drops through one-way platforms"), s5 Wall ("A ledge-grab is automatic within 10 u of a wall's top"), s5 feel rules ("The player never clips a corner they visually cleared"), s13 (the AABB physics sweep; frame budget)
- Fixture(s): `tests/replay/physics/`:
  - `crouch_hop_low_ceiling` (task 3 review M8);
  - from the third physics review: `air_dash_into_ramp_crest`, `air_dash_up_45_ramp_rows`, `air_dash_up_1to2_ramp_rows`, `land_across_ramp_rows_walks_on`, `land_across_ramp_rows_walks_back`, `walk_back_up_ramp_over_sunk_box` and `walk_steps_up_small_lips`;
  - from the fourth: `walk_steps_down_small_lips`, `dash_jump_from_box_a_lip` (and its control `dash_jump_flat_control`), `walk_up_ramp45_onto_door_at_crest`, `walk_up_ramp45_onto_lip_past_crest`, `walk_up_ramp45_onto_lip_far_past_crest`, `walk_up_ramp12_onto_lip_at_crest`, `dash_up_ramp_onto_door_at_crest`, `dash_ride_reaches_walk_stop`, `far_edge_landing_lands` and `far_edge_touch_then_ground_jump`;
  - from the fifth: `walk_down_ramp45_off_door_stays_grounded`, `walk_down_ramp12_off_lip_stays_grounded`, `walk_down_ramp45_over_sunk_door` (and `walk_up_ramp45_over_sunk_door`), `dash_jump_down_ramp45_off_door` (and its control `dash_jump_down_ramp45_control`), `down_dash_lands_on_ledge_far_corner`, `down_dash_from_midair_lands_on_ledge_far_edge`, `fall_toward_raised_step_lands_on_top`, `far_edge_landing_buffered_jump_keeps_stride`, `air_dash_rides_ramp_onto_crest_lip`, `air_dash_lifts_onto_two_lips`, `oneway_lip_step_down_then_drop` and `oneway_lip_crouch_slide_down`.

  `tests/unit/core/physics/` holds a unit test per row, a regression per review finding (the door on a ramp and the crest landing also run as real-player traces in `tests/unit/core/fsm/test_player_on_physics.gd`) and the randomised invariants. Every task 3 movement fixture runs on this sweep.
- Contact sheet: `docs/feel_log/2026-10-17-task2-physics.png`, drawn by `tools/replay/physics_sheet.gd`. Every drop falls a tick at a time. The tool fails if a panel's box does not end where the panel says it does, or starts inside anything solid (panels 4 and 5 did, until the fourth review). Panels:
  1. walking a ground of crests, peaks and a valley at run speed, there and back;
  2. a box dropped from rest at every 12 u across the same ground;
  3. a level dash (20 u a tick, as an air dash moves) into the foot of a ramp two tile rows tall: it rides up both rows and onto the plateau, 20 u every tick (every tick's box is drawn);
  4. falling past a ledge corner;
  5. a dash under two ceiling corners and a jump beside one;
  6. crouch-drop through a one-way, refused beside a wall;
  7. walking up a ramp to a closed door and back down;
  8. walking along a solid box's top onto the slope that rises out of it, and back;
  9. a solid box sunk into a ramp 4 u under its crest: walking down onto it and back up onto the plateau;
  10. walking over lips: a floor 1 u below the tiles beside it and a box 8 u proud of the floor are stepped up; a box 9 u above that stops the walk; walking back, every lip is stepped down on the ground;
  11. the player's hop off a ledge's far edge (the fixture `far_edge_landing_lands`, played through the simulation): the box comes down on the very edge, lands where its straight path meets the ledge (drawn green), then walks the rest of the tick off it. The fifth review found the earlier panel showed an ordinary landing 12 u onto the ledge; the tool now fails unless the landing tick ends off the ledge's end.

## Change

No BUILD.md number changed. BUILD.md's ground corner correction (8 u) now also applies to walking, as a step up onto a lip and a step down off one; the ground table's note says so. One number is new, a world value that is not in BUILD.md:

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Spike hazard inset (`content/physics/world.tres`) | a literal in code | 12 | units below the spike tile's top |

## Why

- **Spike inset.** The spikes are drawn in the lower part of the tile, so touching the top of the tile should not hurt. 12 u also gives the down-strike's 24 u pogo box (BUILD.md s5) 12 u of reach into the spikes' tile before the hurtbox, which sits 2 u above the feet, can touch them. The number was a literal in code, which CLAUDE.md rule 6 forbids; it now lives in content, and a world nobody has tuned starts with the content schema's default instead of 0.
- **Crests.** A box that lands beside a crest now rests on the ramp under its centre, with its corner in the plateau, exactly where walking would have put it (panel 2).
  - The first version held it on the plateau's edge, hovering up to 10 u above the ramp, and the next step down flew off the ramp.
  - The second version fixed this only for a fall that reached the ramp within one tick. A real fall often reached the plateau's edge first and still hovered, and running down then left the ground for 9 frames.
  - The same holds after a corner lift onto a plateau's edge.
- **Doors and ramps.** A solid box behind the player, over its head or under its feet no longer stops a walk on a slope. A player who walked up a ramp to a closed door used to be stuck there; it now walks back down (panel 7). A slope that rises out of a solid box's top takes over where it reaches the player's feet (panel 8).
- **Nothing hidden catches the player.** Slopes cannot show a vertical face or an underside: room validation refuses them. Corner corrections are checked against slopes and one-ways, so a dash next to a ramp or under a ceiling corner never ends inside anything (panels 3 to 5).
- **Ceiling corners off a slope.** Jumping off a ramp with a ceiling corner over the head now slides round it like any other jump. It used to bump, and the jump died.
- **Crouched hops.** A crouched body hopping under a 32 u ceiling is no longer stopped in open air by a wall that is not there (task 3 review M8). Whether a crouched hop may move sideways is a player rule, for task 3.
- **Ramps at dash speed** (third review, H1). The first panel 3 was captioned "a dash into the foot of a ramp rides up onto it". It actually showed the dash parked below the crest, its last six positions on top of one another, and that went unnoticed. A level air dash that touched a ramp was stopped by the crest's wall for the rest of the dash, and on a ramp several rows tall at every row boundary. The crest only stops the upper body now, as it always did for walking, and a dash keeps its 20 u a tick up any ramp (panel 3). Once an air dash has touched down it walks the ground like a ground dash, following a ramp down as well as up (ADR-0010).
- **Landings on long ramps** (H2). A landing that rode up across a tile-row boundary of a 1:2 ramp ended with the foot point inside the slope above, and the player was stuck until they jumped. The ride-up reads the row it rises into.
- **Doors sunk into ramps** (M1). Walking down onto a solid box sunk into a ramp near its crest, the player could not walk back up; the crest's wall stopped the level walk along the box. A box laid 1 u below the tiles beside it stopped a walk dead. Both now walk on (panels 9 and 10): the second by the ground corner correction.
- **A dash under a low ceiling up a ramp** rides up as far as the ceiling allows, where a walk would stop, instead of stopping where its foot first met the slope.
- **Drop-through** works only where one-ways alone hold the player up (panel 6), now including beside a ramp's low side.
- **Stepping down a lip** (fourth review, H1). The step up had no way back: walking off a door left a few units proud of the tiles was a fall with a landing on the far side, and a ground dash off the tiles onto a floor 1 u lower floated over it, so a jump on dash frame 9 had run out of coyote time and came out as the air jump. A walk now steps down onto a floor at most 8 u below and stays on the ground, so the dash-jump off it is a dash-jump (panel 10).
- **Lips at a ramp's crest** (H2). A lip was measured from the feet, which on a ramp are below the floor at the box's leading edge by up to 10 u, so a door lying 1 u proud of a plateau from its crest made the ramp impassable. It is measured from the floor at the leading edge now.
- **The far edge of a ledge** (H3). A hop that came down on a ledge's far edge, moving away from it, was carried past the edge before the fall reached it (the air step moves across, then down), and the next jump was the air jump. Such a fall now lands where its path meets the ledge and walks off it with coyote time (panel 11). "Landing on a 1-pixel ledge edge lands" now holds from both sides.
- **Stepping down off a lip onto a slope** (fifth review, H1). The fourth review's step down counted the drop from the feet at the box's centre while the step up counted from the floor at its leading edge. Walking down off the end of a door on a 45-degree ramp, the ramp under the centre is already 10 u lower than under the trailing edge, so every such step was a flight down the rest of the ramp (in 108 of 600 random ramp lips the walk up stayed on the ground and the walk back down left it), and a dash-jump off a door at a crest came out as the air jump. The step down now counts from the floor under the trailing edge, mirroring the step up; over every lip the walk is on the ground both ways.
- **The diagonal dash and the far edge** (H2). A dash down-right past a ledge's far corner still moved across, then down, and passed through the corner in 39% of the cases where its straight path stood on the ledge. It now touches down there as a fall does (the air jump and dash come back) and runs on along the floor.
- **The near side of a raised step** (M1). The far-edge landing also caught a box falling toward a block on a floor within a tick's fall: moving across first lands it on the block, but it landed on the floor in front, 18 u lower, stopped against the block's face. The far-edge path now applies only when moving across would carry the box off the floor or onto a lower one.
- **A buffered jump on a far-edge landing** (M2) took off from the touch-down point, up to a tick's step (8.7 u at a run, up to 20 u out of a dash-jump) behind where any other landing tick puts it. The landing now walks the rest of its step first.
- **The air lift after a ride** (L1). An air dash skimming a ramp met a lip 8 u proud of its crest and stopped a tick short, because the lift counted from the feet before the ride up the slope; one lifted onto a 2 u lip stopped at a second lip 1 u higher. A move stopped again in the air now steps up a lip within the lift of the floor at its leading edge, as a walk would.
- **The nudge is not eased yet** (L5). A step on a slope moves the box by up to 18 u in one tick (the 8 u lift plus the box's half-width), and the step down adds the same going down. `nudge_y` records every step for the view to ease, but nothing reads it before task 5's presentation work, so "the corner-correction nudge is invisible" cannot pass until then (ADR-0008 decision 10).
- **Cost.** Walking moves a whole tile column in one exact swept step, walking off a ledge finds the edge from the floor spans instead of a loop per sub-pixel, and a move only looks at the solid boxes it can reach. For 200 bodies, in ms per tick (ADR-0008 has the table):
  - flat and sloped ground with no solid boxes costs 1.6 to 2.8 ms;
  - ledges cost 2.4 to 3.3 ms (6.7 to 16.6 before the second review);
  - with 20 solid boxes out of the way, 2.5 to 4.1 ms (4.2 to 21.2 before).

  The third review's fixes cost nothing measurable except ledges at 20 u/f (about 0.3 ms). After the fourth's, five runs a cell sit within the same spread; the bench walks without the corner lift, as enemies do, so the step down and the far-edge landing (the player's alone) are not in it. The fifth's cost about 0.1 ms a tick on the bench (3 to 5%, the sideways move's extra check), within the run-to-run spread of every cell.

## How it plays now

- Ash's movement fixtures (task 3) run unchanged on the new sweep: every fixture's state hash matches the committed golden hashes on every checked tick, after each review's fixes (the fourth's step down and far-edge landing included), with one exception from the fifth: in `pogo_down_dash_pogo` the down-left dash off the pogo bell now touches down on the bell's corner (1.4 u of the box over its top) and runs on, 3.7 u higher than it passed beside it before, then pogoes the spikes as before. `Simulation.VERSION` went up with that re-bless.
- Slopes keep run speed both ways, and walking back over a crest retraces it exactly (randomised test). A dash keeps 20 u a tick up a ramp of any height and onto its plateau.
- Landing anywhere on or beside a ramp, including across a row boundary of a long ramp, the player stays grounded running up or down it.
- A ledge corner within 8 u, or 10 u while holding toward the wall, lifts the player onto the ledge in the air, and the landing counts on that frame; after riding up a slope, or onto a first lip, the next lip within 8 u of the floor ahead is lifted onto too. On the ground, a lip of up to 8 u is stepped onto and off, the player never leaving the ground, at a ramp's crest and anywhere on a ramp, both ways.
- A fall or a diagonal dash that touches a ledge's far edge lands, even moving away from it, and a buffered jump goes from where the landing tick ends; the near side of a raised step lands on its top.

## Open questions for the director

- The ledge-grab's 10 u is measured from the feet: a generous mantle. If you meant the hands within 10 u of the top, it becomes a 54 u climb with its own animation (ADR-0008).
