extends GdUnitTestSuite
# unit-group: room-scratch
## The room editor's document: every edit, undo, validation and saving (CLAUDE.md: "Rooms are
## authored in the room editor plugin and stored as text"; docs/adr/0009, 0014, 0015).

const A_ID: String = "test/ed_scratch/a"
const B_ID: String = "test/ed_scratch/b"
const T: int = TileGrid.TILE


func after_test() -> void:
	var dir: String = ProjectSettings.globalize_path(RoomData.TEST_ROOT + "ed_scratch")
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)


# --- format ---------------------------------------------------------------------------------------


func test_a_new_room_is_valid_and_saves_text_that_loads_back() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	assert_array(doc.problems()).is_empty()
	assert_int(doc.save()).is_equal(OK)
	var back: RoomData = RoomData.load_id(A_ID)
	assert_array(back.errors).is_empty()
	assert_str(back.to_text()).is_equal(doc.text())
	assert_str(FileAccess.get_file_as_string(RoomData.path_for(A_ID))).is_equal(doc.text())
	assert_bool(doc.dirty).is_false()


func test_every_room_in_the_repository_opens_clean_and_saves_as_to_text_writes() -> void:
	var count: int = 0
	for root: String in [RoomData.CONTENT_ROOT, RoomData.TEST_ROOT]:
		for path: String in FileWalk.find(root, [".room"]):
			var doc: RoomDocument = RoomDocument.open(path)
			if path.get_file().begins_with("invalid_"):
				# Rooms made to fail to load (the loader's own tests): the editor shows why.
				assert_array(doc.problems()).override_failure_message(path).is_not_empty()
				continue
			assert_array(doc.problems()).override_failure_message(path).is_empty()
			# Saving writes the text the loader's own inverse writes, and that is stable.
			var again: RoomData = RoomData.parse(doc.text())
			assert_str(again.to_text()).override_failure_message(path).is_equal(doc.text())
			if root == RoomData.CONTENT_ROOT:
				var file: String = FileAccess.get_file_as_string(path)
				assert_str(doc.text()).override_failure_message(path).is_equal(file)
			count += 1
	assert_int(count).is_greater(100)


func test_comments_survive_an_edit_and_a_save() -> void:
	var text: String = (
		"# Before the room line.\n"
		+ "room %s\n# After it.\nsize 12 8\nspawn 96 192\ntiles\n" % A_ID
		+ "############\n#..........#\n#..........#\n#..........#\n"
		+ "#..........#\n#..........#\n############\n############\nend\n"
		+ "# Above the box.\nsolid 96 160 160 192 tag=pogo\n"
		+ "# Above the door.\ndoor east right 64 128 %s west\n" % A_ID
		+ "# Above the dummy.\nentity dummy 200 192 hp=3\n# The last words.\n"
	)
	var doc := RoomDocument.new(RoomData.parse(text), RoomData.path_for(A_ID))
	doc.set_tile(2, 2, TileGrid.SPIKES)
	var saved: String = doc.text()
	for note: String in [
		"# Before the room line.",
		"# After it.",
		"# Above the box.",
		"# Above the door.",
		"# Above the dummy.",
		"# The last words."
	]:
		assert_bool(saved.contains(note)).override_failure_message(note).is_true()
	assert_bool(saved.begins_with("# Before the room line.\nroom ")).is_true()
	# The comment stays with its own box after another box is added and the first one removed.
	doc.objects().add_solid(Rect2i(0, 0, 32, 32))
	doc.objects().remove_solid(0)
	assert_bool(doc.text().contains("# Above the box.")).is_false()


# --- tiles ----------------------------------------------------------------------------------------


func test_painting_filling_and_lines_cover_every_tile_kind() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	for kind: int in range(TileGrid.CHARS.length()):
		doc.set_tile(5 + kind, 5, kind)
	for kind: int in range(TileGrid.CHARS.length()):
		assert_int(doc.room.grid.get_tile(5 + kind, 5)).is_equal(kind)
	assert_int(doc.room.grid.get_tile(5 + TileGrid.PIT, 5)).is_equal(TileGrid.PIT)
	doc.fill(Rect2i(10, 10, 3, 2), TileGrid.ONE_WAY)
	for j: int in range(10, 13):
		for i: int in range(10, 14):
			assert_int(doc.room.grid.get_tile(i, j)).is_equal(TileGrid.ONE_WAY)
	doc.line(Vector2i(2, 2), Vector2i(8, 4), TileGrid.SPIKES)
	assert_int(doc.room.grid.get_tile(2, 2)).is_equal(TileGrid.SPIKES)
	assert_int(doc.room.grid.get_tile(8, 4)).is_equal(TileGrid.SPIKES)
	assert_int(doc.room.grid.get_tile(5, 3)).is_equal(TileGrid.SPIKES)
	# Out of bounds is ignored, not an error, and not an edit.
	var untouched: String = doc.text()
	doc.set_tile(99, 99, TileGrid.SOLID)
	assert_str(doc.text()).is_equal(untouched)
	doc.fill(Rect2i(38, 10, 9, 3), TileGrid.SPIKES)
	assert_int(doc.room.grid.get_tile(38, 11)).is_equal(TileGrid.SPIKES)
	assert_int(doc.room.grid.width).is_equal(40)


func test_a_pit_saves_and_loads_back() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	doc.fill(Rect2i(10, 18, 3, 1), TileGrid.PIT)
	assert_int(doc.save()).is_equal(OK)
	assert_int(RoomData.load_id(A_ID).grid.get_tile(11, 18)).is_equal(TileGrid.PIT)


func test_a_drag_is_one_undo_step_and_redo_restores_it() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	var text_before: String = doc.text()
	doc.history.begin_stroke()
	for i: int in range(3, 9):
		doc.set_tile(i, 6, TileGrid.SOLID)
	doc.history.end_stroke()
	var text_after: String = doc.text()
	doc.set_spawn(200, 544)
	doc.undo()
	assert_str(doc.text()).is_equal(text_after)
	doc.undo()
	assert_str(doc.text()).is_equal(text_before)
	assert_bool(doc.history.can_undo()).is_false()
	doc.redo()
	assert_str(doc.text()).is_equal(text_after)
	# A new edit clears the redo.
	doc.set_tile(1, 1, TileGrid.SOLID)
	assert_bool(doc.history.can_redo()).is_false()


func test_history_keeps_a_bounded_number_of_steps() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	for k: int in range(RoomHistory.DEPTH + 20):
		doc.set_tile(
			2 + k % 30, 3 + (k / 30) % 10, TileGrid.SOLID if k % 2 == 0 else TileGrid.EMPTY
		)
		doc.set_spawn(96 + k, 544)
	var steps: int = 0
	while doc.history.can_undo():
		doc.undo()
		steps += 1
	assert_int(steps).is_equal(RoomHistory.DEPTH)


# --- problems and saving --------------------------------------------------------------------------


func test_a_room_with_a_problem_is_not_saved() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	doc.set_spawn(5 * T, 10 * T)
	doc.set_tile(5, 9, TileGrid.SOLID)
	assert_array(doc.problems()).contains(["the spawn point (160, 320) is inside a wall"])
	assert_int(doc.save()).is_equal(ERR_INVALID_DATA)
	assert_bool(FileAccess.file_exists(RoomData.path_for(A_ID))).is_false()
	doc.set_tile(5, 9, TileGrid.EMPTY)
	assert_int(doc.save()).is_equal(OK)


func test_the_loaders_errors_are_the_documents_problems() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	# Geometry (ADR-0008): a slope must rest on walls.
	doc.set_tile(10, 5, TileGrid.SLOPE_R)
	var found: PackedStringArray = doc.problems()
	assert_bool(found.size() > 0 and found[0].begins_with("slope at column 10")).is_true()
	# An id that does not match the path.
	doc.set_tile(10, 5, TileGrid.EMPTY)
	doc.path = RoomData.path_for("test/ed_scratch/other")
	assert_str(doc.problems()[0]).contains("belongs at")


func test_a_solid_box_buried_in_the_floor_is_a_joins_problem() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	# The floor's top is y 576; a box whose top is 4 u under it is neither ground nor terrain.
	doc.objects().add_solid(Rect2i(200, 580, 100, 20))
	var found: PackedStringArray = doc.problems()
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("buried")
	assert_int(doc.save()).is_equal(ERR_INVALID_DATA)


func test_the_spawn_must_be_inside_the_room() -> void:
	var doc: RoomDocument = RoomDocument.create(A_ID, 40, 20)
	doc.set_spawn(-5, 100)
	assert_str(doc.problems()[0]).contains("outside the room")
	doc.set_spawn(100, 20 * T + 1)
	assert_str(doc.problems()[0]).contains("outside the room")
	doc.set_spawn(100, 18 * T)
	assert_array(doc.problems()).is_empty()


# --- install --------------------------------------------------------------------------------------


func test_the_plugin_is_installed_where_godot_finds_it_and_enabled() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://addons/room_editor/plugin.cfg")).is_equal(OK)
	assert_str(str(cfg.get_value("plugin", "script"))).is_equal("plugin.gd")
	var shim: GDScript = load("res://addons/room_editor/plugin.gd") as GDScript
	assert_object(shim).is_not_null()
	assert_str(shim.get_base_script().get_global_name()).is_equal("RoomEditorPlugin")
	var project := ConfigFile.new()
	assert_int(project.load("res://project.godot")).is_equal(OK)
	var enabled: PackedStringArray = project.get_value("editor_plugins", "enabled")
	assert_bool(enabled.has("res://addons/room_editor/plugin.cfg")).is_true()
