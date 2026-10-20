extends GdUnitTestSuite
## The native physics sweep (native/src/sweep.cpp; docs/adr/0022) against its GDScript reference
## (core/physics/collision_world.gd and collision_queries.gd). Two worlds are built alike from a
## seeded random room, one answering from the GDScript sweep and one from the native one, and the
## same bodies make the same random moves in both: after every move every field of both bodies
## (position, velocity, ground contact, hit flags, nudges) and every returned distance must agree,
## and after every tick so must a batch of the world's queries. The rooms hold every tile kind,
## slopes, one-ways, hazards and solid boxes that move, switch and come and go while the bodies
## play; the bodies walk like enemies, walk, dash and fall like the player (its corner lift and
## slide), at walk, dash and fall speeds. A suite that never lifts, ducks, slides, climbs or lands
## on an edge would prove little, so the last test counts what the others met.

const U: int = Fx.SUB
const SEED: int = 20261021
## How many rooms the coverage test plays on its own.
const COVERAGE_ROOMS: int = 36

## What the random play met, summed over the suite's rooms.
static var met: Dictionary[String, int] = {}
## Whether the random play keeps every distance on whole units (set by one test).
static var aligned: bool = false


func before() -> void:
	met.clear()
	aligned = false


func after_test() -> void:
	aligned = false


func test_native_gives_the_references_answer_on_flat_worlds() -> void:
	var rng: Rng = Rng.seeded(SEED, 1)
	for room: int in range(30):
		_play_room(RandomWorlds.flat_grid(rng), rng, room % 3, "flat room %d" % room)


func test_native_gives_the_references_answer_on_ramps() -> void:
	var rng: Rng = Rng.seeded(SEED, 2)
	for room: int in range(30):
		_play_room(RandomWorlds.ramp_grid(rng), rng, room % 3, "ramp room %d" % room)


func test_native_gives_the_references_answer_on_random_soup() -> void:
	var rng: Rng = Rng.seeded(SEED, 3)
	for room: int in range(40):
		_play_room(RandomWorlds.soup_grid(rng), rng, room % 3, "soup room %d" % room)


func test_native_gives_the_references_answer_with_everything_on_whole_units() -> void:
	# Edges, speeds and starts all on whole units, so that the equalities the sweep tests (a lip
	# exactly as high as the lift, a floor exactly at the feet, a contact exactly at a segment's
	# end) come up far oftener than they do with sub-pixel remainders.
	aligned = true
	var rng: Rng = Rng.seeded(SEED, 7)
	for room: int in range(75):
		var grid: TileGrid = null
		match room % 3:
			0:
				grid = RandomWorlds.flat_grid(rng)
			1:
				grid = RandomWorlds.ramp_grid(rng)
			_:
				grid = RandomWorlds.soup_grid(rng)
		_play_room(grid, rng, 3 + room % 2, "aligned room %d" % room)


func test_native_gives_the_references_answer_with_lips_and_ceilings() -> void:
	var rng: Rng = Rng.seeded(SEED, 4)
	for room: int in range(40):
		var grid: TileGrid = (
			RandomWorlds.ramp_grid(rng) if room % 2 == 0 else RandomWorlds.flat_grid(rng)
		)
		_play_room(grid, rng, 3 + room % 3, "lip room %d" % room)


func test_native_gives_the_references_answer_at_corners() -> void:
	# Small rooms with one lip or ceiling box and a body put right beside it: the corner lift on
	# the ground and in the air, the ledge-grab, the duck under a ceiling corner and the slide.
	var rng: Rng = Rng.seeded(SEED, 5)
	var rows: Array[String] = []
	for j: int in range(10):
		rows.append("#" + ".".repeat(22) + "#" if j < 8 else "#".repeat(24))
	var grid: TileGrid = TileGrid.from_rows(PackedStringArray(rows))
	for trial: int in range(1500):
		var pair: Array[CollisionWorld] = []
		var bx: int = rng.between(6, 14) * 32 * U + _sub(rng)
		var spec: Rect2i
		if trial % 3 == 0:
			# A ceiling: its bottom a little above the body's top.
			spec = Rect2i(bx, 3 * 32 * U, rng.between(1, 3) * 32 * U, rng.between(40, 100) * U)
		else:
			# A lip on the floor (floor y = 8 * 32 u).
			var rise: int = rng.between(1, 16) * U + _sub(rng)
			spec = Rect2i(bx, 8 * 32 * U - rise, rng.between(1, 3) * 32 * U, rise + 8 * U)
		for native: bool in [false, true]:
			var w := CollisionWorld.new(grid.copy())
			w.native = NativeWorld.create(true) if native else null
			w.solids.append(SolidBox.make(spec.position.x, spec.position.y, spec.end.x, spec.end.y))
			pair.append(w)
		var half_w: int = [10 * U, 16 * U][rng.below(2)]
		var height: int = [44 * U, 64 * U, 28 * U][rng.below(3)]
		var side: int = 1 if rng.below(2) == 0 else -1
		var x: int = (
			bx - side * (half_w + rng.between(-1, 40) * U)
			if side > 0
			else bx + spec.size.x + half_w + rng.between(-1, 40) * U
		)
		var y: int = 8 * 32 * U - (0 if rng.below(3) == 0 else rng.between(1, 60) * U)
		var a: Body = Body.make(x, y, half_w, height)
		var b: Body = Body.make(x, y, half_w, height)
		for step: int in range(8):
			a.clear_contacts()
			b.clear_contacts()
			var dx: int = side * rng.between(1, 24) * U + _sub(rng)
			var returned: Array[int] = []
			var what: String = "walk"
			match rng.below(4):
				0:
					returned = [pair[0].walk(a, dx, 8 * U), pair[1].walk(b, dx, 8 * U)]
				1:
					what = "move_x"
					returned = [
						pair[0].move_x(a, dx, 10 * U, 6 * U), pair[1].move_x(b, dx, 10 * U, 6 * U)
					]
				2:
					what = "move_y"
					var dy: int = rng.between(-14, 12) * U + _sub(rng)
					returned = [pair[0].move_y(a, dy, 6 * U), pair[1].move_y(b, dy, 6 * U)]
				_:
					what = "walk and fall"
					returned = [pair[0].walk(a, dx, 0), pair[1].walk(b, dx, 0)]
					pair[0].move_y(a, 4 * U, 6 * U)
					pair[1].move_y(b, 4 * U, 6 * U)
			if a.nudge_y < 0:
				_note("move_x lifted" if what == "move_x" else "walk stepped up")
			elif a.nudge_y > 0:
				_note("move_x ducked")
			if a.nudge_x != 0:
				_note("move_y slid")
			var problem: String = _diff(a, b)
			if returned[0] != returned[1]:
				problem += " returned %d against %d;" % [returned[0], returned[1]]
			if not problem.is_empty():
				fail(
					(
						"corner trial %d step %d, %s at (%d, %d): %s"
						% [trial, step, what, a.x, a.y, problem]
					)
				)
				return


func test_native_gives_the_references_answer_on_the_far_edge_of_a_ledge() -> void:
	# Bodies put just above the far edge of a platform and moving off it, falling: the far-edge
	# landing (landing_contact) and what the player does with it, on platforms three tiles wide
	# with one-tile pits (physics_bench.gd's ledge ground).
	var rng: Rng = Rng.seeded(SEED, 8)
	var rows: Array[String] = []
	for j: int in range(12):
		if j == 6:
			rows.append("#" + "###.".repeat(15) + "##" + "#")
		elif j >= 10:
			rows.append("#".repeat(64))
		else:
			rows.append("#" + ".".repeat(62) + "#")
	var grid: TileGrid = TileGrid.from_rows(PackedStringArray(rows))
	var landed: int = 0
	for trial: int in range(2000):
		var pair: Array[CollisionWorld] = []
		var specs: Array[Rect2i] = RandomWorlds.box_specs(rng, trial % 3)
		for native: bool in [false, true]:
			var w := CollisionWorld.new(grid.copy())
			w.native = NativeWorld.create(true) if native else null
			for sp: Rect2i in specs:
				w.solids.append(SolidBox.make(sp.position.x, sp.position.y, sp.end.x, sp.end.y))
			pair.append(w)
		# Platform k spans x 128 k + 32 to 128 k + 128 u, its top at y 192 u.
		var edge: int = (128 * rng.between(0, 13) + 128) * U
		var half_w: int = [10 * U, 16 * U][rng.below(2)]
		var x: int = edge - rng.between(0, 24) * U + _sub(rng)
		var y: int = 192 * U - rng.between(0, 6) * U + _sub(rng)
		var a: Body = Body.make(x, y, half_w, 44 * U)
		var b: Body = Body.make(x, y, half_w, 44 * U)
		var dx: int = rng.between(2, 24) * U + _sub(rng)
		var dy: int = rng.between(1, 14) * U + _sub(rng)
		var lift: int = 8 * U if rng.below(4) != 0 else 0
		var ca: int = pair[0].landing_contact(a, dx, dy, lift, 6 * U)
		var cb: int = pair[1].landing_contact(b, dx, dy, lift, 6 * U)
		var problem: String = _diff(a, b)
		if ca != cb:
			problem += " landing_contact %d against %d;" % [ca, cb]
		if problem.is_empty() and ca != CollisionQueries.NONE:
			landed += 1
			var ra: int = (
				pair[0].move_x(a, ca) + pair[0].move_y(a, dy) + pair[0].walk(a, dx - ca, lift)
			)
			var rb: int = (
				pair[1].move_x(b, cb) + pair[1].move_y(b, dy) + pair[1].walk(b, dx - cb, lift)
			)
			problem = _diff(a, b)
			if ra != rb:
				problem += " returned %d against %d;" % [ra, rb]
		if not problem.is_empty():
			fail("far-edge trial %d from (%d, %d) dx %d dy %d: %s" % [trial, x, y, dx, dy, problem])
			return
	assert_int(landed).is_greater(100)


func test_native_gives_the_references_answer_at_the_crest_of_a_ramp() -> void:
	# A ramp up to a plateau with a lip box at its crest or beyond: the lift counted from the floor
	# under the leading edge, the air steps over a lip met from a slope.
	var rng: Rng = Rng.seeded(SEED, 6)
	var ramps: Array[String] = ["/#", "#\\", "ab#", "#cd"]
	for trial: int in range(1500):
		var ramp: String = ramps[trial % ramps.size()]
		var at: int = 4 + trial % 7
		var rows: Array[String] = []
		for j: int in range(10):
			var row: String = "#" + ".".repeat(22) + "#"
			if j == 7:
				row = "#" + ".".repeat(at) + ramp + ".".repeat(22 - at - ramp.length()) + "#"
				if ramp.begins_with("#"):
					row = "#" + ".".repeat(at) + ramp + ".".repeat(22 - at - ramp.length()) + "#"
			elif j >= 8:
				row = "#".repeat(24)
			rows.append(row)
		var grid: TileGrid = TileGrid.from_rows(PackedStringArray(rows))
		if not grid.validate().is_empty():
			fail("ramp %s is not a valid room: %s" % [ramp, grid.validate()])
			return
		var crest: int = (1 + at + ramp.length() / 2) * 32 * U
		var rise: int = rng.between(1, 20) * U + _sub(rng)
		var lip := Rect2i(
			crest + rng.between(-2, 2) * 32 * U + rng.between(-12, 12) * U,
			7 * 32 * U - rise,
			rng.between(1, 2) * 32 * U,
			rise + 4 * U
		)
		var pair: Array[CollisionWorld] = []
		for native: bool in [false, true]:
			var w := CollisionWorld.new(grid.copy())
			w.native = NativeWorld.create(true) if native else null
			w.solids.append(SolidBox.make(lip.position.x, lip.position.y, lip.end.x, lip.end.y))
			pair.append(w)
		var half_w: int = [10 * U, 16 * U][rng.below(2)]
		var side: int = 1 if rng.below(2) == 0 else -1
		var x: int = crest - side * rng.between(8, 90) * U
		var y: int = 8 * 32 * U - rng.between(0, 50) * U
		var a: Body = Body.make(x, y, half_w, 44 * U)
		var b: Body = Body.make(x, y, half_w, 44 * U)
		pair[0].move_y(a, 100 * U)
		pair[1].move_y(b, 100 * U)
		for step: int in range(10):
			a.clear_contacts()
			b.clear_contacts()
			var dx: int = side * rng.between(1, 22) * U + _sub(rng)
			var pre: String = (
				"pre (%d, %d) ground %s tile %d slope %s"
				% [a.x, a.y, a.on_ground, a.ground_tile, a.on_slope]
			)
			var lift: int = 8 * U if rng.below(4) != 0 else 0
			var returned: Array[int] = []
			var what: String = "walk"
			if rng.below(3) == 0:
				what = "move_x"
				returned = [pair[0].move_x(a, dx, lift, 6 * U), pair[1].move_x(b, dx, lift, 6 * U)]
			else:
				returned = [pair[0].walk(a, dx, lift), pair[1].walk(b, dx, lift)]
			if rng.below(3) == 0:
				var dy: int = rng.between(-6, 8) * U
				returned[0] += pair[0].move_y(a, dy, 6 * U)
				returned[1] += pair[1].move_y(b, dy, 6 * U)
			if a.nudge_y < 0:
				_note("walk stepped up" if what == "walk" else "move_x lifted")
			var problem: String = _diff(a, b)
			if returned[0] != returned[1]:
				problem += " returned %d against %d;" % [returned[0], returned[1]]
			if not problem.is_empty():
				fail(
					(
						"ramp %s at %d, lip %s, trial %d step %d, %s dx %d lift %d from (%d, %d) hw %d, %s: %s"
						% [
							ramp,
							at,
							lip,
							trial,
							step,
							what,
							dx,
							lift,
							a.x,
							a.y,
							half_w,
							pre,
							problem
						]
					)
				)
				return


func test_the_random_play_met_every_kind_of_move() -> void:
	# Plays its own rooms, so that it means the same run alone, filtered or in any order.
	met.clear()
	var rng: Rng = Rng.seeded(SEED, 9)
	for room: int in range(COVERAGE_ROOMS):
		var grid: TileGrid = null
		match room % 3:
			0:
				grid = RandomWorlds.flat_grid(rng)
			1:
				grid = RandomWorlds.ramp_grid(rng)
			_:
				grid = RandomWorlds.soup_grid(rng)
		_play_room(grid, rng, room % 6, "coverage room %d" % room)
	for key: String in [
		"walk",
		"walk on slope",
		"walk stepped up",
		"walk stepped down",
		"walk off a ledge",
		"move_x",
		"move_x lifted",
		"move_x ducked",
		"move_y",
		"move_y slid",
		"move_y hit ceiling",
		"landed",
		"landing_contact",
		"drop_through",
		"wall hit",
		"spikes",
		"box edit",
		"tile edit"
	]:
		assert_int(met.get(key, 0)).is_greater(0)


func test_a_body_with_no_native_sweep_moves_the_reference_way() -> void:
	var rows: Array[String] = ["#........#", "#........#", "##########", "##########"]
	var w: CollisionWorld = PhysicsKit.world(rows)
	w.native = NativeWorld.create(true)
	assert_object(w.native).is_not_null()
	var body: Body = Body.make(3 * 32 * U, 2 * 32 * U, 10 * U, 44 * U)
	assert_int(w.walk(body, 100)).is_equal(100)
	w.native = null
	assert_int(w.walk(body, 100)).is_equal(100)
	assert_int(body.x).is_equal(3 * 32 * U + 200)


func test_the_mirror_follows_boxes_tiles_and_the_spike_inset() -> void:
	var rows: Array[String] = ["#..........#", "#..........#", "############", "############"]
	var w: CollisionWorld = PhysicsKit.world(rows)
	w.native = NativeWorld.create(true)
	var body: Body = Body.make(3 * 32 * U, 2 * 32 * U, 10 * U, 44 * U)
	# A box raised in the body's way, moved away, switched off, then a wall tile.
	var box: SolidBox = SolidBox.make(5 * 32 * U, 32 * U, 6 * 32 * U, 2 * 32 * U)
	w.solids.append(box)
	w.walk(body, 4 * 32 * U)
	assert_int(body.hit_wall).is_equal(1)
	assert_int(body.x).is_equal(5 * 32 * U - 10 * U)
	body.clear_contacts()
	box.enabled = false
	w.walk(body, 100)
	assert_int(body.hit_wall).is_equal(0)
	box.enabled = true
	box.left += 32 * U
	box.right += 32 * U
	w.walk(body, 3 * 32 * U)
	assert_int(body.hit_wall).is_equal(1)
	assert_int(body.x).is_equal(6 * 32 * U - 10 * U)
	w.grid.set_tile(8, 1, TileGrid.SPIKES)
	var l: int = 8 * 32 * U
	var t: int = 32 * U
	w.spike_inset_sp = 12 * U
	assert_bool(w.touches_spikes(l, l + 32 * U, t, t + 32 * U)).is_true()
	assert_bool(w.touches_spikes(l, l + 32 * U, t, t + 8 * U)).is_false()
	w.spike_inset_sp = 0
	assert_bool(w.touches_spikes(l, l + 32 * U, t, t + 8 * U)).is_true()
	# A new list of the same length is another list.
	var other: SolidBox = SolidBox.make(0, 0, 32 * U, 32 * U)
	w.solids = [other]
	assert_bool(w.region_blocked(U, 2 * U, U, 2 * U)).is_true()


## Plays one random room through both paths. [param level] picks the number of solid boxes.
func _play_room(grid: TileGrid, rng: Rng, level: int, label: String) -> void:
	var specs: Array[Rect2i] = RandomWorlds.box_specs(rng, level)
	if level >= 3:
		specs = RandomWorlds.lip_specs(rng, 6 + rng.below(18))
	var spike: int = Fx.units(rng.between(0, 31))
	var pair: Array[CollisionWorld] = []
	for native: bool in [false, true]:
		var w := CollisionWorld.new(grid.copy())
		w.native = NativeWorld.create(true) if native else null
		w.spike_inset_sp = spike
		for s: Rect2i in specs:
			w.solids.append(SolidBox.make(s.position.x, s.position.y, s.end.x, s.end.y))
		pair.append(w)
	assert_object(pair[1].native).is_not_null()
	for _b: int in range(5):
		if not _play_body(pair, rng, label):
			return


## One body, a few hundred ticks. Returns false at the first disagreement (and fails the test).
func _play_body(pair: Array[CollisionWorld], rng: Rng, label: String) -> bool:
	var ref_world: CollisionWorld = pair[0]
	var nat_world: CollisionWorld = pair[1]
	var a: Body = _start(ref_world, rng)
	var b: Body = Body.make(a.x, a.y, a.half_w, a.height)
	var gravity: int = 9 * U / 8
	for tick: int in range(140):
		a.clear_contacts()
		b.clear_contacts()
		var op: int = rng.below(100)
		var enemy: bool = rng.below(3) == 0
		var lift: int = 0 if enemy else 8 * U
		var slide: int = 0 if enemy else 6 * U
		var out: Array[int] = [0, 0]
		var what: String = ""
		if op < 30:
			what = "walk"
			var dx: int = _speed(rng, rng.below(8) == 0)
			out = [ref_world.walk(a, dx, lift), nat_world.walk(b, dx, lift)]
			_count_walk(a, dx, lift)
		elif op < 38:
			what = "move_x"
			var dx2: int = _speed(rng, rng.below(4) == 0)
			var y0: int = a.y
			out = [ref_world.move_x(a, dx2, lift, slide), nat_world.move_x(b, dx2, lift, slide)]
			_note("move_x")
			if lift > 0 and a.nudge_y < 0:
				_note("move_x lifted")
			if a.nudge_y > 0 and a.y > y0:
				_note("move_x ducked")
		elif op < 62:
			what = "fall"
			var dy: int = rng.between(-10, 16) * U
			a.vy = clampi(a.vy + gravity, -12 * U, 16 * U) if rng.below(2) == 0 else dy
			b.vy = a.vy
			out = [ref_world.move_y(a, a.vy, slide), nat_world.move_y(b, b.vy, slide)]
			_note("move_y")
			if a.nudge_x != 0:
				_note("move_y slid")
			if a.hit_ceiling:
				_note("move_y hit ceiling")
			if a.on_ground:
				_note("landed")
		elif op < 72:
			what = "landing_contact"
			var dx3: int = _speed(rng, false)
			var dy3: int = rng.between(1, 14) * U
			var ca: int = ref_world.landing_contact(a, dx3, dy3, lift, slide)
			var cb: int = nat_world.landing_contact(b, dx3, dy3, lift, slide)
			out = [ca, cb]
			if ca != CollisionQueries.NONE:
				_note("landing_contact")
				# What the player does with it.
				out = [
					ref_world.move_x(a, ca) + ref_world.move_y(a, dy3),
					nat_world.move_x(b, cb) + nat_world.move_y(b, dy3)
				]
		elif op < 76:
			what = "refresh_ground"
			ref_world.refresh_ground(a)
			nat_world.refresh_ground(b)
		elif op < 80:
			what = "drop_through"
			out = [int(ref_world.drop_through(a)), int(nat_world.drop_through(b))]
			if out[0] != 0:
				_note("drop_through")
		elif op < 85:
			what = "edit"
			_edit(pair, rng)
		elif op < 88:
			what = "teleport"
			var spot: Body = _start(ref_world, rng)
			for body: Body in [a, b]:
				body.x = spot.x
				body.y = spot.y
				body.vy = 0
		var problem: String = _diff(a, b)
		if out[0] != out[1]:
			problem += " returned %d against %d;" % [out[0], out[1]]
		if problem.is_empty():
			problem = _query_diff(ref_world, nat_world, a, rng)
		if not problem.is_empty():
			fail("%s, tick %d, %s at (%d, %d): %s" % [label, tick, what, a.x, a.y, problem])
			return false
		if a.y > ref_world.grid.height * 32 * U or a.y < 0:
			var home: Body = _start(ref_world, rng)
			for body: Body in [a, b]:
				body.x = home.x
				body.y = home.y
				body.vy = 0
	return true


## Compares a batch of read-only queries around the body in both worlds.
func _query_diff(r: CollisionWorld, n: CollisionWorld, a: Body, rng: Rng) -> String:
	var out: String = ""
	var dir: int = 1 if rng.below(2) == 0 else -1
	var reach: int = rng.between(1, 12) * U
	var smooth: bool = rng.below(2) == 0
	out += _same(
		"wall_near", r.wall_near(a, dir, reach, smooth), n.wall_near(a, dir, reach, smooth)
	)
	out += _same("can_drop_through", r.can_drop_through(a), n.can_drop_through(a))
	var new_h: int = rng.between(20, 70) * U
	out += _same("headroom", r.headroom(a, new_h), n.headroom(a, new_h))
	out += _same(
		"body_fits",
		r.body_fits(a.x, a.y, a.half_w, a.height),
		n.body_fits(a.x, a.y, a.half_w, a.height)
	)
	var px: int = a.x + rng.between(-40, 40) * U
	var py: int = a.y + rng.between(-60, 40) * U
	out += _same("point_solid", r.point_solid(px, py), n.point_solid(px, py))
	var l: int = a.x + rng.between(-60, 60) * U + _sub(rng)
	var w: int = rng.between(1, 50) * U + _sub(rng)
	var t: int = a.y + rng.between(-70, 40) * U + _sub(rng)
	var h: int = rng.between(1, 50) * U + _sub(rng)
	out += _same(
		"region_blocked", r.region_blocked(l, l + w, t, t + h), n.region_blocked(l, l + w, t, t + h)
	)
	out += _same(
		"touches_spikes", r.touches_spikes(l, l + w, t, t + h), n.touches_spikes(l, l + w, t, t + h)
	)
	out += _same(
		"touches_hazard", r.touches_hazard(l, l + w, t, t + h), n.touches_hazard(l, l + w, t, t + h)
	)
	var y1: int = t + rng.between(0, 40) * U
	out += _same("floor_top_in", r.floor_top_in(l, l + w, t, y1), n.floor_top_in(l, l + w, t, y1))
	if out.is_empty() and r.touches_spikes(l, l + w, t, t + h):
		_note("spikes")
	return out


func _same(label: String, x: Variant, y: Variant) -> String:
	return "" if x == y else " %s %s against %s;" % [label, x, y]


## A random edit of the world, made alike in both: a box moved, switched, made clingable or not,
## added or taken away, a tile changed, the spike inset changed.
func _edit(pair: Array[CollisionWorld], rng: Rng) -> void:
	var count: int = pair[0].solids.size()
	var kind: int = rng.below(8)
	var k: int = rng.below(maxi(count, 1))
	var shift: int = rng.between(-3, 3) * 32 * U + rng.between(-1, 1) * 8 * U
	var ti: int = rng.between(1, pair[0].grid.width - 2)
	var tj: int = rng.between(1, pair[0].grid.height - 2)
	var tile: int = rng.below(TileGrid.PIT + 1)
	var spike: int = Fx.units(rng.between(0, 31))
	for w: CollisionWorld in pair:
		match kind:
			0:
				if count > 0:
					w.solids[k].left += shift
					w.solids[k].right += shift
			1:
				if count > 0:
					w.solids[k].top += shift / 2
					w.solids[k].bottom += shift / 2
			2:
				if count > 0:
					w.solids[k].enabled = not w.solids[k].enabled
			3:
				if count > 0:
					w.solids[k].clingable = not w.solids[k].clingable
			4:
				var x0: int = ti * 32 * U
				var y0: int = tj * 32 * U
				w.solids.append(SolidBox.make(x0, y0, x0 + 32 * U, y0 + 16 * U))
			5:
				if count > 0:
					w.solids.remove_at(k)
			6:
				# Only valid rooms: a slope tile is set only when a wall can hold it.
				var t2: int = tile if not TileGrid.is_slope(tile) else TileGrid.SOLID
				w.grid.set_tile(ti, tj, t2)
			7:
				w.spike_inset_sp = spike
	if kind == 6:
		_note("tile edit")
	elif kind <= 5:
		_note("box edit")


## A sub-pixel remainder: half the time none, so that edges and distances meet on whole units and
## the equalities the sweep tests (a lip exactly as high as the lift, a floor exactly at the feet)
## come up.
func _sub(rng: Rng) -> int:
	return 0 if aligned or rng.below(2) == 0 else rng.below(U)


func _speed(rng: Rng, fast: bool) -> int:
	var dir: int = 1 if rng.below(2) == 0 else -1
	if fast:
		return dir * rng.between(14, 40) * U
	match rng.below(5):
		0:
			return dir * (rng.between(1, 600) if not aligned else rng.between(1, 3) * U)
		1:
			return dir * 9 * U
		2:
			return dir * (rng.between(1, 5120) if not aligned else rng.between(1, 20) * U)
		3:
			return dir * 3 * U
	return dir * rng.between(1, 20) * U


func _start(w: CollisionWorld, rng: Rng) -> Body:
	var half_w: int = [10 * U, 16 * U, 5 * U][rng.below(3)]
	var height: int = [44 * U, 64 * U, 28 * U][rng.below(3)]
	var best: Body = null
	for _try: int in range(60):
		var x: int = rng.between(40, w.grid.width * 32 - 40) * U + _sub(rng)
		var b := Body.make(x, rng.between(32, (w.grid.height - 1) * 32) * U, half_w, height)
		best = b
		# Mostly valid starts, sometimes whatever came (the reference answers those too).
		if w.body_fits(b.x, b.y, b.half_w, b.height) or rng.below(12) == 0:
			return b
	return best


func _count_walk(a: Body, dx: int, lift: int) -> void:
	_note("walk")
	if a.on_slope:
		_note("walk on slope")
	if a.nudge_y < 0 and lift > 0:
		_note("walk stepped up")
	if a.nudge_y > 0:
		_note("walk stepped down")
	if not a.on_ground and dx != 0:
		_note("walk off a ledge")
	if a.hit_wall != 0:
		_note("wall hit")


func _note(key: String) -> void:
	met[key] = met.get(key, 0) + 1


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
