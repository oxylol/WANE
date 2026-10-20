# ADR-0014: Join rooms with paired doors, crossed when the whole body is inside a door's strip

- Status: Accepted
- Date: 2026-10-19
- BUILD.md sections: 3 ("each a hand-built level stitched from authored rooms"; The zones), 5 (the twelve core tech interactions, "taught by the world"), 13 (layer 2: "room and zone state"; "A run is a seed plus an input stream"), CLAUDE.md ("Every Wick, Votive, Vessel, enemy, boss, room and zone is a `.tres` resource under `content/` with a schema validated in CI"; kickoff task 7: "a grey-box zone 1 of 12 rooms")
- Checklist lines: "A 60-second movement-only loop through zone 1 can be played with eyes on the character, never on the HUD"; "Dash-jump ... clears the reference gap in zone 1 room 7 (the grey box's is room 02, ADR-0019 Decision 4) every time"; "Pogo keeps full horizontal speed; a 10-bounce chain across the zone 1 spike pit is possible at 4 bounces per second"; "Pogo resets air dash; pogo, dash, pogo crosses the reference hidden-room gap"

## Summary

- A door is a room-file line, `door <name> <side> <from> <to> <room id> <door name>`; the opening is whole tiles, at least 2 tiles long (see Decision).
- The strip is the opening, 2 tiles (`DOOR_DEPTH_TILES`) deep; the player crosses when the whole collider is inside it at the end of a tick (see The strip).
- The strip and the 2 tiles beyond must be empty; the grid border stays open there, so "outside the grid is solid" still holds (see The strip).
- Side doors stand on floor and a top door lands on safe ground; doors pair on facing sides, same length, and lead back (see Safe ground, Pairs).
- Crossing (`Simulation._take_door`, after combat) keeps speed, state, action and timers, so a dash or fall carries through (see Crossing).
- Enemies, trails and Radiance's light stay behind; the next room's enemies start fresh; a kill ember in flight arrives, a tossed one goes out (see Crossing).
- The tick sends `SimEvents.ROOM`; the camera cuts as on a respawn, the drawn player does not slide, and F3 draws each strip (see Crossing).
- `RoomSet` loads the first room and, breadth first, every room doors reach, once; the content hash covers them all (see Rooms a run can reach).
- Zones are `content/zones/*.tres` (`zone_def.gd`): every listed room reachable from the start, no door leaving the zone; CI checks each (see Zones).
- The `room` probe is the id with slashes as underscores; `Simulation.VERSION` 8 added the current room to the state hash (see Fixture words, Consequences).

## Context

Until task 7 every run lived in one room. A zone is a set of authored rooms the player crosses without a loading pause, and the simulation must cross them deterministically: a replay of a run through ten rooms must step through the same rooms on every platform. BUILD.md names zones and rooms but not how rooms connect, what the player keeps when crossing, or what the camera does. The physics treats everything outside a room's grid as solid (ADR-0008), and that rule is load-bearing for every fixture so far.

## Decision

**A door is a line of the room file** (ADR-0009's format gains one directive):

```
door <name> <left|right|top|bottom> <from> <to> <room id> <door name>
```

- The opening runs `from..to` units along its side, on whole tiles, at least 2 tiles long.
- **The strip.** A door's strip is the opening, 2 tiles (`DOOR_DEPTH_TILES`) deep from the room's edge. The player goes through when the whole collider is inside the strip at the end of a tick. The strip and the 2 tiles beyond it must be empty (no wall tile, no solid box), because the player arrives just beyond the strip in the room on the other side. The grid's border is simply left open across the opening, so the physics' "outside the grid is solid" rule is untouched: the body can always reach the whole strip and never leaves the grid.
- 2 tiles because a standing body is 44 u tall: at a top or bottom door the whole body has to fit inside the strip, and it has to fit beside it in the room beyond.
- **Safe ground.** A side door stands on floor (the tiles under its strip are walls), and a fall through a top door lands on safe ground (straight down from the strip the first tile is not spikes or a pit). So the arrival point can be the player's safe point until they stand anywhere else, and a hazard never sends them into a loop.
- **Pairs.** Every door leads to a door of the room beyond on the facing side (right to left, top to bottom), of the same length, that leads back. Walking through and straight back returns the player to just inside the door they came through, at the same height.

**Crossing** (`Simulation._take_door`, after combat resolves, before the tick ends):
- The player arrives just beyond the strip of the door they are led to, as far along its opening as they were along the one they left. They keep their speed, their state (ground, air, dash, wall), their action and every timer: a dash through a door goes on with its frames counting (`door_dash_carries_through`), a fall or a jump keeps its vertical speed (`door_vertical_fall_and_jump`).
- What stays behind: the room's enemies, Blaze trails and Radiance's light. The next room's enemies start fresh at their markers, so walking back finds a room's dummies standing again (`door_enemies_belong_to_their_room`). A kill ember still in flight reaches the player as they go, with its Flame (`door_kill_ember_in_flight_reaches_ash`); an ember thrown by the Ember Toss stays in the room behind and goes out, its cooldown running on (`door_ember_stays_behind`).
- The arrival point is the player's safe ground until they stand elsewhere (`door_hazard_after_a_door_stays_in_the_room`), and dying returns them to the new room's spawn ("the room's spawn", ADR-0013).
- The tick sends `SimEvents.ROOM` at the arrival point. The camera cuts to the new room inside its bounds (the rig resets, as on a hazard respawn), the drawn player is drawn there rather than sliding, effects of the room behind are cleared, and the room view redraws with each door's opening shown as a passage through the solid beyond the room. The F3 overlay draws each door's strip.

**Rooms a run can reach** (`RoomSet`): building a simulation loads its first room and, breadth first, every room the doors lead to, once. The run never reads a room file afterwards, so a file changing mid-run cannot change it. The content hash covers every room a run can reach (the first room first, so a fixture in a room with no doors hashes exactly as before), and the state hash covers the room the player is in. Problems with any reachable room, or with a pair of doors, are load errors.

**Zones** are content (`core/rooms/zone_def.gd`, `content/zones/*.tres`): an id, a name, the start room and the list of rooms. The schema requires that every listed room is reachable from the start through doors and that no door leads out of the zone; the content stage of CI checks every zone.

**Fixture words.** The `room` probe is the room's id with its slashes as underscores (`test_door_b`), since a fixture word is an identifier.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Open the grid's edge and let the body leave the room, crossing when its centre passes the edge | Every query that treats outside the grid as solid (the sweep, wall_near, the ground probe, ledge-grab) would need a door-aware exception; a door would change physics everywhere instead of nowhere |
| Cross when the body's centre enters a one-tile strip | At a top or bottom door a 44 u body cannot stand wholly inside the room and outside a 32 u strip: arrival would be inside the strip of the door it arrives at, and the player would bounce straight back |
| Doors as entity markers with properties | A door has a side, an extent and a partner; a directive of its own reads as what it is in a diff and can be checked like the tiles |
| Keep enemies' state when leaving a room | Phase 1 has only dummies and no persistence rules; a fresh room is the rule BUILD.md's run loop implies (rooms reset when re-entered until a zone's state exists), and it keeps the state hash per room |
| Fade to black on a door | Takes control from the player for frames; BUILD.md section 5 says no input ever waits. The camera cuts on the tick, the player never stops |
| Load each room when the player reaches its door | File reads in the middle of a run; a run's content would depend on when files changed. Loading the reachable set up front costs about 0.2 ms a room |

## Feel reason

Movement never stops at a door: a dash, a fall or a run carries straight through, and the tick the player crosses is a tick like any other. Nothing about crossing rooms makes the player wait or lose speed.

## Consequences

- `tests/replay/doors/` holds a fixture per rule above, in `tests/replay/rooms/door_a`, `door_b` and `door_up`; `tests/unit/core/rooms/test_doors.gd` checks the format, its rules, the pairs, the zone schema and the hashes. The camera suites play the door fixtures and treat a door like a respawn: a cut.
- `Simulation.VERSION` 8: the state hash gained the room the player is in. No fixture's behaviour moved (every fixture's per-tick state was compared before and after).
- The room editor (task 7) writes doors and checks them as the loader does.
