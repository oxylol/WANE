extends GdUnitTestSuite
## Regression tests for the first independent review of the physics sweep (docs/adr/0008), one per
## finding that valid geometry can still produce, plus BUILD.md section 5 rows it found untested.

const U: int = PhysicsKit.U


func test_landing_on_a_crest_rests_on_the_slope_and_walks_down_grounded() -> void:
	# Finding 1: the plateau's edge used to hold the box 9.75 u above the slope under its centre,
	# and walking down then flew off the ramp. Gravity 3000 u/s^2 as for the player.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "...../##", "########"])
	var b: Body = PhysicsKit.body(186, 20)
	w.move_y(b, 100 * U)
	assert_bool(b.on_ground).is_true()
	assert_bool(b.on_slope).is_true()
	# The slope under x = 186 is at 64 + 32 - 26 = 70.
	assert_int(b.y).is_equal(70 * U)
	for tick: int in range(12):
		PhysicsKit.walk(w, b, -9 * U)
		assert_bool(b.on_ground).override_failure_message("tick %d" % tick).is_true()
		assert_bool(PhysicsKit.embedded(w, b)).is_false()
	assert_int(b.y).is_equal(96 * U)


func test_dashing_into_a_ramp_foot_from_a_ledge_side_never_embeds() -> void:
	# Finding 3, case E: a corner lift beside a ramp used to leave the foot point 8 u inside it.
	var w: CollisionWorld = PhysicsKit.world(["......", ".#\\...", ".##...", "......", "######"])
	var b: Body = PhysicsKit.body(108, 70)
	w.move_x(b, -20 * U, 8 * U, 6 * U)
	assert_bool(PhysicsKit.embedded(w, b)).is_false()
	w.move_y(b, U)
	for _i: int in range(4):
		PhysicsKit.walk(w, b, -4 * U)
		assert_bool(PhysicsKit.embedded(w, b)).is_false()


func test_ducking_never_drops_the_box_below_a_one_way_it_was_above() -> void:
	# Finding 3, case R: the duck under a ceiling corner used to carry the box from 2 u above a
	# one-way top to 2 u below it, and the next fall went through. Now the duck is refused.
	var w: CollisionWorld = PhysicsKit.world(
		["........", "........", "....====", "........", "########"]
	)
	w.solids.append(SolidBox.make(125 * U, 0, 300 * U, 22 * U))
	var b: Body = PhysicsKit.body(115, 62)
	w.move_x(b, 20 * U, 8 * U, 6 * U)
	assert_int(b.y).is_equal(62 * U)
	assert_int(b.x).is_equal(115 * U)
	assert_int(b.hit_wall).is_equal(1)
	assert_int(b.nudge_y).is_equal(0)
	# Without the one-way in the way the same duck is taken.
	var open: CollisionWorld = PhysicsKit.world(
		["........", "........", "........", "........", "########"]
	)
	open.solids.append(SolidBox.make(125 * U, 0, 300 * U, 22 * U))
	var d: Body = PhysicsKit.body(115, 62)
	open.move_x(d, 20 * U, 8 * U, 6 * U)
	assert_int(d.x).is_equal(135 * U)
	assert_int(d.y).is_equal(66 * U)


func test_drop_through_only_when_one_ways_alone_hold_the_box() -> void:
	# Finding 4: dropping through beside a wall used to put the box inside the wall.
	var w: CollisionWorld = PhysicsKit.world(
		["........", "........", "..#==...", "..#.....", "########"]
	)
	var edge: Body = PhysicsKit.body(98, 64)
	w.refresh_ground(edge)
	assert_bool(edge.on_ground).is_true()
	assert_bool(w.can_drop_through(edge)).is_false()
	assert_bool(w.drop_through(edge)).is_false()
	assert_int(edge.y).is_equal(64 * U)
	var clear: Body = PhysicsKit.body(115, 64)
	w.refresh_ground(clear)
	assert_bool(w.drop_through(clear)).is_true()
	assert_bool(clear.on_ground).is_false()
	for _i: int in range(8):
		w.move_y(clear, 10 * U)
		assert_bool(PhysicsKit.embedded(w, clear)).is_false()
	assert_int(clear.y).is_equal(128 * U)


func test_a_corner_lift_landing_is_grounded_at_once() -> void:
	# Finding 5: a lift onto a ledge used to read as airborne until the next vertical move, so a
	# buffered jump fired a tick late (BUILD.md: "Landing: 0 f of lag").
	var w: CollisionWorld = PhysicsKit.world(["......", "......", "...###", "...###", "######"])
	var b: Body = PhysicsKit.body(80, 70)
	w.move_x(b, 9 * U, 8 * U, 6 * U)
	assert_int(b.y).is_equal(64 * U)
	assert_bool(b.on_ground).is_true()


func test_a_grounded_box_is_never_corner_corrected() -> void:
	var w: CollisionWorld = PhysicsKit.world(["......", "......", "......", "######"])
	w.solids.append(SolidBox.make(112 * U, 90 * U, 200 * U, 122 * U))
	var b: Body = PhysicsKit.body(100, 96)
	w.refresh_ground(b)
	w.move_x(b, 9 * U, 8 * U, 6 * U)
	assert_int(b.y).is_equal(96 * U)
	assert_int(b.x).is_equal(102 * U)


func test_the_foot_zone_scales_with_the_body() -> void:
	# Finding 6: a wider body's corner sinks deeper into a 45-degree slope; a world-wide 10 u
	# foot zone stopped a 40-wide body below the crest.
	var w: CollisionWorld = PhysicsKit.world(
		["..........", "..........", "...../####", "##########"]
	)
	var big := Body.make(150 * U, 96 * U, 20 * U, 40 * U)
	w.refresh_ground(big)
	for _i: int in range(24):
		w.walk(big, 4 * U)
	assert_int(big.x).is_equal(246 * U)
	assert_int(big.y).is_equal(64 * U)
	assert_bool(PhysicsKit.embedded(w, big)).is_false()


func test_walking_down_a_slope_onto_a_solid_box_steps_onto_its_top() -> void:
	# Finding 7: the descending step never checked the upper body, and the box walked into the
	# solid along the floor. The box now meets the solid's top (at x = 112 the slope is at 80, the
	# solid's top) and carries on along it.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", "..#\\....", "########"])
	w.solids.append(SolidBox.make(120 * U, 80 * U, 200 * U, 120 * U))
	var b: Body = PhysicsKit.body(100, 68)
	w.refresh_ground(b)
	for _i: int in range(8):
		PhysicsKit.walk(w, b, 4 * U)
		assert_bool(PhysicsKit.embedded(w, b)).is_false()
		assert_bool(b.on_ground).is_true()
	assert_int(b.x).is_equal(132 * U)
	assert_int(b.y).is_equal(80 * U)


func test_walking_downhill_into_a_wall_stops_the_whole_box() -> void:
	# A slope running down into a wall face: the box stops when its side meets the face, its
	# foot zone kept out (the foot zone may only rest in the crest a slope leads up to).
	var w: CollisionWorld = PhysicsKit.world(["....", "....", "#\\#.", "####"])
	var b: Body = PhysicsKit.body(42, 74)
	w.refresh_ground(b)
	assert_bool(b.on_slope).is_true()
	for _i: int in range(4):
		PhysicsKit.walk(w, b, 5 * U)
	assert_int(b.right()).is_equal(64 * U)
	assert_int(b.hit_wall).is_equal(1)
	assert_bool(PhysicsKit.embedded(w, b)).is_false()
	# Nothing of the box, foot zone included, is in the wall it walked into.
	assert_bool(w.point_solid(b.right() - 1, b.y - 1)).is_false()


func test_slopes_at_dash_and_terminal_speed_stay_exact() -> void:
	# BUILD.md s5: slopes up to 45 degrees at unchanged speed, here at 20 u/f (dash) and 25 u/f
	# (terminal velocity) both ways over a ramp, a crest and back down.
	var w: CollisionWorld = PhysicsKit.world(
		["..............", "..............", "....../###\\...", "##############"]
	)
	for speed: int in [20, 25]:
		var b: Body = PhysicsKit.body(40, 96)
		w.refresh_ground(b)
		var path: Array[int] = []
		for _i: int in range(14):
			assert_int(PhysicsKit.walk(w, b, speed * U)).is_equal(speed * U)
			assert_bool(b.on_ground).is_true()
			path.append(b.y)
		for i: int in range(14):
			assert_int(b.y).is_equal(path[13 - i])
			PhysicsKit.walk(w, b, -speed * U)
		assert_int(b.x).is_equal(40 * U)
		assert_int(b.y).is_equal(96 * U)


func test_no_sliding_on_a_slope_under_gravity() -> void:
	var w: CollisionWorld = PhysicsKit.world(["......", "......", "../###", "######"])
	var b: Body = PhysicsKit.body(80, 80)
	w.refresh_ground(b)
	assert_bool(b.on_slope).is_true()
	for _i: int in range(120):
		w.walk(b, 0)
		w.move_y(b, 8 * U)
	assert_int(b.x).is_equal(80 * U)
	assert_int(b.y).is_equal(80 * U)


func test_ledge_grab_while_sliding_down_a_wall() -> void:
	# The wall-cling slide is 3 u/f; each tick the player presses a unit into the wall with a 10 u
	# lift (core/fsm/player.gd moves Fx.SUB toward the wall). Feet within 10 u of the top are
	# lifted onto it; 11 u below are not.
	var w: CollisionWorld = PhysicsKit.world(["........", "........", ".....###", "########"])
	var near: Body = PhysicsKit.body(150, 74)
	w.move_x(near, U, 10 * U)
	assert_int(near.y).is_equal(64 * U)
	assert_bool(near.on_ground).is_true()
	var far: Body = PhysicsKit.body(150, 75)
	w.move_x(far, U, 10 * U)
	assert_int(far.y).is_equal(75 * U)
	assert_int(far.x).is_equal(150 * U)
	assert_int(far.hit_wall).is_equal(1)


func test_flying_into_a_ramp_rides_up_it_and_a_low_ceiling_stops_it_instead() -> void:
	var w: CollisionWorld = PhysicsKit.world(["........", "........", ".../####", "########"])
	var b: Body = PhysicsKit.body(80, 96)
	w.move_x(b, 20 * U)
	# x = 100 is 4 u into the slope tile: its surface there is 96 - 4 = 92.
	assert_int(b.x).is_equal(100 * U)
	assert_int(b.y).is_equal(92 * U)
	assert_bool(b.on_ground).is_true()
	assert_int(b.nudge_y).is_equal(0)
	# With a solid 2 u over the head it rides up only those 2 u, as walking up the ramp would,
	# and stops there (physics review round 3: it used to stop where its foot met the slope).
	var capped: CollisionWorld = PhysicsKit.world(["........", "........", ".../####", "########"])
	capped.solids.append(SolidBox.make(60 * U, 20 * U, 200 * U, 50 * U))
	var c: Body = PhysicsKit.body(80, 96)
	capped.move_x(c, 20 * U)
	assert_int(c.x).is_equal(98 * U)
	assert_int(c.y).is_equal(94 * U)
	assert_int(c.top()).is_equal(50 * U)
	var walker: Body = PhysicsKit.body(80, 96)
	capped.refresh_ground(walker)
	PhysicsKit.walk(capped, walker, 20 * U)
	assert_int(walker.x).is_equal(c.x)
	assert_int(c.hit_wall).is_equal(1)
	assert_bool(PhysicsKit.embedded(capped, c)).is_false()
