extends GdUnitTestSuite
## The flat walk (core/physics/flat_walk.gd; docs/adr/0020) answers exactly what the sweep answers.
## It belongs to the GDScript sweep: every world here has its native sweep taken away, which would
## answer without it (docs/adr/0022).
## Two worlds are built alike, one with the flat walk and one without it (the sweep is the
## reference), and the same bodies make the same random moves in both; every field of every body,
## and every distance returned, must agree after every move. Rooms: flat ground with steps,
## blocks, hazards, one-way platforms and solid boxes (some moved or switched mid-run), and random
## "soup" with slopes. A run that never takes the flat path would prove nothing, so the suite also
## counts the moves it served.

const U: int = PhysicsKit.U
const CHARS: String = "......#S=/\\abcd^~"

## Whether the bodies are sub-unit ones (_start).
var _tiny: bool = false


func test_the_flat_walk_gives_the_sweeps_answer_on_flat_worlds() -> void:
	var rng: Rng = Rng.seeded(20261020, 1)
	var served: int = 0
	var walks: int = 0
	for room: int in range(60):
		var pair: Array[CollisionWorld] = _pair(_flat_grid(rng), _solid_specs(rng, room % 3))
		var stats: Vector2i = _play(pair, rng, "flat room %d" % room)
		served += stats.x
		walks += stats.y
	assert_int(served).is_greater(walks / 4)


func test_the_flat_walk_gives_the_sweeps_answer_on_random_soup() -> void:
	var rng: Rng = Rng.seeded(20261020, 2)
	for room: int in range(60):
		var pair: Array[CollisionWorld] = _pair(_soup_grid(rng), _solid_specs(rng, room % 3))
		_play(pair, rng, "soup room %d" % room)


func test_the_flat_walk_gives_the_sweeps_answer_for_bodies_under_two_units_tall() -> void:
	# The sweep's answer for a body no taller than its half-width, or than a unit, is its own
	# (a crest, a lip and the box itself are one thing there); the flat walk must not answer it.
	_tiny = true
	var rng: Rng = Rng.seeded(20261020, 5)
	for room: int in range(900):
		var grid: TileGrid = _soup_grid(rng) if room % 2 == 1 else _flat_grid(rng)
		var pair: Array[CollisionWorld] = _pair(grid, _solid_specs(rng, room % 3))
		_play(pair, rng, "tiny room %d" % room)
	_tiny = false


func test_a_body_in_a_new_world_does_not_take_its_old_run_for_a_new_one() -> void:
	var rows_a: Array[String] = ["#........#", "#........#", "##########", "##########"]
	var rows_b: Array[String] = ["#........#", "#........#", "#...####.#", "##########"]
	var a: CollisionWorld = PhysicsKit.world(rows_a)
	a.native = null
	var b: CollisionWorld = PhysicsKit.world(rows_b)
	b.native = null
	var body: Body = Body.make(5 * 32 * U, 2 * 32 * U, 10 * U, 44 * U)
	a.walk(body, 100)
	assert_int(a.flat.hits).is_greater(0)
	var reference := Body.make(body.x, body.y, 10 * U, 44 * U)
	b.use_flat_walk = false
	b.walk(reference, 3000)
	b.use_flat_walk = true
	b.walk(body, 3000)
	assert_str(_diff(body, reference)).is_empty()


func test_a_run_is_not_trusted_after_the_world_changes() -> void:
	var rows: Array[String] = ["#..........#", "#..........#", "############", "############"]
	var w: CollisionWorld = PhysicsKit.world(rows)
	w.native = null
	var body: Body = Body.make(3 * 32 * U, 2 * 32 * U, 10 * U, 44 * U)
	w.walk(body, 100)
	var served: int = w.flat.hits
	assert_int(served).is_greater(0)
	# A wall raised in the body's way: the next walk is swept and stopped by it.
	w.grid.set_tile(5, 1, TileGrid.SOLID)
	w.walk(body, 60 * U)
	assert_int(w.flat.hits).is_equal(served)
	assert_int(body.hit_wall).is_equal(1)
	# A solid box moved in front of it.
	var w2: CollisionWorld = PhysicsKit.world(rows)
	w2.native = null
	var box: SolidBox = SolidBox.make(40 * 32 * U, 32 * U, 41 * 32 * U, 2 * 32 * U)
	w2.solids.append(box)
	var b2: Body = Body.make(3 * 32 * U, 2 * 32 * U, 10 * U, 44 * U)
	w2.walk(b2, 100)
	box.left = 4 * 32 * U
	box.right = 5 * 32 * U
	w2.walk(b2, 60 * U)
	assert_int(b2.hit_wall).is_equal(1)


func test_a_body_off_a_tile_boundary_or_near_a_ledge_is_swept() -> void:
	var rows: Array[String] = ["#..........#", "#..........#", "#####..#####", "############"]
	var w: CollisionWorld = PhysicsKit.world(rows)
	w.native = null
	var near_ledge: Body = Body.make(4 * 32 * U + 20 * U, 2 * 32 * U, 10 * U, 44 * U)
	w.walk(near_ledge, 4 * U)
	assert_int(w.flat.hits).is_equal(0)
	var floating: Body = Body.make(2 * 32 * U, 2 * 32 * U - 5, 10 * U, 44 * U)
	w.walk(floating, 4 * U)
	assert_int(w.flat.hits).is_equal(0)


## Plays both worlds of [param pair] through random moves; returns (moves served by the flat
## walk, walks made) and fails at the first disagreement.
func _play(pair: Array[CollisionWorld], rng: Rng, label: String) -> Vector2i:
	var flat_world: CollisionWorld = pair[0]
	var sweep_world: CollisionWorld = pair[1]
	var walks: int = 0
	for _b: int in range(3 if _tiny else 6):
		var a: Body = _start(flat_world, rng)
		if a == null:
			continue
		var r: Body = Body.make(a.x, a.y, a.half_w, a.height)
		r.on_ground = a.on_ground
		r.on_slope = a.on_slope
		r.ground_tile = a.ground_tile
		r.hit_wall = a.hit_wall
		r.hit_ceiling = a.hit_ceiling
		sweep_world.move_y(r, 2000 * U)
		flat_world.move_y(a, 2000 * U)
		for tick: int in range(80 if _tiny else 160):
			var op: int = rng.below(100)
			var lift: int = 8 * U if rng.below(2) == 0 else 0
			var moved_a: int = 0
			var moved_r: int = 0
			if not _tiny:
				a.clear_contacts()
				r.clear_contacts()
			if op < 78:
				var dx: int = _step(rng)
				moved_a = flat_world.walk(a, dx, lift)
				moved_r = sweep_world.walk(r, dx, lift)
				walks += 1
			elif op < 84:
				flat_world.refresh_ground(a)
				sweep_world.refresh_ground(r)
			elif op < 90:
				var dx2: int = _step(rng)
				moved_a = flat_world.move_x(a, dx2, lift, 6 * U)
				moved_r = sweep_world.move_x(r, dx2, lift, 6 * U)
			elif op < 96:
				var dy: int = rng.between(-6, 12) * U
				moved_a = flat_world.move_y(a, dy, 6 * U)
				moved_r = sweep_world.move_y(r, dy, 6 * U)
			elif op < 98 and not flat_world.solids.is_empty():
				var k: int = rng.below(flat_world.solids.size())
				var shift: int = rng.between(-3, 3) * 32 * U
				flat_world.solids[k].left += shift
				flat_world.solids[k].right += shift
				sweep_world.solids[k].left += shift
				sweep_world.solids[k].right += shift
			elif not flat_world.solids.is_empty():
				var k2: int = rng.below(flat_world.solids.size())
				flat_world.solids[k2].enabled = not flat_world.solids[k2].enabled
				sweep_world.solids[k2].enabled = flat_world.solids[k2].enabled
			var problem: String = _diff(a, r)
			if moved_a != moved_r:
				problem += " returned %d against %d" % [moved_a, moved_r]
			if problem != "":
				fail("%s, tick %d, op %d: %s" % [label, tick, op, problem])
				return Vector2i(flat_world.flat.hits, walks)
	return Vector2i(flat_world.flat.hits, walks)


func _step(rng: Rng) -> int:
	var dir: int = 1 if rng.below(2) == 0 else -1
	match rng.below(5):
		0:
			return dir * rng.between(1, 600)
		1:
			return dir * 512
		2:
			return dir * 2304
		3:
			return dir * rng.between(1, 5120)
	return dir * rng.between(1, 40 * U)


func _start(w: CollisionWorld, rng: Rng) -> Body:
	var half_w: int = [10 * U, 16 * U, 5 * U][rng.below(3)]
	var height: int = [44 * U, 64 * U, 28 * U][rng.below(3)]
	if _tiny:
		half_w = rng.between(0, 3 * U)
		height = rng.between(0, 4 * U)
		# Any place, any sub-pixel, any contact left over from before.
		var loose := Body.make(
			rng.between(-40, w.grid.width * 32 + 40) * U + rng.between(0, 255),
			rng.between(0, w.grid.height * 32) * U + rng.between(0, 255),
			half_w,
			height
		)
		loose.on_ground = rng.below(2) == 0
		loose.on_slope = rng.below(4) == 0
		loose.ground_tile = rng.between(-1, TileGrid.PIT)
		loose.hit_wall = rng.between(-1, 1)
		loose.hit_ceiling = rng.below(4) == 0
		return loose
	for _try: int in range(50):
		var x: int = rng.between(40, w.grid.width * 32 - 40) * U + rng.between(0, 255)
		var b := Body.make(x, rng.between(32, (w.grid.height - 2) * 32) * U, half_w, height)
		if w.body_fits(b.x, b.y, b.half_w, b.height):
			return b
	return null


func _diff(a: Body, b: Body) -> String:
	var out: String = ""
	for key: String in [
		"x",
		"y",
		"vx",
		"vy",
		"on_ground",
		"ground_tile",
		"on_slope",
		"hit_wall",
		"hit_ceiling",
		"nudge_x",
		"nudge_y"
	]:
		if a.get(key) != b.get(key):
			out += " %s %s against %s;" % [key, a.get(key), b.get(key)]
	return out


## Two worlds built alike: with the flat walk, then without it.
func _pair(grid: TileGrid, specs: Array[Rect2i]) -> Array[CollisionWorld]:
	var out: Array[CollisionWorld] = []
	for flat: bool in [true, false]:
		var w := CollisionWorld.new(grid.copy())
		w.native = null
		(load(WorldTuning.PATH) as WorldTuning).apply(w)
		w.use_flat_walk = flat
		for s: Rect2i in specs:
			w.solids.append(SolidBox.make(s.position.x, s.position.y, s.end.x, s.end.y))
		out.append(w)
	return out


## Solid boxes for [param count] + 1 kinds of room: none, a few small ones, many.
func _solid_specs(rng: Rng, level: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for _s: int in range(level * 3):
		var l: int = rng.between(2, 40) * 32 * U + rng.between(0, 3) * 64
		var t: int = rng.between(6, 11) * 32 * U + rng.between(0, 4) * 8 * U
		out.append(Rect2i(l, t, rng.between(1, 4) * 32 * U, rng.between(1, 3) * 16 * U))
	return out


## A wide room whose ground is mostly flat, with steps, blocks, hazards and platforms.
func _flat_grid(rng: Rng) -> TileGrid:
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
func _soup_grid(rng: Rng) -> TileGrid:
	var grid := TileGrid.new(30, 14)
	for j: int in range(14):
		for i: int in range(30):
			var t: int = TileGrid.SOLID
			if j < 13:
				t = TileGrid.CHARS.find(CHARS[rng.below(CHARS.length())])
			grid.set_tile(i, j, t)
	for j: int in range(13):
		for i: int in range(30):
			if TileGrid.is_slope(grid.get_tile(i, j)) and rng.below(2) == 0:
				grid.set_tile(i, j + 1, TileGrid.SOLID)
	for _pass: int in range(30):
		var bad: Array[Vector2i] = _bad_slopes(grid)
		if bad.is_empty():
			break
		for cell: Vector2i in bad:
			grid.set_tile(cell.x, cell.y, TileGrid.EMPTY)
	return grid


func _bad_slopes(grid: TileGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var re: RegEx = RegEx.create_from_string("column (\\d+), row (\\d+)")
	for problem: String in grid.validate():
		var m: RegExMatch = re.search(problem)
		if m != null:
			out.append(Vector2i(m.get_string(1).to_int(), m.get_string(2).to_int()))
	return out
