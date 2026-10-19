class_name PlayerContacts
extends RefCounted
## What the world does to the player after its move each tick, beside the wall-cling: pogo
## bounces (BUILD.md section 5 Pogo), hazards and the last safe ground, the hurtbox (CLAUDE.md
## rule 8) and the Kindle Votive's dash-through (tech 12). Static helpers on a [Player], kept apart
## from the state machine so it stays readable; the state they change is the player's.

## How far apart the safe-ground check samples a floor that is not a wall tile (sub-pixels): a
## quarter of a tile, so a gap in the floor narrower than that is the only one it could miss, and
## no gap that narrow can hold the player's 20 u collider.
const SAFE_SAMPLE: int = TileGrid.TILE_SP / 4


## Bounces the player if the down-strike's live pogo box touches spikes or a pogo-able solid;
## true if it did. The bounce answers any jump pressed while the down-strike blocked the jump: that
## press is used up rather than firing the air jump the bounce just restored on the next tick,
## which would cut the bounce short and spend the jump.
static func check_pogo(pl: Player, ring: InputRing) -> bool:
	var box: Rect2i = pl.pogo_box()
	if box.size == Vector2i.ZERO:
		return false
	if not _pogo_target(pl.world, box):
		return false
	bounce(pl, ring, box)
	return true


## The pogo's bounce off whatever [param box] (the live pogo box) touched: spikes, a pogo-able
## solid or an enemy ([Combat]). The bounce answers any jump pressed while the down-strike
## blocked the jump, and hands control straight back ("anything on bounce").
static func bounce(pl: Player, ring: InputRing, box: Rect2i) -> void:
	var b: Body = pl.body
	pl.action_pogoed = true
	PlayerWall.refresh(pl)
	b.vy = -pl.p.pogo_bounce
	pl.air_jumps_left = pl.p.air_jumps
	pl.air_dashes_left = pl.p.air_dashes
	pl.jump_frame = 0
	pl.jump_cut = false
	pl.since_bounce = 1
	if pl.loco == Player.WALL:
		pl.wall_side = 0
	pl.loco = Player.AIR
	pl.left_by_jump = true
	if ring.has_press(InputFrame.JUMP, pl.p.jump_buffer_frames):
		ring.consume(InputFrame.JUMP)
	# The bounce shows where the pogo box hit: its centre.
	pl.events.add(SimEvents.POGO, box.get_center().x, box.get_center().y)
	# "Anything on bounce": the down-strike hands control straight back.
	pl.action = Player.NO_ACTION
	pl.action_frame = 0


static func _pogo_target(world: CollisionWorld, box: Rect2i) -> bool:
	var l: int = box.position.x
	var t: int = box.position.y
	var r: int = box.end.x
	var b: int = box.end.y
	if world.touches_spikes(l, r, t, b):
		return true
	for s: SolidBox in world.solids:
		if s.enabled and s.tag == "pogo" and s.overlaps(l, r, t, b):
			return true
	return false


## A hazard (spikes, or a pit) touching the hurtbox costs a heart (docs/adr/0013) and sends the
## player back to the last safe ground ([method send_back]), or to the spawn if the heart was the
## last.
static func check_hazards(pl: Player, ring: InputRing) -> void:
	if pl.is_invulnerable():
		return
	var hurt: Rect2i = hurtbox(pl)
	if not pl.world.touches_hazard(hurt.position.x, hurt.end.x, hurt.position.y, hurt.end.y):
		return
	pl.events.add(SimEvents.HAZARD, pl.body.x, pl.body.y)
	if not PlayerCombat.hazard(pl, ring):
		send_back(pl, ring, pl.safe_x, pl.safe_y)


## Puts the player at ([param x], [param y]) at rest with the hazard invulnerability; standing
## there again counts as a landing for the airtime's resources. Whatever was under way ends. An
## ember thrown before goes out (the throw's cooldown runs on): left out, a teleport to it would
## undo the send-back. Every press still buffered is used up, so nothing pressed over the hazard
## fires at the safe ground, and a stick held through the send-back is ignored until it is let go
## or turned (movement review 4, M1 and M2).
static func send_back(pl: Player, ring: InputRing, x: int, y: int) -> void:
	var b: Body = pl.body
	b.x = x
	b.y = y
	b.vx = 0
	b.vy = 0
	pl.action = Player.NO_ACTION
	pl.action_frame = 0
	pl.dash_frame = 0
	pl.carry_frames = 0
	pl.jump_frame = 0
	PlayerSpells.stop(pl)
	pl.radiance_burst = false
	pl.knock_left = 0
	pl.world.refresh_ground(b)
	pl.loco = Player.GROUND if b.on_ground else Player.AIR
	pl.wall_side = 0
	pl.toss.active = false
	pl.toss.flying = false
	pl.toss.startup = 0
	if b.on_ground:
		pl.restore_airtime()
	pl.invuln = pl.kit.hazard_invuln_frames
	pl.queued_attack_left = 0
	# Nothing of the wall or the turn carries over either: a wall-jump's direction lock would
	# leave the sprite facing the old way for its frames (movement review 5, L7).
	pl.wall_lock = 0
	pl.wall_coyote = 0
	pl.wall_coyote_side = 0
	pl.turn_left = 0
	for bit: int in InputFrame.BUTTONS:
		ring.consume(bit)
	pl.stick_hold_x = PlayerInput.axis(ring.stick_x(), pl.p.stick_threshold)


## Through a door (docs/adr/0014): the player arrives at bottom-centre ([param x], [param y]) in
## [param world], the next room's collision, keeping the speed, state, action and timers they
## had. An ember in the air stays in the room behind and goes out (its cooldown runs on); the
## arrival point is safe ground until the player stands on other ground (a side door stands on
## floor, and a fall through a top door lands on safe ground: RoomData checks both); dying
## returns to the new room's spawn ([param home_x], [param home_y]).
static func arrive(
	pl: Player, world: CollisionWorld, x: int, y: int, home_x: int, home_y: int
) -> void:
	pl.world = world
	pl.body.x = x
	pl.body.y = y
	world.refresh_ground(pl.body)
	pl.toss.active = false
	pl.toss.flying = false
	pl.safe_x = x
	pl.safe_y = y
	pl.home_x = home_x
	pl.home_y = home_y


## The hurtbox: the collider inset on every side (smaller than the sprite).
static func hurtbox(pl: Player) -> Rect2i:
	var b: Body = pl.body
	var l: int = b.left() + pl.kit.hurt_inset_x
	var r: int = b.right() - pl.kit.hurt_inset_x
	var t: int = b.top() + pl.kit.hurt_inset_top
	var bottom: int = b.y - pl.kit.hurt_inset_bottom
	return Rect2i(l, t, r - l, bottom - t)


## Remembers where the player stands if it is safe ground: flat, not a one-way, solid ground at the
## feet's height under the whole collider and [member KitParams.safe_ground_margin] beyond it on
## each side (a wall rising there is fine; a drop is not), and no hazard within a tile. A respawn
## then never stands on a ledge's lip with the stick that walked off it still carrying the player
## straight back off. The ground must also last (no box the game can take away, such as wax a
## kindle-dash burns) and have room to stand (not a crawl gap), so a send-back always lands a
## standing player on something (movement review 4, M3 and M4).
static func note_safe_ground(pl: Player) -> void:
	var b: Body = pl.body
	if not b.on_ground or b.on_slope or b.ground_tile == TileGrid.ONE_WAY:
		return
	if b.x == pl.safe_x and b.y == pl.safe_y:
		return
	var margin: int = pl.kit.safe_ground_margin
	if not _solid_under(pl.world, b.left() - margin, b.right() + margin, b.y):
		return
	if _fragile_under(pl.world, b.left() - margin, b.right() + margin, b.y):
		return
	if b.height != pl.p.height and not pl.world.headroom(b, pl.p.height):
		return
	var hurt: Rect2i = hurtbox(pl)
	if not pl.world.touches_hazard(
		hurt.position.x - TileGrid.TILE_SP,
		hurt.end.x + TileGrid.TILE_SP,
		hurt.position.y,
		b.y + TileGrid.TILE_SP
	):
		pl.safe_x = b.x
		pl.safe_y = b.y


## True if the sub-pixel row [param y] is solid all along [param l, r): a wall tile whose top is
## at most that row covers a tile column at once; elsewhere (a solid box laid as a floor, a
## slope) the row is sampled every [constant SAFE_SAMPLE] and at its end.
static func _solid_under(w: CollisionWorld, l: int, r: int, y: int) -> bool:
	var j: int = TileGrid.cell(y)
	var x: int = l
	while x < r:
		var c: int = TileGrid.cell(x)
		var end: int = mini((c + 1) * TileGrid.TILE_SP, r)
		if not TileGrid.is_wall(w.grid.get_tile(c, j)):
			var sx: int = x
			while sx < end:
				if not w.point_solid(sx, y):
					return false
				sx += SAFE_SAMPLE
			if not w.point_solid(end - 1, y):
				return false
		x = end
	return true


## True if a box the game can take away ([method SolidBox.fragile]) holds up any of the sub-pixel
## row [param y] along [param l, r).
static func _fragile_under(w: CollisionWorld, l: int, r: int, y: int) -> bool:
	for s: SolidBox in w.solids:
		if s.enabled and s.fragile() and s.overlaps(l, r, y, y + 1):
			return true
	return false


## With the Kindle Votive, wax solids in the dash's path this tick ignite and stop blocking
## (BUILD.md s5 tech 12). Passing through resets the air jump ("dash-through").
static func kindle_ahead(pl: Player) -> void:
	for s: SolidBox in wax_ahead(pl, Vector2i(pl.dash_vx, pl.dash_vy)):
		s.enabled = false
		pl.air_jumps_left = pl.p.air_jumps
		pl.events.add(SimEvents.IGNITE, (s.left + s.right) / 2, (s.top + s.bottom) / 2)


## The wax a kindle-dash at [param v] (sub-pixels a tick) ignites this tick: what the box it
## sweeps touches, reaching one sub-pixel further only on the sides it moves toward, so a wall
## touched at the start counts but one the dash leaves behind does not. None without the Kindle
## Votive.
static func wax_ahead(pl: Player, v: Vector2i) -> Array[SolidBox]:
	var out: Array[SolidBox] = []
	if not pl.kindle_dash:
		return out
	var b: Body = pl.body
	var l: int = mini(b.left(), b.left() + v.x) - (1 if v.x < 0 else 0)
	var r: int = maxi(b.right(), b.right() + v.x) + (1 if v.x > 0 else 0)
	var t: int = mini(b.top(), b.top() + v.y) - (1 if v.y < 0 else 0)
	var bottom: int = maxi(b.y, b.y + v.y) + (1 if v.y > 0 else 0)
	for s: SolidBox in pl.world.solids:
		if s.enabled and s.tag == "wax" and s.overlaps(l, r, t, bottom):
			out.append(s)
	return out


## True if a kindle-dash at [param v] burns through wax this tick: a dash toward a wax wall goes
## into it, even from a cling to it (tech 12; movement review 5, M4).
static func burns_through(pl: Player, v: Vector2i) -> bool:
	return not wax_ahead(pl, v).is_empty()
