class_name CollisionQueries
extends RefCounted
## The read-only half of the physics sweep (docs/adr/0008): what the geometry holds at a point, a
## height or a region, for [CollisionWorld]'s moves and for the state machines that ask about
## contacts. Geometry is a [TileGrid] plus [SolidBox]es; the body model (upper body, foot zone,
## foot point) is described on [CollisionWorld]. Queries leave their findings in member
## variables, so a world must be used from one thread at a time.

## Floor query result: no floor in the range.
const NONE: int = 1 << 60
## Floor query result: the point is already inside something solid.
const INSIDE: int = -(1 << 60)

var grid: TileGrid
var solids: Array[SolidBox] = []
## Whether a body standing or walking on a plain flat floor is answered by [FlatWalk] instead of
## swept (docs/adr/0020). Tests switch it off to play the sweep itself beside it.
var use_flat_walk: bool = true
var flat: FlatWalk = FlatWalk.new()
## Depth below a spike tile's top edge at which its hazard volume begins. A new world starts
## with [WorldTuning]'s defaults; the game applies content/physics/world.tres.
var spike_inset_sp: int = 0

# How many moves are running with [member solids] narrowed to what they can reach: the flat walk
# knows the whole list only when none is.
var _narrowed: int = 0

# What the last floor query found: the tile kind (TileGrid.SOLID for a solid box), whether it is a
# slope, the tile's cell, and whether it was a solid box.
var _hit_tile: int = -1
var _hit_slope: bool = false
var _hit_c: int = 0
var _hit_j: int = 0
var _hit_box: bool = false

# --- floor queries -------------------------------------------------------------------------


func _set_hit(t: int, slope: bool, c: int, j: int, box: bool = false) -> void:
	_hit_tile = t
	_hit_slope = slope
	_hit_c = c
	_hit_j = j
	_hit_box = box


## The topmost floor under the point at [param x] (read in tile column [param c], which differs
## from cell(x) only on a column edge, and against solid boxes at [param xs]) with y in
## [param y_lo, y_hi]: a wall or solid-box top, a slope's surface, or a one-way top no higher than
## [param y_from] (a one-way only catches a box that was above it). Returns [constant NONE] if
## there is none and [constant INSIDE] if the point at y_lo is inside a wall, solid box or slope.
func _floor_at(c: int, x: int, xs: int, y_lo: int, y_hi: int, y_from: int) -> int:
	_set_hit(-1, false, 0, 0)
	var found: int = NONE
	var j: int = TileGrid.cell(y_lo - 1)
	var last: int = TileGrid.cell(y_hi)
	while j <= last:
		var t: int = grid.get_tile(c, j)
		var top: int = j * TileGrid.TILE_SP
		if TileGrid.is_wall(t):
			if top < y_lo:
				return INSIDE
			found = top
			_set_hit(t, false, c, j)
			break
		if TileGrid.is_slope(t):
			var s: int = TileGrid.slope_surface(t, c, j, x)
			if s < y_lo:
				return INSIDE
			if s <= y_hi:
				found = s
				_set_hit(t, true, c, j)
				break
		elif t == TileGrid.ONE_WAY and top >= y_lo and top >= y_from and top <= y_hi:
			found = top
			_set_hit(t, false, c, j)
			break
		j += 1
	for sb: SolidBox in solids:
		if not sb.enabled or xs < sb.left or xs >= sb.right:
			continue
		if sb.top < y_lo and sb.bottom >= y_lo:
			return INSIDE
		if sb.top >= y_lo and sb.top <= y_hi and sb.top < found:
			found = sb.top
			_set_hit(TileGrid.SOLID, false, 0, 0, true)
	return found


## The topmost flat floor (a wall, one-way or solid-box top; not a slope) under any part of
## [param l, r) with y in [param y_lo, y_hi], or [constant NONE]. A column whose tile already
## holds the box's bottom (a corner resting inside a crest) offers no flat floor, and neither does
## a wall top at most [param foot] above [param slope_y], the slope under the box's centre: that
## wall is the crest the slope leads to, and the box's corner rests in it rather than on it.
func _flat_under(
	l: int, r: int, y_lo: int, y_hi: int, y_from: int, slope_y: int = NONE, foot: int = 0
) -> int:
	var found: int = NONE
	var first: int = -Fx.div_floor(-y_lo, TileGrid.TILE_SP)
	var last: int = TileGrid.cell(y_hi)
	var hit_t: int = -1
	var hit_c: int = 0
	var hit_j: int = 0
	if first <= last:
		# The row holding y_lo - 1, just above the first candidate row.
		var inside_row: int = first - 1
		for c: int in range(TileGrid.cell(l), TileGrid.cell(r - 1) + 1):
			if TileGrid.is_wall(grid.get_tile(c, inside_row)):
				continue
			for j: int in range(first, last + 1):
				var top: int = j * TileGrid.TILE_SP
				if top >= found:
					break
				var t: int = grid.get_tile(c, j)
				var wall: bool = TileGrid.is_wall(t)
				if wall and top < slope_y and slope_y - top <= foot:
					break
				if wall or (t == TileGrid.ONE_WAY and top >= y_from):
					found = top
					hit_t = t
					hit_c = c
					hit_j = j
					break
				if TileGrid.is_slope(t):
					break
	for sb: SolidBox in solids:
		if sb.enabled and sb.left < r and sb.right > l and sb.top >= y_lo and sb.top <= y_hi:
			if sb.top < found:
				found = sb.top
				hit_t = TileGrid.SOLID
				hit_c = 0
				hit_j = 0
	_set_hit(hit_t, false, hit_c, hit_j)
	return found


## Where a box falling from [param y0] to [param y1] lands, or [constant NONE]; the hit fields say
## on what. The centre stands on any floor; the rest of the width stands on flat floors, so a box
## overlapping a ledge by a single sub-pixel stands on it. A wall top no more than the foot zone
## above the slope under the centre is the crest that slope leads to and holds nothing up: the
## box comes to rest on the slope with its corner in the crest, exactly as walking there leaves
## it, even when the slope is still below [param y1] (the box then carries on falling).
func _landing(body: Body, y0: int, y1: int) -> int:
	var foot: int = body.half_w
	var centre: int = _floor_at(TileGrid.cell(body.x), body.x, body.x, y0, y1 + foot, y0)
	var c_tile: int = _hit_tile
	var c_slope: bool = _hit_slope
	var c_c: int = _hit_c
	var c_j: int = _hit_j
	var slope_y: int = centre if c_slope and centre != INSIDE else NONE
	if centre == INSIDE or centre > y1:
		centre = NONE
	var edge: int = _flat_under(body.left(), body.right(), y0, y1, y0, slope_y, foot)
	if centre != NONE and centre <= edge:
		_set_hit(c_tile, c_slope, c_c, c_j)
		return centre
	return edge


func _set_ground(body: Body, grounded: bool) -> void:
	body.on_ground = grounded
	body.ground_tile = _hit_tile if grounded else -1
	body.on_slope = _hit_slope if grounded else false


## Re-reads the ground contact of a body without moving it.
func refresh_ground(body: Body) -> void:
	if use_flat_walk and _narrowed == 0 and flat.try_ground(body, grid, solids):
		return
	_set_ground(body, _landing(body, body.y, body.y) == body.y)


# --- region queries ------------------------------------------------------------------------


## True if [param l, r) x [param t, b) overlaps a wall tile, an enabled solid box, or the solid
## part of a slope.
func region_blocked(l: int, r: int, t: int, b: int) -> bool:
	if r <= l or b <= t:
		return false
	for c: int in range(TileGrid.cell(l), TileGrid.cell(r - 1) + 1):
		for j: int in range(TileGrid.cell(t), TileGrid.cell(b - 1) + 1):
			var tile: int = grid.get_tile(c, j)
			if TileGrid.is_wall(tile):
				return true
			if TileGrid.is_slope(tile) and _slope_overlaps(tile, c, j, l, r, b):
				return true
	return _solid_overlaps(l, r, t, b)


## True if the solid part of slope tile [param t] at (c, j) reaches above [param b] anywhere in
## [param l, r) (the caller has checked that the region meets the tile).
func _slope_overlaps(t: int, c: int, j: int, l: int, r: int, b: int) -> bool:
	var xa: int = maxi(l, c * TileGrid.TILE_SP)
	var xb: int = mini(r, (c + 1) * TileGrid.TILE_SP) - 1
	var s: int = mini(TileGrid.slope_surface(t, c, j, xa), TileGrid.slope_surface(t, c, j, xb))
	return s < b


func _solid_overlaps(l: int, r: int, t: int, b: int) -> bool:
	for sb: SolidBox in solids:
		if sb.enabled and sb.overlaps(l, r, t, b):
			return true
	return false


## True if the non-empty region [param l, r) x [param t, b) overlaps a wall tile or an enabled
## solid box.
func _walls_overlap(l: int, r: int, t: int, b: int) -> bool:
	for c: int in range(TileGrid.cell(l), TileGrid.cell(r - 1) + 1):
		for j: int in range(TileGrid.cell(t), TileGrid.cell(b - 1) + 1):
			if TileGrid.is_wall(grid.get_tile(c, j)):
				return true
	return _solid_overlaps(l, r, t, b)


## True if a box with bottom-centre ([param cx], [param bottom]) fits where it is: nothing solid
## overlaps it anywhere (not even its foot zone) and its foot point is not inside a slope. Used to
## place a body (a teleport, a respawn).
func body_fits(cx: int, bottom: int, half_w: int, height: int) -> bool:
	if region_blocked(cx - half_w, cx + half_w, bottom - height, bottom):
		return false
	return _floor_at(TileGrid.cell(cx), cx, cx, bottom, bottom, bottom) != INSIDE


## True if the point is inside a wall tile, an enabled solid box, or a slope below its surface.
func point_solid(x_sp: int, y_sp: int) -> bool:
	var c: int = TileGrid.cell(x_sp)
	var j: int = TileGrid.cell(y_sp)
	var t: int = grid.get_tile(c, j)
	if TileGrid.is_wall(t):
		return true
	if TileGrid.is_slope(t) and y_sp >= TileGrid.slope_surface(t, c, j, x_sp):
		return true
	return _solid_overlaps(x_sp, x_sp + 1, y_sp, y_sp + 1)


## The topmost floor a box spanning [param l, r) would stand on with its bottom anywhere from
## [param y0] to [param y1]: a wall or solid-box top, the highest point of a slope's surface
## under the span, or a one-way top (at or below [param y0], so one the box was above). Returns
## [constant NONE] if there is none; a span that already reaches into a wall gets [param y0].
## A read-only query for presentation (the camera's look ahead
## of a fall): unlike the floor queries the moves use, it leaves no finding behind in the world.
func floor_top_in(l: int, r: int, y0: int, y1: int) -> int:
	var best: int = NONE
	if r <= l or y1 < y0:
		return best
	for c: int in range(TileGrid.cell(l), TileGrid.cell(r - 1) + 1):
		for j: int in range(TileGrid.cell(y0), TileGrid.cell(y1) + 1):
			var top: int = j * TileGrid.TILE_SP
			if top >= best:
				break
			var t: int = grid.get_tile(c, j)
			var y: int = NONE
			if TileGrid.is_wall(t):
				# A span already reaching into a wall stands on it at once.
				y = maxi(top, y0)
			elif t == TileGrid.ONE_WAY:
				y = top
			elif TileGrid.is_slope(t):
				var xa: int = maxi(l, c * TileGrid.TILE_SP)
				var xb: int = mini(r, (c + 1) * TileGrid.TILE_SP) - 1
				y = mini(TileGrid.slope_surface(t, c, j, xa), TileGrid.slope_surface(t, c, j, xb))
			if y >= y0 and y <= y1:
				best = mini(best, y)
				break
	for sb: SolidBox in solids:
		if sb.enabled and sb.left < r and sb.right > l and sb.top >= y0 and sb.top <= y1:
			best = mini(best, sb.top)
	return best


# --- obstacles above and ahead -------------------------------------------------------------


## How far the top edge [l, r) at [param t] can rise (up to [param dist]) before meeting a wall,
## a slope's underside or a solid box. Tiles the top already overlaps are ignored.
func _clear_up(l: int, r: int, t: int, dist: int) -> int:
	var best: int = dist
	var j: int = TileGrid.cell(t) - 1
	var j_end: int = TileGrid.cell(t - dist)
	var c0: int = TileGrid.cell(l)
	var c1: int = TileGrid.cell(r - 1)
	while j >= j_end:
		var blocked: bool = false
		for c: int in range(c0, c1 + 1):
			if TileGrid.blocks_from_below(grid.get_tile(c, j)):
				blocked = true
				break
		if blocked:
			best = t - (j + 1) * TileGrid.TILE_SP
			break
		j -= 1
	for s: SolidBox in solids:
		if s.enabled and s.bottom <= t and s.right > l and s.left < r:
			best = mini(best, t - s.bottom)
	return maxi(best, 0)


## Top y of the highest wall tile or solid overlapping [l, r) x [t, b), or [param b] if none.
func _highest_wall_top(l: int, r: int, t: int, b: int) -> int:
	var best: int = b
	for c: int in range(TileGrid.cell(l), TileGrid.cell(r - 1) + 1):
		for j: int in range(TileGrid.cell(t), TileGrid.cell(b - 1) + 1):
			if TileGrid.is_wall(grid.get_tile(c, j)):
				best = mini(best, j * TileGrid.TILE_SP)
				break
	for s: SolidBox in solids:
		if s.enabled and s.overlaps(l, r, t, b):
			best = mini(best, s.top)
	return best


## Top y of the highest wall tile or solid that the box [l, r) x [t, b) would enter moving one
## sub-pixel in [param dir] (the strip just ahead of its leading edge), or [param b] if none: what a
## corner lift must clear. A wall the box already rests in is not in its way: a box on a slope has
## its foot zone in the crest wall uphill of it, up to its half-width above the feet, and walking
## downhill that wall is behind it (physics review 8).
func _wall_top_ahead(l: int, r: int, t: int, b: int, dir: int) -> int:
	var x: int = r if dir > 0 else l - 1
	return _highest_wall_top(x, x + 1, t, b)


## Bottom y of the lowest ceiling (a wall, a slope's underside or a solid) overlapping
## [l, r) x [t, b), or [param t] if none.
func _lowest_ceiling_bottom(l: int, r: int, t: int, b: int) -> int:
	var best: int = t
	for c: int in range(TileGrid.cell(l), TileGrid.cell(r - 1) + 1):
		var j: int = TileGrid.cell(b - 1)
		while j >= TileGrid.cell(t):
			if TileGrid.blocks_from_below(grid.get_tile(c, j)):
				best = maxi(best, (j + 1) * TileGrid.TILE_SP)
				break
			j -= 1
	for s: SolidBox in solids:
		if s.enabled and s.overlaps(l, r, t, b):
			best = maxi(best, s.bottom)
	return best


# --- contacts ------------------------------------------------------------------------------


## True if the grounded [param body] stands only on one-way platforms, so it may drop through
## (BUILD.md section 5: crouch "drops through one-way platforms"). A wall or solid box at its
## feet holds it up; a slope tile under its width does not (a box standing on a slope is
## on_slope, and anywhere else a slope's surface is below its feet).
func can_drop_through(body: Body) -> bool:
	if not body.on_ground or body.on_slope:
		return false
	var y: int = body.y
	var j: int = Fx.div_floor(y, TileGrid.TILE_SP)
	if j * TileGrid.TILE_SP != y:
		return false
	var one_way: bool = false
	var other: bool = false
	for c: int in range(TileGrid.cell(body.left()), TileGrid.cell(body.right() - 1) + 1):
		var t: int = grid.get_tile(c, j)
		other = other or TileGrid.is_wall(t)
		one_way = one_way or t == TileGrid.ONE_WAY
	for sb: SolidBox in solids:
		if sb.enabled and sb.top == y and sb.left < body.right() and sb.right > body.left():
			other = true
	return one_way and not other


## True if a clingable wall (or, with [param include_smooth], any wall) lies within
## [param reach] sub-pixels of the body's side in [param dir], beside the body above its foot zone.
func wall_near(body: Body, dir: int, reach: int, include_smooth: bool = false) -> bool:
	var l: int = body.right() if dir > 0 else body.left() - reach
	var r: int = body.right() + reach if dir > 0 else body.left()
	var t: int = body.top()
	var b: int = body.y - body.half_w
	for c: int in range(TileGrid.cell(l), TileGrid.cell(r - 1) + 1):
		for j: int in range(TileGrid.cell(t), TileGrid.cell(b - 1) + 1):
			var tile: int = grid.get_tile(c, j)
			if tile == TileGrid.SOLID or (include_smooth and tile == TileGrid.SMOOTH):
				return true
	for s: SolidBox in solids:
		if s.enabled and s.clingable and s.overlaps(l, r, t, b):
			return true
	return false


## True if the box [l, r) x [t, b) overlaps the hazard volume of any spike tile: the tile below
## [member spike_inset_sp] from its top.
func touches_spikes(l: int, r: int, t: int, b: int) -> bool:
	return _touches_tile(l, r, t, b, TileGrid.SPIKES, spike_inset_sp)


## True if the box [param l], [param r], [param t], [param b] (sub-pixels) touches a hazard: a
## spike tile's hazard part, or any part of a pit tile. What sends the player back; only spikes
## can be pogoed off ([method touches_spikes]).
func touches_hazard(l: int, r: int, t: int, b: int) -> bool:
	return touches_spikes(l, r, t, b) or _touches_tile(l, r, t, b, TileGrid.PIT, 0)


## True if the box touches a [param kind] tile below [param inset] from the tile's top.
func _touches_tile(l: int, r: int, t: int, b: int, kind: int, inset: int) -> bool:
	for c: int in range(TileGrid.cell(l), TileGrid.cell(r - 1) + 1):
		for j: int in range(TileGrid.cell(t), TileGrid.cell(b - 1) + 1):
			if grid.get_tile(c, j) == kind:
				if b > j * TileGrid.TILE_SP + inset:
					return true
	return false


## True if the body could stand where it is at [param new_height] (for un-crouching): the part of
## the taller box above its foot zone is clear.
func headroom(body: Body, new_height: int) -> bool:
	var top: int = body.y - new_height
	return not (
		region_blocked(body.left(), body.right(), top, body.y - body.half_w)
		or _solid_overlaps(body.left(), body.right(), top, body.y)
	)
