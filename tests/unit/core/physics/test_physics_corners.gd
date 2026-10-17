extends GdUnitTestSuite
## Corner correction: BUILD.md section 5 ground table ("horizontal: 8 u nudge over ledge corners;
## vertical: 6 u nudge around ceiling corners"), the wall table's automatic ledge-grab within 10 u,
## and the feel rule "The player never clips a corner they visually cleared".

const U: int = PhysicsKit.U
const HALF_W: int = PhysicsKit.HALF_W
const STAND: int = PhysicsKit.STAND
const CROUCH: int = PhysicsKit.CROUCH


func test_horizontal_corner_correction_lifts_up_to_eight_units() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		["........", "........", ".....###", ".....###", "########"]
	)
	var ok: Body = PhysicsKit.body(145, 72)
	assert_int(w.move_x(ok, 9 * U, 8 * U)).is_equal(9 * U)
	assert_int(ok.y).is_equal(64 * U)
	assert_int(ok.nudge_y).is_equal(-8 * U)
	assert_int(ok.x).is_equal(154 * U)
	var too_low: Body = PhysicsKit.body(145, 73)
	assert_int(w.move_x(too_low, 9 * U, 8 * U)).is_equal(5 * U)
	assert_int(too_low.y).is_equal(73 * U)
	assert_int(too_low.hit_wall).is_equal(1)


func test_ledge_grab_reaches_ten_units() -> void:
	# BUILD.md wall table: "A ledge-grab is automatic within 10 u of a wall's top".
	var w: CollisionWorld = PhysicsKit.world(
		["........", "........", ".....###", ".....###", "########"]
	)
	var grab: Body = PhysicsKit.body(150, 74)
	assert_int(w.move_x(grab, 2 * U, 10 * U)).is_equal(2 * U)
	assert_int(grab.y).is_equal(64 * U)
	var miss: Body = PhysicsKit.body(150, 75)
	assert_int(w.move_x(miss, 2 * U, 10 * U)).is_equal(0)


func test_lift_needs_free_space_above() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		["........", "........", ".....###", ".....###", "########"]
	)
	var b: Body = PhysicsKit.body(100, 70)
	assert_int(w.move_x(b, 70 * U, 8 * U)).is_equal(70 * U)
	assert_int(b.y).is_equal(64 * U)
	# A solid box 4 u above the head where the box meets the ledge leaves no room for the 8 u
	# lift. (A tile cannot do this: tile ceilings sit on 32 u steps and the box is 44 tall.)
	var boxed: Body = PhysicsKit.body(145, 72)
	w.solids.append(SolidBox.make(138 * U, 10 * U, 162 * U, 24 * U))
	assert_int(w.move_x(boxed, 9 * U, 8 * U)).is_equal(5 * U)
	assert_int(boxed.y).is_equal(72 * U)
	assert_int(boxed.nudge_y).is_equal(0)
	# Raised 5 u, the solid leaves room for the 7 u lift there is now.
	w.solids[0].bottom = 20 * U
	var room: Body = PhysicsKit.body(145, 71)
	assert_int(w.move_x(room, 9 * U, 8 * U)).is_equal(9 * U)
	assert_int(room.y).is_equal(64 * U)


func test_no_corner_correction_while_grounded() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		["........", ".....###", ".....###", ".....###", "########"]
	)
	var b: Body = PhysicsKit.body(145, 128)
	assert_int(PhysicsKit.walk(w, b, 9 * U)).is_equal(5 * U)


func test_horizontal_duck_under_a_ceiling_corner() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		[".....###", ".....###", "........", "........", "########"]
	)
	var ok: Body = PhysicsKit.body(145, 102)
	assert_int(w.move_x(ok, 9 * U, 0, 6 * U)).is_equal(9 * U)
	assert_int(ok.top()).is_equal(64 * U)
	var too_deep: Body = PhysicsKit.body(145, 101)
	assert_int(w.move_x(too_deep, 9 * U, 0, 6 * U)).is_equal(5 * U)


func test_vertical_corner_correction_both_sides() -> void:
	var w: CollisionWorld = PhysicsKit.world(
		["........", "...#....", "........", "........", "########"]
	)
	var left_side: Body = PhysicsKit.body(92, 114)
	assert_int(w.move_y(left_side, -10 * U, 6 * U)).is_equal(-10 * U)
	assert_int(left_side.x).is_equal(86 * U)
	assert_int(left_side.nudge_x).is_equal(-6 * U)
	assert_bool(left_side.hit_ceiling).is_false()
	var right_side: Body = PhysicsKit.body(132, 114)
	w.move_y(right_side, -10 * U, 6 * U)
	assert_int(right_side.x).is_equal(138 * U)
	var centred: Body = PhysicsKit.body(93, 114)
	assert_int(w.move_y(centred, -10 * U, 6 * U)).is_equal(-6 * U)
	assert_bool(centred.hit_ceiling).is_true()
	assert_int(centred.top()).is_equal(64 * U)
	assert_int(centred.x).is_equal(93 * U)


func test_corner_correction_never_pushes_into_a_wall() -> void:
	# A ceiling overlaps the right 6 units of the box, but the wall on the left leaves no room.
	var w: CollisionWorld = PhysicsKit.world(
		["........", "........", ".#......", ".#......", "########"]
	)
	w.solids.append(SolidBox.make(78 * U, 40 * U, 120 * U, 64 * U))
	var b: Body = PhysicsKit.body(74, 114)
	assert_int(w.move_y(b, -10 * U, 6 * U)).is_equal(-6 * U)
	assert_bool(b.hit_ceiling).is_true()
	assert_int(b.nudge_x).is_equal(0)
	assert_int(b.x).is_equal(74 * U)


func _open_air() -> CollisionWorld:
	return PhysicsKit.world(["........", "........", "........", "........", "########"])


func test_a_lift_that_could_not_carry_on_is_not_taken() -> void:
	# A 6 u step whose top has a solid right above it: lifted, the box would meet the solid at
	# once, so the lift is refused and the box stops at the step's face.
	var w: CollisionWorld = _open_air()
	w.solids.append(SolidBox.make(160 * U, 90 * U, 200 * U, 128 * U))
	w.solids.append(SolidBox.make(160 * U, 0, 200 * U, 50 * U))
	var b: Body = PhysicsKit.body(150, 96)
	assert_int(w.move_x(b, 9 * U, 8 * U, 6 * U)).is_equal(0)
	assert_int(b.y).is_equal(96 * U)
	assert_int(b.nudge_y).is_equal(0)
	assert_int(b.hit_wall).is_equal(1)


func test_a_duck_that_could_not_carry_on_is_not_taken() -> void:
	# A ceiling corner overlapping the top 4 u, but a low solid ahead at the lowered height.
	var w: CollisionWorld = _open_air()
	w.solids.append(SolidBox.make(160 * U, 0, 200 * U, 56 * U))
	w.solids.append(SolidBox.make(160 * U, 98 * U, 200 * U, 128 * U))
	var b: Body = PhysicsKit.body(150, 96)
	assert_int(w.move_x(b, 9 * U, 8 * U, 6 * U)).is_equal(0)
	assert_int(b.y).is_equal(96 * U)
	assert_int(b.nudge_y).is_equal(0)
	assert_int(b.hit_wall).is_equal(1)


func test_a_duck_that_meets_a_wall_further_on_stops_there() -> void:
	var w: CollisionWorld = _open_air()
	w.solids.append(SolidBox.make(160 * U, 0, 200 * U, 56 * U))
	w.solids.append(SolidBox.make(166 * U, 56 * U, 180 * U, 128 * U))
	var b: Body = PhysicsKit.body(150, 96)
	assert_int(w.move_x(b, 9 * U, 8 * U, 6 * U)).is_equal(6 * U)
	assert_int(b.y).is_equal(100 * U)
	assert_int(b.nudge_y).is_equal(4 * U)
	assert_int(b.hit_wall).is_equal(1)
	assert_bool(PhysicsKit.embedded(w, b)).is_false()


func test_a_ceiling_slide_never_passes_through_a_wall_beside_the_box() -> void:
	# A ceiling corner over the box's left 4 u would slide it right, but a ledge stands flush
	# against its right side: the strip it would slide through is not free, so the head bumps.
	var w: CollisionWorld = _open_air()
	w.solids.append(SolidBox.make(60 * U, 0, 94 * U, 100 * U))
	w.solids.append(SolidBox.make(110 * U, 130 * U, 140 * U, 200 * U))
	var b: Body = PhysicsKit.body(100, 150)
	w.move_y(b, -17 * U, 6 * U)
	assert_int(b.nudge_x).is_equal(0)
	assert_int(b.x).is_equal(100 * U)
	assert_int(b.y).is_equal(144 * U)
	assert_bool(b.hit_ceiling).is_true()


func test_a_ceiling_slide_never_leaves_the_feet_inside_a_slope() -> void:
	# On a 1:2 slope the box slides 6 u uphill round a corner over its right side but can only
	# rise 2 u there: its feet would end a unit inside the slope, so the slide is refused.
	var w: CollisionWorld = PhysicsKit.world(
		["..........", "..........", "..........", "...#cd....", "##########"]
	)
	var b: Body = PhysicsKit.body(150, 0)
	b.y = TileGrid.slope_surface(TileGrid.SLOPE_L_HI, 4, 3, b.x)
	assert_int(b.y).is_equal(107 * U)
	w.solids.append(SolidBox.make(154 * U, 0, 200 * U, 62 * U))
	w.solids.append(SolidBox.make(100 * U, 0, 150 * U, 61 * U))
	w.move_y(b, -17 * U, 6 * U)
	assert_int(b.nudge_x).is_equal(0)
	assert_int(b.y).is_equal(106 * U)
	assert_bool(b.hit_ceiling).is_true()


func test_a_ceiling_slide_never_puts_the_upper_body_into_a_slope() -> void:
	# The same on a 45-degree slope: sliding 6 u uphill while rising only 2 u would put the box's
	# side into the slope above its foot zone, so the slide is refused.
	var w: CollisionWorld = PhysicsKit.world(
		["..........", "..........", "..........", "...#\\.....", "##########"]
	)
	var b: Body = PhysicsKit.body(150, 0)
	b.y = TileGrid.slope_surface(TileGrid.SLOPE_L, 4, 3, b.x)
	assert_int(b.y).is_equal(118 * U)
	w.solids.append(SolidBox.make(154 * U, 0, 200 * U, 73 * U))
	w.solids.append(SolidBox.make(100 * U, 0, 150 * U, 72 * U))
	w.move_y(b, -17 * U, 6 * U)
	assert_int(b.nudge_x).is_equal(0)
	assert_int(b.y).is_equal(117 * U)
	assert_bool(b.hit_ceiling).is_true()
