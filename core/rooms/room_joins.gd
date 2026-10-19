class_name RoomJoins
extends RefCounted
## Where a room's solid boxes meet its tiles, the joins the physics defines (docs/adr/0008,
## decision 10). A box's top is ground: it must be open to the air, flush with the terrain beside
## it, a lip above it, or so deep in terrain that no foot reaches it. A top buried a few units
## under a slope or a wall top is neither ground nor terrain: the walk reads a floor inside solid
## ground there, and leaves the ground or hovers (physics review 6, H1 and M5). Likewise a one-way
## top a few units above a box top beside it is a shelf the walk passes under and drops through
## (L5). Both are authoring mistakes, so loading such a room is an error, not a case the physics
## handles.
##
## "A few units" is the world's join band ([member WorldTuning.join_band_u]): more than any
## Wick's corner lift or ledge-grab, so a buried top or a shelf deeper than the band is out of
## every reach.


## Problems with [param room]'s joins, one per offending box, for a band of [param band_sp]
## sub-pixels.
static func errors(room: RoomData, band_sp: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for i: int in range(room.solids.size()):
		var s: SolidBox = room.solids[i]
		var buried: String = _buried(room, i, band_sp)
		if buried != "":
			out.append(buried)
		var shelf: String = _shelf(room, s, band_sp)
		if shelf != "":
			out.append(shelf)
	return out


## The first unit of box [param i]'s top that lies inside tile terrain within the band, as an
## error. Boxes may overlap boxes: a step built of two boxes is ground the sweep reads as one.
static func _buried(room: RoomData, i: int, band_sp: int) -> String:
	var s: SolidBox = room.solids[i]
	var x: int = s.left + Fx.SUB / 2
	while x < s.right:
		var surface: int = _tile_surface(room.grid, x, s.top - 1)
		var depth: int = s.top - surface
		if surface != CollisionQueries.NONE and depth > 0 and depth <= band_sp:
			return (
				(
					"solid %s: its top (y %s) is buried %s u under the ground at x %s; a box's top must "
					% [_name(s), _u(s.top), _u(depth), _u(x)]
				)
				+ (
					"be flush with the ground it meets, above it, or more than %s u under it"
					% _u(band_sp)
				)
			)
		x += Fx.SUB
	return ""


## A one-way top in the columns the box spans (or just beside it) that is above the box's top by
## no more than the band.
static func _shelf(room: RoomData, s: SolidBox, band_sp: int) -> String:
	for c: int in range(TileGrid.cell(s.left - 1), TileGrid.cell(s.right) + 1):
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
