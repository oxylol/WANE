# 2026-10-19: Zone 1 room 11, the Ember-toss cancel chasm

- Author: Claude
- BUILD.md section and table row: section 5, the twelve core tech interactions, 11 "Ember-toss cancel (Ash): throw the ember mid-dash, teleport after landing. Taught by a chasm"; section 6, Ember Toss ("600 u/s projectile", "3 f startup", "6 f of invulnerability")
- Fixture(s): `tests/replay/zone1/11_ember_toss_cancel.fixture` (the teaching route, from the west arrival at x 74 to the east door crossing at tick 246), `11_control_dash_jump_only.fixture`, `11_control_plain_throw.fixture`
- Contact sheet: `docs/feel_log/2026-10-19-zone1-11-ember-toss-cancel.png` (row 1: the whole route, a frame every 20 ticks from tick 4; row 2: the throw and the teleport, a frame every 5 ticks from tick 146; F3 overlay on)

## Change

First implementation of room 11 (`content/rooms/zone1/11_ember_toss_cancel.room`, a stub before); no tuning number changed. The numbers the room is built on, all measured with `tools/replay/gap_reach.gd` on `test/longchasm` (the near half of this room's chasm, no far side):

| Number | Before | After | Unit |
| --- | --- | --- | --- |
| Chasm width, near edge 480 to far face 2880 | stub, none | 2400 (75 tiles) | u |
| Farthest reach, dash-jump with air jump and air dash, no toss | 2243 (measured) | 2243 | u past the edge |
| Farthest reach, the same route with one Ember Toss thrown up-right on air-dash frame 6 | 2505 (measured) | 2505 | u past the edge |
| Reach a crossing needs (width less half the body's 20 u) | none | 2390 | u |

## Why

Tech 11 must be taught by a chasm that only the throw crosses. The toss adds a free 400 u of flight, so the chasm has to be wider than anything a dash-jump with every resource reaches (2243 u, 147 u short of 2390) and narrower than the same route with a toss thrown mid-dash (2505 u, 115 u over). The best throws are late in the air dash, up-right, so the ember is as far ahead as it can be when the body would fall into the pit; the teleport then comes on the last tick before the fall reaches the pit (16 u above it). Routes with a toss but no dash-jump reach 1592 u at most (ADR-0010) and a plain throw 400 u past the throwing spot.

The room is 105 x 20 tiles, not 60 x 34: the chasm needs 75 tiles and the ceiling 12 tiles above the ledge is part of what was measured. It has a safe first encounter, a dip 128 u wide and 64 u deep 54 u from the door, which costs nothing to fall into and crosses with a tap jump.

The contact sheet shows the route as built: row 1, the tap jump over the dip, the dash off the near ledge (it runs flat past the edge), the dash-jump, the air jump high over the pit, the air dash, the teleport, the landing on the far ledge and the run to the door; row 2, the throw on air-dash frame 6 (the dash carries on to its ninth frame), the ember going up-right, the body dropping towards the pit, and on the teleport the body jumping to the ember near the ceiling with the far ledge in view and falling onto it. The camera stays level with the player throughout and does not lose them at the teleport (it cuts to the new position as on any teleport). At sheet size the player is small; the overlay's boxes are readable only on a zoomed crop.

## How it plays now

A skilled player runs 3 s, jumps the dip, dash-jumps off the ledge, spends the air jump over the middle of the chasm, air-dashes up-right and throws on its sixth frame, falls towards the pit and teleports on the last tick, then lands on the far side: 246 ticks (4.1 s) from the west door to the east one. `11_control_dash_jump_only` runs every resource but the toss and falls into the pit short of the far face; `11_control_plain_throw` throws and teleports from the near ledge and falls well short (the ember stops 400 u out, at 816 u). The window is tight, the teleport has no more than a few ticks of slack on either side, by design: a crossing only 115 u inside the toss route's reach.

## Open questions for the director

- Play it: is a throw timed to the air dash and a teleport on the last tick too hard for a teaching room? The width can come down to about 2300 u (a 147 u margin over the dash-jump becomes about 50) if so, at the cost of a thinner proof that the toss is needed.
- The room cannot read "after landing" literally: the teleport comes while the body is still airborne over the pit, and the landing is the teleport's. If the director wants a literal landing in the chasm, it needs an island and gives up "the only way across".
