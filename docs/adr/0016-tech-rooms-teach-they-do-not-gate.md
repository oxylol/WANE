# ADR-0016: A tech room teaches the cheapest route; it does not claim to be the only one

- Status: Accepted
- Date: 2026-10-19
- BUILD.md sections: 3 (hidden rooms "hold a guaranteed Lantern-tier Votive or a Lamplighter note"; "the tech differs, the access does not"), 5 (the twelve core tech interactions, "taught by the world"; Wall-jump "Resets double jump and air dash"; the fresh-cling rule of ADR-0010), 6 (Ember Toss: 0 Flame, 12 s cooldown)
- Checklist lines: "Pogo resets air dash; pogo, dash, pogo crosses the reference hidden-room gap"; "Wall-kick climbs a single wall without the player ever feeling stuck to it"; "wall-jump, then dash, then wall-cling the next wall"

## Context

Zone 1's rooms 4 to 6 were written to make their tech "the only way", with control fixtures that try the strongest alternatives. The review of those rooms found two routes the controls did not model:

- **Room 4.** A control tried one Ember Toss plus its landing trick, because the toss has a 12 s (720 tick) cooldown and the author assumed it could not be waited out. A spike post is a place to wait: each down-strike on it costs nothing and restores the air jump and the air dash, so a player bounces on post k until the toss is back, throws the ember (up and across, from the air jump's top) to land above post k+1, falls back onto post k, teleports once the ember has flown, and repeats from post k+1. Four tosses take the player to the alcove in 2516 ticks (42 s) with no air dash after the approach and no hazard touched (`tests/replay/zone1/bypass/04_bypass_toss_wait`).
- **Room 5.** A wall-jump gives back the air dash and the next cling is fresh (ADR-0010), so a wall-jump and an up-dash from every cling climb the well faster than the kicks (`05_wall_jump_dash_cycle`: over the top on tick 301, kicks 386).

## Decision

1. **A tech room's contract is "the cheapest route by far, and the one it teaches", not "the only route".** The controls prove what each single-use alternative cannot do (one toss, no second dash, no kick); the room header says so in those words and says what is not modelled.
2. **Known bypasses are pinned, with their cost, as fixtures**, so a change that closes or widens one is seen: `bypass/04_bypass_toss_wait` (expects the alcove reached only after tick 2400, no dash after the approach) and `05_wall_jump_dash_cycle`. A fixture under `tests/replay/zone1/bypass/` is a bypass record, not a teaching route, and the camera sweep does not play it (see Consequences).
3. **The rewards behind tech rooms are not progress gates.** BUILD.md section 3 puts a Lantern-tier Votive or a Lamplighter note in a hidden room; a player who waits out a cooldown for it has paid for it. Nothing a bypass reaches opens a way a run needs.
4. **No core rule changes.** BUILD.md's wall-jump row and the toss's cooldown stand.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Make room 4's step between posts too tall for a toss | The toss's flight (400 u) is a dash's direction at a longer range from the same point, so a step the dash crosses the toss crosses, and a toss with a bounce, an air jump and the dash the bounce gave back reaches far more than the dash route's 507 u. Taller steps would also break the teaching route. |
| A hazard ceiling or a narrow pocket over each post, so that a bounce in place is lethal | A bounce followed by a sideways dash out, an air jump and a return under the ceiling closes the loop again; the room becomes a timing test that does not teach the tech, and the first post (the safe first encounter) is lost. |
| Walls or slabs that stop the ember | Whatever a window lets the dash through it lets a straight ember through; the teleport then puts the player past it. |
| Pause the toss's cooldown unless the player is on the ground | A change to BUILD.md section 6 and to Ash's kit to fix a room; the floor is a perch too. |
| Wall-jump restores the air dash only when the next cling is on another wall (or the first re-cling on the same wall restores nothing) | The wall-jump's own restore feeds the cycle (the dash is back from the jump, not from the cling), so it needs the restore moved to the cling: a change to BUILD.md's wall-jump row and to tech 6's fixtures for a room whose checklist line ("climbs a single wall without feeling stuck") already holds. |

## Feel reason

Movement is the first pillar. A player who has put pogo, dash and the toss together should be allowed to; a room that is made unfair to them to prove a point is worse than one that is honest about the cost. Room 4's teaching route is 7.5 s against 42 s for the toss bypass. In room 5 the cycle is 85 ticks faster than the kicks but needs the wall-jump and the dash put together, which the zone teaches in room 6.

## Consequences

- Every future "only way" claim in a room header is read against this ADR. A control that says "no toss" must also run the waiting route; one that models a single toss says "one toss".
- The toss's 12 s cooldown can be waited out on any perch that restores nothing it spends (a post, a wall band with a wall-jump, the floor). A room that needs a toss to be unavailable must make it unavailable by its content, not by its geometry.
- **Camera.** `tests/unit/game/test_camera_rig.gd` now plays `tests/replay/zone1` at four screen shapes; the nine room fixtures hold its rules. The bypass fixture is kept out because it exposes a camera jolt: a pogo bounce during a teleport's glide changes the view's vertical speed by 13.7 u in one tick at 1920x1440 (the follow turns with the player at once, and the glide's own offset keeps its rate), against the 5 u limit. Tracked in PROGRESS.md.
- **Length.** BUILD.md has no length guide for a tech room's teaching route; the measured times (room 4's hidden route 9.2 s, room 5 6.9 s, room 6 8.1 s, each with about 2 s of running to and from the tech) are in the feel log.
- Revisit when Votives and hidden-room rewards exist (Phase 1 task 8 and later): if a bypass makes a reward trivially cheap, the cost, not the geometry, is what to tune.
