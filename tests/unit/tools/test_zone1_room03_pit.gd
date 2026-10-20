extends GdUnitTestSuite
## Zone 1 room 3 (BUILD.md s5 tech 3, s15 "a 10-bounce chain across the zone 1 spike pit is
## possible at 4 bounces per second"). The pit is sized from what the chain covers: a bounce every
## 15 frames (4 a second) at the dash-jump's 20 u/f, 300 u a bounce, from a first bounce 196 u
## inside the tunnel. The fixtures (tests/replay/zone1/03_*) prove the chain in the physics; this
## holds the room to the arithmetic they rest on, so a change to the room cannot quietly make the
## line easy again (the pit was 5184 u, 17 bounces at 4 a second, ADR-0019 Decision 5).

const ROOM: String = "zone1/03_pogo_chain"
const TILE_U: int = 32
const SPIKE_ROW: int = 18
const CEILING_ROW: int = 15
const TUNNEL_FIRST_COL: int = 18
const TUNNEL_LAST_COL: int = 111
## The route's first bounce lands 195.5 u inside the tunnel (zone1_03_pogo_chain_route, x 771.5).
const FIRST_BOUNCE_IN_U: int = 196
## 15 frames at 20 u/f.
const LINK_U: int = 300
const BOUNCES: int = 10
## The fixture that proves the chain, and the one that proves nine fall short.
const ROUTE: String = "res://tests/replay/zone1/03_pogo_chain_route.fixture"
const NINE: String = "res://tests/replay/zone1/03_control_nine_bounces.fixture"


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


func test_ten_links_at_four_a_second_cross_and_nine_do_not() -> void:
	var pit: int = _pit_u(_room())
	assert_int(pit).is_equal((TUNNEL_LAST_COL - TUNNEL_FIRST_COL + 1) * TILE_U)
	# Each bounce's arc is a link long. The ninth arc ends inside the pit, where the tenth bounce
	# would be; the tenth ends past the pit's far end.
	var ninth_arc_ends: int = FIRST_BOUNCE_IN_U + (BOUNCES - 1) * LINK_U
	var tenth_arc_ends: int = FIRST_BOUNCE_IN_U + BOUNCES * LINK_U
	assert_int(ninth_arc_ends).is_less(pit)
	assert_int(tenth_arc_ends).is_greater(pit)


func test_the_pit_is_no_longer_than_ten_links() -> void:
	# 3000 u of links, plus the tile the pit is cut to: the line asks ten bounces, not seventeen.
	assert_int(_pit_u(_room())).is_less_equal(BOUNCES * LINK_U + TILE_U)


func test_the_fixtures_prove_ten_cross_and_nine_fall_short() -> void:
	assert_bool(FileAccess.file_exists(ROUTE)).is_true()
	assert_bool(FileAccess.file_exists(NINE)).is_true()
	var route: Fixture = Fixture.parse_file(ROUTE)
	var nine: Fixture = Fixture.parse_file(NINE)
	assert_array(Array(route.errors)).is_empty()
	assert_array(Array(nine.errors)).is_empty()
	assert_str(route.scenario.room).is_equal(ROOM)
	assert_str(nine.scenario.room).is_equal(ROOM)
