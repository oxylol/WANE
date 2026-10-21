extends GdUnitTestSuite
# unit-group: room-scratch
## The room editor's edit layer refuses what the text format cannot hold (a name with a space, an
## empty name, a '#' that starts a comment), so no edit can leave a room that does not parse and
## no undo can drop a door or a property; a no-op edit is no undo step; undo of an id change keeps
## the path with the id; shrinking a side with a door keeps the door's passage (Phase 1 task 7,
## docs/adr/0014, 0015).

const A_ID: String = "test/ed_scratch/a"
const B_ID: String = "test/ed_scratch/b"
const T: int = TileGrid.TILE


func after_test() -> void:
	var dir: String = ProjectSettings.globalize_path(RoomData.TEST_ROOT + "ed_scratch")
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)


## The problems of [param doc] that contain any of [param words].
func _with(doc: RoomDocument, words: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for p: String in doc.problems():
		for w: String in words:
			if p.contains(w):
				out.append(p)
				break
	return out


func _door_doc() -> RoomDocument:
	var doc: RoomDocument = RoomDocument.create(A_ID, 20, 12)
	var k: int = doc.doors().add(RoomData.LEFT, 160, 256)
	doc.doors().set_target(k, B_ID, "x")
	return doc


# --- nothing the edit layer accepts can make the text unparseable ---------------------------


func test_a_door_name_that_is_empty_or_has_a_space_or_hash_is_refused() -> void:
	var doc: RoomDocument = _door_doc()
	for bad: String in ["", " ", "a b", "a\tb", "a#b"]:
		assert_bool(doc.doors().rename(0, bad)).is_false()
		assert_str(doc.room.doors[0].name).is_equal("left")
	assert_bool(doc.doors().rename(0, "gate")).is_true()
	assert_str(doc.room.doors[0].name).is_equal("gate")


func test_undo_after_a_refused_door_edit_keeps_the_door() -> void:
	var doc: RoomDocument = _door_doc()
	doc.doors().rename(0, "")
	doc.doors().rename(0, "a b")
	doc.doors().set_target(0, "test/a b", "x")
	doc.doors().set_target(0, "test/other", "")
	assert_array(doc.room.errors).is_empty()
	assert_array(_with(doc, ["line "])).is_empty()
	doc.doors().rename(0, "right")
	doc.undo()
	assert_int(doc.room.doors.size()).is_equal(1)
	assert_str(doc.room.doors[0].name).is_equal("left")
	assert_str(doc.room.doors[0].target_room).is_equal(B_ID)


func test_a_door_target_with_a_space_or_empty_is_refused() -> void:
	var doc: RoomDocument = _door_doc()
	assert_bool(doc.doors().set_target(0, "", "x")).is_false()
	assert_bool(doc.doors().set_target(0, "t e", "x")).is_false()
	assert_bool(doc.doors().set_target(0, B_ID, "x y")).is_false()
	assert_str(doc.room.doors[0].target_room).is_equal(B_ID)
	assert_str(doc.room.doors[0].target_door).is_equal("x")
	assert_bool(doc.doors().set_target(0, A_ID, "z")).is_true()


func test_a_new_door_with_a_bad_name_is_refused_and_a_blank_one_names_itself() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 20, 12)
	assert_int(doc.doors().add(RoomData.LEFT, 160, 256, "a b")).is_equal(-1)
	assert_int(doc.room.doors.size()).is_equal(0)
	assert_bool(doc.history.can_undo()).is_false()
	assert_int(doc.doors().add(RoomData.LEFT, 160, 256)).is_equal(0)
	assert_str(doc.room.doors[0].name).is_equal("left")


func test_solid_tags_must_be_one_word_without_equals_or_hash() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 20, 12)
	var s: int = doc.objects().add_solid(Rect2i(64, 64, 64, 32), "pogo")
	for bad: String in ["a b", "a=b", "a#b", "a\tb"]:
		assert_bool(doc.objects().set_solid_options(s, bad, true)).is_false()
		assert_int(doc.objects().add_solid(Rect2i(0, 0, 32, 32), bad)).is_equal(-1)
	assert_str(doc.room.solids[0].tag).is_equal("pogo")
	assert_int(doc.room.solids.size()).is_equal(1)
	assert_bool(doc.objects().set_solid_options(s, "", true)).is_true()
	assert_str(doc.room.solids[0].tag).is_equal("")
	assert_array(RoomData.parse(doc.text()).errors).is_empty()


func test_entity_kinds_keys_and_values_must_survive_the_text() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 20, 12)
	assert_int(doc.objects().add_entity("", 64, 64)).is_equal(-1)
	assert_int(doc.objects().add_entity("du mmy", 64, 64)).is_equal(-1)
	var bad_props: Dictionary[String, String] = {"hp": "5 6"}
	assert_int(doc.objects().add_entity("dummy", 64, 64, bad_props)).is_equal(-1)
	var e: int = doc.objects().add_entity("dummy", 64, 64)
	assert_bool(doc.objects().set_entity_prop(e, "hp", "5 6")).is_false()
	assert_bool(doc.objects().set_entity_prop(e, "h p", "5")).is_false()
	assert_bool(doc.objects().set_entity_prop(e, "hp", "5=6")).is_false()
	assert_bool(doc.objects().set_entity_prop(e, "", "5")).is_false()
	assert_bool(doc.objects().set_entity_props(e, bad_props)).is_false()
	assert_bool(doc.objects().set_entity_prop(e, "hp", "7")).is_true()
	assert_bool(doc.objects().set_entity_prop(e, "hp", "")).is_true()
	doc.objects().set_entity_prop(e, "hp", "8")
	doc.undo()
	assert_int(doc.room.entities.size()).is_equal(1)
	assert_array(RoomData.parse(doc.text()).errors).is_empty()


# --- undo of an id change ---------------------------------------------------------------------


func test_undoing_an_id_change_puts_the_path_back_with_the_id() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 20, 12)
	doc.set_id(B_ID)
	assert_str(doc.path).is_equal(RoomData.path_for(B_ID))
	doc.undo()
	assert_str(doc.room.id).is_equal(A_ID)
	assert_str(doc.path).is_equal(RoomData.path_for(A_ID))
	assert_array(doc.problems()).is_empty()
	doc.redo()
	assert_str(doc.room.id).is_equal(B_ID)
	assert_str(doc.path).is_equal(RoomData.path_for(B_ID))
	assert_array(doc.problems()).is_empty()


# --- shrinking a side with a door -------------------------------------------------------------


func test_shrinking_the_side_of_a_carved_door_keeps_its_passage() -> void:
	for anchor: Vector2i in [Vector2i(-1, -1), Vector2i(1, 1), Vector2i(0, 0)]:
		var doc: RoomDocument = RoomDocument.create(A_ID, 30, 14)
		var m: int = doc.doors().add(RoomData.RIGHT, 256, 352)
		doc.doors().set_target(m, B_ID, "left")
		doc.doors().carve(m)
		var l: int = doc.doors().add(RoomData.LEFT, 256, 352)
		doc.doors().set_target(l, B_ID, "right")
		doc.doors().carve(l)
		doc.resize(24, 14, anchor)
		assert_array(_with(doc, ["floor", "not empty"])).is_empty()


func test_shrinking_the_side_of_a_carved_top_door_keeps_its_passage() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 30, 20)
	var k: int = doc.doors().add(RoomData.TOP, 256, 352)
	doc.doors().set_target(k, B_ID, "bottom")
	doc.doors().carve(k)
	# Tiles in the rows a shrink takes to the top edge would block the passage if it did not carry.
	doc.fill(Rect2i(8, 7, 3, 3), TileGrid.SOLID)
	doc.resize(30, 14, Vector2i(1, 1))
	assert_array(_with(doc, ["not empty", "lands"])).is_empty()


# --- no-op edits, new rooms ------------------------------------------------------------------


func test_an_edit_that_changes_nothing_is_no_undo_step_and_does_not_dirty_a_saved_room() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 20, 12)
	assert_int(doc.save()).is_equal(OK)
	doc.fill(Rect2i(0, 0, 0, 0), TileGrid.SOLID)
	doc.line(Vector2i(0, 0), Vector2i(3, 0), TileGrid.SOLID)
	doc.set_spawn(doc.room.spawn_x_u, doc.room.spawn_y_u)
	doc.set_tile(0, 0, TileGrid.SOLID)
	assert_bool(doc.history.can_undo()).is_false()
	assert_bool(doc.dirty).is_false()
	doc.fill(Rect2i(0, 0, 1, 0), TileGrid.EMPTY)
	assert_bool(doc.history.can_undo()).is_true()
	assert_bool(doc.dirty).is_true()


func test_a_new_unsaved_room_is_marked_changed() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 20, 12)
	assert_bool(doc.dirty).is_true()
	doc.save()
	assert_bool(doc.dirty).is_false()
