class_name CollisionWorld
extends CollisionQueries
## The physics sweep (BUILD.md section 5, the ground and wall tables and the feel rules; section
## 13: "the AABB physics sweep (slopes, one-way platforms, corner correction)"; docs/adr/0008).
##
## Geometry is a [TileGrid] plus [SolidBox]es. Rooms are validated before they reach the physics
## ([method TileGrid.validate]): every slope rests on a wall, and each raised side of a slope meets
## a wall or a slope edge of the same height, so a slope only ever shows its diagonal surface.
##
## A [Body] collides in three parts:
## - its upper body, everything above the foot zone, never overlaps a wall, a solid box or a
##   slope;
## - its foot point, the bottom-centre, stands on floors and slopes and never goes inside
##   anything solid;
## - its foot zone, the lowest [member Body.half_w] of the box, may overlap slopes and the edge of
##   a wall that continues a slope (a crest): a box standing by its centre on a 45-degree slope has
##   its uphill corner exactly that deep in the ground.
## Solid boxes block the whole box. Every distance is in sub-pixels and every result is exact
## integer arithmetic. The geometry questions the moves ask live in [CollisionQueries]; like
## them, a move keeps working state in member variables, so a world must be used from one thread
## at a time. While a move runs, [member solids] holds only the enabled boxes the
## move can reach (a broad phase; the order is kept); the full list is back before it returns.

# The box a walking sweep moves (see _sweep_walk and _swept_advance): its left, right and top
# edges, direction, horizontal distance and rise or fall.
var _sw_l: int = 0
var _sw_r: int = 0
var _sw_t: int = 0
var _sw_dir: int = 0
var _sw_seg: int = 0
var _sw_dy: int = 0
# Set by the walking sweep: the descent was cut short by landing on a solid box's top, and the
# last swept contact was through the obstacle's top or bottom edge rather than its side.
var _walk_onto_top: bool = false
var _swept_by_y: bool = false


func _init(p_grid: TileGrid = null) -> void:
	grid = p_grid if p_grid != null else TileGrid.new()
	WorldTuning.new().apply(self)
	native = NativeWorld.create()


## Called at the start of every simulation tick: the native copy of the boxes is compared with
## the list as it stands now ([method NativeWorld.recheck]), so a box put in place of another, or
## two swapped, is seen.
func begin_tick() -> void:
	if native != null:
		native.recheck()


# --- horizontal, airborne ------------------------------------------------------------------


## Airborne horizontal movement: moves [param body] by [param dx], stopping at walls and solid
## boxes, and riding up a slope its foot point flies into. [param lift_sp] is the corner
## correction over ledge corners (BUILD.md: 8 u; 10 u while the player holds toward the wall, the
## automatic ledge-grab) and [param duck_sp] the correction under ceiling corners; neither applies
## to a body on the ground, which moves with [method walk]. Returns the distance moved.
func move_x(body: Body, dx: int, lift_sp: int = 0, duck_sp: int = 0) -> int:
	if dx == 0:
		return 0
	if native != null:
		return native.move_x(self, body, dx, lift_sp, duck_sp)
	var all: Array[SolidBox] = solids
	if not all.is_empty():
		all = _narrow_solids(body, absi(dx))
	var x0: int = body.x
	var airborne: bool = not body.on_ground
	_move_x(body, dx, lift_sp, duck_sp)
	if airborne and lift_sp > 0 and body.hit_wall == signi(dx):
		_air_steps(body, dx, x0, lift_sp)
	_restore_solids(all)
	return body.x - x0


## The solid boxes within [param reach] plus the body's half-width and a tile of it, in their
## order, made the world's list while a move runs; returns the full list to restore.
func _narrow_solids(body: Body, reach: int) -> Array[SolidBox]:
	var all: Array[SolidBox] = solids
	var m: int = reach + body.half_w + TileGrid.TILE_SP
	var l: int = body.x - body.half_w - m
	var r: int = body.x + body.half_w + m
	var t: int = body.y - body.height - m
	var b: int = body.y + m
	var near: Array[SolidBox] = []
	for sb: SolidBox in all:
		if sb.enabled and sb.left < r and sb.right > l and sb.top < b and sb.bottom > t:
			near.append(sb)
	solids = near
	_narrowed += 1
	return all


## True if a walk of [param dx] by [param body] would be served by [FlatWalk]: it stands on a
## plain flat floor that goes on under it for the whole move. A cheap "is there floor ahead" for
## a walker (docs/adr/0020); false only says the sweep must be asked.
func flat_ahead(body: Body, dx: int) -> bool:
	if native != null:
		return false
	return use_flat_walk and _narrowed == 0 and flat.covers(body, dx, grid, solids)


## Puts the full list [param all] back after a move that may have narrowed it.
func _restore_solids(all: Array[SolidBox]) -> void:
	if not is_same(solids, all):
		_narrowed -= 1
		solids = all


## The air corner lift is measured from the feet where the move began. Skimming over a slope,
## riding up one, or after a first lift onto a lip, the floor at the box's leading edge is higher:
## a lip that stopped the move from [param x0] by [param dx] within [param lift_sp] of that floor
## is stepped up as a walk steps it, and the move carries on. Each step rises and the move after
## it makes progress, so this ends.
func _air_steps(body: Body, dx: int, x0: int, lift_sp: int) -> void:
	var dir: int = signi(dx)
	var stepped: bool = false
	while body.hit_wall == dir:
		var left: int = absi(dx) - absi(body.x - x0)
		if left <= 0 or not _step_up(body, dir, lift_sp):
			break
		stepped = true
		body.hit_wall = 0
		_move_x(body, dir * left, 0, 0)
	if stepped:
		refresh_ground(body)


func _move_x(body: Body, dx: int, lift_sp: int, duck_sp: int) -> void:
	var dir: int = 1 if dx > 0 else -1
	var left: int = absi(dx)
	var y0: int = body.y
	var allowed: int = _sweep_x(
		body.left(), body.right(), body.top(), body.y, dir, left, body.half_w
	)
	if allowed < left and not body.on_ground:
		if lift_sp > 0 and _try_lift(body, dir, left, allowed, lift_sp):
			return
		if duck_sp > 0 and _try_duck(body, dir, left, allowed, duck_sp):
			return
	while true:
		var xs: int = body.x
		var ys: int = body.y
		var target: int = xs + dir * allowed
		body.x = target
		_settle_foot(body, xs, dir)
		left -= absi(body.x - xs)
		if left == 0 or allowed == 0 or body.x != target or body.y == ys:
			break
		# Riding up a slope brought what stopped the sweep (the crest ahead, or the wall under
		# the next row's slope) into the foot zone: the move carries on from the new height.
		allowed = _sweep_x(body.left(), body.right(), body.top(), body.y, dir, left, body.half_w)
	if left > 0:
		body.hit_wall = dir
	# A body that was on the ground, or rose onto a slope, learns where it stands now. One that
	# was in the air and slid level is still in the air unless its feet happen to reach a floor
	# at exactly their height; the move_y every air step makes next finds that (and a walk's
	# airborne remainder refreshes itself), so the full ground query is not run twice a tick.
	if body.on_ground or body.y != y0:
		refresh_ground(body)


## How far a box [l, r) x [t, b) can travel in [param dir] (up to [param dist]) before touching a
## wall tile or solid box it does not already overlap. Slopes are left to [method _settle_foot],
## and so is the crest a slope leads to: its wall only stops the box above the foot zone (the
## lowest [param foot] of it), as when walking (see [method _column_blocks]).
func _sweep_x(l: int, r: int, t: int, b: int, dir: int, dist: int, foot: int = 0) -> int:
	var best: int = dist
	var row_a: int = TileGrid.cell(t)
	var row_b: int = TileGrid.cell(b - 1)
	var foot_top: int = b - foot
	if dir > 0:
		var c: int = TileGrid.cell(r - 1) + 1
		var c_end: int = TileGrid.cell(r + dist - 1)
		while c <= c_end:
			if _column_blocks(c, row_a, row_b, foot_top, dir):
				best = c * TileGrid.TILE_SP - r
				break
			c += 1
	else:
		var c: int = TileGrid.cell(l) - 1
		var c_end: int = TileGrid.cell(l - dist)
		while c >= c_end:
			if _column_blocks(c, row_a, row_b, foot_top, dir):
				best = l - (c + 1) * TileGrid.TILE_SP
				break
			c -= 1
	for sb: SolidBox in solids:
		if not sb.enabled or sb.bottom <= t or sb.top >= b:
			continue
		if dir > 0 and sb.left >= r:
			best = mini(best, sb.left - r)
		elif dir < 0 and sb.right <= l:
			best = mini(best, l - sb.right)
	return best


## True if tile column [param c] has a wall in rows [param row_a] to [param row_b] that stops a box
## moving in [param dir] whose foot zone starts at [param foot_top]. The first wall down the column
## stops it unless it is the crest a slope leads to: its top is in the foot zone and the tile
## before it (in [param dir]) is a slope whose raised side meets that top. The foot point rides up
## the slope onto it ([method _settle_foot]); a box walking or dashing up a ramp passes its crest,
## or the wall under the next row's slope, without stopping.
func _column_blocks(c: int, row_a: int, row_b: int, foot_top: int, dir: int) -> bool:
	for j: int in range(row_a, row_b + 1):
		if not TileGrid.is_wall(grid.get_tile(c, j)):
			continue
		if j * TileGrid.TILE_SP < foot_top:
			return true
		var before: int = grid.get_tile(c - dir, j)
		if not TileGrid.is_slope(before):
			return true
		var edges: Vector2i = TileGrid.slope_edge_heights(before)
		return (edges.y if dir > 0 else edges.x) != TileGrid.TILE_SP
	return false


## After a horizontal move from [param x0] at the body's height: if the foot point's path went
## into a slope (or into the wall a crest corner already rested in), the body rides up onto the
## surface when it has the headroom and the rise is no steeper than the slopes allow. If the rise
## does not fit all the way (a ceiling or a solid box over the ramp ahead), the body goes as far
## as it can riding up under the lowest ceiling over its path, as a walk up the slope would, and
## stops there. Its upper body stays clear on the way: the sweep cleared it of walls and solid
## boxes at the old height, the rise only enters the space found clear above, and a box whose
## foot point is on a slope cannot reach the slope with the rest of its body.
func _settle_foot(body: Body, x0: int, dir: int) -> void:
	var x1: int = body.x
	if x1 == x0:
		return
	var y: int = body.y
	var limit: int = maxi(absi(x1 - x0) + Fx.SUB, body.half_w)
	var depth: int = _rise(x0, x1, y, limit)
	if depth <= 0:
		return
	if depth <= limit and _ride_fits(body, depth):
		body.y = y - depth
		return
	body.hit_wall = dir
	# The furthest point at which the rise fits under the lowest ceiling over the path travelled
	# to it (and is no steeper than the slopes allow); at x0 itself the foot point is on the
	# surface. A ceiling beyond that point never shortens the ride.
	var ok: int = 0
	var bad: int = absi(x1 - x0)
	while bad - ok > 1:
		var mid: int = (ok + bad) / 2
		var most: int = mini(
			_space_over(body, x0, x0 + dir * mid, limit), maxi(mid + Fx.SUB, body.half_w)
		)
		if _rise(x0, x0 + dir * mid, y, most) <= most:
			ok = mid
		else:
			bad = mid
	body.x = x0 + dir * ok
	body.y = y - _rise(x0, body.x, y, _space_over(body, x0, body.x, limit))


## The free space (up to [param limit]) above the box's top over its path from [param x0] to
## [param x1].
func _space_over(body: Body, x0: int, x1: int, limit: int) -> int:
	return _clear_up(mini(x0, x1) - body.half_w, maxi(x0, x1) + body.half_w, body.top(), limit)


## How far the foot point must rise to cross [param x0] to [param x1] at height [param y] on top
## of the floors it meets: a rise that lifts it into the tile row above can meet the slope that
## carries on up there, so the depth is read again at each new height until the path is clear.
## Stops counting once past [param limit].
func _rise(x0: int, x1: int, y: int, limit: int) -> int:
	var depth: int = _foot_depth(x0, x1, y)
	var more: int = depth
	while more > 0 and depth <= limit:
		more = _foot_depth(x0, x1, y - depth)
		depth += more
	return depth


## True if [param body] can rise by [param rise] where it is: nothing above its top in the way,
## and its upper body clear of anything solid at the new height.
func _ride_fits(body: Body, rise: int) -> bool:
	if _clear_up(body.left(), body.right(), body.top(), rise) < rise:
		return false
	return not region_blocked(
		body.left(), body.right(), body.top() - rise, body.y - rise - body.half_w
	)


## How deep the foot point's level path from [param x0] to [param x1] at height [param y] goes
## below the floor surfaces it crosses: the most it would have to rise to stay on top, 0 if the
## path is clear. Only the row holding the foot point (y - 1) can hold such a floor: a slope's
## surface, or the top of a wall a crest corner already rests in. Anything in a row above it is a
## ceiling over the box, never a floor it has sunk into; a rise into that row reads it again
## ([method _settle_foot]).
func _foot_depth(x0: int, x1: int, y: int) -> int:
	var lo: int = mini(x0, x1)
	var hi: int = maxi(x0, x1)
	var depth: int = 0
	var j: int = TileGrid.cell(y - 1)
	for c: int in range(TileGrid.cell(lo), TileGrid.cell(hi) + 1):
		var t: int = grid.get_tile(c, j)
		if TileGrid.is_wall(t):
			depth = maxi(depth, y - _wall_top(c, j))
		elif TileGrid.is_slope(t):
			var xa: int = maxi(lo, c * TileGrid.TILE_SP)
			var xb: int = mini(hi, (c + 1) * TileGrid.TILE_SP - 1)
			var s: int = mini(
				TileGrid.slope_surface(t, c, j, xa), TileGrid.slope_surface(t, c, j, xb)
			)
			depth = maxi(depth, y - s)
	return depth


## The top of the wall run containing tile (c, j): the first non-wall tile above it, looking at
## most two tiles up (a run taller than that is deeper than any rise a move allows, and outside
## the grid every tile is a wall).
func _wall_top(c: int, j: int) -> int:
	var k: int = j
	while k > j - 3 and TileGrid.is_wall(grid.get_tile(c, k - 1)):
		k -= 1
	return k * TileGrid.TILE_SP


## Corner correction over a ledge: having stopped [param allowed] short against a wall or solid
## whose top is at most [param max_lift] above the box's bottom, the box rises onto it and carries
## on, if the space is free and it makes progress. It never lifts onto a crest: the crest a slope
## leads to does not stop the foot zone ([method _column_blocks]). As on the ground
## ([method _step_up]), the lift is to the top of what stands just ahead of the box, not of a crest
## wall its foot zone already rests in behind it.
func _try_lift(body: Body, dir: int, dist: int, allowed: int, max_lift: int) -> bool:
	var x0: int = body.x
	var y0: int = body.y
	var xs: int = x0 + dir * allowed
	var l: int = xs - body.half_w
	var r: int = xs + body.half_w
	var top: int = y0 - body.height
	var obstacle_top: int = _wall_top_ahead(l, r, top, y0, dir)
	var lift: int = y0 - obstacle_top
	if lift <= 0 or lift > max_lift:
		return false
	if _clear_up(l, r, top, lift) < lift:
		return false
	var rest: int = dist - allowed
	var after: int = _sweep_x(l, r, top - lift, y0 - lift, dir, rest, body.half_w)
	if after <= 0:
		return false
	body.x = xs + dir * after
	body.y = y0 - lift
	_settle_foot(body, xs, dir)
	if after < rest or body.x != xs + dir * after:
		body.hit_wall = dir
	body.nudge_y -= lift
	refresh_ground(body)
	return true


## Corner correction under a ceiling corner: having stopped [param allowed] short against a wall
## or solid that overlaps at most the top [param max_duck] of the box, the box drops under it and
## carries on, if nothing it could stand on (a floor, a one-way top, a slope) lies in the way down,
## here or where it ends up.
func _try_duck(body: Body, dir: int, dist: int, allowed: int, max_duck: int) -> bool:
	var x0: int = body.x
	var y0: int = body.y
	var xs: int = x0 + dir * allowed
	var l: int = xs - body.half_w
	var r: int = xs + body.half_w
	var top: int = y0 - body.height
	var duck: int = _lowest_ceiling_bottom(l + dir, r + dir, top, y0) - top
	if duck <= 0 or duck > max_duck:
		return false
	body.x = xs
	if _landing(body, y0, y0 + duck) != NONE or _walls_overlap(l, r, y0, y0 + duck):
		body.x = x0
		return false
	var rest: int = dist - allowed
	var after: int = _sweep_x(l, r, top + duck, y0 + duck, dir, rest, body.half_w)
	if after <= 0:
		body.x = x0
		return false
	body.x = xs + dir * after
	if _landing(body, y0, y0 + duck) != NONE or _foot_depth(xs, body.x, y0 + duck) > 0:
		body.x = x0
		return false
	body.y = y0 + duck
	body.nudge_y = duck
	if after < rest:
		body.hit_wall = dir
	refresh_ground(body)
	return true


# --- vertical ------------------------------------------------------------------------------


## Moves [param body] by [param dy] vertically. Upward moves stop at ceilings (walls, solids and
## the undersides of slopes), sliding up to [param corner_sp] sideways around a ceiling corner
## (BUILD.md: 6 u). Downward moves land on floors; a one-way platform only stops a box whose
## bottom starts at or above it. Updates the ground contact. Returns the distance moved.
func move_y(body: Body, dy: int, corner_sp: int = 0) -> int:
	if native != null:
		return native.move_y(self, body, dy, corner_sp)
	if dy == 0:
		refresh_ground(body)
		return 0
	if solids.is_empty():
		return _move_up(body, -dy, corner_sp) if dy < 0 else _move_down(body, dy)
	var all: Array[SolidBox] = _narrow_solids(body, absi(dy))
	var moved: int = _move_up(body, -dy, corner_sp) if dy < 0 else _move_down(body, dy)
	_restore_solids(all)
	return moved


func _move_up(body: Body, dist: int, corner_sp: int) -> int:
	var allowed: int = _clear_up(body.left(), body.right(), body.top(), dist)
	if allowed < dist and corner_sp > 0:
		for shift: int in _ceiling_nudges(body, allowed, corner_sp):
			var after: int = _clear_up(body.left() + shift, body.right() + shift, body.top(), dist)
			if after > allowed and _slide_fits(body, shift, after):
				body.x += shift
				body.nudge_x = shift
				allowed = after
				break
	if allowed < dist:
		body.hit_ceiling = true
	if allowed == 0:
		# Under a flush ceiling the box has not left wherever it was: read that again, whatever
		# the caller assumed.
		refresh_ground(body)
		return 0
	body.y -= allowed
	body.on_ground = false
	body.ground_tile = -1
	body.on_slope = false
	return -allowed


## Candidate sideways shifts that might clear a ceiling corner: the box's overlap with the
## blocking row's obstacles, if at most [param max_shift] on one side (right first when both).
func _ceiling_nudges(body: Body, allowed: int, max_shift: int) -> Array[int]:
	var out: Array[int] = []
	var t: int = body.top() - allowed - 1
	var l: int = body.left()
	var r: int = body.right()
	var j: int = TileGrid.cell(t)
	var lo: int = r
	var hi: int = l
	for c: int in range(TileGrid.cell(l), TileGrid.cell(r - 1) + 1):
		if TileGrid.blocks_from_below(grid.get_tile(c, j)):
			lo = mini(lo, maxi(c * TileGrid.TILE_SP, l))
			hi = maxi(hi, mini((c + 1) * TileGrid.TILE_SP, r))
	for s: SolidBox in solids:
		if s.enabled and s.overlaps(l, r, t, t + 1):
			lo = mini(lo, maxi(s.left, l))
			hi = maxi(hi, mini(s.right, r))
	if lo == l and hi - l <= max_shift:
		out.append(hi - l)
	if hi == r and r - lo <= max_shift:
		out.append(lo - r)
	return out


## True if a box rising by [param rise] while sliding [param shift] sideways around a ceiling
## corner ends somewhere walking could have put it: no wall or solid box in the strip it slides
## through or anywhere in the box where it ends, no slope above its foot zone there, and its foot
## point not inside a slope. A box jumping off a slope may start with its uphill corner in the
## ground; only where it ends counts.
func _slide_fits(body: Body, shift: int, rise: int) -> bool:
	var x: int = body.x + shift
	var y: int = body.y - rise
	var hw: int = body.half_w
	var top: int = y - body.height
	var sl: int = body.right() if shift > 0 else body.left() + shift
	if _walls_overlap(sl, sl + absi(shift), top, body.y) or _walls_overlap(x - hw, x + hw, top, y):
		return false
	if region_blocked(x - hw, x + hw, top, y - hw):
		return false
	return _floor_at(TileGrid.cell(x), x, x, y, y, y) != INSIDE


## How far across a box falling by ([param dx], [param dy]) this tick has gone when its straight
## path meets a floor that is under it now but that moving across first, as an air step does,
## would carry it off: a box over a ledge's far edge, moving away from it, lands there rather than
## being carried past the edge before the fall reaches it (BUILD.md s15: "Landing on a 1-pixel
## ledge edge lands"). [constant NONE] if there is no such flat floor, if the box is still over it
## after the whole move across, or if the straight path there is not clear. Also NONE whenever the
## usual x-then-y step, with the mover's own corner lift ([param lift_sp]) and slide
## ([param slide_sp]), ends on ground at least as high: the near side of a raised step, or a block
## across a notch that the lift or a ledge-grab puts the box on (docs/adr/0008, decision 9).
func landing_contact(body: Body, dx: int, dy: int, lift_sp: int = 0, slide_sp: int = 0) -> int:
	if dx == 0 or dy <= 0:
		return NONE
	if native != null:
		return native.landing_contact(self, body, dx, dy, lift_sp, slide_sp)
	var x0: int = body.x
	var y0: int = body.y
	var floor_y: int = _landing(body, y0, y0 + dy)
	if floor_y == NONE or _hit_slope:
		return NONE
	var contact: int = NONE
	body.x = x0 + dx
	var across: int = _landing(body, y0, y0 + dy)
	if across == NONE or across > floor_y:
		var at: int = signi(dx) * Fx.div_floor(absi(dx) * (floor_y - y0), dy)
		body.x = x0 + at
		var l: int = mini(x0, body.x) - body.half_w
		var r: int = maxi(x0, body.x) + body.half_w
		if (
			_landing(body, floor_y, floor_y) == floor_y
			and not region_blocked(l, r, y0 - body.height, floor_y)
		):
			contact = at
	body.x = x0
	if contact != NONE and _plain_step_lands(body, dx, dy, lift_sp, slide_sp, floor_y):
		return NONE
	return contact


## True if the usual x-then-y step of [param body], tried on a copy, ends on ground no lower
## than [param floor_y].
func _plain_step_lands(
	body: Body, dx: int, dy: int, lift_sp: int, slide_sp: int, floor_y: int
) -> bool:
	var trial: Body = body.copy()
	move_x(trial, dx, lift_sp, slide_sp)
	move_y(trial, dy, slide_sp)
	return trial.on_ground and trial.y <= floor_y


func _move_down(body: Body, dist: int) -> int:
	var landing: int = _landing(body, body.y, body.y + dist)
	if landing != NONE:
		var moved: int = landing - body.y
		body.y = landing
		_set_ground(body, true)
		return moved
	body.y += dist
	_set_hit(-1, false, 0, 0)
	_set_ground(body, false)
	return dist


# --- grounded movement ---------------------------------------------------------------------


## Grounded horizontal movement (BUILD.md section 5: "Slope handling: Up to 45 degrees, speed
## unchanged; no sliding on slopes"). The foot point walks the floor's surface one tile column at a
## time: along a flat or a slope it moves in a single exact step, checking the whole way that the
## upper body meets no wall and the box no solid box. A floor that rises steeper than 45 degrees
## where the centre crosses into the next column is a wall face; a floor that drops away leaves the
## box standing on any flat floor still under its width (a box overlapping a ledge by one
## sub-pixel stands on it), and once nothing is under it the rest of the move is airborne. A slope
## that rises out of a solid box's top takes over from the top where it reaches the walking
## height. A wall or solid box whose top is at most [param lift_sp] above the feet is stepped up
## onto (BUILD.md: "Horizontal: 8 u nudge over ledge corners"; see [method _step_up]). Returns the
## horizontal distance moved.
func walk(body: Body, dx: int, lift_sp: int = 0) -> int:
	if native != null:
		return native.walk(self, body, dx, lift_sp)
	if dx == 0:
		refresh_ground(body)
		return 0
	if use_flat_walk and _narrowed == 0 and flat.try_walk(body, dx, grid, solids):
		return dx
	# Twice the distance: a walk that runs off a ledge carries on through the air from up to dx
	# away, and that move looks a further dx ahead.
	if solids.is_empty():
		return _walk(body, dx, lift_sp)
	var all: Array[SolidBox] = _narrow_solids(body, 2 * absi(dx))
	var moved: int = _walk(body, dx, lift_sp)
	_restore_solids(all)
	return moved


func _walk(body: Body, dx: int, lift_sp: int) -> int:
	var dir: int = 1 if dx > 0 else -1
	var remaining: int = absi(dx)
	var x_start: int = body.x
	# Whether the last step stood on the floor under the centre (whose kind is then known).
	var on_centre: bool = false
	var st: int = -1
	var slope: bool = false
	while remaining > 0:
		var x0: int = body.x
		var y0: int = body.y
		var c: int = TileGrid.cell(x0) if dir > 0 else TileGrid.cell(x0 - 1)
		var xs: int = x0 if dir > 0 else x0 - 1
		var to_edge: int = (c + 1) * TileGrid.TILE_SP - x0 if dir > 0 else x0 - c * TileGrid.TILE_SP
		var seg: int = _to_solid_edge(x0, dir, mini(remaining, to_edge))
		var entry: int = _floor_at(c, x0, xs, y0, y0 + seg, y0)
		if entry == INSIDE:
			body.hit_wall = dir
			on_centre = false
			break
		slope = _hit_slope
		st = _hit_tile
		var sj: int = _hit_j
		var airborne_after: int = -1
		# Level: the floor under the centre drops away (or runs under a solid box's top the box
		# has come down onto), and the box carries on at its height while a flat floor there is
		# under it.
		var level: bool = entry != y0
		if level or _hit_box:
			# At its height the box can meet a slope rising out of the floor it is on (a solid
			# box's top or an edge; never a tile's top, which no slope rises out of in a valid
			# room): it walks level only until the slope reaches its feet.
			seg = maxi(1, _until_slope_rises(c, x0, y0, dir, seg))
		var x1: int = x0 + dir * seg
		var y1: int = y0
		var adv: int = seg
		if not level:
			if slope:
				y1 = TileGrid.slope_surface(st, c, sj, x1)
			adv = _sweep_walk(body, dir, seg, y1 - y0)
			if adv < seg and _walk_onto_top:
				if adv > 0:
					# Walking downhill onto a solid box's top: step down to it first.
					_walk_to(body, x0 + dir * adv, c, st, sj, slope, y0)
					remaining -= absi(body.x - x0)
					continue
				level = true
		on_centre = not level
		if level:
			slope = false
			var run: int = _edge_run(body, dir, seg)
			if run <= seg:
				seg = run
				airborne_after = run
			x1 = x0 + dir * seg
			y1 = y0
			adv = _sweep_walk(body, dir, seg, 0)
		if adv < seg:
			_walk_to(body, x0 + dir * adv, c, st, sj, slope, y0)
			if lift_sp > 0 and _step_up(body, dir, lift_sp):
				remaining -= absi(body.x - x0)
				on_centre = false
				continue
			body.hit_wall = dir
			break
		body.x = x1
		body.y = y1
		remaining -= seg
		if airborne_after >= 0 and lift_sp > 0 and _step_down(body, dir, lift_sp):
			# The floor dropped by no more than the lift: the box stays on the ground, as walking up
			# the same step keeps it there.
			on_centre = false
			continue
		if airborne_after >= 0:
			body.on_ground = false
			body.ground_tile = -1
			body.on_slope = false
			if remaining > 0:
				# The rest of the move is airborne (within the reach the walk narrowed the solid
				# boxes to). A fast walk can carry the box over a gap onto the next ledge within
				# the tick.
				_move_x(body, dir * remaining, 0, 0)
				refresh_ground(body)
			return body.x - x_start
	if on_centre:
		body.on_ground = true
		body.ground_tile = st
		body.on_slope = slope
	else:
		refresh_ground(body)
	return body.x - x_start


## Corner correction on the ground: a walk stopped against a wall or solid box whose top is at
## most [param max_lift] above the floor at the box's leading edge steps up onto it, when the box
## has the headroom and can carry on at the new height (a solid box laid as a floor a few units
## below the tiles beside it would otherwise stop the player dead). The lift counts from the floor
## under the leading edge, not the feet: on a slope that floor is higher than the feet at the
## centre by up to the box's half-width, and a lip at a ramp's crest is no taller for being met
## from the slope. The lift is to the top of what stands just ahead of the leading edge
## ([method _wall_top_ahead]), not of everything under the box: walking downhill, the box's
## trailing foot zone rests in the crest wall uphill of it, up to its half-width above the feet,
## and counting that wall made a lip 6 u proud of the feet a 9 u step, refused, and the walk stood
## at the lip's face for good (physics review 8). Returns false, and leaves the body, if not.
func _step_up(body: Body, dir: int, max_lift: int) -> bool:
	var l: int = body.left()
	var r: int = body.right()
	var top: int = body.top()
	var y: int = body.y
	var lift: int = y - _wall_top_ahead(l, r, top, y, dir)
	var lead: int = r - 1 if dir > 0 else l
	var under: int = _floor_at(TileGrid.cell(lead), lead, lead, y - body.half_w, y, y)
	var rise: int = y - under if under != NONE and under != INSIDE else 0
	if lift <= 0 or lift > max_lift + rise or _clear_up(l, r, top, lift) < lift:
		return false
	if _sweep_x(l, r, top - lift, y - lift, dir, 1, body.half_w) <= 0:
		return false
	body.y = y - lift
	body.nudge_y -= lift
	return true


## Corner correction going down: a walk whose floor has just ended (nothing flat under the box at
## its height any more) steps down onto a floor at most [param max_drop] below, staying on the
## ground, as [method _step_up] steps up onto one. Like the step up, the drop counts from the
## floor under the box's trailing edge, the side the walk in [param dir] is leaving: walking off a
## lip onto a slope (or onto the floor at a slope's foot, the box's corner in the slope), the
## floor under the centre is lower than the slope under that edge by up to the box's half-width,
## and the lip is no taller for being left onto a slope. The drop goes into [member Body.nudge_y]
## so a view can ease it. Returns false, and leaves the body, if there is no such floor.
func _step_down(body: Body, dir: int, max_drop: int) -> bool:
	var y: int = body.y
	var floor_y: int = _landing(body, y, y + max_drop)
	if floor_y == NONE:
		# Any flat floor under the box within the drop was found above, so a floor under the
		# trailing edge within it is a slope's surface.
		var trail: int = body.left() if dir > 0 else body.right() - 1
		var under: int = _floor_at(TileGrid.cell(trail), trail, trail, y, y + max_drop, y)
		if under == NONE or under == INSIDE:
			return false
		floor_y = _landing(body, y, y + max_drop + body.half_w)
		if floor_y == NONE:
			return false
	if floor_y <= y:
		return false
	body.y = floor_y
	body.nudge_y += floor_y - y
	_set_ground(body, true)
	return true


## [param seg] shortened so that a box walking level at [param y0] from [param x0] stops where a
## slope in column [param c] rises to its feet (from there it walks up the slope). Slope surfaces
## change by at most a sub-pixel per sub-pixel, so a box whose feet are clear at x0 can always go
## at least one sub-pixel.
func _until_slope_rises(c: int, x0: int, y0: int, dir: int, seg: int) -> int:
	var j: int = TileGrid.cell(y0 - 1)
	var t: int = grid.get_tile(c, j)
	if not TileGrid.is_slope(t) or TileGrid.slope_surface(t, c, j, x0 + dir * seg) >= y0:
		return seg
	var ok: int = 0
	var bad: int = seg
	while bad - ok > 1:
		var mid: int = (ok + bad) / 2
		if TileGrid.slope_surface(t, c, j, x0 + dir * mid) >= y0:
			ok = mid
		else:
			bad = mid
	return ok


## Puts a walking body at [param x] on the support it was following (column [param c], tile
## [param t] in row [param j] if [param slope], else the height [param y0]). The swept test that
## chose x is exact for the straight line between the segment's ends, and a 1:2 slope's stepped
## surface is never more than half a sub-pixel off that line, so the box there is clear.
func _walk_to(body: Body, x: int, c: int, t: int, j: int, slope: bool, y0: int) -> void:
	body.x = x
	body.y = TileGrid.slope_surface(t, c, j, x) if slope else y0


## [param seg] shortened so the move stops at the next enabled solid-box edge ahead of
## [param x0].
func _to_solid_edge(x0: int, dir: int, seg: int) -> int:
	for sb: SolidBox in solids:
		if not sb.enabled:
			continue
		var d: int = (sb.left - x0) * dir
		if d > 0 and d < seg:
			seg = d
		d = (sb.right - x0) * dir
		if d > 0 and d < seg:
			seg = d
	return seg


## How far (up to [param seg]) the box can move level at its height before no flat floor at that
## height is under any part of it: the first such distance, or seg + 1 if it stays supported.
## Each flat span [a, b) at the body's height holds the centre p while a - half_w < p < b +
## half_w; the walk jumps from one held range's end to the next, so the cost is the number of
## spans, not the distance.
func _edge_run(body: Body, dir: int, seg: int) -> int:
	var y: int = body.y
	var hw: int = body.half_w
	var lo: int = body.x - hw - (seg if dir < 0 else 0)
	var hi: int = body.x + hw + (seg if dir > 0 else 0)
	# Pairs (first, last) of centre positions each span holds.
	var held: PackedInt64Array = PackedInt64Array()
	if Fx.div_floor(y, TileGrid.TILE_SP) * TileGrid.TILE_SP == y:
		var j: int = Fx.div_floor(y, TileGrid.TILE_SP)
		for c: int in range(TileGrid.cell(lo), TileGrid.cell(hi - 1) + 1):
			var t: int = grid.get_tile(c, j)
			if TileGrid.is_wall(t) or t == TileGrid.ONE_WAY:
				held.append(c * TileGrid.TILE_SP - hw + 1)
				held.append((c + 1) * TileGrid.TILE_SP + hw - 1)
	for sb: SolidBox in solids:
		if sb.enabled and sb.top == y and sb.right > lo and sb.left < hi:
			held.append(sb.left - hw + 1)
			held.append(sb.right + hw - 1)
	var p: int = body.x + dir
	while absi(p - body.x) <= seg:
		var reach: int = p
		for k: int in range(0, held.size(), 2):
			if held[k] <= p and p <= held[k + 1]:
				reach = maxi(reach, held[k + 1] + 1) if dir > 0 else mini(reach, held[k] - 1)
		if reach == p:
			return absi(p - body.x)
		p = reach
	return seg + 1


## How far (up to [param seg]) the body can walk in [param dir] while the foot point rises or
## falls by [param dy] in proportion, before the box meets a wall or a solid box. Exact for
## straight surfaces: the swept box is tested against each obstacle as a moving rectangle. The
## foot zone may pass into a wall only where that wall is the crest of the slope being walked: the
## wall ahead while climbing, or the wall already under the box while walking down and away from
## it; a wall walked into on the level or downhill stops the whole box, and so does a solid box.
## [member _walk_onto_top] reports a descent cut short by landing on a solid box's top.
func _sweep_walk(body: Body, dir: int, seg: int, dy: int) -> int:
	_walk_onto_top = false
	var l: int = body.left()
	var r: int = body.right()
	var t: int = body.top()
	if dy == 0:
		return _sweep_x(l, r, t, body.y, dir, seg, body.half_w)
	_sw_l = l
	_sw_r = r
	_sw_t = t
	_sw_dir = dir
	_sw_seg = seg
	_sw_dy = dy
	var foot_top: int = body.y - body.half_w
	var best: int = seg
	var mx: int = dir * seg
	var x_lo: int = mini(l, l + mx)
	var x_hi: int = maxi(r, r + mx)
	var y_lo: int = mini(t, t + dy)
	var y_hi: int = maxi(body.y, body.y + dy)
	for c: int in range(TileGrid.cell(x_lo), TileGrid.cell(x_hi - 1) + 1):
		var ol: int = c * TileGrid.TILE_SP
		var o_r: int = ol + TileGrid.TILE_SP
		var crest: bool = dy < 0 or (ol < r and o_r > l)
		var b: int = foot_top if crest else body.y
		for j: int in range(TileGrid.cell(y_lo), TileGrid.cell(y_hi - 1) + 1):
			if TileGrid.is_wall(grid.get_tile(c, j)):
				var ot: int = j * TileGrid.TILE_SP
				best = mini(best, _swept_advance(b, ol, ot, o_r, ot + TileGrid.TILE_SP))
	var onto: bool = false
	for sb: SolidBox in solids:
		if not sb.enabled:
			continue
		var adv: int = _swept_advance(body.y, sb.left, sb.top, sb.right, sb.bottom)
		var top_contact: bool = _swept_by_y and dy > 0
		if adv < best:
			best = adv
			onto = top_contact
		elif adv == best and not top_contact:
			onto = false
	_walk_onto_top = onto and best < seg
	return best


## The furthest advance a in [0, seg] (horizontal distance along the sweep's direction, with the
## box from _sw_l, _sw_r, _sw_t down to [param b] rising or falling by dy * a / seg) at which it
## has not yet entered the obstacle [param ol, o_r) x [param ot, ob); seg if it never does. Only a
## contact at a >= 0 counts: an obstacle the box is already in, or is moving away from, never
## blocks it. [member _swept_by_y] says whether the box would enter through the obstacle's top or
## bottom edge rather than its side. Corner to corner, where both are reached at the same advance,
## it is the top or bottom edge: a box walking downhill whose leading foot corner meets a box's top
## corner exactly stands level with that top and walks on along it (physics review 8, H1: read as
## the side, the walk asked the corner lift to step up 0 u, which is no step, and stopped dead).
func _swept_advance(b: int, ol: int, ot: int, o_r: int, ob: int) -> int:
	var l: int = _sw_l
	var r: int = _sw_r
	var t: int = _sw_t
	var seg: int = _sw_seg
	var dy: int = _sw_dy
	# The overlap is the open interval of a between the largest lower bound and the smallest
	# upper bound; each bound is a fraction n / d with d > 0.
	_swept_by_y = false
	var lo_n: int = (ol - r) if _sw_dir > 0 else (l - o_r)
	var lo_d: int = 1
	var hi_n: int = (o_r - l) if _sw_dir > 0 else (r - ol)
	var hi_d: int = 1
	var dn: int = absi(dy)
	# Bounds from the vertical extent, as fractions of seg.
	var y_lo: int = ((t - ob) if dy < 0 else (ot - b)) * seg
	var y_hi: int = ((b - ot) if dy < 0 else (ob - t)) * seg
	if y_lo * lo_d >= lo_n * dn:
		lo_n = y_lo
		lo_d = dn
		_swept_by_y = true
	if y_hi * hi_d < hi_n * dn:
		hi_n = y_hi
		hi_d = dn
	# No overlap at all, overlap only before a = 0 or already under way (lo < 0), or none
	# within this segment.
	if hi_n * lo_d <= lo_n * hi_d or lo_n < 0 or lo_n >= seg * lo_d:
		return seg
	return Fx.div_floor(lo_n, lo_d)


# --- one-way platforms ---------------------------------------------------------------------


## Drops a body standing only on one-way platforms through them. Returns false (and does nothing)
## if anything else holds it up.
func drop_through(body: Body) -> bool:
	if not can_drop_through(body):
		return false
	body.y += 1
	body.on_ground = false
	body.ground_tile = -1
	body.on_slope = false
	return true
