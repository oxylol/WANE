extends GdUnitTestSuite
## Zone 1 room 11 teaches tech 11 (Ember-toss cancel) with a chasm sized from
## tools/replay/gap_reach.gd's measurements on test/longchasm: the dash-jump with every resource
## and no toss reaches 2243 u past the edge, the same with one Ember Toss 2505 u. The room's
## chasm needs a reach past its width less half the body's width. The measure holds only while
## the room is the long chasm up to its far face (the same ledge, ceiling and pit), as
## test_gap_reach_room.gd keeps tech 2's.

const ROOM: String = "zone1/11_ember_toss_cancel"
const LEDGE_ROW: int = 12
const PIT_ROW: int = 18
const NEAR_EDGE_COL: int = 15
const FAR_FACE_COL: int = 90
## gap_reach.gd on test/longchasm (docs/adr/0010; the room's header comment).
const DASH_JUMP_REACH_U: int = 2243
const DASH_JUMP_TOSS_REACH_U: int = 2505
const BODY_HALF_WIDTH_U: int = 10
const TILE_U: int = 32
## The dip of the safe first encounter, columns 4 to 7, two tiles deep.
const DIP_FIRST_COL: int = 4
const DIP_LAST_COL: int = 7


func _room(room_id: String) -> RoomData:
	var room: RoomData = RoomData.load_id(room_id)
	assert_array(Array(room.errors)).is_empty()
	return room


func test_the_chasm_needs_the_toss_and_the_toss_route_has_it() -> void:
	var gap_u: int = (FAR_FACE_COL - NEAR_EDGE_COL) * TILE_U
	var needed: int = gap_u - BODY_HALF_WIDTH_U
	assert_int(needed).is_greater(DASH_JUMP_REACH_U)
	assert_int(needed).is_less(DASH_JUMP_TOSS_REACH_U)


func test_the_room_is_the_long_chasm_up_to_its_far_face() -> void:
	var room: RoomData = _room(ROOM)
	var long: RoomData = _room("test/longchasm")
	assert_int(room.grid.height).is_equal(long.grid.height)
	# Past the dip, the near ledge, the chasm and the pit are the long chasm's.
	for j: int in range(room.grid.height - 1):
		for i: int in range(DIP_LAST_COL + 1, FAR_FACE_COL):
			(
				assert_int(room.grid.get_tile(i, j))
				. override_failure_message("tile (%d, %d) differs" % [i, j])
				. is_equal(long.grid.get_tile(i, j))
			)
	# The far face is smooth from the ledge to the pit.
	for j: int in range(LEDGE_ROW, PIT_ROW + 1):
		assert_int(room.grid.get_tile(FAR_FACE_COL, j)).is_equal(TileGrid.SMOOTH)
	# The pit is the same 192 u below the ledges.
	for i: int in range(NEAR_EDGE_COL, FAR_FACE_COL):
		assert_int(room.grid.get_tile(i, PIT_ROW)).is_equal(TileGrid.PIT)


func test_the_first_encounter_is_a_dip_that_costs_nothing() -> void:
	var room: RoomData = _room(ROOM)
	for i: int in range(DIP_FIRST_COL, DIP_LAST_COL + 1):
		assert_int(room.grid.get_tile(i, LEDGE_ROW)).is_equal(TileGrid.EMPTY)
		assert_int(room.grid.get_tile(i, LEDGE_ROW + 1)).is_equal(TileGrid.EMPTY)
		assert_int(room.grid.get_tile(i, LEDGE_ROW + 2)).is_equal(TileGrid.SOLID)
