class_name TileGrid
extends RefCounted
## A room's static collision: a grid of [constant TILE]-unit tiles (BUILD.md section 5: "Full
## hold reaches 5.5 tiles (176 u)", so one tile is 32 units). Coordinates are sub-pixels; tile
## (i, j) covers x in [i * TILE_SP, (i + 1) * TILE_SP) and y in [j * TILE_SP, (j + 1) * TILE_SP),
## with +y pointing down. Outside the grid everything is solid. See docs/adr/0008.

const TILE: int = 32
const TILE_SP: int = TILE * Fx.SUB
const HALF_SP: int = TILE_SP / 2

const EMPTY: int = 0
## Solid on every side; wall-clingable (textured).
const SOLID: int = 1
## Solid on every side; not clingable (visibly smooth or wet; BUILD.md section 5 feel rules).
const SMOOTH: int = 2
## A platform whose top edge is solid only from above; down+jump drops through.
const ONE_WAY: int = 3
## 45-degree floor slope rising to the right ("/"): solid below the diagonal.
const SLOPE_R: int = 4
## 45-degree floor slope rising to the left ("\").
const SLOPE_L: int = 5
## 1:2 floor slope rising to the right over two tiles: low half then high half.
const SLOPE_R_LO: int = 6
const SLOPE_R_HI: int = 7
## 1:2 floor slope rising to the left: high half then low half.
const SLOPE_L_HI: int = 8
const SLOPE_L_LO: int = 9
## Spikes: not solid; a hazard volume in the lower part of the tile; pogo-able.
const SPIKES: int = 10
## A bottomless pit: not solid; the whole tile is a hazard volume, and there is nothing in it to
## pogo off (movement review 5, H1: tech 2's chasm).
const PIT: int = 11
## Map characters, in tile-id order (see docs/adr/0009).
const CHARS: String = ".#S=/\\abcd^~"

var width: int = 0
var height: int = 0
## Counts the grid's edits, for what is cached from its tiles ([FlatWalk]).
var revision: int = 0
var _tiles: PackedByteArray = PackedByteArray()


func _init(w: int = 0, h: int = 0) -> void:
	resize(w, h)


func resize(w: int, h: int) -> void:
	revision += 1
	width = maxi(w, 0)
	height = maxi(h, 0)
	_tiles.resize(width * height)
	_tiles.fill(EMPTY)


## Builds a grid from map rows, one character per tile (see [constant CHARS]). Unknown
## characters are reported in [param errors] and read as empty.
static func from_rows(rows: PackedStringArray, errors: PackedStringArray = []) -> TileGrid:
	var w: int = 0
	for row: String in rows:
		w = maxi(w, row.length())
	var g := TileGrid.new()
	g.width = w
	g.height = rows.size()
	var lookup := PackedByteArray()
	lookup.resize(256)
	lookup.fill(255)
	for t: int in range(CHARS.length()):
		lookup[CHARS.unicode_at(t)] = t
	# Rooms repeat rows (open air between two walls), so each distinct row is read once.
	var seen: Dictionary[String, PackedByteArray] = {}
	for j: int in range(rows.size()):
		var row: String = rows[j]
		if seen.has(row):
			g._tiles.append_array(seen[row])
			continue
		var line := PackedByteArray()
		line.resize(w)
		line.fill(EMPTY)
		var clean: bool = true
		for i: int in range(row.length()):
			var c: int = row.unicode_at(i)
			var t: int = lookup[c] if c < 256 else 255
			if t == 255:
				errors.append("unknown tile '%s' at column %d, row %d" % [row[i], i, j])
				t = EMPTY
				clean = false
			line[i] = t
		if clean:
			seen[row] = line
		g._tiles.append_array(line)
	return g


func to_rows() -> PackedStringArray:
	var rows: PackedStringArray = []
	var line := PackedByteArray()
	line.resize(width)
	for j: int in range(height):
		for i: int in range(width):
			line[i] = CHARS.unicode_at(_tiles[j * width + i])
		rows.append(line.get_string_from_ascii())
	return rows


## An independent copy (a simulation's world never shares its grid with the room it came from).
func copy() -> TileGrid:
	var g := TileGrid.new()
	g.width = width
	g.height = height
	g._tiles = _tiles.duplicate()
	return g


func in_bounds(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < width and j < height


## The tile at (i, j); [constant SOLID] outside the grid.
func get_tile(i: int, j: int) -> int:
	if not in_bounds(i, j):
		return SOLID
	return _tiles[j * width + i]


## The tiles, row by row, as the native sweep copies them ([NativeWorld]).
func raw() -> PackedByteArray:
	return _tiles


func set_tile(i: int, j: int, t: int) -> void:
	if in_bounds(i, j):
		revision += 1
		_tiles[j * width + i] = t


static func is_wall(t: int) -> bool:
	return t == SOLID or t == SMOOTH


static func is_slope(t: int) -> bool:
	return t >= SLOPE_R and t <= SLOPE_L_LO


## True if a tile of type [param t] stops a box moving up into it from below.
static func blocks_from_below(t: int) -> bool:
	return is_wall(t) or is_slope(t)


## Column or row index containing sub-pixel coordinate [param sp].
static func cell(sp: int) -> int:
	return Fx.div_floor(sp, TILE_SP)


## Surface y (sub-pixels, world) of slope tile (i, j) at world x [param x_sp], which must lie in
## column i. Larger y is lower.
static func slope_surface(t: int, i: int, j: int, x_sp: int) -> int:
	var lx: int = x_sp - i * TILE_SP
	var top: int = j * TILE_SP
	match t:
		SLOPE_R:
			return top + TILE_SP - lx
		SLOPE_L:
			return top + lx
		SLOPE_R_LO:
			return top + TILE_SP - Fx.div_floor(lx, 2)
		SLOPE_R_HI:
			return top + HALF_SP - Fx.div_floor(lx, 2)
		SLOPE_L_HI:
			return top + Fx.div_floor(lx, 2)
		SLOPE_L_LO:
			return top + HALF_SP + Fx.div_floor(lx, 2)
	return top


## Height of a slope's high edge above its tile bottom, at the left and right tile borders, in
## sub-pixels. Used by room validation to check that slopes join their neighbours.
static func slope_edge_heights(t: int) -> Vector2i:
	match t:
		SLOPE_R:
			return Vector2i(0, TILE_SP)
		SLOPE_L:
			return Vector2i(TILE_SP, 0)
		SLOPE_R_LO:
			return Vector2i(0, HALF_SP)
		SLOPE_R_HI:
			return Vector2i(HALF_SP, TILE_SP)
		SLOPE_L_HI:
			return Vector2i(TILE_SP, HALF_SP)
		SLOPE_L_LO:
			return Vector2i(HALF_SP, 0)
	return Vector2i(TILE_SP, TILE_SP)


## Geometry rules the physics relies on (docs/adr/0008): every slope rests on a wall, and every
## side of a slope that stands above its tile's bottom meets a wall or a slope edge of the same
## height, so a slope never shows a vertical face or an underside. Returns one message per
## broken rule.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	# Only slopes have rules: find them with the native search rather than visiting every tile,
	# then check them in row order.
	var slopes := PackedInt32Array()
	for kind: int in range(SLOPE_R, SLOPE_L_LO + 1):
		var at: int = _tiles.find(kind)
		while at >= 0:
			slopes.append(at)
			at = _tiles.find(kind, at + 1)
	slopes.sort()
	for at: int in slopes:
		var i: int = at % width
		var j: int = Fx.div_floor(at, width)
		var t: int = _tiles[at]
		if not is_wall(get_tile(i, j + 1)):
			errors.append("slope at column %d, row %d does not rest on a wall" % [i, j])
		var edges: Vector2i = slope_edge_heights(t)
		if edges.x > 0 and not _side_sealed(get_tile(i - 1, j), edges.x, false):
			errors.append(
				(
					"slope at column %d, row %d: its left side needs a wall or a matching slope"
					% [i, j]
				)
			)
		if edges.y > 0 and not _side_sealed(get_tile(i + 1, j), edges.y, true):
			errors.append(
				(
					"slope at column %d, row %d: its right side needs a wall or a matching slope"
					% [i, j]
				)
			)
	return errors


## True if tile [param n], beside a slope side of height [param h], covers that side: a wall, or a
## slope whose touching edge (its left edge when [param n_is_right]) has the same height.
static func _side_sealed(n: int, h: int, n_is_right: bool) -> bool:
	if is_wall(n):
		return true
	if not is_slope(n):
		return false
	var e: Vector2i = slope_edge_heights(n)
	return (e.x if n_is_right else e.y) == h


## Hashes every tile (through SHA-256 of the tile bytes, which is native and stable across
## engine versions). The grid never changes during a run, so the simulation hashes it once, as
## content ([ContentHash]), not every tick.
func hash_into(h: StateHasher) -> void:
	h.add_int(width)
	h.add_int(height)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not _tiles.is_empty():
		ctx.update(_tiles)
	var digest: PackedByteArray = ctx.finish()
	for k: int in range(0, digest.size(), 4):
		h.add_int(digest.decode_u32(k))
