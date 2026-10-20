extends GdUnitTestSuite
## Zone 1 room 3 (BUILD.md s5 tech 3, s15 "a 10-bounce chain across the zone 1 spike pit is
## possible at 4 bounces per second"). The pit is sized from what the chain covers: a bounce every
## 15 frames (4 a second) at the dash-jump's 20 u/f, 300 u a bounce, from a first bounce about 196 u
## inside the tunnel. The fixtures (tests/replay/zone1/03_*) prove the chain in the physics; this
## holds the room to the arithmetic they rest on, so a change to the room cannot quietly make the
## line easy again (the pit was 5184 u, 17 bounces at 4 a second, ADR-0019 Decision 5). The
## numbers are read out of the fixtures' own expectations (bounce frames, vx, the first bounce's x),
## not copied, so a fixture and this test cannot drift apart.
##
## What the pit does not do: demand ten of every chain. A slow link buys distance, and the opening
## link is one a player slows with an ordinary air jump (nine 4-a-second bounces after a 25-frame
## opening link cross, 03_route_slow_opener). The line is that ten at 4 a second are possible and
## that a chain whose first bounce comes on the dash-jump's own arc (frame 57) needs them; the test
## pins both.

const ROOM: String = "zone1/03_pogo_chain"
const TILE_U: int = 32
const SPIKE_ROW: int = 18
const CEILING_ROW: int = 15
const TUNNEL_FIRST_COL: int = 18
const TUNNEL_LAST_COL: int = 111
const BOUNCES: int = 10
const FPS: int = 60
## The fixture that proves the chain, the one that proves nine fall short, and the one that proves
## what a slow opening link buys (nine cross).
const ROUTE: String = "res://tests/replay/zone1/03_pogo_chain_route.fixture"
const NINE: String = "res://tests/replay/zone1/03_control_nine_bounces.fixture"
const SLOW_OPENER: String = "res://tests/replay/zone1/03_route_slow_opener.fixture"
const ROOM_FILE: String = "res://content/rooms/zone1/03_pogo_chain.room"
const ADR_FILE: String = "res://docs/adr/0019-zone1-grey-box-gates-and-teaches.md"


func _room() -> RoomData:
	var room: RoomData = RoomData.load_id(ROOM)
	assert_array(Array(room.errors)).is_empty()
	return room


func _pit_u(room: RoomData) -> int:
	var cols: int = 0
	for i: int in range(room.grid.width):
		if room.grid.get_tile(i, SPIKE_ROW) == TileGrid.SPIKES and i >= TUNNEL_FIRST_COL:
			cols += 1
	return cols * TILE_U


func test_the_tunnel_is_a_floor_of_spikes_under_a_low_ceiling() -> void:
	var room: RoomData = _room()
	for i: int in range(TUNNEL_FIRST_COL, TUNNEL_LAST_COL + 1):
		assert_int(room.grid.get_tile(i, SPIKE_ROW)).is_equal(TileGrid.SPIKES)
		assert_int(room.grid.get_tile(i, CEILING_ROW)).is_equal(TileGrid.SOLID)
		for j: int in range(CEILING_ROW + 1, SPIKE_ROW):
			assert_int(room.grid.get_tile(i, j)).is_equal(TileGrid.EMPTY)
	# The east hall's floor line is open: no spike, no wall in the way of the last arc.
	assert_int(room.grid.get_tile(TUNNEL_LAST_COL + 1, SPIKE_ROW)).is_equal(TileGrid.EMPTY)


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
	var pit: int = _pit_u(_room())
	assert_int(pit).is_equal((TUNNEL_LAST_COL - TUNNEL_FIRST_COL + 1) * TILE_U)
	var route: Chain = _chain(ROUTE)
	var nine: Chain = _chain(NINE)
	assert_int(nine.frames.size()).is_equal(BOUNCES - 1)
	# Same rhythm, same opening: the nine control is the route's first nine bounces.
	assert_int(_link_frames(nine)).is_equal(_link_frames(route))
	assert_int(_first_in_u(nine)).is_equal(_first_in_u(route))
	# Each bounce's arc is a link long. The ninth arc ends inside the pit; the tenth ends past it.
	assert_int(_arc_ends_after(route, BOUNCES - 1)).is_less(pit)
	assert_int(_arc_ends_after(route, BOUNCES)).is_greater(pit)


func test_the_pit_is_no_longer_than_ten_links() -> void:
	# Ten links, plus the tile the pit is cut to: the line asks ten bounces, not seventeen.
	var route: Chain = _chain(ROUTE)
	var link_u: int = _link_frames(route) * route.vx_u
	assert_int(_pit_u(_room())).is_less_equal(BOUNCES * link_u + TILE_U)


func test_nine_bounces_cross_when_the_opening_link_is_slow() -> void:
	# An air jump in the opener (the no-pogo controls' dash-jump and air jump) lands the first
	# bounce 256 u farther in, at frame 72 instead of 57. The chain after it is the route's rhythm,
	# nine bounces, and the ninth arc ends past the pit: ten are not needed after a slow opening.
	var pit: int = _pit_u(_room())
	var route: Chain = _chain(ROUTE)
	var slow: Chain = _chain(SLOW_OPENER)
	assert_int(slow.frames.size()).is_equal(BOUNCES - 1)
	assert_int(_link_frames(slow)).is_equal(_link_frames(route))
	assert_int(slow.frames[0]).is_greater(route.frames[0])
	assert_int(_first_in_u(slow)).is_greater(_first_in_u(route) + 200)
	assert_int(_arc_ends_after(slow, BOUNCES - 1)).is_greater(pit)
	# The same opening and one bounce fewer falls short (n8).
	assert_int(_arc_ends_after(slow, BOUNCES - 2)).is_less(pit)


func test_the_room_header_and_the_adr_say_what_a_slow_opening_buys() -> void:
	var header: String = FileAccess.get_file_as_string(ROOM_FILE)
	var adr: String = FileAccess.get_file_as_string(ADR_FILE)
	assert_bool(header.contains("03_route_slow_opener")).is_true()
	assert_bool(adr.contains("03_route_slow_opener")).is_true()
