extends GdUnitTestSuite
## The sweep against BUILD.md section 5 ground table rows: run speed, slopes, ledges, landing, one-
## way platforms and crouch headroom (docs/adr/0008).

const U: int = PhysicsKit.U
const HALF_W: int = PhysicsKit.HALF_W
const STAND: int = PhysicsKit.STAND
const CROUCH: int = PhysicsKit.CROUCH


func test_free_run_moves_exactly_nine_units_per_tick_both_ways() -> void:
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "........", "########"])
	var b: Body = PhysicsKit.body(100, 96)
	w.refresh_ground(b)
	assert_bool(b.on_ground).is_true()
	PhysicsKit.walk(w, b, 9 * U)
	assert_int(b.x).is_equal(109 * U)
	assert_int(b.y).is_equal(96 * U)
	PhysicsKit.walk(w, b, -9 * U)
	assert_int(b.x).is_equal(100 * U)
	assert_bool(b.on_ground).is_true()


func test_wall_stops_the_box_flush_on_both_sides() -> void:
	var w: CollisionWorld = PhysicsKit.world([".#...#..", ".#...#..", ".#...#..", "########"])
	var b: Body = PhysicsKit.body(145, 96)
	assert_int(PhysicsKit.walk(w, b, 9 * U)).is_equal(5 * U)
	assert_int(b.right()).is_equal(160 * U)
	assert_int(b.hit_wall).is_equal(1)
	assert_int(PhysicsKit.walk(w, b, 9 * U)).is_equal(0)
	var c: Body = PhysicsKit.body(75, 96)
	assert_int(PhysicsKit.walk(w, c, -9 * U)).is_equal(-1 * U)
	assert_int(c.left()).is_equal(64 * U)
	assert_int(c.hit_wall).is_equal(-1)


func test_sub_pixel_moves_are_exact() -> void:
	var w: CollisionWorld = PhysicsKit.world(["....#", "....#", "....#", "#####"])
	var b: Body = PhysicsKit.body(100, 96)
	b.x = 117 * U + 37
	assert_int(w.move_x(b, 3 * U)).is_equal(U - 37)
	assert_int(b.right()).is_equal(128 * U)


func test_one_way_platforms_never_block_sideways() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		["........", "........", "..====..", "........", "########"]
	)
	var b: Body = PhysicsKit.body(30, 80)
	assert_int(w.move_x(b, 100 * U)).is_equal(100 * U)
	assert_int(b.y).is_equal(80 * U)


func test_flying_into_a_slope_lifts_onto_its_surface() -> void:
	# The centre crosses into a "/" tile below its surface: the box is lifted onto the surface,
	# the way it would have walked up it.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "...../##", "########"])
	var b: Body = PhysicsKit.body(150, 95)
	assert_int(w.move_x(b, 20 * U)).is_equal(20 * U)
	assert_int(b.y).is_equal(86 * U)
	# A slope it cannot rise onto (no headroom) stops it like a wall.
	var c: CollisionWorld = PhysicsKit.world(["........", ".....###", "...../##", "########"])
	var d: Body = PhysicsKit.body(150, 95)
	assert_int(c.move_x(d, 20 * U)).is_equal(0)
	assert_int(d.hit_wall).is_equal(1)


func test_walk_up_and_down_a_45_degree_slope() -> void:
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "...../##", "########"])
	var b: Body = PhysicsKit.body(141, 96)
	w.refresh_ground(b)
	for _i: int in range(10):
		var before_x: int = b.x
		PhysicsKit.walk(w, b, 9 * U)
		assert_int(b.x - before_x).is_equal(9 * U)
		assert_bool(b.on_ground).is_true()
		var expected: int = 96 * U - clampi(b.x - 160 * U, 0, 32 * U)
		assert_int(b.y).is_equal(expected)
	assert_int(b.y).is_equal(64 * U)
	for _i: int in range(10):
		PhysicsKit.walk(w, b, -9 * U)
		assert_bool(b.on_ground).is_true()
		assert_int(b.y).is_equal(96 * U - clampi(b.x - 160 * U, 0, 32 * U))
	assert_int(b.y).is_equal(96 * U)


func test_no_sliding_when_standing_on_a_slope() -> void:
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "...../##", "########"])
	var b: Body = PhysicsKit.body(175, 81)
	w.refresh_ground(b)
	assert_bool(b.on_ground).is_true()
	assert_bool(b.on_slope).is_true()
	for _i: int in range(60):
		PhysicsKit.walk(w, b, 0)
	assert_int(b.x).is_equal(175 * U)
	assert_int(b.y).is_equal(81 * U)


func test_shallow_slope_rises_half_a_unit_per_unit() -> void:
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "..ab####", "########"])
	var b: Body = PhysicsKit.body(60, 96)
	w.refresh_ground(b)
	for _i: int in range(12):
		PhysicsKit.walk(w, b, 6 * U)
		assert_bool(b.on_ground).is_true()
		var along: int = clampi(b.x - 64 * U, 0, 64 * U)
		assert_int(absi(b.y - (96 * U - along / 2))).is_less_equal(1)


func test_slope_crests_and_troughs_never_pop() -> void:
	# Flat, down a 45-degree slope into a trough, up again, then flat.
	var w: CollisionWorld = PhysicsKit.world(
		["..........", "..........", "##\\..../##", "###\\../###", "##########"]
	)
	var b: Body = PhysicsKit.body(40, 64)
	w.refresh_ground(b)
	for speed: int in [U, 3 * U, 9 * U]:
		b.x = 40 * U
		b.y = 64 * U
		w.refresh_ground(b)
		while b.x < 280 * U:
			var before_y: int = b.y
			PhysicsKit.walk(w, b, speed)
			assert_bool(b.on_ground).is_true()
			assert_int(absi(b.y - before_y)).is_less_equal(speed)


func test_low_ceiling_refuses_the_step_up() -> void:
	# The ceiling's underside is at y = 32: standing at 96 the head is at 52, so the box may climb
	# 20 units of slope (centre x up to 180) and no further.
	var w: CollisionWorld = PhysicsKit.world([".....###", "........", "...../##", "########"])
	var b: Body = PhysicsKit.body(150, 96)
	w.refresh_ground(b)
	for _i: int in range(20):
		PhysicsKit.walk(w, b, 4 * U)
		assert_bool(b.top() >= 32 * U).is_true()
		assert_bool(b.on_ground).is_true()
	assert_int(b.x).is_less_equal(180 * U)
	assert_int(b.x).is_greater(176 * U)


func test_walking_off_a_ledge_leaves_the_ground_only_when_fully_off() -> void:
	var w: CollisionWorld = PhysicsKit.world(["......", "......", "###...", "......", "######"])
	var b: Body = PhysicsKit.body(80, 64)
	w.refresh_ground(b)
	PhysicsKit.walk(w, b, 15 * U)
	assert_int(b.left()).is_equal(85 * U)
	assert_bool(b.on_ground).is_true()
	PhysicsKit.walk(w, b, 10 * U)
	assert_int(b.left()).is_equal(95 * U)
	assert_bool(b.on_ground).is_true()
	PhysicsKit.walk(w, b, 1 * U)
	assert_bool(b.on_ground).is_false()
	assert_int(b.y).is_equal(64 * U)


func test_landing_on_a_single_sub_pixel_of_ledge() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		["......", "......", "###...", "......", "......", "######"]
	)
	var b: Body = PhysicsKit.body(106, 50)
	b.x = 96 * U - 1 + HALF_W
	assert_int(w.move_y(b, 20 * U)).is_equal(14 * U)
	assert_bool(b.on_ground).is_true()
	assert_int(b.y).is_equal(64 * U)
	var miss: Body = PhysicsKit.body(106, 50)
	w.move_y(miss, 20 * U)
	assert_bool(miss.on_ground).is_false()
	assert_int(miss.y).is_equal(70 * U)


func test_falling_never_tunnels_at_terminal_velocity() -> void:
	var w: CollisionWorld = PhysicsKit.world(["....", "....", "....", "....", "####"])
	var b: Body = PhysicsKit.body(64, 10)
	while not b.on_ground:
		w.move_y(b, 25 * U)
	assert_int(b.y).is_equal(128 * U)


func test_one_way_platform_rules() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		["........", "........", "..====..", "........", "########"]
	)
	# From above it is a floor.
	var b: Body = PhysicsKit.body(100, 50)
	w.move_y(b, 20 * U)
	assert_bool(b.on_ground).is_true()
	assert_int(b.y).is_equal(64 * U)
	# From below it is not a ceiling, and a box rising through it does not stop on it.
	var c: Body = PhysicsKit.body(100, 128)
	assert_int(w.move_y(c, -50 * U)).is_equal(-50 * U)
	assert_bool(c.hit_ceiling).is_false()
	# A box whose feet are already below the top passes on down (this is the drop-through) and
	# lands on the floor beneath, even though the platform is still under its edges.
	var d: Body = PhysicsKit.body(100, 64)
	d.y += 1
	w.move_y(d, 20 * U)
	assert_bool(d.on_ground).is_false()
	assert_int(d.y).is_equal(84 * U + 1)
	w.move_y(d, 60 * U)
	assert_bool(d.on_ground).is_true()
	assert_int(d.y).is_equal(128 * U)


func test_crouch_headroom() -> void:
	var w: CollisionWorld = PhysicsKit.world(["........", "###..###", "........", "########"])
	var tunnel: Body = PhysicsKit.body(40, 96, CROUCH)
	assert_bool(w.headroom(tunnel, CROUCH)).is_true()
	assert_bool(w.headroom(tunnel, STAND)).is_false()
	var open: Body = PhysicsKit.body(112, 96, CROUCH)
	assert_bool(w.headroom(open, STAND)).is_true()


func test_a_body_whose_feet_are_inside_a_slope_does_not_walk_deeper() -> void:
	# Nothing the physics does leaves a foot point inside a slope; if a body is ever placed there
	# (a bad teleport), walking refuses to drive it further in either way.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "...../##", "########"])
	var b: Body = PhysicsKit.body(176, 82)
	assert_int(TileGrid.slope_surface(TileGrid.SLOPE_R, 5, 2, b.x)).is_equal(80 * U)
	for dir: int in [1, -1]:
		assert_int(PhysicsKit.walk(w, b, dir * 4 * U)).is_equal(0)
		assert_int(b.hit_wall).is_equal(dir)
		assert_int(b.x).is_equal(176 * U)


func test_walking_downhill_onto_a_solid_top_partway_through_a_step() -> void:
	# The solid's top (90) is met 22 u into a 25 u step down the slope: the box steps down onto
	# it there and walks the last 3 u along it.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "..#\\....", "########"])
	w.solids.append(SolidBox.make(90 * U, 90 * U, 200 * U, 130 * U))
	var b: Body = PhysicsKit.body(100, 68)
	w.refresh_ground(b)
	assert_bool(b.on_slope).is_true()
	assert_int(PhysicsKit.walk(w, b, 25 * U)).is_equal(25 * U)
	assert_int(b.x).is_equal(125 * U)
	assert_int(b.y).is_equal(90 * U)
	assert_bool(b.on_ground).is_true()
	assert_bool(PhysicsKit.embedded(w, b)).is_false()


func test_a_disabled_solid_box_never_touches_a_slope_walk() -> void:
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "...../##", "########"])
	var door := SolidBox.make(180 * U, 0, 188 * U, 70 * U)
	door.enabled = false
	w.solids.append(door)
	var b: Body = PhysicsKit.body(170, 86)
	w.refresh_ground(b)
	assert_int(PhysicsKit.walk(w, b, 20 * U)).is_equal(20 * U)
	assert_int(b.y).is_equal(66 * U)
