extends GdUnitTestSuite
## The stress room and its scripted run (tests/perf/; docs/adr/0020; BUILD.md section 13, "a stress
## room (200 enemies, 40 procs, Pitch lighting)"): the room loads clean with 200 dummies placed in
## free air over its ground, most of them walking, some swinging white and red, over flats, both
## kinds of ramp, one-way platforms and solid boxes; the run is long enough and uses every verb.

const ROOM_ID: String = "perf/stress"
const RUN: String = "res://tests/perf/stress_run.fixture"


func test_the_room_loads_clean_and_holds_the_crowd() -> void:
	var room: RoomData = RoomData.load_id(ROOM_ID)
	assert_array(Array(room.errors)).is_empty()
	var walkers: int = 0
	var fallers: int = 0
	var white: int = 0
	var red: int = 0
	var dummies: int = 0
	for e: RoomData.RoomEntity in room.entities:
		if e.kind != "dummy":
			continue
		dummies += 1
		walkers += 1 if e.prop_int("patrol") != 0 else 0
		fallers += 1 if e.prop_int("fall") != 0 else 0
		if e.prop_int("attack") != 0:
			if e.prop_int("red") != 0:
				red += 1
			else:
				white += 1
	assert_int(dummies).is_equal(200)
	assert_int(walkers).is_equal(151)
	assert_int(fallers).is_greater(10)
	assert_int(white).is_greater(20)
	assert_int(red).is_greater(10)


func test_the_ground_has_every_kind_the_sweep_has_to_handle() -> void:
	var room: RoomData = RoomData.load_id(ROOM_ID)
	var kinds: Dictionary[int, int] = {}
	for j: int in range(room.grid.height):
		for i: int in range(room.grid.width):
			var t: int = room.grid.get_tile(i, j)
			kinds[t] = kinds.get(t, 0) + 1
	for t: int in [
		TileGrid.SOLID,
		TileGrid.ONE_WAY,
		TileGrid.SLOPE_R,
		TileGrid.SLOPE_L,
		TileGrid.SLOPE_R_LO,
		TileGrid.SLOPE_R_HI,
		TileGrid.SLOPE_L_HI,
		TileGrid.SLOPE_L_LO
	]:
		assert_bool(kinds.has(t)).is_true()
	assert_int(room.solids.size()).is_greater(10)


func test_every_dummy_starts_in_free_air_and_the_run_loads() -> void:
	var fx: Fixture = Fixture.parse_file(RUN)
	assert_array(Array(fx.errors)).is_empty()
	var sim := Simulation.new(fx.scenario)
	assert_array(Array(sim.load_errors)).is_empty()
	assert_int(sim.combat.enemies.size()).is_equal(200)
	for e: Enemy in sim.combat.enemies:
		assert_bool(sim.world.point_solid(e.body.x, e.body.y - 1)).is_false()
		assert_bool(sim.world.point_solid(e.body.x, e.body.y - e.body.height + 1)).is_false()
	# The three stress Votives are stacked: a Taper hit raises 40 events and fires 39 procs.
	assert_int(sim.procs.votives.size()).is_equal(3)


func test_the_run_is_long_enough_and_uses_every_verb() -> void:
	var fx: Fixture = Fixture.parse_file(RUN)
	assert_int(fx.frame_total).is_greater_equal(3600)
	var pressed: int = 0
	for i: int in range(fx.frame_total):
		pressed |= fx.held[i]
	for button: int in [InputFrame.JUMP, InputFrame.ATTACK, InputFrame.DASH, InputFrame.SPELL]:
		assert_int(pressed & button).is_not_equal(0)
	var downs: int = 0
	for i: int in range(fx.frame_total):
		downs += 1 if fx.stick_y[i] > 0 else 0
	assert_int(downs).is_greater(0)
	var lefts: int = 0
	var rights: int = 0
	for i: int in range(fx.frame_total):
		lefts += 1 if fx.stick_x[i] < 0 else 0
		rights += 1 if fx.stick_x[i] > 0 else 0
	assert_int(lefts).is_greater(1000)
	assert_int(rights).is_greater(1000)


func test_the_pin_is_the_runs_first_ticks() -> void:
	var run: Fixture = Fixture.parse_file(RUN)
	var pin: Fixture = Fixture.parse_file("res://tests/replay/perf/stress_pin.fixture")
	assert_int(pin.frame_total).is_less(run.frame_total)
	for i: int in range(pin.frame_total):
		assert_int(pin.held[i]).is_equal(run.held[i])
		assert_int(pin.taps[i]).is_equal(run.taps[i])
		assert_int(pin.stick_x[i]).is_equal(run.stick_x[i])
		assert_int(pin.stick_y[i]).is_equal(run.stick_y[i])
	assert_str(pin.scenario.room).is_equal(run.scenario.room)
