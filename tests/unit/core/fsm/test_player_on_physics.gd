extends GdUnitTestSuite
## The physics reviews' findings traced through the real player ([Simulation] in the test rooms
## under tests/replay/rooms/): the second physics review's findings 1 and 2, the fifth's H2 and
## the first task 3 review's M8. Their collision-only regressions are in
## tests/unit/core/physics/test_physics_review_round2.gd and test_physics_fuzz_lift.gd.

const U: int = PhysicsKit.U
const LEFT: int = -InputFrame.STICK_MAX
const RIGHT: int = InputFrame.STICK_MAX


func _sim(room: String, x_u: int, y_u: int) -> Simulation:
	var s := Scenario.make(1, room)
	s.spawn_x = x_u
	s.spawn_y = y_u
	var sim := Simulation.new(s)
	assert_array(Array(sim.load_errors)).is_empty()
	return sim


func _hold(sim: Simulation, stick_x: int) -> void:
	sim.step(InputFrame.make(0, 0, stick_x, 0))


func test_player_walks_back_down_a_ramp_from_a_closed_door() -> void:
	# Finding 1: on a slope every solid box in the room went through the swept test, and one the
	# box was moving away from (behind it, above its head, below its feet) blocked it. The player
	# walked up the test/slopes ramp into a door and could not walk back down.
	var sim: Simulation = _sim("test/slopes", 290, 544)
	var door := SolidBox.make(340 * U, 400 * U, 348 * U, 520 * U)
	sim.world.solids.append(door)
	var b: Body = sim.player.body
	for _i: int in range(30):
		_hold(sim, RIGHT)
	var stop_x: int = b.x
	assert_int(b.right()).is_equal(340 * U)
	assert_bool(b.on_slope).is_true()
	for _i: int in range(20):
		_hold(sim, LEFT)
		assert_bool(b.on_ground).is_true()
	assert_int(b.x).is_less(stop_x - 60 * U)
	assert_int(b.y).is_equal(544 * U)


func test_player_lands_beside_a_crest_on_the_ramp_and_runs_down_it() -> void:
	# Finding 2: a box landing under per-tick gravity rested on the plateau's edge, 6 u above the
	# ramp under its centre, and running down the ramp then flew off it for 9 frames.
	var sim: Simulation = _sim("test/slopes", 346, 500)
	var b: Body = sim.player.body
	var landed: int = -1
	for i: int in range(20):
		_hold(sim, 0)
		if landed < 0 and b.on_ground:
			landed = i
	assert_int(landed).is_greater_equal(0)
	# The ramp (column 10, x 320..352, rising to 512 at its right edge) is at 544 - 26 there.
	assert_bool(b.on_slope).is_true()
	assert_int(b.y).is_equal(518 * U)
	for i: int in range(20):
		_hold(sim, LEFT)
		assert_bool(b.on_ground).override_failure_message("frame %d" % i).is_true()
	assert_int(b.y).is_equal(544 * U)


func test_a_crouched_player_hops_freely_in_a_low_gap() -> void:
	# Task 3 review M8 through the real player in the review's room (tests/replay/physics/ has the
	# fixture): crouch-dash into the 32 u gap, then hop.
	var sim: Simulation = _sim("test/longgap", 600, 544)
	var pb: Body = sim.player.body
	for i: int in range(28):
		var stick_y: int = InputFrame.STICK_MAX if i < 4 else 0
		var bits: int = InputFrame.DASH if i == 3 else (InputFrame.JUMP if i == 16 else 0)
		var stick_x: int = RIGHT if i >= 4 else 0
		sim.step(InputFrame.make(bits, bits, stick_x, stick_y))
		if i >= 16:
			assert_int(pb.hit_wall).override_failure_message("frame %d" % i).is_equal(0)


func test_a_diagonal_dash_down_lands_wherever_its_straight_path_stands_on_a_ledge() -> void:
	# Physics review 5, H2: the diagonal air dash moved across, then down, and passed through a
	# ledge's far corner where a fall with the same path lands (BUILD.md s15: "Landing on a
	# 1-pixel ledge edge lands"). Dashes down-right from anywhere near test/ledge448's right edge
	# (x 608, top y 448): wherever the dash's straight path stands on the ledge with at least a
	# sixteenth of a unit of the box over it, the dash touches down.
	var sim: Simulation = _sim("test/ledge448", 100, 448)
	var w: CollisionWorld = sim.world
	var pl: Player = sim.player
	var d: int = Fx.permille(pl.p.dash_speed, Fx.DIAGONAL_PERMILLE)
	var top: int = 448 * U
	var rng: Rng = Rng.seeded(59, 11)
	var checked: int = 0
	for trial: int in range(1500):
		var x: int = 608 * U + rng.between(-12 * U, 16 * U)
		var y: int = top - rng.between(1, 14 * U)
		if not _path_stands(w, x, y, d, d, top):
			continue
		checked += 1
		pl.spawn(x, y)
		pl.air_dashes_left = 1
		var bits: int = InputFrame.DASH
		sim.step(InputFrame.make(bits, bits, RIGHT, InputFrame.STICK_MAX))
		assert_bool(sim.events.has(SimEvents.DASH)).is_true()
		if not sim.events.has(SimEvents.LAND):
			fail("trial %d: the dash from (%d, %d) passed the ledge's corner" % [trial, x, y])
			return
	assert_int(checked).is_greater(200)


## True if a box at ([param x], [param y]) moving straight by ([param dx], [param dy]) reaches the
## ledge top [param top] standing on it there, with at least a sixteenth of a unit of it over the
## ledge, and is clear where it starts and there.
func _path_stands(w: CollisionWorld, x: int, y: int, dx: int, dy: int, top: int) -> bool:
	var hw: int = PhysicsKit.HALF_W
	var h: int = PhysicsKit.STAND
	if top < y or top > y + dy or not w.body_fits(x, y, hw, h):
		return false
	var at: int = x + signi(dx) * Fx.div_floor(absi(dx) * (top - y), dy)
	if not w.body_fits(at, top, hw, h):
		return false
	for inset: int in [0, U / 16, -U / 16]:
		var probe: Body = Body.make(at + inset, top, hw, h)
		w.refresh_ground(probe)
		if not probe.on_ground:
			return false
	return true
