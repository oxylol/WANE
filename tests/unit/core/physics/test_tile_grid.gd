extends GdUnitTestSuite
## TileGrid: map characters, bounds, slope surfaces and the geometry rules (docs/adr/0008).

const U: int = Fx.SUB
const T: int = TileGrid.TILE_SP


func test_rows_round_trip_and_bounds() -> void:
	var rows := PackedStringArray(["..#", "=/\\", "abcd", "S^.."])
	var errors: PackedStringArray = []
	var g: TileGrid = TileGrid.from_rows(rows, errors)
	assert_array(Array(errors)).is_empty()
	assert_int(g.width).is_equal(4)
	assert_int(g.height).is_equal(4)
	assert_int(g.get_tile(2, 0)).is_equal(TileGrid.SOLID)
	assert_int(g.get_tile(0, 1)).is_equal(TileGrid.ONE_WAY)
	assert_int(g.get_tile(1, 1)).is_equal(TileGrid.SLOPE_R)
	assert_int(g.get_tile(2, 1)).is_equal(TileGrid.SLOPE_L)
	assert_int(g.get_tile(0, 3)).is_equal(TileGrid.SMOOTH)
	assert_int(g.get_tile(1, 3)).is_equal(TileGrid.SPIKES)
	# Short rows are padded with empty tiles; outside the grid is solid.
	assert_int(g.get_tile(3, 0)).is_equal(TileGrid.EMPTY)
	assert_int(g.get_tile(-1, 0)).is_equal(TileGrid.SOLID)
	assert_int(g.get_tile(0, 4)).is_equal(TileGrid.SOLID)
	assert_array(Array(g.to_rows())).is_equal(["..#.", "=/\\.", "abcd", "S^.."])


func test_unknown_character_is_reported() -> void:
	var errors: PackedStringArray = []
	var g: TileGrid = TileGrid.from_rows(PackedStringArray([".X."]), errors)
	assert_int(errors.size()).is_equal(1)
	assert_int(g.get_tile(1, 0)).is_equal(TileGrid.EMPTY)


func test_cell_floors_negative_coordinates() -> void:
	assert_int(TileGrid.cell(0)).is_equal(0)
	assert_int(TileGrid.cell(T - 1)).is_equal(0)
	assert_int(TileGrid.cell(T)).is_equal(1)
	assert_int(TileGrid.cell(-1)).is_equal(-1)


func test_45_degree_slope_surfaces() -> void:
	# Tile (2, 3): x in [64u, 96u), y in [96u, 128u).
	assert_int(TileGrid.slope_surface(TileGrid.SLOPE_R, 2, 3, 64 * U)).is_equal(128 * U)
	assert_int(TileGrid.slope_surface(TileGrid.SLOPE_R, 2, 3, 80 * U)).is_equal(112 * U)
	assert_int(TileGrid.slope_surface(TileGrid.SLOPE_R, 2, 3, 96 * U - 1)).is_equal(96 * U + 1)
	assert_int(TileGrid.slope_surface(TileGrid.SLOPE_L, 2, 3, 64 * U)).is_equal(96 * U)
	assert_int(TileGrid.slope_surface(TileGrid.SLOPE_L, 2, 3, 80 * U)).is_equal(112 * U)


func test_shallow_slope_surfaces_join_continuously() -> void:
	# Rising right over two tiles: low half then high half, meeting at the middle height.
	var lo_end: int = TileGrid.slope_surface(TileGrid.SLOPE_R_LO, 0, 0, T - 2)
	var hi_start: int = TileGrid.slope_surface(TileGrid.SLOPE_R_HI, 1, 0, T)
	assert_int(hi_start).is_equal(T / 2)
	assert_int(absi(lo_end - hi_start)).is_less_equal(1)
	assert_int(TileGrid.slope_surface(TileGrid.SLOPE_R_LO, 0, 0, 0)).is_equal(T)
	assert_int(TileGrid.slope_surface(TileGrid.SLOPE_L_HI, 0, 0, 0)).is_equal(0)
	assert_int(TileGrid.slope_surface(TileGrid.SLOPE_L_LO, 1, 0, T)).is_equal(T / 2)


func test_edge_heights() -> void:
	assert_bool(TileGrid.slope_edge_heights(TileGrid.SLOPE_R) == Vector2i(0, T)).is_true()
	assert_bool(TileGrid.slope_edge_heights(TileGrid.SLOPE_L_LO) == Vector2i(T / 2, 0)).is_true()
	assert_bool(TileGrid.is_slope(TileGrid.SLOPE_L_LO)).is_true()
	assert_bool(TileGrid.is_slope(TileGrid.SPIKES)).is_false()
	assert_bool(TileGrid.blocks_from_below(TileGrid.ONE_WAY)).is_false()


func test_valid_slope_layouts_pass() -> void:
	var layouts: Array[PackedStringArray] = [
		PackedStringArray(["/#", "##"]),
		PackedStringArray(["#\\", "##"]),
		PackedStringArray(["/\\", "##"]),
		PackedStringArray(["#\\/#", "####"]),
		PackedStringArray(["ab#", "###"]),
		PackedStringArray(["#cd", "###"]),
		PackedStringArray(["../###\\..", "#########"]),
		PackedStringArray([".#", "/#", "##"]),
	]
	for rows: PackedStringArray in layouts:
		var g: TileGrid = TileGrid.from_rows(rows)
		assert_array(Array(g.validate())).override_failure_message(str(rows)).is_empty()


func test_slopes_that_would_show_a_face_or_underside_are_rejected() -> void:
	# The first review's tunnelling layouts: a slope's high side against a one-way or air, a
	# slope over empty space, and 1:2 halves without their partner.
	var cases: Dictionary[String, PackedStringArray] = {
		"its right side": PackedStringArray(["...../==", "########"]),
		"its left side": PackedStringArray(["..==\\...", "########"]),
		"does not rest": PackedStringArray(["...../##", "........", "########"]),
		"right side needs": PackedStringArray(["a.", "##"]),
		"left side needs": PackedStringArray([".b#", "###"]),
	}
	for expected: String in cases:
		var g: TileGrid = TileGrid.from_rows(cases[expected])
		var text: String = "\n".join(g.validate())
		assert_str(text).override_failure_message("%s: %s" % [cases[expected], text]).contains(
			expected
		)


func test_rooms_report_invalid_geometry() -> void:
	var room: RoomData = RoomData.parse("room x\nspawn 0 0\ntiles\n...../==\n########\nend\n")
	assert_str("\n".join(room.errors)).contains("right side needs a wall")
