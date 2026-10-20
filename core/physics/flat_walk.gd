class_name FlatWalk
extends RefCounted
## The commonest case of the sweep, answered without sweeping it (docs/adr/0020).
##
## A body standing with its feet on a tile boundary, on a floor of one kind of tile (a wall or a
## one-way platform), under open air and clear of every solid box that could matter, walks level:
## the sweep's answer for a step is the body moved along, standing on that tile kind, and its
## ground contact the same kind's. The same holds for [method CollisionQueries.refresh_ground]. A
## body in such a stretch (a "flat run") need not be swept, and the stress room's 200 enemies
## spend nearly every tick in one.
##
## A run is the contiguous tile columns around the body where every column has the same tile kind
## in the row under the feet, nothing but empty tiles in the rows the box fills, and no solid box
## near (enabled or not) in height and in the columns or the one beside them. The body may be
## anywhere its whole width is in those columns. The run is found once, kept on the [Body] (it is
## not state), and trusted until the world's tiles or solid boxes change or the body's feet or
## size do.
##
## The sweep stays the reference: [member CollisionQueries.use_flat_walk] switches this off, and
## tests/unit/core/physics/test_flat_walk.gd plays both side by side on random worlds and demands
## the same bodies, tick for tick. A move this cannot vouch for (the body near a wall, a ledge, a
## slope or a solid box, off a tile boundary, or going further than its run) is swept as before.

## A tile's side in sub-pixels, and the mask of an offset inside one.
const TILE: int = TileGrid.TILE_SP
const MASK: int = TileGrid.TILE_SP - 1

## Gives each picture of the world its own number, across worlds, so a body that crosses from one
## room's world into another's never takes its old run for a new one.
static var _tokens: int = 0

## How many moves and contact refreshes this has answered, for the tests and the bench.
var hits: int = 0
## Names the world as last seen; a body's run is good only under the token it was found under.
var token: int = 0
var _grid: TileGrid
var _grid_rev: int = -1
var _boxes_rev: int = -1
var _box_count: int = -1


## Moves [param body] by [param dx] as the walk would, if it is and stays in a flat run; false
## (and the body untouched) if the sweep must do it.
func try_walk(body: Body, dx: int, g: TileGrid, solids: Array[SolidBox]) -> bool:
	if not _in_flat(body, g, solids):
		return false
	var nx: int = body.x + dx
	if nx < body.run_lo or nx > body.run_hi:
		return false
	hits += 1
	body.x = nx
	body.on_ground = true
	body.ground_tile = body.run_tile
	body.on_slope = false
	return true


## True if a walk of [param dx] would be served by [method try_walk]: the floor is there under
## the body all the way (and for as far as the run goes, nothing else is).
func covers(body: Body, dx: int, g: TileGrid, solids: Array[SolidBox]) -> bool:
	if not _in_flat(body, g, solids):
		return false
	var nx: int = body.x + dx
	return nx >= body.run_lo and nx <= body.run_hi


## Sets the ground contact of [param body] as a refresh would, if it is in a flat run; false (and
## the body untouched) if not.
func try_ground(body: Body, g: TileGrid, solids: Array[SolidBox]) -> bool:
	if not _in_flat(body, g, solids):
		return false
	hits += 1
	body.on_ground = true
	body.ground_tile = body.run_tile
	body.on_slope = false
	return true


## True if [param body] is in a flat run under the world as it is now (found, if need be).
func _in_flat(body: Body, g: TileGrid, solids: Array[SolidBox]) -> bool:
	if body.y & MASK != 0:
		return false
	if (
		g != _grid
		or g.revision != _grid_rev
		or SolidBox.revision != _boxes_rev
		or solids.size() != _box_count
	):
		_grid = g
		_grid_rev = g.revision
		_boxes_rev = SolidBox.revision
		_box_count = solids.size()
		_tokens += 1
		token = _tokens
	return _in_run(body) or _find(body, solids)


## True if the run kept on [param body] is the current picture's, for its feet and size, and the
## body is in it.
func _in_run(body: Body) -> bool:
	return (
		body.run_token == token
		and body.run_y == body.y
		and body.run_h == body.height
		and body.run_hw == body.half_w
		and body.x >= body.run_lo
		and body.x <= body.run_hi
	)


## Finds the run around [param body], keeps it on the body, and says whether the body is in one.
## A miss is kept too (an empty run), and not looked into again until the body has moved a tile.
func _find(body: Body, solids: Array[SolidBox]) -> bool:
	if (
		body.run_token == token
		and body.run_y == body.y
		and body.run_h == body.height
		and body.run_hw == body.half_w
		and body.run_lo > body.run_hi
		and absi(body.x - body.run_miss_x) < TILE
	):
		return false
	var found: bool = _scan(body, solids)
	if not found:
		body.run_token = token
		body.run_y = body.y
		body.run_h = body.height
		body.run_hw = body.half_w
		body.run_lo = 1
		body.run_hi = 0
		body.run_miss_x = body.x
	return found


func _scan(body: Body, solids: Array[SolidBox]) -> bool:
	var j0: int = body.y / TILE
	var top_row: int = TileGrid.cell(body.y - body.height)
	var kind: int = _grid.get_tile(TileGrid.cell(body.x), j0)
	if not TileGrid.is_wall(kind) and kind != TileGrid.ONE_WAY:
		return false
	var first: int = TileGrid.cell(body.x - body.half_w)
	var last: int = TileGrid.cell(body.x + body.half_w - 1)
	for c: int in range(first, last + 1):
		if not _column_ok(c, j0, top_row, kind):
			return false
	var ca: int = first
	while _column_ok(ca - 1, j0, top_row, kind):
		ca -= 1
	var cb: int = last
	while _column_ok(cb + 1, j0, top_row, kind):
		cb += 1
	# A solid box that could matter at this height keeps the run a column clear of it.
	var low: int = body.y - body.height
	var high: int = body.y + TILE
	for sb: SolidBox in solids:
		if sb.right <= sb.left or sb.bottom < low or sb.top > high:
			continue
		var s0: int = TileGrid.cell(sb.left)
		var s1: int = TileGrid.cell(sb.right - 1)
		if s1 + 1 < first:
			ca = maxi(ca, s1 + 2)
		elif s0 - 1 > last:
			cb = mini(cb, s0 - 2)
		else:
			return false
	body.run_lo = ca * TILE + body.half_w
	body.run_hi = (cb + 1) * TILE - body.half_w
	body.run_y = body.y
	body.run_h = body.height
	body.run_hw = body.half_w
	body.run_token = token
	body.run_tile = kind
	return true


## A column belongs to a run if its floor tile is [param kind] and the rows the box fills above it
## are empty.
func _column_ok(c: int, j0: int, top_row: int, kind: int) -> bool:
	if _grid.get_tile(c, j0) != kind:
		return false
	for r: int in range(top_row, j0):
		if _grid.get_tile(c, r) != TileGrid.EMPTY:
			return false
	return true
