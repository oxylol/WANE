extends GdUnitTestSuite
## The room editor's edits of solid boxes, entities, doors and the room's size (docs/adr/0009,
## 0014, 0015), through [RoomDocument]'s helpers.

const A_ID: String = "test/ed_scratch/a"
const B_ID: String = "test/ed_scratch/b"
const T: int = TileGrid.TILE


func after_test() -> void:
	var dir: String = ProjectSettings.globalize_path(RoomData.TEST_ROOT + "ed_scratch")
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)


## The problems of [param doc] other than doors that have no target yet.
func _real(doc: RoomDocument) -> PackedStringArray:
	var out: PackedStringArray = []
	for p: String in doc.problems():
		if not p.contains("has no target yet"):
			out.append(p)
	return out


## Two 40 x 20 rooms with a door each, on the right of the first and the left of the second, both
## carved, leading to each other.
func _pair(doc_a: RoomDocument, doc_b: RoomDocument) -> void:
	var east: int = doc_a.doors().add(RoomData.RIGHT, 320, 448, "east")
	doc_a.doors().carve(east)
	doc_a.doors().set_target(east, B_ID, "west")
	var west: int = doc_b.doors().add(RoomData.LEFT, 320, 448, "west")
	doc_b.doors().carve(west)
	doc_b.doors().set_target(west, A_ID, "east")


# --- solid boxes and entities ---------------------------------------------------------------------


func test_solid_boxes_carry_their_tags_and_save_in_the_loaders_format() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var pogo: int = doc.objects().add_solid(Rect2i(160, 480, 64, 96), "pogo")
	var wax: int = doc.objects().add_solid(Rect2i(480, 416, 32, 160), "wax", false)
	var plain: int = doc.objects().add_solid(Rect2i(800, 544, 64, 32))
	assert_array(doc.problems()).is_empty()
	var text: String = doc.text()
	assert_bool(text.contains("solid 160 480 224 576 tag=pogo\n")).is_true()
	assert_bool(text.contains("solid 480 416 512 576 tag=wax cling=0\n")).is_true()
	assert_bool(text.contains("solid 800 544 864 576\n")).is_true()
	doc.objects().set_solid_options(plain, "pogo", false)
	assert_bool(doc.text().contains("solid 800 544 864 576 tag=pogo cling=0\n")).is_true()
	doc.objects().move_solid(pogo, Vector2i(32, 0))
	assert_bool(doc.text().contains("solid 192 480 256 576 tag=pogo\n")).is_true()
	doc.objects().remove_solid(wax)
	assert_int(doc.room.solids.size()).is_equal(2)
	doc.undo()
	assert_int(doc.room.solids.size()).is_equal(3)
	assert_bool(doc.room.solids[wax].clingable).is_false()
	assert_str(doc.room.solids[wax].tag).is_equal("wax")


func test_the_dummy_and_its_properties_are_edited_and_saved() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var d: int = doc.objects().add_entity("dummy", 700, 576)
	doc.objects().set_entity_prop(d, "attack", "1")
	doc.objects().set_entity_prop(d, "period", "60")
	doc.objects().set_entity_prop(d, "facing", "1")
	doc.objects().set_entity_prop(d, "hp", "10")
	assert_array(doc.problems()).is_empty()
	(
		assert_bool(doc.text().contains("entity dummy 700 576 attack=1 facing=1 hp=10 period=60\n"))
		. is_true()
	)
	doc.objects().set_entity_prop(d, "hp", "")
	assert_bool(doc.room.entities[d].props.has("hp")).is_false()
	doc.objects().move_entity(d, 764, 576)
	doc.objects().set_entity_props(d, {"red": "1"})
	assert_bool(doc.text().contains("entity dummy 764 576 red=1\n")).is_true()
	doc.undo()
	doc.undo()
	assert_int(doc.room.entities[d].x_u).is_equal(700)
	var back: RoomData.RoomEntity = RoomData.parse(doc.text()).entities[0]
	assert_int(back.prop_int("period")).is_equal(60)
	doc.objects().remove_entity(d)
	assert_array(doc.room.entities).is_empty()


func test_a_dummy_with_a_bad_property_or_outside_the_room_is_a_problem() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var d: int = doc.objects().add_entity("dummy", 700, 576)
	doc.objects().set_entity_prop(d, "hp", "lots")
	doc.objects().set_entity_prop(d, "colour", "1")
	doc.objects().set_entity_prop(d, "facing", "2")
	var found: PackedStringArray = doc.problems()
	assert_int(found.size()).is_equal(3)
	assert_str(found[0]).contains("has no property 'colour'")
	doc.objects().set_entity_props(d, {})
	doc.objects().move_entity(d, 2000, 576)
	assert_str(doc.problems()[0]).contains("is outside the room")
	# A kind the editor does not know is placed and saved as given.
	doc.objects().move_entity(d, 300, 576)
	doc.objects().add_entity("lantern", 400, 576, {"glow": "3"})
	assert_array(doc.problems()).is_empty()


# --- doors ----------------------------------------------------------------------------------------


func test_a_new_door_names_itself_and_has_no_target_until_one_is_set() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var first: int = doc.doors().add(RoomData.RIGHT, 320, 448)
	var second: int = doc.doors().add(RoomData.RIGHT, 160, 288)
	assert_str(doc.room.doors[first].name).is_equal("right")
	assert_str(doc.room.doors[second].name).is_equal("right2")
	var found: PackedStringArray = doc.problems()
	assert_bool(found.has("door 'right' has no target yet: set its room and door")).is_true()
	assert_int(doc.save()).is_equal(ERR_INVALID_DATA)
	# The text round-trips, so undo keeps a door that has no target yet.
	doc.doors().remove(second)
	doc.undo()
	assert_int(doc.room.doors.size()).is_equal(2)
	assert_str(doc.room.doors[second].target_room).is_equal(RoomDocument.UNSET)


func test_carving_a_door_clears_its_strip_and_lays_floor_under_a_side_door() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var door: int = doc.doors().add(RoomData.RIGHT, 320, 448, "east")
	assert_str(doc.problems()[0]).contains("not empty")
	doc.doors().carve(door)
	# Cleared: the strip and the two tiles beyond it; the floor under it is a wall.
	for j: int in range(10, 14):
		for i: int in range(36, 40):
			assert_int(doc.room.grid.get_tile(i, j)).is_equal(TileGrid.EMPTY)
		for i: int in range(36, 40):
			assert_int(doc.room.grid.get_tile(i, 14)).is_equal(TileGrid.SOLID)
	assert_array(_real(doc)).is_empty()
	# One undo takes the whole carve back.
	doc.undo()
	assert_int(doc.room.grid.get_tile(39, 11)).is_equal(TileGrid.SOLID)


func test_a_top_door_needs_safe_ground_to_land_on() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var door: int = doc.doors().add(RoomData.TOP, 320, 448, "up")
	doc.doors().carve(door)
	assert_array(_real(doc)).is_empty()
	doc.fill(Rect2i(11, 18, 2, 2), TileGrid.SPIKES)
	assert_str(_real(doc)[0]).contains("lands on no safe ground")


func test_doors_move_resize_and_change_side_within_their_edge() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var door: int = doc.doors().add(RoomData.RIGHT, 320, 448, "east")
	doc.doors().slide(door, -2000)
	assert_int(doc.room.doors[door].from_u).is_equal(0)
	assert_int(doc.room.doors[door].span_u()).is_equal(128)
	doc.doors().slide(door, 99999)
	assert_int(doc.room.doors[door].to_u).is_equal(20 * T)
	doc.doors().set_span(door, 160, 352)
	assert_int(doc.room.doors[door].span_u()).is_equal(192)
	doc.doors().set_side(door, RoomData.TOP)
	assert_int(doc.room.doors[door].side).is_equal(RoomData.TOP)
	doc.doors().set_side(door, RoomData.LEFT)
	doc.doors().rename(door, "west")
	assert_str(doc.room.doors[door].name).is_equal("west")
	# A span the loader refuses is a problem to read, not an edit to refuse.
	doc.doors().set_span(door, 40, 100)
	var found: PackedStringArray = doc.problems()
	assert_bool(found.size() > 0 and found[0].contains("not on whole tiles")).is_true()
	doc.doors().remove(door)
	assert_array(doc.room.doors).is_empty()
	for _k: int in range(12):
		doc.undo()
	assert_int(doc.room.doors.size()).is_equal(0)
	assert_bool(doc.history.can_undo()).is_false()


func test_two_doors_that_lead_to_each_other_are_checked_as_a_pair() -> void:
	var a: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var b: RoomDocument = RoomDocument.create(B_ID, 40, 20)
	_pair(a, b)
	# B does not exist yet: A can be saved, and says what is missing.
	assert_array(a.problems()).is_empty()
	assert_str(a.warnings()[0]).contains("has no file yet")
	assert_int(a.save()).is_equal(OK)
	# B's door leads back to A's, so B passes and so does A against B.
	assert_array(b.problems()).is_empty()
	assert_int(b.save()).is_equal(OK)
	assert_array(a.warnings()).is_empty()
	assert_array(a.problems()).is_empty()


func test_doors_that_do_not_pair_are_refused_while_the_other_room_exists() -> void:
	var a: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var b: RoomDocument = RoomDocument.create(B_ID, 40, 20)
	_pair(a, b)
	assert_int(a.save()).is_equal(OK)
	assert_int(b.save()).is_equal(OK)
	# A door of B that A's door does not lead to.
	b.doors().set_target(0, A_ID, "other")
	assert_str(b.problems()[0]).contains("which has none")
	# A door on the wrong side.
	b.doors().set_target(0, A_ID, "east")
	b.doors().set_side(0, RoomData.TOP)
	b.doors().carve(0)
	assert_bool(" ".join(b.problems()).contains("it must be on the right")).is_false()
	assert_bool(" ".join(b.problems()).contains("must be on the")).is_true()
	# A door of a different length.
	b.doors().set_side(0, RoomData.LEFT)
	b.doors().set_span(0, 288, 448)
	b.doors().carve(0)
	assert_str(b.problems()[0]).contains("is 160 u")
	# A door the other room does not lead back to: refused, so the pair cannot be left half done.
	b.doors().set_span(0, 320, 448)
	b.doors().set_target(0, A_ID, "east")
	assert_array(b.problems()).is_empty()
	a.doors().rename(0, "gate")
	assert_str(a.problems()[0]).contains("which does not lead back")
	assert_int(a.save()).is_equal(ERR_INVALID_DATA)


# --- size -----------------------------------------------------------------------------------------


func test_growing_copies_the_edge_so_walls_and_door_openings_carry_on() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var east: int = doc.doors().add(RoomData.RIGHT, 320, 448, "east")
	doc.doors().carve(east)
	doc.resize(46, 24, Vector2i(-1, -1))
	assert_int(doc.room.grid.width).is_equal(46)
	assert_int(doc.room.grid.height).is_equal(24)
	assert_array(_real(doc)).is_empty()
	assert_int(doc.room.grid.get_tile(45, 11)).is_equal(TileGrid.EMPTY)
	assert_int(doc.room.grid.get_tile(45, 20)).is_equal(TileGrid.SOLID)
	assert_int(doc.room.grid.get_tile(0, 23)).is_equal(TileGrid.SOLID)
	assert_int(doc.room.doors[east].from_u).is_equal(320)


func test_growing_up_and_left_moves_the_contents_with_it() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var east: int = doc.doors().add(RoomData.RIGHT, 320, 448, "east")
	doc.doors().carve(east)
	var top: int = doc.doors().add(RoomData.TOP, 320, 448, "up")
	doc.doors().carve(top)
	doc.objects().add_solid(Rect2i(160, 480, 64, 96), "pogo")
	doc.objects().add_entity("dummy", 700, 576)
	doc.resize(44, 23, Vector2i(1, 1))
	assert_int(doc.room.spawn_x_u).is_equal(3 * T + 4 * T)
	assert_int(doc.room.spawn_y_u).is_equal(18 * T + 3 * T)
	assert_int(doc.room.entities[0].x_u).is_equal(700 + 4 * T)
	assert_int(doc.room.entities[0].y_u).is_equal(576 + 3 * T)
	assert_int(doc.room.solids[0].left).is_equal(Fx.units(160 + 4 * T))
	# The right door slides down with the rows; the top door slides right with the columns.
	assert_int(doc.room.doors[east].from_u).is_equal(320 + 3 * T)
	assert_int(doc.room.doors[top].from_u).is_equal(320 + 4 * T)
	assert_array(_real(doc)).is_empty()


func test_shrinking_takes_the_rows_inside_the_edge_and_keeps_the_edge() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	doc.set_tile(30, 5, TileGrid.SMOOTH)
	doc.resize(34, 20, Vector2i(-1, -1))
	assert_int(doc.room.grid.width).is_equal(34)
	assert_int(doc.room.grid.get_tile(33, 5)).is_equal(TileGrid.SOLID)
	assert_int(doc.room.grid.get_tile(30, 5)).is_equal(TileGrid.SMOOTH)
	doc.resize(30, 20, Vector2i(0, 0))
	assert_int(doc.room.grid.width).is_equal(30)
	assert_int(doc.room.grid.get_tile(0, 4)).is_equal(TileGrid.SOLID)
	assert_int(doc.room.grid.get_tile(29, 4)).is_equal(TileGrid.SOLID)
	doc.undo()
	assert_int(doc.room.grid.width).is_equal(34)
	doc.undo()
	assert_int(doc.room.grid.width).is_equal(40)
