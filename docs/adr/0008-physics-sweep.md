# ADR-0008: Tile physics with validated slopes, a three-part body and exact swept walking

- Status: Accepted
- Date: 2026-10-17 (revised after the second, third, fourth and fifth physics reviews and the task 3 review's M8)
- BUILD.md sections: 5 (ground table: slope handling, corner correction, crouch; wall table: ledge-grab; feel rules: "The player never clips a corner they visually cleared"), 13 ("the AABB physics sweep (slopes, one-way platforms, corner correction)"; frame budget: input and simulation 3.0 ms)
- Checklist lines: Movement, "Landing on a 1-pixel ledge edge lands; the corner-correction nudge is invisible"; "Dash-jump keeps 100% of dash speed" (off a lip too); "Head bumping a ceiling corner by under 6 units slides around it"; "60-second movement-only loop" (no snags)

## Context

BUILD.md asks for an AABB sweep with slopes up to 45 degrees ("speed unchanged; no sliding on slopes"), one-way platforms, corner correction of 8 u over ledge corners and 6 u around ceiling corners, and an automatic ledge-grab within 10 u of a wall's top. One tile is 32 u ("5.5 tiles (176 u)"). It does not say how a box meets a slope, which slopes exist, or how corner correction interacts with walls.

The first version walked the surface one unit at a time and treated slopes as non-blocking sideways. Its review found these problems:
- a slope's vertical face and flat underside could be walked or flown through;
- landing on a crest left the box hovering on the plateau's edge;
- corner corrections ignored slopes;
- dropping through a one-way beside a wall embedded the box;
- walking 200 bodies on slopes cost 11 to 20 ms a tick, against a 3 ms budget.

The second version (validated slopes, swept walking) was reviewed again. That review found:
- on a slope, a solid box behind the box, over its head or under its feet blocked the walk; a player who walked up a ramp to a closed door could not walk back down;
- the crest hover was fixed only for a fall that reached the slope within one tick. Under per-tick gravity about 3 landings in 10 beside a crest still hovered, and running down the ramp then flew off it for 8 to 9 frames;
- walking along a solid box's top into a slope that rose out of it embedded the box;
- walking off a ledge cost a loop per sub-pixel: about 0.4 ms per body per tick, 17 ms a tick for 200 bodies on ledges;
- jumping off a slope into a ceiling corner bumped instead of sliding;
- drop-through was refused beside a ramp's low side.

The task 3 review (M8) added one more: a crouched (28 u) body in the air, 4 u under a ceiling, reported a wall and could not move sideways in open space.

The third review found three ways the sweep still broke the feel, each reaching a real player:
- **An air dash parked on ramps.** A level air dash that touched down on a ramp was stopped at the crest's face, and at every tile-row boundary of a tall ramp, for the rest of the dash. The sideways sweep tested the whole box, foot zone included, against walls, so the crest's top (inside the foot zone) stopped it; walking exempts that wall, the sideways move did not.
- **A landing across a row boundary of a long ramp soft-locked the player.** Riding up measured its depth in the foot point's row only, so a rise that crossed into the row above left the foot point inside the slope that carries on there, and every move after that was refused.
- **A solid box sunk into a ramp near its crest trapped the walk back up**, and a solid box laid 1 u below the tiles beside it stopped a walk dead.

It also found the test oracles too lenient to see any of these, and claims in this ADR and the feel log that they contradicted.

The fourth review found three more, all at the edges of the corner correction:
- **Walking down a lip left the ground.** The 8 u step up had no step down: walking off a door laid a few units proud of the tiles was a fall, with a landing on the far side. A ground dash off the tiles onto a box 1 u below them floated over it for the whole dash, so a jump on dash frame 9 had run out of coyote time and was the air jump (85%, and the air jump spent) instead of a dash-jump.
- **A lip at a ramp's crest stopped the walk dead.** The step up measured the lip from the feet at the box's centre, which on a slope are below the floor at the box's leading edge by up to its half-width (10 u on a 45-degree ramp). A door lying 1 u proud of a plateau from its crest edge made the ramp impassable, on foot and dashing.
- **A landing on a ledge's far edge was missed.** In the air the box moves across before it falls (decision 9), so a box over a ledge and moving away from it was carried past the edge before the fall reached the ledge: 41 such crossings in 4,800 scripted hops. A jump the next tick was the air jump.

It also found a dash's partial ride stopping 2 u short of where walking stops (the ceiling over the whole path counted, not the path travelled), two contact-sheet panels that started with the box inside something solid, and no invariant able to see any of the three.

The fifth review found that three of the fourth's fixes held only in the geometry they were tested in:
- **Walking down off a lip on a ramp flew the rest of the ramp.** The step up counted from the floor at the box's leading edge, the step down from the feet at its centre; walking off the downhill end of a door on a 45-degree ramp, the ramp under the centre is already 10 u lower than under the trailing edge, so every such step down was a fall. In 108 of 600 random ramp lips the walk up stayed on the ground and the walk back down left it; a ground dash off a door at a crest floated and its jump on dash frame 9 was the air jump.
- **A diagonal air dash down passed through a ledge's far corner.** The far-edge landing covered falls only; the dash still moved across, then down, and missed 39% of the landings its straight path stood on.
- **The far-edge landing changed the near side of a raised step.** A box falling toward a block on a floor within a tick's fall, which moving across first lands on, landed on the floor in front of it instead, 18 u lower and stopped against its face.
- **A buffered jump on a far-edge landing took off from the touch-down point**, up to a whole tick's step behind where any other landing tick puts it.
- **The air corner lift was checked once, from the feet before a ride up a slope**, so a dash skimming a ramp stopped a tick short at a lip 8 u proud of the crest, and one lifted onto a lip stopped at a second lip 1 u higher; and contact-sheet panel 11 showed an ordinary landing, not a far-edge one.

## Decision

1. **Geometry.** Rooms are grids of 32 u tiles (`TileGrid`) plus `SolidBox` rectangles for things that change (doors, wax walls). Outside the grid is solid. The tile kinds are:
   - solid (clingable) and smooth (solid, not clingable);
   - one-way;
   - spikes: a hazard volume, not solid; its depth below the tile top is `spike_inset_u` in `content/physics/world.tres` (a new world starts with `WorldTuning`'s defaults, never an untuned 0);
   - floor slopes: 45 degrees rising right or left, and 1:2 slopes over two tiles.
2. **Validated slopes.** `TileGrid.validate()` is part of loading every room. Each slope must rest on a wall, and each of its sides that stands above the tile's bottom must meet a wall or a slope edge of the same height. A slope therefore never shows a vertical face or an underside: from outside, only its diagonal surface can be reached. A one-way beside a slope's face does not seal it. The physics relies on this, and the room editor (task 7) refuses rooms that break it. Solid boxes are validated against the tiles too, where their tops meet the ground (decision 12).
3. **The body has three parts.** A `Body` is a box positioned by its bottom-centre in sub-pixels.
   - Its **upper body**, everything above the lowest `half_w`, never overlaps a wall, a solid box or a slope.
   - Its **foot point**, the bottom-centre, stands on floors and slopes and never goes inside anything solid.
   - Its **foot zone**, the lowest `half_w`, may overlap slopes and the edge of a wall that continues a slope (a crest). A box standing by its centre on a 45-degree slope has its uphill corner exactly that deep in the ground. The foot zone is per body, so a wider body sinks its corner deeper, as a 45-degree slope requires.
   - Solid boxes block the whole box.
4. **Floors.**
   - The centre stands on any floor: a wall or solid-box top, a slope surface, or a one-way top it was above.
   - The rest of the width stands on flat floors, so a box overlapping a ledge by a single sub-pixel stands on it.
   - **A wall top no more than the foot zone above the slope under the centre is the crest that slope leads to, and it holds nothing up.** The box comes to rest on the slope, with its corner in the crest, exactly as walking there leaves it. The rule holds in every place that decides ground contact:
     - a fall step that reaches the crest but not yet the slope keeps falling, and the next step lands on the slope;
     - re-reading the ground of a box at a crest's edge finds it airborne.

     One-way and solid-box tops always hold the box.
5. **Walking** (`CollisionWorld.walk`) moves the foot point along the floor one tile column at a time. Within a column the floor under the centre is a single flat or straight slope, so each step is one exact move.
   - **The swept test.** A swept test checks each step against every obstacle as a moving rectangle. It is exact for diagonal motion and needs no unit stepping, and 1:2 slopes' stepped surfaces are never more than half a sub-pixel off the swept line. Only a contact at or ahead of the box's start counts: an obstacle the box is already in, or is moving away from, never blocks it. The test checks:
     - the upper body against walls;
     - the whole box against solid boxes;
     - the foot zone against walls, except for a wall that is the crest of the slope being walked: the wall ahead while climbing, or the wall already under the box while walking down and away from it. A wall walked into on the level or downhill stops the whole box.
   - **Where the centre crosses into the next column:**
     - a floor that rises is a wall face (steeper than 45 degrees);
     - a floor that drops away leaves the box walking level while a flat floor is still under it; once nothing is under it, a floor at most the corner lift below is stepped down onto (decision 7), and otherwise the rest of the move is airborne;
     - a box walking downhill onto a solid box's top steps onto it and carries on along it.
   - **A slope rising out of a solid box's top.** It takes over where it reaches the walking height: the box walks along the top to that point and up the slope from there, and back down and along the top the other way. Decision 12 now refuses a room whose box top lies just under tile ground, so a slope can only rise out of a box's top more than the join band below it: the walk handles the rest, but the sixth review found the walk leaving the ground over a top buried 0.25 to 2 u, and lifting onto a crest's top over one sunk 1 to 9 u.
   - **Level walking** finds where support runs out from the spans of flat floor at the box's height, in time proportional to the number of spans, not the distance. A level sweep, like the climbing one, lets the foot zone into the crest a slope leads to (decision 6), so a box walking along a solid box sunk into a ramp near its crest walks on to where the slope rises and up it.
   - **Stepping up and down.** A walk stopped against a wall or solid box whose top is at most the corner lift above the floor at its leading edge steps up onto it, if the box has the headroom there and can carry on; a walk whose floor ends steps down onto one at most the corner lift below (decision 7).

   A slope never changes horizontal speed, and walking back retraces the same heights exactly, across lips too. A walk and the same walk taken in pieces end in the same place, to within a sub-pixel: on a 1:2 slope under a ceiling the swept contact with the stepped surface can round either way.
6. **Sideways moves** (`move_x`: the player in the air, and an air dash, which moves level whether or not it has touched down) sweep the box against walls and solid boxes.
   - **Crests.** The upper body is swept against every wall; the foot zone only against walls that are not the crest a slope leads to. A crest is the top of a wall run whose top is inside the foot zone, with a slope before it (in the direction of travel) whose raised side meets that top: the plateau a ramp climbs to, or the wall that carries the next row's slope on a ramp several tiles tall. Walking already treated it so (decision 5); the sideways move now agrees.
   - **Riding up.** If the foot point's path went into a slope, or into the wall a crest corner already rested in, the box rides up onto the surface. A rise that lifts the foot point into the tile row above can meet the slope that carries on up there, so the depth is read again at each new height until the path is clear. Only the row holding the foot point can hold such a floor at each height; a wall in a row above it is a ceiling over the box (M8: a crouched box under a low ceiling read that ceiling as ground it had sunk into).
   - The ride is allowed when it is no steeper than the slopes allow and the box has the headroom. If the headroom runs out partway (a ceiling or a solid box over the ramp ahead), the box goes as far as it can riding up under the lowest ceiling over the path it travels to that point, exactly where walking up the slope stops (before the third review it stopped where its foot point first met the slope; before the fourth, a ceiling beyond the point it could reach still counted, and it stopped 2 u short).
   - **Carrying on.** A ride up a slope can bring what stopped the sweep (the crest ahead, the wall under the next row's slope) into the foot zone, so the move carries on from the new height with what is left of its distance. A dash at 20 u a tick therefore climbs a ramp at full speed.
   - Riding up is not a corner-correction nudge.
7. **Corner correction.**
   - **On the ground**, the horizontal correction is a step, up or down: a walk given the corner lift (the player's 8 u, `walk(body, dx, lift)`) steps onto a wall or solid box whose top is at most that far above the floor at its leading edge, if it has the headroom and can carry on at the new height; and a walk whose floor runs out steps down onto a floor at most that far below, staying on the ground. Tile tops are always 32 u apart, so in practice this is a solid box: a door left open as a floor a few units off the tiles beside it, a platform. Enemies walk without it for now. BUILD.md's ground table lists the corner correction with the ground's rules; without the step up a 1 u lip stopped the player dead (third review, M1), and without the step down the way back off it was a fall and a landing (fourth review, H1).
     - The step up is measured from the floor under the box's leading edge, not its feet: on a slope that floor is higher by up to the box's half-width, so a lip at a ramp's crest is no taller for being met from the ramp (fourth review, H2).
     - The step down mirrors it, measured from the floor under the box's trailing edge, the side the walk is leaving: walking off a lip onto a slope (or onto the floor at a slope's foot, the box's corner in the slope), the floor under the centre is lower than the slope under that edge by up to the box's half-width, and the lip is no taller for being left onto a slope (fifth review, H1). Walking up and back down over any lip within the lift never leaves the ground.
     - Both add their height to `nudge_y`, so the view can ease them. On a slope a step moves the box up or down by as much as the lift plus the box's half-width (18 u on a 45-degree ramp) in one tick, which is why the easing matters (decision 10).
   - **Ledge corners in the air.** Sideways into a ledge whose top is at most 8 u above the box's bottom, the box rises onto it and continues (BUILD.md 8 u).
     - The lift is measured from the feet where the move began. A move that rides up a slope, skims over one, or has already lifted onto a lip and is stopped again steps up a lip within the lift of the floor at its leading edge, as a walk steps it, and carries on: an air dash up a ramp onto a lip at its crest, or over two lips in a row, keeps its 20 u a tick (fifth review, L1).
     - While the stick holds toward the wall the player passes 10 u instead: the automatic ledge-grab, measured from the feet (see the director question under Consequences).
     - A corner-lift landing is grounded at once, so a buffered jump fires on that frame.
     - A lift never ends on a crest: the crest a slope leads to does not stop the foot zone (decision 6), so there is nothing to lift over.
   - **Ducking under ceiling corners.** Sideways into a ceiling corner that overlaps at most the top 6 u of the box, the box drops under it and continues. It does not if anything it could stand on (a floor, a one-way top it is above, a slope) lies in the way down, either where it is or where it ends up.
   - **Sliding round ceiling corners.** Upward into a ceiling corner that overlaps at most 6 u at either side, the box slides sideways around it. The slide is vetted where it ends, by the rules walking keeps:
     - no wall or solid box in the strip it slides through or anywhere in the box where it ends;
     - no slope above its foot zone there;
     - its foot point not inside a slope.

     So a box jumping off a slope, whose uphill corner starts in the ground, slides like any other.
   - A correction must make progress and must leave the box valid, or it is not applied.
8. **One-way platforms** stop a box only if its bottom started the move at or above the platform top. `drop_through` (crouch and jump) moves the box one sub-pixel below the top. It works only when one-way platforms alone hold the box up:
   - a wall or a solid-box top at its feet stops it;
   - a slope tile beside the platform does not, since its surface there is below the box's feet (a box standing on a slope is `on_slope` and cannot drop).
9. **Axis order.** In the air the player moves x before y. A box above a ledge corner at the start of a tick therefore gets the corner correction before a fast fall carries its feet past the corner.
   - **The far edge.** A falling box that is over a flat floor at the start of a tick, and that moving across first would carry off it before the fall reaches it, instead lands where its straight path meets the floor (`landing_contact`), when the path there is clear and the box still has the floor under it at that point. The player then touches down (the event and the resources), walks the rest of the step, off the edge with coyote time if it leads there, and only then starts a buffered jump, dash or strike, so it goes from where the landing tick's step ends as on any landing tick (fourth review, H3; fifth, M2).
     - A diagonal air dash down does the same (fifth review, H2): it touches down where its straight path meets the ledge, the air jump and dash come back, and it runs on along the floor for the rest of the tick.
     - Only a step that moving across would carry off the floor, or onto a lower one, takes this path. One that moving across first lands on a higher floor (the near side of a raised step) keeps x before y, so the near side's landing and corner correction are unchanged (fifth review, M1).
     - "Moving across first" is the mover's own step, with its corner lift or ledge-grab and its slide: the step is tried on a copy of the body (`landing_contact(body, dx, dy, lift, slide)`), and the far-edge landing is taken only if that step would end in the air or lower. A fall past a ledge's end toward a block across a notch, its top within the lift or the grab, lands on the block as it always did, not on the ledge's last unit against the block's face (sixth review, M1).
     - A diagonal dash walks the rest of the tick's step at every touch-down on a far edge, not only the first: down a staircase it keeps its 14.14 u a tick (sixth review, M2).
     - Once a diagonal dash has touched down and is on the ground, it walks with the corner lift, as a level dash that has touched down does, so it steps up a lip instead of stopping against it; run off the floor's end, it goes on down at once (sixth review, M3).
     - A buffered jump on a far-edge landing during a missed down-strike fires: the landing counts for the jump even when the rest of the step walks off the edge (sixth review, M4).
10. **Contacts.**
    - `on_ground`, `ground_tile` and `on_slope` are refreshed by every vertical move and every walk. A sideways move refreshes them when the body was on the ground or changed height. A body in the air that slides level stays in the air unless its feet reach a floor at exactly their height, which the `move_y` every air step makes next finds; a walk's airborne remainder refreshes itself. Running the full ground query there too cost 0.4 ms a tick for 200 bodies on ledges and changed nothing a caller sees.
    - An upward move that finds no headroom at all (a flush ceiling) leaves the ground contact as it was: the box never left the floor.
    - `hit_wall`, `hit_ceiling` and the corner-correction `nudge_*` accumulate until `clear_contacts`, which the player calls at the start of every tick. They are read only within the tick and are not part of the state hash.
    - `nudge_x` and `nudge_y` are there for the view to ease, so that a corner correction does not show as a snap (checklist: "the nudge is invisible"). The player view eases them over `nudge_ease_frames` (3; `content/player_view.tres`), never falling more than the run's largest nudge behind (task 5; docs/feel_log/2026-10-17-nudge-ease.md). The simulation is unchanged by it, and the F3 overlay draws the collider, so the frame-stepper still shows each nudge on its tick.
11. **Broad phase.** While a move runs, the world's solid-box list holds only the enabled boxes within reach of that move: its distance, twice that for a walk, plus the body's half-width and a tile. The order is kept, so results and replays are unchanged. The full list is back before the move returns.
12. **Joins** (`core/rooms/room_joins.gd`, sixth review). A solid box's top is ground. Loading a room refuses one whose box top lies inside tile ground no more than `join_band_u` below its surface (12 u in `content/physics/world.tres`, more than any Wick's corner lift or ledge-grab with BUILD.md's 15% between Wicks). Such a top is neither ground nor terrain: the walk reads a floor inside solid ground, and leaves the ground over it (H1, 0.25 to 2 u deep under a ramp) or lifts onto the wrong top (M5, 1 to 9 u under a plateau). It is an authoring mistake, not a case the physics handles. Also refused: a one-way top 1 to 12 u above a box's top beside it, a shelf the walk passes under and drops through on the way back (L5).
    - A top flush with the ground, a lip above it, a box filling a corridor up to its ceiling, and a step built of overlapping boxes are all fine. Boxes are only checked against tiles.
    - Doors open and close but never move, so the check at load covers every state a room can be in. A moving box, when one exists, must keep to the same rule along its whole path.
    - The rooms the earlier reviews built with sunk doors (`ramp45_sunk_door`, `review_door_ramp`) and their fixtures are gone. `tests/replay/rooms/invalid_buried_door.room` is kept as the refused example, and every room in the repository is checked in the tests.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Per-unit stepping for all motion | Exact but slow: one collision query per unit moved. The first version stepped this way near slopes, and walking 200 bodies cost 11 to 20 ms a tick |
| Sweep, then snap to the ground ("follow ground") | Tried in the first version; it stopped boxes short below crests and let a dash step onto a wall top beside a descending slope |
| Physics that handles exposed slope faces and undersides | Possible, but every query would need triangle cases for geometry no room needs. Validation makes those cases impossible instead, and the room editor tells the designer at once |
| Validation that forbids solid boxes overlapping slopes | Solid boxes change at run time, and a door on a ramp is ordinary level design; letting the slope take over where it rises out of a top is one local rule instead |
| Crest rule only within one fall step (the second version) | A fall step under real gravity often reaches the plateau's edge but not the slope below; the edge then held the box |
| Two foot sensors for slopes | Makes a box hang off slope tops by half its width and pop when the second sensor leaves |
| Polygon collision (SAT) with arbitrary slopes | More general than a grid game needs, harder to keep exact in integers, and rooms stop being a text grid |

## Feel reason

Slopes never change speed or push the player around, crests never hover or pop, and every corner the eye says was cleared is cleared. Nothing the player cannot see, such as a hidden face, an underside or a door behind them, ever catches them.

## Consequences

- **Tests.** `tests/unit/core/physics/` holds:
  - a test per BUILD.md section 5 physics row;
  - a regression test per finding of all five reviews (`test_physics_review.gd`, `test_physics_review_round2.gd`, `test_physics_review_round3.gd`, and for the fourth and fifth the fixtures below and `test_physics_fuzz_lift.gd`; the fifth's diagonal dash also through the real player in `test_player_on_physics.gd`). The door on a ramp and the crest landing also run as real-player traces through `Simulation` in `test/slopes`, and M8 in `test/longgap` (`tests/unit/core/fsm/test_player_on_physics.gd`, with the player). M8's fixture is `tests/replay/physics/crouch_hop_low_ceiling.fixture`. The third review's findings are real-player fixtures in `tests/replay/physics/` too: an air dash into a crest and up 45-degree and 1:2 ramps several rows tall (180 u in 9 f, every frame 20 u), landings across a row boundary that walk on and back, the walk back up over a sunk box, and the lips a walk steps up. The fourth review's are there as well: the lips walked back down, a dash-jump off the tiles onto a box 1 u below them (with its control on flat tiles), walks and a dash up 45-degree and 1:2 ramps onto lips and a door at and past the crest, the dash's ride stopping where the walk stops, and the far-edge landing with the coyote jump after it. The fifth review's: walks down 45-degree and 1:2 ramps off a door and a lip and over a door sunk flush (and back up), a dash-jump down a ramp off a door (with its control), diagonal down dashes onto a ledge's far edge, a fall toward a raised step that lands on top, a buffered jump on a far-edge landing that keeps its stride, an air dash up a ramp onto a lip at its crest and over two lips, and a lip on a one-way stepped down onto and dropped through;
  - a test for every branch of `collision_world.gd` and `collision_queries.gd` (the moves, and the geometry questions they ask, split so neither file passes the 1000-line limit).

  It also holds randomised invariants:
  - in random valid rooms with solid boxes:
    - no move leaves the upper body in anything solid or the foot point inside anything, and no fall passes a floor;
    - falls under per-tick gravity never come to rest hovering on a crest;
    - a walk stopped by a "wall" always has something solid within a unit of it, and an unstopped walk that stays on the ground moves exactly as far as asked;
  - on random continuous ground with every slope kind, walking never leaves the ground, keeps its speed and walks back to exactly where it started;
  - after per-tick-gravity drops anywhere across crests, peaks and valleys, walking off stays grounded every tick;
  - level walking's span jumps equal a sub-pixel-by-sub-pixel reference;
  - since the third review: random continuous ground has ramps several rows tall; a walk ends where the same walk in pieces ends (within a sub-pixel); a sideways move on the ground (an air dash that has touched down) goes wherever a walk of the same distance goes level or uphill; air steps with sideways speed and per-tick gravity land cleanly on those ramps and walk on. "Stopped by nothing" no longer accepts the crest a slope leads to as a reason, and a solid box's top under the centre is the floor there, not a crest.

  - since the fourth review (`test_physics_fuzz_lift.gd`, walking with the player's 8 u lift as the player always walks): over random lips 1 to 8 u up and down, walking never leaves the ground and is never stopped; a lip 1 to 8 u proud of a ramp's plateau, anywhere from the crest to two tiles past it, never stops a walk or dash up the ramp; and an air step lands wherever its straight path stands on a ledge with at least a sixteenth of a unit over it.
  - since the fifth: a solid box sunk into a 45-degree or 1:2 ramp rising either way, 0 to 8 u proud at one face, is walked over up and back down at walk and dash speed without leaving the ground or stopping; an air step never lands lower than moving across first would put it on the ground (blocks 1 to 24 u tall); an air move skimming a ramp lifts onto a lip at its crest in one tick, and onto two lips in a row; and the real player's diagonal dash down touches down wherever its straight path stands on a ledge.

  Each of the third review's fixes was switched off in turn (the crest rule, reading the row above, carrying on after a ride): every one makes at least two of these tests fail. So does each of the fourth's (the step down, the lift from the leading edge, the far-edge landing) and the fifth's (the step down from the trailing edge, the dash's far edge, the near side, the air step up): each makes its invariant fail.
- **Replays.** None of the second, third or fourth reviews' fixes moved a fixture. The fixture stage checks every fixture's state hashes against `tests/replay/golden_hashes.txt` (every 60 ticks and the last tick). After the third review's fixes all 135 earlier fixtures matched their committed hashes, and blessing added only the 7 new physics fixtures; after the fourth's, every fixture whose inputs and rooms were unchanged matched, and blessing added its 11 physics fixtures. The fifth's moved one: in `pogo_down_dash_pogo` the down-left dash off the pogo bell now touches down on the bell's corner (1.4 u of the box over its top) and runs on, 3.7 u higher than it passed beside it before, and still pogoes the spikes below as the fixture expects. That moved hash is a change to the simulation, so `Simulation.VERSION` went up with the re-bless (ADR-0006); every other fixture matched. The sixth review's fixes moved no committed fixture: played tick by tick against the code before them, every fixture whose path changed in that batch changed by a movement rule (docs/adr/0010, Consequences), and the hashes were re-blessed under `Simulation.VERSION` 4 for those. The sixth review's own five fixtures were blessed new.
- **Performance.** `tools/bench/physics_bench.gd` measures 200 bodies patrolling, walking off ledges and falling, in this container's headless GDScript, in ms per tick. Each "now" cell is the median of five runs on an idle machine after the sixth review's fixes.
  - "Solid boxes" means 20 boxes out of the bodies' way, which every query used to examine and the broad phase now skips.
  - "Round 2" is the sweep the third review saw, measured beside the third review's fixes in that session; the first version cost 3.9 ms on flat ground and 11.1 to 19.7 ms on slopes, and the second version before the broad phase 4.2 to 21.2 ms with solid boxes.
  - "Enemy" bodies walk without the corner lift, as enemies do. "Player" bodies move as the player does: the 8 u lift and 6 u slide, and in the air the far-edge landing first, which since the sixth review tries the plain step on a copy of the body (L3). The player is one body, so its columns are a worst case: 200 of them cost up to 0.6 ms more than 200 enemies on ledges at 20 u/f, about 3 microseconds a body a tick.
  - The fifth review's fixes cost about 0.1 ms on this bench (3 to 5%, measured against the code before the air step-up, three runs each, alternated): the sideways move's extra check.

  | Ground | Solid boxes | 9 u/f round 2 | 9 u/f enemy | 9 u/f player | 20 u/f round 2 | 20 u/f enemy | 20 u/f player |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | Flat | 0 | 1.7 | 1.6 | 1.6 | 2.1 | 2.1 | 2.0 |
  | Flat | 20 | 2.6 | 2.6 | 2.4 | 3.0 | 2.6 | 3.0 |
  | Slopes | 0 | 2.1 | 2.1 | 1.9 | 2.7 | 2.7 | 2.8 |
  | Slopes | 20 | 3.1 | 3.0 | 2.9 | 3.6 | 3.8 | 3.6 |
  | Ledges | 0 | 2.4 | 2.4 | 2.7 | 3.0 | 2.9 | 3.5 |
  | Ledges | 20 | 4.1 | 4.1 | 3.8 | 4.4 | 4.0 | 4.5 |

  Run-to-run spread on this container is wide: the five runs of a cell span up to 1.3 ms (most 0.3 to 0.8 ms), so a difference under about half a millisecond between two cells is noise. The 3.0 ms budget covers the whole simulation step for 200 bodies. Inside it: flat ground and slopes with no solid boxes, and ledges with none at 9 u/f. The third review measured 20 boxes flush with the floor in the walkers' paths, which the broad phase cannot skip, at 3.1 to 4.5 ms. Task 8 therefore profiles the stress room. If the sweep is still the hot path, it ports `CollisionWorld` to C++ (GDExtension), keeping this GDScript as the reference implementation and testing the port against it (CLAUDE.md).
- **Threads.** Queries keep scratch results in member variables, and a move narrows the solid-box list while it runs, so a world must be used from one thread at a time. A threaded or C++ port must make both local.
- **Director question.** BUILD.md lists the ledge-grab under wall-cling ("automatic within 10 u of a wall's top"). This implementation measures the 10 u from the feet, which makes it a generous mantle. If the director meant the hands (the top of the box) within 10 u, the grab becomes a 54 u climb and needs its own animation and timing. The in-air step-up measures from the floor at the box's leading edge when the move skims a slope, as a walk does (decision 7), so on a ramp an air move can climb a lip up to the lift plus half the box's width above its feet in one tick: the sixth review's fuzz saw a jump at a ramp's foot climb a door 21.1 u above the feet (a 16.4 u nudge).
