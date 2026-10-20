extends GdUnitTestSuite
## Zone 1 room 3 (BUILD.md s5 tech 3, s15 "a 10-bounce chain across the zone 1 spike pit is
## possible at 4 bounces per second"; the director's play, 2026-10-20: "The low roof is way too
## difficult and the lineup is almost impossible"). The room has two routes and this holds each to
## the arithmetic its fixtures rest on, so a change to the room cannot quietly undo either.
##
## The MAIN ROUTE is an open pit of spikes (78 tiles, 2496 u) under a roof far above any bounce,
## crossed by a chain at the natural pace. Its width is the strongest route without a pogo that
## tools/replay/gap_reach.gd finds on test/longpit, plus a slack; the two control fixtures play
## those routes in the room itself.
##
## The OPTIONAL PATH is the old room's low tunnel, moved up (3008 u, ceiling 64 u over the spikes):
## a bounce every 15 frames (4 a second) at the dash-jump's 20 u/f carries 300 u, from a first
## bounce about 196 u inside the tunnel, so ten cross and nine do not. The numbers are read out of
## the fixtures' own expectations (bounce frames, vx, the first bounce's x), not copied, so a
## fixture and this test cannot drift apart. What the tunnel does not do: demand ten of every
## chain. A slow link buys distance, and the opening link is one a player slows with an ordinary
## air jump (nine 4-a-second bounces after a 25-frame opening link cross, 03_route_slow_opener).

const ROOM: String = "zone1/03_pogo_chain"
const TILE_U: int = 32
const FPS: int = 60
const BOUNCES: int = 10
## The tunnel (the optional path).
const SPIKE_ROW: int = 9
const CEILING_ROW: int = 6
const TUNNEL_FIRST_COL: int = 18
const TUNNEL_LAST_COL: int = 111
## The main pit.
const FLOOR_ROW: int = 21
const ROOF_ROW: int = 11
const PIT_FIRST_COL: int = 18
const PIT_COLS: int = 78
const DEEP_COLS: int = 8
const DEEP_ROW: int = 25
const SHALLOW_ROW: int = 23
const LIP_COLS: int = 4
const LIP_ROW: int = 22
## The farthest reach of the strongest route without a pogo (a ground dash-jump, the air jump, the
## air dash and the Ember Toss), tools/replay/gap_reach.gd on test/longpit: units past the near
## edge, at the floor's height.
const STRONGEST_REACH_U: int = 2432
const NEAR_EDGE_U: int = 576
const HALF_BODY_U: int = 10
## Where the ladder's platforms stand (tiles) and how far west of the pit's edge it must stay.
const LADDER_FIRST_COL: int = 5
const LADDER_LAST_COL: int = 7
const LADDER_ROWS: Array[int] = [12, 15, 18]
const LADDER_MIN_DISTANCE_U: int = 300
## The fixtures.
const ROUTE: String = "res://tests/replay/zone1/03_pogo_chain_route.fixture"
const NINE: String = "res://tests/replay/zone1/03_control_nine_bounces.fixture"
const SLOW_OPENER: String = "res://tests/replay/zone1/03_route_slow_opener.fixture"
const MAIN_ROUTE: String = "res://tests/replay/zone1/03_main_route.fixture"
const CONTROL_TOSS: String = "res://tests/replay/zone1/03_main_control_no_pogo_toss.fixture"
const CONTROL_PLAIN: String = "res://tests/replay/zone1/03_main_control_no_pogo.fixture"
const ROOM_FILE: String = "res://content/rooms/zone1/03_pogo_chain.room"
const ADR_FILE: String = "res://docs/adr/0019-zone1-grey-box-gates-and-teaches.md"
const MOVEMENT: String = "res://content/wicks/ash/movement.tres"


func _room() -> RoomData:
	var room: RoomData = RoomData.load_id(ROOM)
	assert_array(Array(room.errors)).is_empty()
	return room


func _tunnel_u(room: RoomData) -> int:
	var cols: int = 0
	for i: int in range(room.grid.width):
		if room.grid.get_tile(i, SPIKE_ROW) == TileGrid.SPIKES and i >= TUNNEL_FIRST_COL:
			cols += 1
	return cols * TILE_U


func _pit_u() -> int:
	return PIT_COLS * TILE_U


## Where the spikes of pit column [param i] (counted from the pit's first column) stand.
func _spike_row(i: int) -> int:
	if i >= PIT_COLS - LIP_COLS:
		return LIP_ROW
	if i < DEEP_COLS:
		return DEEP_ROW
	return SHALLOW_ROW


# -- The main route: an open pit -------------------------------------------------------------


func test_the_main_pit_is_spikes_under_open_air() -> void:
	var room: RoomData = _room()
	for i: int in range(PIT_COLS):
		var col: int = PIT_FIRST_COL + i
		var spikes: int = _spike_row(i)
		assert_int(room.grid.get_tile(col, spikes)).is_equal(TileGrid.SPIKES)
		# Open from the floor's height down to the spikes, and from the roof's underside down.
		for j: int in range(ROOF_ROW + 1, spikes):
			assert_int(room.grid.get_tile(col, j)).is_equal(TileGrid.EMPTY)
		assert_int(room.grid.get_tile(col, ROOF_ROW)).is_equal(TileGrid.SOLID)
	# The far wall is smooth (no cling, no kick) from the floor's height down.
	var east: int = PIT_FIRST_COL + PIT_COLS
	for j: int in range(FLOOR_ROW, FLOOR_ROW + 3):
		assert_int(room.grid.get_tile(east, j)).is_equal(TileGrid.SMOOTH)
	assert_int(room.grid.get_tile(east - 1, FLOOR_ROW)).is_equal(TileGrid.EMPTY)


func test_the_roof_is_far_above_any_bounce() -> void:
	# The pit that replaced the 64 u tunnel (the director: "way too difficult"): from the lowest
	# spikes' tops the roof's underside is more than twice the longest bounce, and a bounce with
	# its air jump fits under it with room.
	var tuning: Resource = load(MOVEMENT)
	var v: int = tuning.get("pogo_bounce_ups")
	var g: int = tuning.get("gravity_rise_ups2")
	var apex_u: int = v * v / (2 * g)
	assert_int(apex_u).is_equal(131)
	var underside_u: int = (ROOF_ROW + 1) * TILE_U
	var room: RoomData = _room()
	for i: int in range(PIT_COLS):
		var clearance_u: int = _spike_row(i) * TILE_U - underside_u
		assert_int(clearance_u).is_greater_equal(2 * apex_u + TILE_U)
	assert_int(room.grid.get_tile(PIT_FIRST_COL, ROOF_ROW + 1)).is_equal(TileGrid.EMPTY)


func test_the_pit_is_wider_than_the_strongest_route_without_a_pogo() -> void:
	# A crossing needs the centre within half a body of the far wall: reach more than width - 10.
	var crossing_u: int = _pit_u() - HALF_BODY_U
	assert_int(crossing_u).is_greater(STRONGEST_REACH_U)
	# Slack in units, held to the 54 u the controls were measured at.
	assert_int(crossing_u - STRONGEST_REACH_U).is_greater_equal(50)
	assert_int(_pit_u()).is_equal(PIT_COLS * TILE_U)


func _max_x_u(path: String, hazard_frames: Array[int]) -> int:
	var fx: Fixture = Fixture.parse_file(path)
	assert_array(Array(fx.errors)).is_empty()
	assert_str(fx.scenario.room).is_equal(ROOM)
	var sim := Simulation.new(fx.scenario)
	var best: int = 0
	for i: int in range(fx.frame_total):
		sim.step(fx.input_frame(i))
		if sim.events.has(SimEvents.HAZARD):
			hazard_frames.append(i)
			break
		best = maxi(best, Fx.div_floor(sim.player.body.x, Fx.SUB))
	return best


func test_the_strongest_controls_fall_short_in_the_room() -> void:
	var wall_u: int = (PIT_FIRST_COL + PIT_COLS) * TILE_U
	for path: String in [CONTROL_TOSS, CONTROL_PLAIN]:
		var hazards: Array[int] = []
		var best: int = _max_x_u(path, hazards)
		assert_int(hazards.size()).is_equal(1)
		# Never within half a body and a margin of the wall: not a near miss.
		assert_int(best).is_less(wall_u - HALF_BODY_U - 40)
	# The Toss route is the nearer miss, the one the width was sized against.
	var none: Array[int] = []
	var with_toss: int = _max_x_u(CONTROL_TOSS, none)
	var without: Array[int] = []
	assert_int(with_toss).is_greater(_max_x_u(CONTROL_PLAIN, without))


func test_the_main_chain_is_a_few_bounces_at_the_natural_pace() -> void:
	var fx: Fixture = Fixture.parse_file(MAIN_ROUTE)
	assert_array(Array(fx.errors)).is_empty()
	var sim := Simulation.new(fx.scenario)
	var ticks: Array[int] = []
	var xs: Array[int] = []
	for i: int in range(fx.frame_total):
		sim.step(fx.input_frame(i))
		if sim.events.has(SimEvents.POGO):
			ticks.append(i)
			xs.append(Fx.div_floor(sim.player.body.x, Fx.SUB))
	# The patch, then the pit's chain.
	var pit_ticks: Array[int] = []
	var pit_xs: Array[int] = []
	for i: int in range(ticks.size()):
		if xs[i] > NEAR_EDGE_U:
			pit_ticks.append(ticks[i])
			pit_xs.append(xs[i])
	assert_int(ticks.size() - pit_ticks.size()).is_equal(1)
	assert_int(pit_ticks.size()).is_between(6, 9)
	# The natural pace, not a gauntlet: 30 to 40 frames a bounce (1.5 to 2 a second).
	for i: int in range(1, pit_ticks.size()):
		assert_int(pit_ticks[i] - pit_ticks[i - 1]).is_between(30, 40)
	# The last bounce is on the lip, close enough to the far wall for the arc to clear it.
	var wall_u: int = (PIT_FIRST_COL + PIT_COLS) * TILE_U
	assert_int(wall_u - pit_xs[pit_xs.size() - 1]).is_between(40, 160)


func test_the_ladder_is_no_launch_pad_for_the_pit() -> void:
	var room: RoomData = _room()
	var reach_col: int = 0
	for j: int in range(room.grid.height):
		for i: int in range(PIT_FIRST_COL):
			if room.grid.get_tile(i, j) == TileGrid.ONE_WAY:
				reach_col = maxi(reach_col, i)
				assert_int(i).is_between(LADDER_FIRST_COL, LADDER_LAST_COL)
				assert_bool(LADDER_ROWS.has(j)).is_true()
	assert_int(reach_col).is_equal(LADDER_LAST_COL)
	assert_int(PIT_FIRST_COL * TILE_U - (reach_col + 1) * TILE_U).is_greater_equal(
		LADDER_MIN_DISTANCE_U
	)


func test_the_reward_is_a_lantern_votive_past_the_tunnel() -> void:
	var room: RoomData = _room()
	var votives: int = 0
	for e: RoomData.RoomEntity in room.entities:
		if e.kind == "votive":
			votives += 1
			assert_str(e.props["tier"]).is_equal("lantern")
			assert_int(e.x_u).is_greater((TUNNEL_LAST_COL + 1) * TILE_U)
			assert_int(e.y_u).is_equal((SPIKE_ROW + 1) * TILE_U)
	assert_int(votives).is_equal(1)


# -- The optional path: the tunnel -------------------------------------------------------------


func test_the_tunnel_is_a_floor_of_spikes_under_a_low_ceiling() -> void:
	var room: RoomData = _room()
	for i: int in range(TUNNEL_FIRST_COL, TUNNEL_LAST_COL + 1):
		assert_int(room.grid.get_tile(i, SPIKE_ROW)).is_equal(TileGrid.SPIKES)
		assert_int(room.grid.get_tile(i, CEILING_ROW)).is_equal(TileGrid.SOLID)
		for j: int in range(CEILING_ROW + 1, SPIKE_ROW):
			assert_int(room.grid.get_tile(i, j)).is_equal(TileGrid.EMPTY)
	# The hall past the tunnel keeps the low roof and its floor line is open: no spike, no wall in
	# the way of the last arc.
	assert_int(room.grid.get_tile(TUNNEL_LAST_COL + 1, SPIKE_ROW)).is_equal(TileGrid.EMPTY)
	assert_int(room.grid.get_tile(TUNNEL_LAST_COL + 1, CEILING_ROW)).is_equal(TileGrid.SOLID)


class Chain:
	var frames: Array[int] = []
	var vx_u: int = 0
	var first_x_u: int = -1


## One fixture's pogo expectations, read as data: the frame of each bounce, vx at it, and the x
## floor the first bounce is asserted past (in whole units).
func _chain(path: String) -> Chain:
	assert_bool(FileAccess.file_exists(path)).is_true()
	var fx: Fixture = Fixture.parse_file(path)
	assert_array(Array(fx.errors)).is_empty()
	assert_str(fx.scenario.room).is_equal(ROOM)
	var chain := Chain.new()
	for e: Fixture.Expectation in fx.expectations:
		if e.kind != "at":
			continue
		var is_bounce: bool = false
		for c: Fixture.Condition in e.conditions:
			if c.key == "event.pogo" and c.terms[0].literal_int == 1:
				is_bounce = true
		if not is_bounce:
			continue
		chain.frames.append(e.from.frame)
		for c: Fixture.Condition in e.conditions:
			if c.key == "vx":
				chain.vx_u = c.terms[0].literal_int / Fx.SUB
			if c.key == "x" and c.op == ">" and chain.first_x_u < 0:
				chain.first_x_u = c.terms[0].literal_int / Fx.SUB
	chain.frames.sort()
	return chain


func _link_frames(chain: Chain) -> int:
	var link: int = chain.frames[2] - chain.frames[1]
	for i: int in range(1, chain.frames.size()):
		assert_int(chain.frames[i] - chain.frames[i - 1]).is_equal(link)
	return link


## Where bounce n lands, in units inside the tunnel, from what the fixture asserts.
func _first_in_u(chain: Chain) -> int:
	assert_int(chain.first_x_u).is_greater(0)
	return chain.first_x_u - TUNNEL_FIRST_COL * TILE_U


func _arc_ends_after(chain: Chain, bounces: int) -> int:
	var link_u: int = _link_frames(chain) * chain.vx_u
	return _first_in_u(chain) + bounces * link_u


func test_the_route_is_ten_bounces_at_four_a_second_at_full_speed() -> void:
	var chain: Chain = _chain(ROUTE)
	assert_int(chain.frames.size()).is_equal(BOUNCES)
	assert_int(FPS / _link_frames(chain)).is_equal(4)
	# The dash-jump's 20 u/f, kept at every bounce (s5 Pogo), so a link is 300 u.
	assert_int(chain.vx_u).is_equal(20)
	assert_int(_link_frames(chain) * chain.vx_u).is_equal(300)


func test_ten_links_at_four_a_second_cross_and_nine_do_not() -> void:
	var pit: int = _tunnel_u(_room())
	assert_int(pit).is_equal((TUNNEL_LAST_COL - TUNNEL_FIRST_COL + 1) * TILE_U)
	var route: Chain = _chain(ROUTE)
	var nine: Chain = _chain(NINE)
	assert_int(nine.frames.size()).is_equal(BOUNCES - 1)
	# Same rhythm, same opening: the nine control is the route's first nine bounces.
	assert_int(_link_frames(nine)).is_equal(_link_frames(route))
	assert_int(_first_in_u(nine)).is_equal(_first_in_u(route))
	# Each bounce's arc is a link long. The ninth arc ends inside the tunnel; the tenth ends past it.
	assert_int(_arc_ends_after(route, BOUNCES - 1)).is_less(pit)
	assert_int(_arc_ends_after(route, BOUNCES)).is_greater(pit)


func test_the_tunnel_is_no_longer_than_ten_links() -> void:
	# Ten links, plus the tile the tunnel is cut to: the line asks ten bounces, not seventeen.
	var route: Chain = _chain(ROUTE)
	var link_u: int = _link_frames(route) * route.vx_u
	assert_int(_tunnel_u(_room())).is_less_equal(BOUNCES * link_u + TILE_U)


func test_nine_bounces_cross_when_the_opening_link_is_slow() -> void:
	# An air jump in the opener (the no-pogo controls' dash-jump and air jump) lands the first
	# bounce 256 u farther in, at frame 72 instead of 57. The chain after it is the route's rhythm,
	# nine bounces, and the ninth arc ends past the tunnel: ten are not needed after a slow opening.
	var pit: int = _tunnel_u(_room())
	var route: Chain = _chain(ROUTE)
	var slow: Chain = _chain(SLOW_OPENER)
	assert_int(slow.frames.size()).is_equal(BOUNCES - 1)
	assert_int(_link_frames(slow)).is_equal(_link_frames(route))
	assert_int(slow.frames[0]).is_greater(route.frames[0])
	assert_int(_first_in_u(slow)).is_greater(_first_in_u(route) + 200)
	assert_int(_arc_ends_after(slow, BOUNCES - 1)).is_greater(pit)
	# The same opening and one bounce fewer falls short (n8).
	assert_int(_arc_ends_after(slow, BOUNCES - 2)).is_less(pit)


func test_the_room_header_and_the_adr_say_what_the_room_is() -> void:
	var header: String = FileAccess.get_file_as_string(ROOM_FILE)
	var adr: String = FileAccess.get_file_as_string(ADR_FILE)
	for word: String in [
		"03_route_slow_opener",
		"03_main_control_no_pogo_toss",
		"03_main_route",
		"03_optional_way_back",
		"gap_reach",
	]:
		assert_bool(header.contains(word)).is_true()
	assert_bool(adr.contains("03_route_slow_opener")).is_true()
	assert_bool(adr.contains("03_main_control_no_pogo_toss")).is_true()
