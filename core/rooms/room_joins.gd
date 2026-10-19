class_name RoomJoins
extends RefCounted
## Where a room's solid boxes meet its tiles, the joins the physics defines (docs/adr/0008,
## decision 12). A box's top is ground: it must be open to the air, flush with the terrain beside
## it, a lip above it, or so deep in terrain that no foot reaches it. A top buried a few units
## under a slope or a wall top is neither ground nor terrain: the walk reads a floor inside solid
## ground there, and leaves the ground or hovers (physics review 6, H1 and M5). Likewise a one-way
## top a few units above a box top beside it is a shelf the walk passes under and drops through
## (L5). Both are authoring mistakes, so loading such a room is an error, not a case the physics
## handles.
##
## One buried top is the physics' own case (decision 5): a slope rising out of the top, where the
## top runs on as open ground past the point the slope rises from, and the box's other end lies
## deeper than the band under the slope: a trapdoor at a ramp's foot that runs under it, a box
## under a ramp's rise (physics review 7, L2). The walk goes along the top to that point and up the
## slope, and back. A top that stays a few units under the slope to the box's edge (H1) or under a
## plateau (M5) is still refused.
##
## "A few units" is the world's join band ([member WorldTuning.join_band_u]): more than any
## Wick's corner lift or ledge-grab, so a buried top or a shelf deeper than the band is out of
## every reach. "Beside" a top is as far as the widest Wick overhangs a box's edge
## ([member WorldTuning.join_reach_u]).

## What a unit of a box's top meets: open air (or ground flush with it), terrain at most the band
## above it, or terrain deeper than that.
enum { OPEN, BURIED, DEEP }


## Problems with [param room]'s joins, one per offending box, for a band of [param band_sp]
## sub-pixels and a one-way reach of [param reach_sp] beside a box's edges.
static func errors(room: RoomData, band_sp: int, reach_sp: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for i: int in range(room.solids.size()):
		var s: SolidBox = room.solids[i]
		var buried: String = _buried(room, i, band_sp)
		if buried != "":
			out.append(buried)
		var shelf: String = _shelf(room, s, band_sp, reach_sp)
		if shelf != "":
			out.append(shelf)
	return out


## The first unit of box [param i]'s top that lies inside tile terrain within the band, unless a
## slope rises out of the top there, as an error. Boxes may overlap boxes: a step built of two
## boxes is ground the sweep reads as one.
static func _buried(room: RoomData, i: int, band_sp: int) -> String:
	var s: SolidBox = room.solids[i]
	var xs: PackedInt32Array = []
	var depths: PackedInt32Array = []
	var x: int = s.left + Fx.SUB / 2
	while x < s.right:
		var surface: int = _tile_surface(room.grid, x, s.top - 1)
		xs.append(x)
		depths.append(s.top - surface if surface != CollisionQueries.NONE else 0)
		x += Fx.SUB
	var k: int = 0
	while k < xs.size():
		if _kind(depths[k], band_sp) != BURIED:
			k += 1
			continue
		var first: int = k
		while k < xs.size() and _kind(depths[k], band_sp) == BURIED:
			k += 1
		if not _rises_out(room.grid, s, xs, depths, first, k - 1, band_sp):
			return (
				(
					"solid %s: its top (y %s) is buried %s u under the ground at x %s; a box's top must "
					% [_name(s), _u(s.top), _u(depths[first]), _u(xs[first])]
				)
				+ (
					(
						"be flush with the ground it meets, above it, more than %s u under it, "
						% _u(band_sp)
					)
					+ "or have a slope rise out of it"
				)
			)
	return ""


static func _kind(depth: int, band_sp: int) -> int:
	if depth <= 0:
		return OPEN
	return BURIED if depth <= band_sp else DEEP


## True if the buried run of samples [param first] to [param last] is a slope rising out of the
## top: at one end the slope comes down to the top's height and the top runs on as open ground; at
## the other the top is deeper than the band, inside the box's span.
static func _rises_out(
	grid: TileGrid,
	s: SolidBox,
	xs: PackedInt32Array,
	depths: PackedInt32Array,
	first: int,
	last: int,
	band_sp: int
) -> bool:
	var left: int = _kind(depths[first - 1], band_sp) if first > 0 else -1
	var right: int = _kind(depths[last + 1], band_sp) if last + 1 < xs.size() else -1
	var out_left: bool = left == OPEN and _slope_meets(grid, s, xs[first], depths[first])
	var out_right: bool = right == OPEN and _slope_meets(grid, s, xs[last], depths[last])
	return (out_left and right == DEEP) or (out_right and left == DEEP)


## True if the terrain over the top at [param x] is a slope that comes down to the top's height
## within the next unit ([param depth] at most one unit): the slope rises out of the top there.
static func _slope_meets(grid: TileGrid, s: SolidBox, x: int, depth: int) -> bool:
	if depth > Fx.SUB:
		return false
	var c: int = TileGrid.cell(x)
	var j: int = TileGrid.cell(s.top - 1)
	var t: int = grid.get_tile(c, j)
	while TileGrid.is_wall(t) and j > 0:
		j -= 1
		t = grid.get_tile(c, j)
	return TileGrid.is_slope(t)


## A one-way top that is above the box's top by no more than the band, in a column the box spans or
## one within [param reach_sp] beside its edges (a body standing on the edge overhangs it that far).
static func _shelf(room: RoomData, s: SolidBox, band_sp: int, reach_sp: int) -> String:
	for c: int in range(
		TileGrid.cell(s.left - reach_sp), TileGrid.cell(s.right + reach_sp - 1) + 1
	):
		for j: int in range(room.grid.height):
			if room.grid.get_tile(c, j) != TileGrid.ONE_WAY:
				continue
			var rise: int = s.top - j * TileGrid.TILE_SP
			if rise > 0 and rise <= band_sp:
				return (
					(
						"solid %s: the one-way at column %d is %s u above its top; a one-way beside a "
						% [_name(s), c, _u(rise)]
					)
					+ "box's top must be level with it or more than %s u above it" % _u(band_sp)
				)
	return ""


## The top of the tile terrain holding the point ([param x], [param y]), or
## [constant CollisionQueries.NONE] if the point is open.
static func _tile_surface(grid: TileGrid, x: int, y: int) -> int:
	var c: int = TileGrid.cell(x)
	var j: int = TileGrid.cell(y)
	var t: int = grid.get_tile(c, j)
	if TileGrid.is_slope(t):
		var surface: int = TileGrid.slope_surface(t, c, j, x)
		return surface if y >= surface else CollisionQueries.NONE
	if not TileGrid.is_wall(t):
		return CollisionQueries.NONE
	# Up the column to the top of the wall, or of a slope standing on it.
	while j > 0:
		j -= 1
		t = grid.get_tile(c, j)
		if TileGrid.is_wall(t):
			continue
		if TileGrid.is_slope(t):
			return TileGrid.slope_surface(t, c, j, x)
		return (j + 1) * TileGrid.TILE_SP
	return 0


static func _name(s: SolidBox) -> String:
	var tag: String = " '%s'" % s.tag if s.tag != "" else ""
	return "%s..%s x %s..%s%s" % [_u(s.left), _u(s.right), _u(s.top), _u(s.bottom), tag]


## Sub-pixels (never negative here) as units, with two decimals only when not whole.
static func _u(sp: int) -> String:
	if sp % Fx.SUB == 0:
		return str(sp / Fx.SUB)
	return "%d.%02d" % [sp / Fx.SUB, (sp % Fx.SUB) * 100 / Fx.SUB]
