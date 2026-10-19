extends RoomEditorSuite
## The room editor's panel and canvas, driven the way the mouse and the palette drive them
## (Phase 1 task 7; docs/adr/0018): open, create, paint every tile kind, draw boxes, place the
## dummy and edit its properties, resize the room, save and play, every edit undoable.

# --- opening and creating -------------------------------------------------------------------------


func test_the_picker_lists_every_room_under_both_roots_and_their_subfolders() -> void:
	assert_int(_panel.room_picker.item_count).is_greater(100)
	var names: PackedStringArray = []
	for i: int in range(_panel.room_picker.item_count):
		names.append(_panel.room_picker.get_item_text(i))
	assert_bool(names.has("content/rooms/sandbox.room")).is_true()
	assert_bool(names.has("content/rooms/zone1/01_dash_slash.room")).is_true()
	assert_bool(names.has("tests/replay/rooms/door_a.room")).is_true()


func test_a_room_opens_from_the_picker_and_shows_its_doors_and_no_problems() -> void:
	_panel.open("res://content/rooms/zone1/01_dash_slash.room")
	assert_str(_doc().room.id).is_equal("zone1/01_dash_slash")
	assert_int(_doc().room.doors.size()).is_greater(0)
	assert_int(_panel.problems_list.item_count).is_equal(1)
	assert_str(_panel.problems_list.get_item_text(0)).contains("No problems")
	assert_bool(_panel.save_button.disabled).is_false()
	assert_str(_panel.room_picker.get_item_text(_panel.room_picker.selected)).contains(
		"zone1/01_dash_slash"
	)


func test_a_new_room_needs_a_fresh_valid_id() -> void:
	_panel.new_id_edit.text = "Bad Id"
	_panel._on_new()
	assert_object(_panel.document).is_null()
	assert_str(_panel.status.text).contains("lower-case")
	_panel.new_id_edit.text = "test/door_a"
	_panel._on_new()
	assert_object(_panel.document).is_null()
	assert_str(_panel.status.text).contains("already")
	_panel.new_id_edit.text = A_ID
	_panel.width_box.value = 30
	_panel.height_box.value = 16
	_panel._on_new()
	assert_int(_doc().room.grid.width).is_equal(30)
	assert_str(_doc().path).is_equal(RoomData.path_for(A_ID))


func test_switching_rooms_keeps_the_unsaved_edits_and_marks_them() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.PAINT)
	_tile(TileGrid.SPIKES)
	_click(_centre(10, 10))
	assert_str(_panel.room_picker.get_item_text(_panel.room_picker.selected)).ends_with("*")
	var edited: RoomDocument = _doc()
	_panel.open("res://content/rooms/sandbox.room")
	assert_str(_doc().room.id).is_equal("sandbox")
	_panel.open(RoomData.path_for(A_ID))
	assert_object(_doc()).is_same(edited)
	assert_int(_doc().room.grid.get_tile(10, 10)).is_equal(TileGrid.SPIKES)
	assert_bool(_doc().history.can_undo()).is_true()


# --- tiles ----------------------------------------------------------------------------------------


func test_a_drag_paints_a_continuous_stroke_that_undoes_in_one_step() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.PAINT)
	_tile(TileGrid.SOLID)
	# A fast drag skips tiles between events; the stroke still has no gaps.
	_drag(_centre(3, 5), _centre(12, 5))
	for i: int in range(3, 13):
		assert_int(_doc().room.grid.get_tile(i, 5)).is_equal(TileGrid.SOLID)
	_doc().undo()
	for i: int in range(3, 13):
		assert_int(_doc().room.grid.get_tile(i, 5)).is_equal(TileGrid.EMPTY)


func test_every_tile_kind_in_the_palette_paints_and_saves() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.PAINT)
	assert_int(_panel.tile_list.item_count).is_equal(TileGrid.CHARS.length())
	for kind: int in range(TileGrid.CHARS.length()):
		_tile(kind)
		_click(_centre(4 + kind, 4))
	for kind: int in range(TileGrid.CHARS.length()):
		assert_int(_doc().room.grid.get_tile(4 + kind, 4)).is_equal(kind)
	# The right button erases.
	_click(_centre(4 + TileGrid.PIT, 4), MOUSE_BUTTON_RIGHT)
	assert_int(_doc().room.grid.get_tile(4 + TileGrid.PIT, 4)).is_equal(TileGrid.EMPTY)


func test_rectangles_and_lines_fill_between_the_press_and_the_release() -> void:
	_panel.create(A_ID, 40, 20)
	_tile(TileGrid.ONE_WAY)
	_tool(RoomCanvas.Tool.RECT)
	_drag(_centre(10, 8), _centre(14, 9))
	for j: int in range(8, 10):
		for i: int in range(10, 15):
			assert_int(_doc().room.grid.get_tile(i, j)).is_equal(TileGrid.ONE_WAY)
	_tile(TileGrid.SPIKES)
	_tool(RoomCanvas.Tool.LINE)
	_drag(_centre(2, 2), _centre(8, 2))
	assert_int(_doc().room.grid.get_tile(5, 2)).is_equal(TileGrid.SPIKES)
	_doc().undo()
	assert_int(_doc().room.grid.get_tile(5, 2)).is_equal(TileGrid.EMPTY)
	assert_int(_doc().room.grid.get_tile(12, 8)).is_equal(TileGrid.ONE_WAY)


# --- boxes, entities, spawn -----------------------------------------------------------------------


func test_solid_boxes_are_drawn_with_a_tag_selected_edited_moved_and_erased() -> void:
	_panel.create(A_ID, 40, 20)
	_panel.tag_edit.text_changed.emit("pogo")
	_tool(RoomCanvas.Tool.SOLID)
	_drag(Vector2(160, 480), Vector2(224, 576))
	assert_int(_doc().room.solids.size()).is_equal(1)
	assert_str(_doc().room.solids[0].tag).is_equal("pogo")
	assert_int(_panel.canvas.selected_solid).is_equal(0)
	assert_bool(_panel.solid_section.visible).is_true()
	assert_str(_panel.solid_tag_edit.text).is_equal("pogo")
	# The inspector turns the wall-cling off and renames the tag.
	_panel.solid_tag_edit.text = "wax"
	_panel.solid_tag_edit.text_submitted.emit("wax")
	_panel.solid_cling_box.button_pressed = false
	assert_str(_doc().text()).contains("solid 160 480 224 576 tag=wax cling=0")
	# Select and move: a drag of two tiles.
	_tool(RoomCanvas.Tool.MOVE)
	_drag(Vector2(190, 520), Vector2(222, 520))
	assert_str(_doc().text()).contains("solid 192 480 256 576 tag=wax cling=0")
	_panel.canvas.delete_selected()
	assert_array(_doc().room.solids).is_empty()
	_doc().undo()
	_click(Vector2(220, 520), MOUSE_BUTTON_RIGHT)
	assert_array(_doc().room.solids).is_empty()


func test_a_slow_jittery_drag_leaves_the_box_on_the_pointers_snapped_travel() -> void:
	# The pointer's remainder below the half-tile snap is never lost: however the drag is split,
	# the box ends where the snapped pointer is, relative to where the drag began.
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.SOLID)
	_drag(Vector2(160, 480), Vector2(224, 576))
	_tool(RoomCanvas.Tool.MOVE)
	_panel.canvas.press(MOUSE_BUTTON_LEFT, Vector2(190, 520))
	for x: float in [196.0, 200.0, 207.0, 213.0, 205.0, 211.0, 219.0, 222.0]:
		_panel.canvas.drag_to(Vector2(x, 520))
	_panel.canvas.release(MOUSE_BUTTON_LEFT, Vector2(222, 520))
	assert_str(_doc().text()).contains("solid 192 480 256 576")


func test_the_tag_and_kind_fields_keep_only_words() -> void:
	_panel.create(A_ID, 40, 20)
	_panel.tag_edit.text_changed.emit("pogo")
	_panel.tag_edit.text_changed.emit("po go")
	assert_str(_panel.canvas.solid_tag).is_equal("pogo")
	assert_str(_panel.status.text).contains("one word")
	_panel.kind_edit.text_changed.emit("")
	assert_str(_panel.canvas.entity_kind).is_equal("dummy")
	_tool(RoomCanvas.Tool.ENTITY)
	_click(Vector2(300, 300))
	assert_int(_doc().room.entities.size()).is_equal(1)


func test_the_dummy_is_placed_and_its_properties_are_edited_from_the_form() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.ENTITY)
	_click(Vector2(704, 576))
	assert_str(_doc().room.entities[0].kind).is_equal("dummy")
	assert_bool(_panel.entity_section.visible).is_true()
	assert_int(_panel.entity_controls.size()).is_equal(7)
	(_panel.entity_controls["attack"] as CheckBox).button_pressed = true
	(_panel.entity_controls["period"] as SpinBox).value = 45
	(_panel.entity_controls["hp"] as SpinBox).value = 12
	var facing: OptionButton = _panel.entity_controls["facing"] as OptionButton
	facing.select(2)
	facing.item_selected.emit(2)
	assert_str(_doc().text()).contains("entity dummy 704 576 attack=1 facing=1 hp=12 period=45")
	assert_array(_doc().problems()).is_empty()
	# Back to the content's defaults: a property that is off is not written.
	(_panel.entity_controls["attack"] as CheckBox).button_pressed = false
	(_panel.entity_controls["hp"] as SpinBox).value = 0
	assert_str(_doc().text()).contains("entity dummy 704 576 facing=1 period=45\n")
	# The form shows what the text says.
	_panel.entity_props_edit.text_submitted.emit("red=1 poise=9")
	_panel.refresh()
	assert_bool((_panel.entity_controls["red"] as CheckBox).button_pressed).is_true()
	assert_int(int((_panel.entity_controls["poise"] as SpinBox).value)).is_equal(9)
	assert_bool((_panel.entity_controls["attack"] as CheckBox).button_pressed).is_false()
	# Select and move it two tiles; one undo puts it back, and Delete removes it.
	_tool(RoomCanvas.Tool.MOVE)
	_drag(Vector2(706, 578), Vector2(770, 578))
	assert_int(_doc().room.entities[0].x_u).is_equal(768)
	_doc().undo()
	assert_int(_doc().room.entities[0].x_u).is_equal(704)
	var key := InputEventKey.new()
	key.keycode = KEY_DELETE
	key.pressed = true
	_panel.canvas._gui_input(key)
	assert_array(_doc().room.entities).is_empty()
	assert_bool(_panel.entity_section.visible).is_false()


func test_the_spawn_tool_places_the_spawn_and_a_spawn_in_a_wall_is_a_problem() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.SPAWN)
	_click(Vector2(480, 576))
	assert_int(_doc().room.spawn_x_u).is_equal(480)
	assert_int(_doc().room.spawn_y_u).is_equal(576)
	_click(Vector2(480, 640))
	assert_str(_panel.problems_list.get_item_text(0)).contains("inside a wall")
	assert_bool(_panel.save_button.disabled).is_true()


# --- size, saving, playing ------------------------------------------------------------------------


func test_resizing_from_the_toolbar_keeps_the_room_valid() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.DOOR)
	_drag(Vector2(1260, 330), Vector2(1250, 420))
	_panel.width_box.value = 50
	_panel.height_box.value = 24
	_panel.anchor_picker.select(1)
	_panel._on_resize()
	assert_int(_doc().room.grid.width).is_equal(50)
	assert_int(_doc().room.grid.height).is_equal(24)
	assert_array(_real()).is_empty()
	assert_int(_doc().room.doors[0].from_u).is_equal(320 + 4 * T)
	_doc().undo()
	assert_int(_doc().room.grid.width).is_equal(40)


func test_save_is_refused_with_problems_and_play_asks_the_editor_to_run_the_saved_room() -> void:
	var played: Array[String] = []
	_panel.play_requested.connect(func(id: String) -> void: played.append(id))
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.SPAWN)
	_click(Vector2(480, 640))
	assert_int(_panel.save()).is_equal(ERR_INVALID_DATA)
	_panel._on_play()
	assert_array(played).is_empty()
	assert_str(_panel.status.text).contains("Fix the problems")
	assert_bool(FileAccess.file_exists(RoomData.path_for(A_ID))).is_false()
	_doc().undo()
	_panel._on_play()
	assert_array(played).is_equal([A_ID] as Array[String])
	assert_bool(FileAccess.file_exists(RoomData.path_for(A_ID))).is_true()
	assert_bool(_doc().dirty).is_false()
	# The new room is in the picker, no longer marked.
	assert_str(_panel.room_picker.get_item_text(_panel.room_picker.selected)).is_equal(
		"tests/replay/rooms/ed_scratch/a.room"
	)


func test_the_hover_line_names_the_tile_under_the_pointer() -> void:
	_panel.create(A_ID, 40, 20)
	_panel.canvas.drag_to(_centre(0, 0))
	assert_str(_panel.status.text).contains("tile 0, 0 (Wall)")
	_panel.canvas.drag_to(_centre(5, 5))
	assert_str(_panel.status.text).contains("tile 5, 5 (Empty)")
