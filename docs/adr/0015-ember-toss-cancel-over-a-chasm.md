# ADR-0015: Teach tech 11 as "throw during the dash-jump chain, teleport over the chasm"

- Status: Accepted
- Date: 2026-10-19
- BUILD.md sections: 5 (the twelve core tech interactions, 11 "Ember-toss cancel"), 6 (Ember Toss: 600 u/s, 3 f startup, 6 f of invulnerability, 12 s cooldown)
- Checklist lines: "All 12 core tech interactions (section 5) stable and taught in-game" (tech 11, zone 1 room 11)

## Summary

- BUILD.md s5 tech 11 reads "throw the ember mid-dash, teleport after landing"; room 11 teaches "throw during the dash-jump chain, teleport over the chasm" (see Decision 1).
- The teleport comes while the body is airborne over the pit, 16 u above it, because a landing in the chasm is a hazard (see Decision 1).
- The chasm (2400 u wide) needs a reach past 2390 u: dash-jump with every resource reaches 2243 u, the same with one thrown ember 2505 u (see Decision 2).
- The throw is taught in the air dash and just after it; the room proves the toss is required, not the exact frame of the throw (see Decision 3).
- A throw spent before the chasm, or on a failed attempt, leaves the toss cooling down for 12 s (720 ticks); the room does not reset it (see Decision 4).
- The dip before the chasm teaches nothing about the toss; a control fixture holds the 12 s consequence (see Decision 4).

## Context

BUILD.md s5 line 236: "11. Ember-toss cancel (Ash): throw the ember mid-dash, teleport after landing. Taught by a chasm." A literal reading needs a landing between the throw and the teleport. In a chasm, the only landings are on the far side (the crossing is already made) or in the pit (a hazard that sends Ash back, ADR-0013). The pit, the smooth far face and the width of the gap are what make the chasm "the only way across"; an island to land on would give up that proof. The doc also leaves open how exactly the mid-dash throw is checked.

## Decision

1. Tech 11 is taught as: throw the ember during the dash-jump chain (the air dash is where the room's route throws), teleport to it over the pit, land on the far side. The "landing" of the BUILD.md line is the teleport's: it puts the body up and on, with 6 f of invulnerability, and the body lands past the far face. BUILD.md s5 line 236 is reworded to say so.
2. The chasm is 75 tiles (2400 u, near edge 480 u to the far face 2880 u). Numbers measured with `tools/replay/gap_reach.gd` on `test/longchasm`: 2243 u past the edge for a dash-jump with the air jump and air dash and no toss; 2505 u with one Ember Toss thrown up-right in the air dash; a crossing needs 2390 u (the gap less half the body's 20 u). `tests/unit/tools/test_zone1_room11_chasm.gd` holds the room to those numbers and runs the control fixtures to hold the numbers to the physics.
3. The throw may come up to 12 ticks after the air dash ends and still cross (measured); the room does not tighten it. What it proves is that no route without the toss crosses and that the route with a toss thrown after the dash-jump chain does.
4. The toss's 12 s cooldown (`toss_cooldown_frames` 720, from the throw) is not reset by the pit's send-back: it would make a hazard a free refill. The dip 54 u from the door is a warm-up jump and is not an invitation to throw; `tests/replay/zone1/11_control_toss_spent_in_dip.fixture` records that a toss spent there (or on a failed attempt) leaves the chasm uncrossable until the cooldown ends, about 9 s of waiting on the safe near ledge. A cooldown readout belongs to the HUD in Phase 2.

## Alternatives considered

| Option | Why not |
| --- | --- |
| An island in the chasm, land on it, then teleport | Gives up "the only way across": the island can be reached without the toss, or the width falls below what a dash-jump reaches |
| Reset the toss on the pit's send-back | A hazard would refill a 12 s ability; the cooldown is the spec |
| Require the throw on a named dash frame | Windows of 4 ticks on chained inputs are already tight for a teaching room (feel log) |

## Feel reason

The teleport over the pit with 6 f of invulnerability is the tech's payoff; making it the end of a crossing rather than a repositioning on the ground keeps it a movement tool (pillar one).

## Consequences

- BUILD.md s5 tech 11 reads "throw the ember during the dash-jump chain, teleport over the chasm (docs/adr/0015)".
- A failed attempt that threw costs 12 s on the near ledge; a HUD cooldown readout is a Phase 2 task.
- A literal landing-then-teleport reading remains an open question for the director (feel log 2026-10-19-zone1-11-ember-toss-cancel).
