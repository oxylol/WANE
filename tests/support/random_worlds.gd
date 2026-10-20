class_name RandomWorlds
extends RefCounted
## Random rooms and solid boxes for the suites that play two implementations of the sweep side by
## side (test_native_sweep.gd): every tile kind, slopes that obey the room rules, one-ways, hazards
## and boxes, all from a seeded [Rng].

const U: int = Fx.SUB
## One character per tile kind; a few more dots keep rooms mostly open.
const SOUP_CHARS: String = "......#S=/\\abcd^~"


## A wide room whose ground is mostly flat, with steps, blocks, hazards and platforms.
static func flat_grid(rng: Rng) -> TileGrid:
	var width: int = 60
	var height: int = 14
	var grid := TileGrid.new(width, height)
	for i: int in range(width):
		for j: int in range(height):
			var edge: bool = i == 0 or i == width - 1 or j == 0
			grid.set_tile(i, j, TileGrid.SOLID if edge else TileGrid.EMPTY)
	var level: int = 10
	for i: int in range(1, width - 1):
		if rng.below(9) == 0:
			level = clampi(level + rng.between(-1, 1), 8, 11)
		var kind: int = TileGrid.SMOOTH if (i / 12) % 3 == 1 else TileGrid.SOLID
		for j: int in range(level, height):
			grid.set_tile(i, j, kind)
	for _n: int in range(rng.between(0, 8)):
		var bi: int = rng.between(2, width - 4)
		var bj: int = rng.between(6, 9)
		var odd: Array[int] = [TileGrid.SOLID, TileGrid.SPIKES, TileGrid.PIT, TileGrid.ONE_WAY]
		grid.set_tile(bi, bj, odd[rng.below(odd.size())])
	for _p: int in range(rng.between(0, 3)):
		var pi: int = rng.between(2, width - 8)
		for k: int in range(rng.between(3, 6)):
			grid.set_tile(pi + k, rng.between(5, 7), TileGrid.ONE_WAY)
	return grid


## Random tiles with every slope that breaks the room rules cleared.
static func soup_grid(rng: Rng) -> TileGrid:
	var grid := TileGrid.new(30, 14)
	for j: int in range(14):
		for i: int in range(30):
			var t: int = TileGrid.SOLID
			if j < 13:
				t = TileGrid.CHARS.find(SOUP_CHARS[rng.below(SOUP_CHARS.length())])
			grid.set_tile(i, j, t)
	for j: int in range(13):
		for i: int in range(30):
			if TileGrid.is_slope(grid.get_tile(i, j)) and rng.below(2) == 0:
				grid.set_tile(i, j + 1, TileGrid.SOLID)
	_clear_bad_slopes(grid)
	return grid


## A floor of ramps and plateaus (all six slope kinds), with ledges, ceilings and one-ways above.
static func ramp_grid(rng: Rng) -> TileGrid:
	var width: int = 64
	var height: int = 16
	var grid := TileGrid.new(width, height)
	for i: int in range(width):
		for j: int in range(height):
			var edge: bool = i == 0 or i == width - 1 or j == 0 or j == height - 1
			grid.set_tile(i, j, TileGrid.SOLID if edge else TileGrid.EMPTY)
	var level: int = 12
	var i: int = 1
	var kinds: Array[int] = [
		TileGrid.SLOPE_R,
		TileGrid.SLOPE_L,
		TileGrid.SLOPE_R_LO,
		TileGrid.SLOPE_R_HI,
		TileGrid.SLOPE_L_HI,
		TileGrid.SLOPE_L_LO
	]
	while i < width - 1:
		var run: int = rng.between(1, 4)
		var kind: int = kinds[rng.below(kinds.size())]
		for k: int in range(run):
			if i + k >= width - 1:
				break
			grid.set_tile(i + k, level, kind)
			for j: int in range(level + 1, height - 1):
				grid.set_tile(i + k, j, TileGrid.SOLID)
		i += run
		for k: int in range(rng.between(1, 5)):
			if i >= width - 1:
				break
			for j: int in range(level, height - 1):
				grid.set_tile(i, j, TileGrid.SOLID)
			i += 1
		level = clampi(level + rng.between(-1, 1), 9, 12)
	for _n: int in range(rng.between(2, 10)):
		var odd: Array[int] = [
			TileGrid.SOLID, TileGrid.SMOOTH, TileGrid.ONE_WAY, TileGrid.SPIKES, TileGrid.PIT
		]
		grid.set_tile(rng.between(2, width - 3), rng.between(3, 9), odd[rng.below(odd.size())])
	_clear_bad_slopes(grid)
	return grid


## [param level] * 3 rectangles in sub-pixels, as boxes: none, a few small ones, many.
static func box_specs(rng: Rng, level: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for _s: int in range(level * 3):
		var l: int = rng.between(2, 40) * 32 * U + rng.between(0, 3) * 64
		var t: int = rng.between(4, 11) * 32 * U + rng.between(0, 4) * 8 * U
		out.append(Rect2i(l, t, rng.between(1, 4) * 32 * U, rng.between(1, 3) * 16 * U))
	return out


## [param count] boxes laid as lips on the floors of [method flat_grid] and [method ramp_grid]
## rooms (tops a few units above or below a floor row) and as ceilings a few units under a row,
## for the corner lift, the ledge-grab and the corner slide to work on.
static func lip_specs(rng: Rng, count: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for _s: int in range(count):
		var l: int = rng.between(2, 56) * 32 * U + rng.between(0, 3) * 64
		var wide: int = rng.between(1, 3) * 32 * U
		if rng.below(3) == 0:
			var row: int = rng.between(3, 8)
			out.append(Rect2i(l, row * 32 * U - 32 * U, wide, 32 * U + rng.between(1, 14) * U))
		else:
			var row2: int = rng.between(8, 12)
			var top: int = row2 * 32 * U - rng.between(0, 14) * U
			out.append(Rect2i(l, top, wide, rng.between(2, 40) * U))
	return out


static func _clear_bad_slopes(grid: TileGrid) -> void:
	for _pass: int in range(30):
		var bad: Array[Vector2i] = _bad_slopes(grid)
		if bad.is_empty():
			break
		for cell: Vector2i in bad:
			grid.set_tile(cell.x, cell.y, TileGrid.EMPTY)


static func _bad_slopes(grid: TileGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var re: RegEx = RegEx.create_from_string("column (\\d+), row (\\d+)")
	for problem: String in grid.validate():
		var m: RegExMatch = re.search(problem)
		if m != null:
			out.append(Vector2i(m.get_string(1).to_int(), m.get_string(2).to_int()))
	return out
