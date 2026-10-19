extends GdUnitTestSuite
## tools/replay/gap_reach.gd measures tech 2's routes on test/longchasm, a chasm with no far side;
## the fixtures cross test/chasm. The measure holds only while the two are the same room up to the
## far ledge: the same ledge, ceiling and pit, so a plan is sent back on the tick it would be in
## the chasm (movement review 5, H1: a deeper chasm than the measuring room let a toss route fall
## far and teleport back up across it).

const FAR_FACE: int = 67
const LEDGE_ROW: int = 12
const PIT_ROW: int = 18

## Zone 1 room 2 (zone1/02_dash_jump) is tech 2's room: its chasm is test/chasm's, moved right and
## down. Everything from the near edge's run-up to the east ledge (and the headroom above it, up to
## the ceiling) is the same tile for tile, so the fixtures that prove the gap needs a dash-jump
## (tests/replay/zone1/02_control_*) and gap_reach.gd's measure hold for it as for test/chasm.
const ZONE_ROOM: String = "zone1/02_dash_jump"
const ZONE_COL_OFFSET: int = 18
const ZONE_ROW_OFFSET: int = 7
## test/chasm's border columns are walls above the ledges; the zone room's run-up is open to the
## ditch on one side and its east ledge runs to the door on the other, so the comparison stops one
## tile inside each border.
const CHASM_FIRST_COL: int = 1
const CHASM_LAST_COL: int = 78


func _room(room_id: String) -> RoomData:
	var room: RoomData = RoomData.load_id(room_id)
	assert_array(Array(room.errors)).is_empty()
	return room


func test_gap_reach_measures_on_the_long_chasm() -> void:
	var tool: Script = load("res://tools/replay/gap_reach.gd") as Script
	var room: String = tool.get_script_constant_map()["ROOM"]
	assert_str(room).is_equal("test/longchasm")


func test_the_measuring_room_is_the_chasm_up_to_its_far_face() -> void:
	var chasm: RoomData = _room("test/chasm")
	var long: RoomData = _room("test/longchasm")
	assert_int(long.grid.height).is_equal(chasm.grid.height)
	assert_int(long.spawn_x_u).is_equal(chasm.spawn_x_u)
	assert_int(long.spawn_y_u).is_equal(chasm.spawn_y_u)
	for j: int in range(chasm.grid.height - 1):
		for i: int in range(FAR_FACE):
			(
				assert_int(long.grid.get_tile(i, j))
				. override_failure_message("tile (%d, %d) differs" % [i, j])
				. is_equal(chasm.grid.get_tile(i, j))
			)
	# No far side: the pit runs on to the room's wall.
	for i: int in range(FAR_FACE, long.grid.width - 1):
		assert_int(long.grid.get_tile(i, PIT_ROW)).is_equal(TileGrid.PIT)
		assert_int(long.grid.get_tile(i, LEDGE_ROW)).is_equal(TileGrid.EMPTY)


func test_the_chasm_has_a_pit_floor_and_a_smooth_far_face() -> void:
	var chasm: RoomData = _room("test/chasm")
	for i: int in range(15, FAR_FACE):
		assert_int(chasm.grid.get_tile(i, PIT_ROW)).is_equal(TileGrid.PIT)
		for j: int in range(LEDGE_ROW, PIT_ROW):
			assert_int(chasm.grid.get_tile(i, j)).is_equal(TileGrid.EMPTY)
	for j: int in range(LEDGE_ROW, PIT_ROW + 1):
		assert_int(chasm.grid.get_tile(FAR_FACE, j)).is_equal(TileGrid.SMOOTH)


func test_the_zone_room_holds_the_chasm_tile_for_tile() -> void:
	var chasm: RoomData = _room("test/chasm")
	var zone: RoomData = _room(ZONE_ROOM)
	assert_int(zone.grid.height).is_greater_equal(chasm.grid.height + ZONE_ROW_OFFSET)
	for j: int in range(chasm.grid.height):
		for i: int in range(CHASM_FIRST_COL, CHASM_LAST_COL + 1):
			(
				assert_int(zone.grid.get_tile(i + ZONE_COL_OFFSET, j + ZONE_ROW_OFFSET))
				. override_failure_message("chasm tile (%d, %d) differs in the zone room" % [i, j])
				. is_equal(chasm.grid.get_tile(i, j))
			)


func test_the_zone_rooms_chasm_is_the_same_width_and_depth() -> void:
	var zone: RoomData = _room(ZONE_ROOM)
	var chasm: RoomData = _room("test/chasm")
	var ledge_row: int = LEDGE_ROW + ZONE_ROW_OFFSET
	var pit_row: int = PIT_ROW + ZONE_ROW_OFFSET
	var near_edge: int = 15 + ZONE_COL_OFFSET
	var far_face: int = FAR_FACE + ZONE_COL_OFFSET
	assert_int(far_face - near_edge).is_equal(52)
	assert_int(zone.grid.get_tile(near_edge - 1, ledge_row)).is_equal(TileGrid.SOLID)
	for i: int in range(near_edge, far_face):
		assert_int(zone.grid.get_tile(i, pit_row)).is_equal(TileGrid.PIT)
		assert_int(zone.grid.get_tile(i, ledge_row)).is_equal(TileGrid.EMPTY)
	for j: int in range(ledge_row, pit_row + 1):
		assert_int(zone.grid.get_tile(far_face, j)).is_equal(TileGrid.SMOOTH)
	# The 15 tiles of run-up to the near edge are floor at the ledge's height, as in test/chasm.
	for i: int in range(near_edge - 15, near_edge):
		assert_int(zone.grid.get_tile(i, ledge_row)).is_equal(TileGrid.SOLID)
		assert_int(chasm.grid.get_tile(i - ZONE_COL_OFFSET, LEDGE_ROW)).is_equal(TileGrid.SOLID)
