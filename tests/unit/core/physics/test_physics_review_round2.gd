extends GdUnitTestSuite
## Regression tests for the second independent review of the physics sweep (docs/adr/0008), one
## per finding, plus the task 3 review's M8. The real-player traces of findings 1 and 2 and of M8
## are in tests/unit/core/fsm/test_player_on_physics.gd.

const U: int = PhysicsKit.U


func test_solid_boxes_behind_above_or_below_never_block_a_slope_walk() -> void:
	# Finding 1 in the sweep itself, on a 45-degree and a 1:2 ramp: a solid beside the box
	# (touching after the step, or 20 u away), slabs 2 to 50 u over its head, and a solid buried
	# in the ramp under its feet. The box stands at x = 118 (feet at 106 on the 45-degree ramp,
	# 117 on the 1:2 one) and steps 4 u each way; none of them is in the way.
	for row: String in [".../######", "...ab#####"]:
		var shallow: bool = row.begins_with("...a")
		# Left, top, right, bottom in units, then 1 to walk only downhill (left) or 2 for both
		# ways: a slab 2 u over the head on the 45-degree ramp is legitimately in the way uphill.
		var head: int = 73 if shallow else 62
		var cases: Array[PackedInt32Array] = [
			PackedInt32Array([132, 30, 142, 110, 2]),
			PackedInt32Array([152, 30, 162, 110, 2]),
			PackedInt32Array([50, 0, 300, head - 2, 2 if shallow else 1]),
			PackedInt32Array([50, 0, 300, head - 10, 2]),
			PackedInt32Array([50, 0, 300, head - 50, 2]),
			PackedInt32Array([112, 124, 124, 128, 2]),
		]
		for case: PackedInt32Array in cases:
			for dir: int in [-1] if case[4] == 1 else [-1, 1]:
				var w: CollisionWorld = PhysicsKit.world(
					["..........", "..........", "..........", row, "##########"]
				)
				var b: Body = PhysicsKit.body(118, 10)
				w.move_y(b, 200 * U)
				assert_int(b.top()).is_equal(head * U)
				w.solids.append(SolidBox.make(case[0] * U, case[1] * U, case[2] * U, case[3] * U))
				assert_bool(PhysicsKit.embedded(w, b)).is_false()
				var moved: int = PhysicsKit.walk(w, b, dir * 4 * U)
				(
					assert_int(moved)
					. override_failure_message("%s dir %d solid %s" % [row, dir, str(case)])
					. is_equal(dir * 4 * U)
				)
				assert_bool(b.on_ground).is_true()
				assert_bool(PhysicsKit.embedded(w, b)).is_false()


func test_jumping_off_a_slope_slides_round_a_ceiling_corner() -> void:
	# Finding 5: the slide was vetted with body_fits, which refuses any overlap of the foot zone,
	# and a box standing on a slope has its uphill corner in the ground. The jump bumped and died.
	var w: CollisionWorld = PhysicsKit.world(
		["......", "......", "..##..", "......", "#\\....", "######"]
	)
	for overlap: int in [4, 6]:
		var b: Body = PhysicsKit.body(54 + overlap, 0)
		b.y = TileGrid.slope_surface(TileGrid.SLOPE_L, 1, 4, b.x)
		w.refresh_ground(b)
		assert_bool(b.on_slope).is_true()
		b.clear_contacts()
		w.move_y(b, -17 * U, 6 * U)
		assert_int(b.nudge_x).is_equal(-overlap * U)
		assert_bool(b.hit_ceiling).is_false()
		assert_bool(PhysicsKit.embedded(w, b)).is_false()


func test_drop_through_beside_a_ramps_low_side() -> void:
	# Finding 6: a slope tile under the box's width counted as a support even where its surface is
	# below the box's feet.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "..===/##", "########"])
	for x_u: int in [140, 152]:
		var b: Body = PhysicsKit.body(x_u, 64)
		w.refresh_ground(b)
		assert_bool(w.can_drop_through(b)).is_true()
		assert_bool(w.drop_through(b)).is_true()
		PhysicsKit.fall(w, b)
		assert_bool(PhysicsKit.embedded(w, b)).is_false()
		assert_int(b.y).is_equal(96 * U)


func test_walking_along_a_solid_top_steps_onto_the_slope_rising_out_of_it() -> void:
	# Finding 3: walking flat on a solid box's top inside a slope's column went into the slope.
	# Where the slope rises to the walking height the box walks up it instead.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "..#\\....", "########"])
	w.solids.append(SolidBox.make(96 * U, 86 * U, 200 * U, 120 * U))
	var b: Body = PhysicsKit.body(120, 86)
	w.refresh_ground(b)
	assert_bool(b.on_ground).is_true()
	assert_bool(b.on_slope).is_false()
	for _i: int in range(6):
		assert_int(PhysicsKit.walk(w, b, -6 * U)).is_equal(-6 * U)
		assert_bool(b.on_ground).is_true()
		assert_bool(PhysicsKit.embedded(w, b)).is_false()
	# 86 is the slope's height at x = 118; from there it climbs 1 u per unit to the crest at 64.
	assert_int(b.x).is_equal(84 * U)
	assert_int(b.y).is_equal(64 * U)
	assert_bool(b.on_ground).is_true()
	# And back: down the slope, onto the solid's top, along it.
	for _i: int in range(6):
		assert_int(PhysicsKit.walk(w, b, 6 * U)).is_equal(6 * U)
		assert_bool(PhysicsKit.embedded(w, b)).is_false()
	assert_int(b.x).is_equal(120 * U)
	assert_int(b.y).is_equal(86 * U)


func test_flying_into_a_crest_passes_it_and_comes_down_on_the_slope() -> void:
	# Finding 2 through the corner lift: lifted onto the plateau while its centre was still over
	# the ramp, the box hovered 8 u above it and running down the ramp flew off. Since round 3 the
	# crest only stops the upper body, so the box needs no lift: its corner passes into the crest,
	# and the fall that follows lands it on the ramp, which it then runs down.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "...../##", "########"])
	var b: Body = PhysicsKit.body(175, 70)
	w.move_x(b, 9 * U, 8 * U, 6 * U)
	assert_int(b.x).is_equal(184 * U)
	assert_int(b.y).is_equal(70 * U)
	assert_int(b.nudge_y).is_equal(0)
	assert_int(b.hit_wall).is_equal(0)
	assert_bool(b.on_ground).is_false()
	# The ramp under x = 184 is at 96 - 24.
	PhysicsKit.fall(w, b)
	assert_int(b.y).is_equal(72 * U)
	assert_bool(b.on_slope).is_true()
	assert_bool(PhysicsKit.hovering(w, b)).is_false()
	for _i: int in range(10):
		PhysicsKit.walk(w, b, -9 * U)
		assert_bool(b.on_ground).is_true()


func test_drops_at_every_unit_across_crests_never_hover() -> void:
	# Finding 2: under per-tick gravity a fall step often reached the plateau's edge but not the
	# slope below it. Every crest kind, dropped from 4 to 60 u above the plateau.
	for crest: String in ["....../###", "###\\......", ".....ab###", "###cd....."]:
		var rows: Array[String] = ["..........", "..........", crest, "##########"]
		var w: CollisionWorld = PhysicsKit.world(rows)
		for x_u: int in range(40, 290, 3):
			for h: int in [4, 13, 30, 60]:
				var b: Body = PhysicsKit.body(x_u, 64 - h)
				if not w.body_fits(b.x, b.y, b.half_w, b.height):
					continue
				PhysicsKit.fall(w, b)
				(
					assert_bool(PhysicsKit.hovering(w, b))
					. override_failure_message(
						"%s drop at x=%d from %d hovers at y=%d" % [rows[2], x_u, 64 - h, b.y]
					)
					. is_false()
				)


func test_a_crouched_box_hopping_under_a_low_ceiling_moves_freely() -> void:
	# Task 3 review M8: _foot_depth read the ceiling row above the foot point's row as a floor
	# the body had sunk into, so a 28 u box 4 u under a ceiling reported a wall in open space.
	var w: CollisionWorld = PhysicsKit.world(["############", "............", "############"])
	var b: Body = PhysicsKit.body(100, 60, PhysicsKit.CROUCH)
	assert_int(b.top()).is_equal(32 * U)
	for dir: int in [1, -1]:
		b.clear_contacts()
		assert_int(w.move_x(b, dir * 9 * U, 8 * U, 6 * U)).is_equal(dir * 9 * U)
		assert_int(b.hit_wall).is_equal(0)
		assert_int(b.y).is_equal(60 * U)
