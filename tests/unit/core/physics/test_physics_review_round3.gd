extends GdUnitTestSuite
## Regression tests for the third independent review of the physics sweep (docs/adr/0008), one
## or more per finding. The real-player versions are fixtures in tests/replay/physics/.

const U: int = PhysicsKit.U


## A box moved sideways [param ticks] times by [param dx] with move_x then move_y(0), the way an
## air dash moves; returns the ticks on which it reported a wall.
func _level_moves(w: CollisionWorld, b: Body, dx: int, ticks: int) -> int:
	var walled: int = 0
	for _i: int in range(ticks):
		b.clear_contacts()
		w.move_x(b, dx, 8 * U, 6 * U)
		if b.hit_wall != 0:
			walled += 1
		w.move_y(b, 0)
		assert_bool(PhysicsKit.embedded(w, b)).is_false()
	return walled


func test_a_level_move_up_a_ramp_passes_its_crest() -> void:
	# H1: the crest wall's top was inside the foot zone, so the sweep stopped the box at its face
	# and the move then went nowhere, forever, where a walk passes.
	var w: CollisionWorld = PhysicsKit.world(
		["..........", "..........", "..........", ".../######", "##########"]
	)
	var b: Body = PhysicsKit.body(40, 128)
	w.refresh_ground(b)
	assert_int(_level_moves(w, b, 20 * U, 9)).is_equal(0)
	assert_int(b.x).is_equal((40 + 180) * U)
	assert_int(b.y).is_equal(96 * U)
	assert_bool(b.on_ground).is_true()


func test_a_level_move_climbs_every_row_of_a_tall_ramp() -> void:
	# H1: on a ramp several tiles tall, the wall under the next row's slope stopped the box at
	# every row boundary. Every speed from a crawl to a dash, 45-degree and 1:2 ramps, with
	# headroom over the plateau.
	var ramps: Array[PackedStringArray] = [
		PackedStringArray(
			[
				"..........",
				"..........",
				"..........",
				"......./##",
				"....../###",
				"...../####",
				"##########",
			]
		),
		PackedStringArray(
			[
				"............",
				"............",
				"............",
				".......ab###",
				".....ab#####",
				"...ab#######",
				"############",
			]
		),
	]
	for src: PackedStringArray in ramps:
		var rows: Array[String] = []
		rows.assign(Array(src))
		var w: CollisionWorld = PhysicsKit.world(rows)
		var floor_y: int = (rows.size() - 1) * TileGrid.TILE
		var top_y: int = 3 * TileGrid.TILE
		for speed_u: int in [1, 3, 9, 14, 20]:
			var b: Body = PhysicsKit.body(40, floor_y)
			w.refresh_ground(b)
			var ticks: int = 0
			while b.y > top_y * U and ticks < 400:
				b.clear_contacts()
				w.move_x(b, speed_u * U, 8 * U, 6 * U)
				if b.hit_wall != 0 or PhysicsKit.embedded(w, b):
					fail(
						(
							"%s at %d u/f: stopped or embedded at (%d, %d)"
							% [rows[3], speed_u, b.x, b.y]
						)
					)
					return
				w.move_y(b, 0)
				ticks += 1
			assert_int(b.y).is_equal(top_y * U)


func test_a_ride_up_across_a_row_boundary_reads_the_slope_above() -> void:
	# H2: the ride-up measured its depth in the foot point's row only, so rising across a tile-row
	# boundary left the foot point inside the slope that carries on in the row above, and the box
	# was stuck there. Grounded and airborne with the lifts on, as the review found it.
	var rows: Array[String] = ["......", "...a##", ".ab###", "######"]
	var w: CollisionWorld = PhysicsKit.world(rows)
	for start: Vector2i in [Vector2i(24084, 16630), Vector2i(24084, 16500)]:
		var b := Body.make(start.x, start.y, PhysicsKit.HALF_W, PhysicsKit.STAND)
		w.refresh_ground(b)
		w.move_x(b, 888, 8 * U, 6 * U)
		w.move_y(b, 100 if not b.on_ground else 0)
		assert_bool(PhysicsKit.embedded(w, b)).is_false()
		assert_bool(w.point_solid(b.x, b.y - 1)).is_false()
		# The foot point is on or above the 'a' surface at its x.
		var s: int = TileGrid.slope_surface(TileGrid.SLOPE_R_LO, 3, 1, b.x)
		assert_int(b.y).is_less_equal(s)
		# And from there it walks both ways.
		for dir: int in [1, -1]:
			var c := Body.make(b.x, b.y, b.half_w, b.height)
			w.refresh_ground(c)
			assert_int(PhysicsKit.walk(w, c, dir * 4 * U)).is_equal(dir * 4 * U)


func test_a_box_sunk_into_a_ramp_lets_the_walk_back_up() -> void:
	# M1: a solid box (a door left open as a floor) sunk into a ramp just under its crest. The
	# walk down onto the box worked, but walking back up stopped at the crest wall's face for any
	# box top up to the foot zone below the crest. Every height across the ramp's tile, at a
	# crawl, a run and a dash, on every crest kind.
	var layouts: Array[PackedStringArray] = [
		PackedStringArray(["..........", "..........", "...../####", "##########"]),
		PackedStringArray(["..........", "..........", "...ab#####", "##########"]),
		PackedStringArray(["..........", "..........", "####\\.....", "##########"]),
		PackedStringArray(["..........", "..........", "####cd....", "##########"]),
	]
	var crests: Array[int] = [192, 160, 128, 128]
	var dirs: Array[int] = [1, 1, -1, -1]
	for k: int in range(layouts.size()):
		var rows: Array[String] = []
		rows.assign(Array(layouts[k]))
		var crest_x: int = crests[k]
		var dir: int = dirs[k]
		for depth_q: int in range(1, 128, 3):
			var top: int = 64 * U + depth_q * U / 4
			for speed: int in [2 * U, 9 * U, 20 * U]:
				var w: CollisionWorld = PhysicsKit.world(rows)
				var far: int = crest_x * U - dir * 120 * U
				var near: int = crest_x * U - dir * 2 * U
				w.solids.append(SolidBox.make(mini(far, near), top, maxi(far, near), 128 * U))
				var b := Body.make(
					crest_x * U - dir * 100 * U, top, PhysicsKit.HALF_W, PhysicsKit.STAND
				)
				w.refresh_ground(b)
				if not b.on_ground:
					continue
				var arrived: bool = false
				for _t: int in range(200 * U / speed):
					PhysicsKit.walk(w, b, dir * speed)
					if b.y == 64 * U and (b.x - crest_x * U) * dir > 12 * U:
						arrived = true
						break
					if b.hit_wall != 0:
						break
				(
					assert_bool(arrived)
					. override_failure_message(
						(
							"%s, box top %.2f u under the crest, %d u/f: stuck at (%d, %d)"
							% [rows[2], depth_q / 4.0, speed / U, b.x, b.y]
						)
					)
					. is_true()
				)


func test_walking_steps_up_onto_a_floor_at_most_the_corner_lift_higher() -> void:
	# M1 on flat ground: a solid box laid 1 u below the tiles beside it stopped a walk dead.
	# BUILD.md section 5 Ground, "Corner correction: Horizontal: 8 u nudge over ledge corners":
	# a walk given the lift steps up at most that much; without it (enemies) a lip is a wall.
	for rise_u: int in [1, 4, 8, 9]:
		for lift: int in [0, 8 * U]:
			var w: CollisionWorld = PhysicsKit.world(
				["..........", "..........", ".....#####", "##########"]
			)
			w.solids.append(SolidBox.make(0, (64 + rise_u) * U, 160 * U, 128 * U))
			var b: Body = PhysicsKit.body(120, 64 + rise_u)
			w.refresh_ground(b)
			for _i: int in range(8):
				b.clear_contacts()
				w.walk(b, 9 * U, lift)
			var stepped: bool = lift > 0 and rise_u <= 8
			assert_bool(b.x > 160 * U).is_equal(stepped)
			assert_int(b.y).is_equal((64 if stepped else 64 + rise_u) * U)
			assert_bool(b.on_ground).is_true()
			assert_bool(PhysicsKit.embedded(w, b)).is_false()


func test_a_step_up_needs_headroom() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		["..........", ".....#####", "..........", ".....#####", "##########"]
	)
	# A 4 u lip under a ceiling 44 u above the lower floor: rising 4 u would put the head in it.
	w.solids.append(SolidBox.make(0, 100 * U, 160 * U, 128 * U))
	var b: Body = PhysicsKit.body(120, 100)
	b.height = 44 * U
	w.refresh_ground(b)
	assert_int(b.top()).is_equal(56 * U)
	for _i: int in range(4):
		b.clear_contacts()
		w.walk(b, 9 * U, 8 * U)
	assert_int(b.x).is_equal(150 * U)
	assert_int(b.hit_wall).is_equal(1)


func test_a_step_up_that_cannot_move_on_is_not_taken() -> void:
	# A 4 u lip with a solid box hanging just ahead whose bottom is 2 u above the head: at the
	# floor's height the box passes under it, but stepped up it would meet it at once.
	var w: CollisionWorld = PhysicsKit.world(
		["..........", "..........", "..........", "##########"]
	)
	w.solids.append(SolidBox.make(160 * U, 92 * U, 300 * U, 96 * U))
	w.solids.append(SolidBox.make(160 * U, 0, 300 * U, 52 * U))
	var b: Body = PhysicsKit.body(140, 96)
	w.refresh_ground(b)
	assert_int(b.top()).is_equal(52 * U)
	for _i: int in range(4):
		b.clear_contacts()
		w.walk(b, 9 * U, 8 * U)
	assert_int(b.x).is_equal(150 * U)
	assert_int(b.y).is_equal(96 * U)
	assert_int(b.hit_wall).is_equal(1)


func test_a_jump_under_a_flush_ceiling_never_leaves_the_floor() -> void:
	# L1: the upward move cleared the ground contact before finding no headroom, so a jump
	# against a flush ceiling showed a frame in the air and a landing.
	var w: CollisionWorld = PhysicsKit.world(["######", "......", "......", "######"])
	var b: Body = PhysicsKit.body(80, 96)
	b.height = 64 * U
	w.refresh_ground(b)
	assert_bool(b.on_ground).is_true()
	assert_int(w.move_y(b, -10 * U)).is_equal(0)
	assert_bool(b.on_ground).is_true()
	assert_bool(b.hit_ceiling).is_true()


func test_a_sideways_move_off_a_ledge_refreshes_the_ground_contact() -> void:
	# L1: move_x left on_ground stale when y did not change. A body on the ground learns at once
	# that it has left it; a body in the air sliding level onto a floor at exactly its feet's
	# height is found standing by the move_y every air step makes next (docs/adr/0008 decision
	# 10).
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "###.....", "########"])
	var b: Body = PhysicsKit.body(80, 64)
	w.refresh_ground(b)
	assert_bool(b.on_ground).is_true()
	w.move_x(b, 30 * U)
	assert_bool(b.on_ground).is_false()
	w.move_x(b, -30 * U)
	w.move_y(b, 0)
	assert_bool(b.on_ground).is_true()


func test_a_disabled_box_never_stops_a_walk_even_without_the_broad_phase() -> void:
	# L3: the walk's sweeps relied on the broad phase to drop disabled boxes. A walk run on the
	# full list (no narrowing) must ignore them too: up a slope, along a top, and to an edge.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "..../###", "########"])
	var door := SolidBox.make(130 * U, 40 * U, 140 * U, 96 * U)
	door.enabled = false
	w.solids.append(door)
	var b: Body = PhysicsKit.body(100, 96)
	w.refresh_ground(b)
	b.clear_contacts()
	assert_int(w._walk(b, 60 * U, 0)).is_equal(60 * U)
	assert_int(b.hit_wall).is_equal(0)
	assert_int(b.y).is_equal(64 * U)
