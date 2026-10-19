class_name CameraSubject
extends RefCounted
## What the camera follows on one tick, read from the simulation (presentation reads the core and
## never writes it). Units are world units, y down.

## [member ground_below] when nothing below would hold the player up.
const NO_GROUND: float = 1.0e9

## The player's collider.
var box: Rect2 = Rect2()
## The standing collider's height, so crouching does not move the camera.
var stand_height: float = 0.0
var facing: int = 1
## The player is asking to look down: standing crouched on the ground, the stick held straight
## down, not dashing and not striking (a crouch-dash, a crawl under a low ceiling or a crouched
## strike in a fight is not a request to look; CLAUDE.md rule 9).
var looking_down: bool = false
## Dashing upward (straight or diagonally): the camera looks ahead of it, as it does of a fall.
var dashing_up: bool = false
## On the ground, on a wall (clinging, wall-jumping or kicking off it) or bouncing off a pogo this
## tick: a height the camera settles on (see [CameraRig]).
var supported: bool = false
## Standing on the ground (one kind of support).
var on_ground: bool = false
## On a wall this tick: clinging, or kicking or wall-jumping off it.
var walled: bool = false
## How far below the feet the ground is that the player's fall will land on, following their
## path ([constant NO_GROUND] if none within the look-ahead): see [method of].
var ground_below: float = NO_GROUND
## Vertical speed, units per tick, down positive.
var vy: float = 0.0
## Sent back to safe ground by a hazard this tick: the camera cuts.
var respawned: bool = false
## Teleported to the ember this tick: the camera glides after.
var teleported: bool = false


## The subject for [param sim]'s player. [param ahead_frames] is how many ticks of the fall's
## path the ground below is looked for along (0: not at all).
static func of(sim: Simulation, ahead_frames: int = 0) -> CameraSubject:
	var s := CameraSubject.new()
	var pl: Player = sim.player
	var b: Body = pl.body
	s.box = Rect2(
		float(b.left()) / Fx.SUB,
		float(b.top()) / Fx.SUB,
		float(b.right() - b.left()) / Fx.SUB,
		float(b.height) / Fx.SUB
	)
	s.stand_height = float(pl.p.height) / Fx.SUB
	s.facing = pl.facing
	var t: int = pl.p.stick_threshold
	var stick_down: bool = sim.input.stick_y() >= t and absi(sim.input.stick_x()) < t
	s.looking_down = (
		pl.crouching
		and stick_down
		and b.on_ground
		and pl.loco == Player.GROUND
		and pl.action == Player.NO_ACTION
	)
	s.dashing_up = pl.loco == Player.DASH and pl.dash_vy < 0
	s.on_ground = b.on_ground
	s.walled = (
		pl.loco == Player.WALL
		or sim.events.has(SimEvents.WALL_KICK)
		or sim.events.has(SimEvents.WALL_JUMP)
	)
	s.supported = (
		b.on_ground
		or pl.loco == Player.WALL
		or sim.events.has(SimEvents.POGO)
		or sim.events.has(SimEvents.WALL_KICK)
		or sim.events.has(SimEvents.WALL_JUMP)
	)
	if b.on_ground:
		s.ground_below = 0.0
	elif ahead_frames > 0:
		s.ground_below = _ground_ahead(sim.world, pl, ahead_frames)
	s.vy = float(b.vy) / Fx.SUB
	s.respawned = sim.events.has(SimEvents.HAZARD)
	s.teleported = sim.events.has(SimEvents.TELEPORT)
	return s


## How far below the feet the first floor is along the player's path over the next
## [param frames] ticks, the path keeping the horizontal speed it has and falling under the
## Wick's gravity, its horizontal travel held up by a wall for as long as the wall is there (the
## player keeps the speed while the stick holds that way, so a wall that ends lets the path on).
## Each tick's step is checked as one box spanning all of it, so ground between the ticks is never
## missed, and ledges the path passes above are not counted. The box is widened on each side by how
## far air control could still steer the player that way by then ([method _steer_reach]), up to
## the first wall or solid box at the player's height there ([method _clear_beside]): the camera
## cannot know the stick's future, so a ledge the player could still steer onto counts as the
## ground the fall lands on, and the look never reaches past it, while a wall beside the fall (a
## cling let go, a shaft) is not ground. A ledge top up to the ledge-grab above the feet in the
## widened part counts too: steering into its side lifts the player onto it (camera review 5,
## H1). Read-only queries: the camera never writes the core.
static func _ground_ahead(world: CollisionWorld, pl: Player, frames: int) -> float:
	var b: Body = pl.body
	var x: int = b.x
	var y: int = b.y
	var pvx: int = b.vx
	var pvy: int = b.vy
	for k: int in range(1, frames + 1):
		pvy = mini(pvy + (pl.p.gravity_rise if pvy < 0 else pl.p.gravity_fall), pl.p.terminal)
		var nx: int = x + pvx
		if (
			pvx != 0
			and world.region_blocked(
				mini(x, nx) - b.half_w, maxi(x, nx) + b.half_w, y - b.height, y - b.half_w
			)
		):
			nx = x
		var ny: int = y + pvy
		if pvy > 0:
			var near_l: int = mini(x, nx) - b.half_w
			var near_r: int = maxi(x, nx) + b.half_w
			var top: int = y - b.height
			var l: int = (
				near_l - _clear_beside(world, near_l, top, y, -1, _steer_reach(pl, b.vx, -1, k))
			)
			var r: int = (
				near_r + _clear_beside(world, near_r, top, y, 1, _steer_reach(pl, b.vx, 1, k))
			)
			var floor_y: int = world.floor_top_in(l, r, y, ny)
			if floor_y == CollisionQueries.NONE:
				var grab: int = pl.p.ledge_grab
				if (
					world.floor_top_in(l, near_l, y - grab, y) != CollisionQueries.NONE
					or world.floor_top_in(near_r, r, y - grab, y) != CollisionQueries.NONE
				):
					floor_y = y
			if floor_y != CollisionQueries.NONE:
				return float(floor_y - b.y) / Fx.SUB
		x = nx
		y = ny
	return NO_GROUND


## How far (up to [param reach]) a span from x [param edge] outward in [param dir] is clear of
## walls and solid boxes over the heights [param top, bottom): the room the player has to steer
## that way at that height. Slopes do not stop it: the player can come down onto one.
static func _clear_beside(
	world: CollisionWorld, edge: int, top: int, bottom: int, dir: int, reach: int
) -> int:
	if reach <= 0:
		return 0
	var free: int = reach
	var row_a: int = TileGrid.cell(top)
	var row_b: int = TileGrid.cell(bottom - 1)
	var c: int = TileGrid.cell(edge) if dir > 0 else TileGrid.cell(edge - 1)
	var last: int = TileGrid.cell(edge + reach - 1) if dir > 0 else TileGrid.cell(edge - reach)
	while (c <= last) if dir > 0 else (c >= last):
		for j: int in range(row_a, row_b + 1):
			if TileGrid.is_wall(world.grid.get_tile(c, j)):
				var face: int = c * TileGrid.TILE_SP if dir > 0 else (c + 1) * TileGrid.TILE_SP
				free = mini(free, maxi((face - edge) * dir, 0))
				break
		if free < reach:
			break
		c += dir
	for sb: SolidBox in world.solids:
		if not sb.enabled or sb.bottom <= top or sb.top >= bottom:
			continue
		var gap: int = (sb.left - edge) if dir > 0 else (edge - sb.right)
		var past: bool = (sb.right > edge) if dir > 0 else (sb.left < edge)
		if past:
			free = mini(free, maxi(gap, 0))
	return free


## How much further toward [param dir] air control could carry a player moving at [param vx] in
## [param ticks] ticks than that speed alone: accelerating at the air acceleration until the
## speed that way reaches run speed (BUILD.md "Air control: 0 to max in 8 f"), in sub-pixels, plus
## the ledge-grab's reach. The player's speed changes before each tick's move, so the travel is
## the sum a + 2a + ... per tick (camera review 5, H1: a*k^2/2 fell short by a*k/2).
static func _steer_reach(pl: Player, vx: int, dir: int, ticks: int) -> int:
	var gain: int = pl.p.run_speed - vx * dir
	if gain <= 0:
		return 0
	var accel: int = pl.p.air_accel
	var full: int = gain / accel
	if ticks <= full:
		return Fx.div_floor(accel * ticks * (ticks + 1), 2) + pl.p.ledge_grab
	return Fx.div_floor(accel * full * (full + 1), 2) + gain * (ticks - full) + pl.p.ledge_grab


## The point the camera aims at before its lead: the centre of a standing player.
func anchor() -> Vector2:
	return Vector2(box.get_center().x, box.end.y - stand_height * 0.5)
