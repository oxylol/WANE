extends GdUnitTestSuite
## tools/replay/gap_reach.gd measures tech 2's routes on test/longchasm, a chasm with no far side;
## the fixtures cross test/chasm. The measure holds only while the two are the same room up to the
## far ledge: the same ledge, ceiling and pit, so a plan is sent back on the tick it would be in
## the chasm (movement review 5, H1: a deeper chasm than the measuring room let a toss route fall
## far and teleport back up across it).

const FAR_FACE: int = 67
const LEDGE_ROW: int = 12
const PIT_ROW: int = 18


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
