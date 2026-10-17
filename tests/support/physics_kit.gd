class_name PhysicsKit
extends RefCounted
## Shared helpers for the physics unit suites: worlds from map rows, player-sized bodies, the
## grounded step the player state machine performs, falls under per-tick gravity, and the
## invariants every move must keep. Distances are in world units.

const U: int = Fx.SUB
const HALF_W: int = 10 * Fx.SUB
const STAND: int = 44 * Fx.SUB
const CROUCH: int = 28 * Fx.SUB
## Ash's movement tuning, for the fall gravity and terminal speed drops use.
const MOVEMENT_PATH: String = "res://content/wicks/ash/movement.tres"


## A world from map rows, with the game's world tuning. The rows must pass
## [method TileGrid.validate] (rooms that do not never reach the physics).
static func world(rows: Array[String]) -> CollisionWorld:
	var grid: TileGrid = TileGrid.from_rows(PackedStringArray(rows))
	var problems: PackedStringArray = grid.validate()
	assert(problems.is_empty(), "test room is not valid: %s" % "; ".join(problems))
	var w := CollisionWorld.new(grid)
	(load(WorldTuning.PATH) as WorldTuning).apply(w)
	return w


## A 20 x [param height] box with its bottom-centre at ([param x_u], [param y_u]) units.
static func body(x_u: int, y_u: int, height: int = STAND) -> Body:
	return Body.make(x_u * U, y_u * U, HALF_W, height)


## Grounded step, as the player state machine performs it.
static func walk(w: CollisionWorld, b: Body, dx: int) -> int:
	b.clear_contacts()
	return w.walk(b, dx)


## Ash's fall gravity, in sub-pixels per tick per tick (BUILD.md section 5 Jump table, "Gravity
## (fall)", as tuned in content), so drops fall the way the player does.
static func fall_gravity() -> int:
	return Fx.accel((load(MOVEMENT_PATH) as MovementTuning).gravity_fall_ups2)


## Ash's terminal fall speed, in sub-pixels per tick ("Terminal velocity", as tuned in content).
static func terminal() -> int:
	return Fx.speed((load(MOVEMENT_PATH) as MovementTuning).terminal_ups)


## Lets [param b] fall from rest one tick at a time under Ash's fall gravity, the way the player
## falls, until it lands or [param max_ticks] pass. Returns the ticks taken.
static func fall(w: CollisionWorld, b: Body, max_ticks: int = 200) -> int:
	var g: int = fall_gravity()
	var top: int = terminal()
	var vy: int = 0
	for tick: int in range(max_ticks):
		vy = mini(vy + g, top)
		w.move_y(b, vy)
		if b.on_ground:
			return tick + 1
	return max_ticks


## True if the body's upper body (above its foot zone) overlaps anything solid, or its foot
## point is inside something solid: the two things the physics never allows.
static func embedded(w: CollisionWorld, b: Body) -> bool:
	if w.region_blocked(b.left(), b.right(), b.top(), b.y - b.half_w):
		return true
	if w.point_solid(b.x, b.y - 1):
		return true
	for s: SolidBox in w.solids:
		if s.enabled and s.overlaps(b.left(), b.right(), b.top(), b.y):
			return true
	return false


## True if a grounded body hovers: it rests on a wall top while the slope under its centre is at
## most its foot zone lower (the crest that slope leads to, which holds nothing up). A one-way or
## solid-box top under it at its height is a real support.
static func hovering(w: CollisionWorld, b: Body) -> bool:
	if not b.on_ground or b.on_slope:
		return false
	var c: int = TileGrid.cell(b.x)
	var j: int = TileGrid.cell(b.y)
	var t: int = w.grid.get_tile(c, j)
	if not TileGrid.is_slope(t):
		return false
	var s: int = TileGrid.slope_surface(t, c, j, b.x)
	if s <= b.y or s - b.y > b.half_w:
		return false
	for sb: SolidBox in w.solids:
		if sb.enabled and sb.top == b.y and sb.left < b.right() and sb.right > b.left():
			return false
		# A solid box's top above the slope under the centre is the floor there, not the slope:
		# the wall top beside it is a ledge, not a crest.
		if sb.enabled and sb.top > b.y and sb.top <= s and sb.left <= b.x and b.x < sb.right:
			return false
	var row: int = Fx.div_floor(b.y, TileGrid.TILE_SP)
	if row * TileGrid.TILE_SP == b.y:
		for col: int in range(TileGrid.cell(b.left()), TileGrid.cell(b.right() - 1) + 1):
			if w.grid.get_tile(col, row) == TileGrid.ONE_WAY:
				return false
	return true


## True if something solid lies within a unit of the body in [param dir]: beside it, above its
## head, or in its foot zone just ahead (the only things that may stop a walk). A walk that
## reports a wall with none of these near was stopped by nothing. In the foot zone, the crest a
## slope leads to (a wall whose top is in the foot zone, with a slope before it whose raised side
## meets that top) does not count: the foot zone passes into it and the foot point rides up.
static func blocked_for_a_reason(w: CollisionWorld, b: Body, dir: int) -> bool:
	var l: int = b.left() - (U if dir < 0 else 0)
	var r: int = b.right() + (U if dir > 0 else 0)
	if w.region_blocked(l, r, b.top() - U, b.y - b.half_w):
		return true
	for s: SolidBox in w.solids:
		if s.enabled and s.overlaps(l, r, b.top() - U, b.y + U):
			return true
	var al: int = b.right() if dir > 0 else b.left() - U
	var foot_top: int = b.y - b.half_w
	for c: int in range(TileGrid.cell(al), TileGrid.cell(al + U - 1) + 1):
		for j: int in range(TileGrid.cell(foot_top), TileGrid.cell(b.y - 1) + 1):
			var t: int = w.grid.get_tile(c, j)
			if TileGrid.is_wall(t) and not _crest(w, c, j, dir):
				return true
			if TileGrid.is_slope(t) and w.region_blocked(al, al + U, foot_top, b.y):
				return true
	return false


## True if wall tile (c, j) is the crest a slope leads to for a box moving in [param dir]: the
## top of its run, with a slope before it whose raised side meets that top.
static func _crest(w: CollisionWorld, c: int, j: int, dir: int) -> bool:
	if TileGrid.is_wall(w.grid.get_tile(c, j - 1)):
		return false
	var before: int = w.grid.get_tile(c - dir, j)
	if not TileGrid.is_slope(before):
		return false
	var edges: Vector2i = TileGrid.slope_edge_heights(before)
	return (edges.y if dir > 0 else edges.x) == TileGrid.TILE_SP
