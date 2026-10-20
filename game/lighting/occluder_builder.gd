class_name OccluderBuilder
extends RefCounted
## Turns a room's collision into the few polygons the ember's shadows are cast from (Phase 1
## stand-in for BUILD.md section 10's shadows against the collision layer). Wall tiles (solid and
## smooth) merge into the fewest rectangles a row-by-row sweep finds: a run of tiles in a row,
## extended downward while the next row has the same run. A run of floor-slope tiles in a row
## merges into one polygon along its top edge. Spikes, pits and one-way platforms cast nothing (a
## thin one-way platform would only flicker the light). The solid beyond the room's edge is four
## bands around it, so no light leaves through the walls. Solid boxes are not here: they move
## and burn away, so the rig keeps one occluder per box.


## Rectangles and slope polygons for the walls of [param grid], in world units. Doors do not cut
## the border: the next room is never drawn with this one.
static func tile_polygons(grid: TileGrid) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var t: float = float(TileGrid.TILE)
	# Rectangles still growing downward: key is the run (x0 * 100000 + x1), value is [x0, x1, y0].
	var open: Dictionary[int, Vector3i] = {}
	for j: int in range(grid.height + 1):
		var runs: Array[Vector2i] = []
		if j < grid.height:
			runs = _wall_runs(grid, j)
		var next: Dictionary[int, Vector3i] = {}
		for run: Vector2i in runs:
			var key: int = run.x * 100000 + run.y
			next[key] = open[key] if open.has(key) else Vector3i(run.x, run.y, j)
		for key: int in open:
			if not next.has(key):
				var r: Vector3i = open[key]
				out.append(_rect(r.x * t, r.z * t, (r.y + 1) * t, j * t))
		open = next
		if j < grid.height:
			out.append_array(_slope_polygons(grid, j))
	return out


## The room's border: four bands [param width_u] thick around [param grid]'s edge.
static func border_polygons(grid: TileGrid, width_u: float) -> Array[PackedVector2Array]:
	var w: float = float(grid.width * TileGrid.TILE)
	var h: float = float(grid.height * TileGrid.TILE)
	var out: Array[PackedVector2Array] = []
	out.append(_rect(-width_u, -width_u, w + width_u, 0.0))
	out.append(_rect(-width_u, h, w + width_u, h + width_u))
	out.append(_rect(-width_u, 0.0, 0.0, h))
	out.append(_rect(w, 0.0, w + width_u, h))
	return out


## [param s] as a rectangle in world units.
static func box_polygon(s: SolidBox) -> PackedVector2Array:
	return _rect(
		float(s.left) / Fx.SUB,
		float(s.top) / Fx.SUB,
		float(s.right) / Fx.SUB,
		float(s.bottom) / Fx.SUB
	)


## A rectangle as a polygon, corners clockwise from the top left.
static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


## The runs [first column, last column] of wall tiles in row [param j].
static func _wall_runs(grid: TileGrid, j: int) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var start: int = -1
	for i: int in range(grid.width + 1):
		var wall: bool = i < grid.width and TileGrid.is_wall(grid.get_tile(i, j))
		if wall and start < 0:
			start = i
		elif not wall and start >= 0:
			runs.append(Vector2i(start, i - 1))
			start = -1
	return runs


## The floor-slope tiles of row [param j], runs of neighbours merged into one polygon each: the
## bottom edge of the run, then its top edge back from the right.
static func _slope_polygons(grid: TileGrid, j: int) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var t: float = float(TileGrid.TILE)
	var top := PackedVector2Array()
	var left: float = 0.0
	var i: int = 0
	while i <= grid.width:
		var tile: int = grid.get_tile(i, j) if i < grid.width else TileGrid.EMPTY
		if TileGrid.is_slope(tile):
			var edges: Vector2i = TileGrid.slope_edge_heights(tile)
			if top.is_empty():
				left = float(i) * t
			var y: float = float(j + 1) * t
			top.append(Vector2(float(i) * t, y - float(edges.x) / Fx.SUB))
			top.append(Vector2(float(i + 1) * t, y - float(edges.y) / Fx.SUB))
		elif not top.is_empty():
			out.append(_slope_run(top, left, float(j + 1) * t))
			top = PackedVector2Array()
		i += 1
	return out


## One polygon for a run of slope tiles whose top-edge points are [param top] (two a tile).
static func _slope_run(top: PackedVector2Array, left: float, bottom: float) -> PackedVector2Array:
	var poly := PackedVector2Array([Vector2(left, bottom), Vector2(top[top.size() - 1].x, bottom)])
	var k: int = top.size() - 1
	while k >= 0:
		# The shared point between two tiles appears twice: keep one.
		if k == top.size() - 1 or not top[k].is_equal_approx(poly[poly.size() - 1]):
			poly.append(top[k])
		k -= 1
	return poly
