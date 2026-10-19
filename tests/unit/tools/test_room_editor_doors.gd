extends RoomEditorSuite
## The room editor's doors, drawn, moved, resized, edited and deleted the way the mouse and the
## inspector do it (docs/adr/0014, 0015).

# --- doors ----------------------------------------------------------------------------------------


func test_a_door_is_drawn_along_an_edge_carved_and_one_undo_removes_it() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.DOOR)
	# Dragged from y 330 to y 420 beside the right edge: whole tiles 10 to 14, a 128 u opening.
	_drag(Vector2(1260, 330), Vector2(1250, 420))
	var door: RoomData.Door = _doc().room.doors[0]
	assert_int(door.side).is_equal(RoomData.RIGHT)
	assert_int(door.from_u).is_equal(320)
	assert_int(door.to_u).is_equal(448)
	assert_str(door.name).is_equal("right")
	assert_int(_panel.canvas.selected_door).is_equal(0)
	assert_bool(_panel.door_section.visible).is_true()
	assert_array(_real()).is_empty()
	assert_int(_doc().room.grid.get_tile(39, 11)).is_equal(TileGrid.EMPTY)
	_doc().undo()
	assert_array(_doc().room.doors).is_empty()
	assert_int(_doc().room.grid.get_tile(39, 11)).is_equal(TileGrid.SOLID)


func test_a_door_on_each_side_and_at_least_two_tiles_long() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.DOOR)
	_click(Vector2(10, 300))
	_click(Vector2(500, 10))
	_click(Vector2(1000, 20 * T - 5))
	_click(Vector2(1270, 100))
	var sides: Array[int] = []
	for d: RoomData.Door in _doc().room.doors:
		sides.append(d.side)
		assert_int(d.span_u()).is_equal(2 * T)
	assert_array(sides).is_equal(
		[RoomData.LEFT, RoomData.TOP, RoomData.BOTTOM, RoomData.RIGHT] as Array[int]
	)
	# A door at the end of a side stays inside it.
	assert_int(_doc().room.doors[3].from_u).is_equal(96)
	_click(Vector2(1270, 600))
	assert_int(_doc().room.doors[4].to_u).is_equal(20 * T)


func test_an_inspector_name_the_text_cannot_hold_is_refused_and_the_field_goes_back() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.DOOR)
	_drag(Vector2(1260, 330), Vector2(1250, 420))
	_panel.door_name_edit.text = "east"
	_panel.door_name_edit.text_submitted.emit("east")
	for bad: String in ["", "ea st", "ea#st"]:
		_panel.door_name_edit.text = bad
		_panel.door_name_edit.text_submitted.emit(bad)
		assert_str(_doc().room.doors[0].name).is_equal("east")
		assert_str(_panel.door_name_edit.text).is_equal("east")
		assert_str(_panel.status.text).contains("one word")
	_panel.door_room_edit.text = "a b"
	_panel.door_target_edit.text = "west"
	_panel.door_target_edit.text_submitted.emit("west")
	assert_str(_panel.door_room_edit.text).is_equal("")
	assert_str(_doc().room.doors[0].target_room).is_equal(RoomDocument.UNSET)
	assert_array(_doc().room.errors).is_empty()
	_doc().undo()
	assert_int(_doc().room.doors.size()).is_equal(1)
	assert_str(_doc().room.doors[0].name).is_equal("right")


func test_a_doors_inspector_sets_its_name_side_opening_and_target() -> void:
	var partner: RoomDocument = RoomDocument.create(B_ID, 40, 20)
	var west: int = partner.doors().add(RoomData.LEFT, 320, 448, "west")
	partner.doors().carve(west)
	partner.doors().set_target(west, A_ID, "east")
	assert_int(partner.save()).is_equal(OK)
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.DOOR)
	_drag(Vector2(1260, 330), Vector2(1250, 420))
	_panel.door_name_edit.text = "east"
	_panel.door_name_edit.text_submitted.emit("east")
	_panel.door_room_edit.text = B_ID
	_panel.door_target_edit.text = "west"
	_panel.door_target_edit.text_submitted.emit("west")
	_panel.refresh()
	assert_str(_doc().text()).contains("door east right 320 448 %s west" % B_ID)
	assert_array(_doc().problems()).is_empty()
	assert_str(_panel.door_hint.text).contains("west (left, 4 tiles)")
	assert_bool(_panel.save_button.disabled).is_false()
	# Its opening in tiles: 11 to 14 is a 96 u door, which does not pair with the 128 u one.
	_panel.door_from_box.value = 11
	_panel.refresh()
	assert_str(_doc().problems()[0]).contains("is 96 u long")
	assert_array(_panel.canvas.flagged_doors).contains(["east"])
	_panel.door_from_box.value = 10
	assert_array(_doc().problems()).is_empty()
	# A side the door does not lead to a facing door on is a problem.
	_panel.door_side_picker.item_selected.emit(RoomData.TOP)
	assert_str(" ".join(_doc().problems())).contains("must be on the")


func test_a_door_is_selected_slid_and_resized_by_dragging_each_a_single_undo_step() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.DOOR)
	_drag(Vector2(1260, 330), Vector2(1250, 420))
	_tool(RoomCanvas.Tool.MOVE)
	_panel.canvas.zoom = 0.25
	# The middle of the opening slides it two tiles down, in tile steps (a drag has many events).
	var canvas: RoomCanvas = _panel.canvas
	canvas.press(MOUSE_BUTTON_LEFT, Vector2(1250, 384))
	for dy: int in range(0, 70, 7):
		canvas.drag_to(Vector2(1250, 384 + dy))
	canvas.release(MOUSE_BUTTON_LEFT, Vector2(1250, 450))
	assert_int(_doc().room.doors[0].from_u).is_equal(384)
	assert_int(_doc().room.doors[0].to_u).is_equal(512)
	_doc().undo()
	assert_int(_doc().room.doors[0].from_u).is_equal(320)
	# The ends resize it: the far end down two tiles, then the near end up one.
	_drag(Vector2(1250, 446), Vector2(1250, 510))
	assert_int(_doc().room.doors[0].to_u).is_equal(512)
	assert_int(_doc().room.doors[0].from_u).is_equal(320)
	_drag(Vector2(1250, 322), Vector2(1250, 290))
	assert_int(_doc().room.doors[0].from_u).is_equal(288)
	_doc().undo()
	_doc().undo()
	assert_int(_doc().room.doors[0].to_u).is_equal(448)
	# It never shrinks below two tiles or leaves its side.
	_drag(Vector2(1250, 446), Vector2(1250, 0))
	assert_int(_doc().room.doors[0].to_u).is_equal(320 + 2 * T)
	_drag(Vector2(1250, 380), Vector2(1250, 5000))
	assert_int(_doc().room.doors[0].to_u).is_equal(20 * T)


func test_a_door_is_deleted_with_the_right_button_the_key_or_the_button() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.DOOR)
	_drag(Vector2(1260, 330), Vector2(1250, 420))
	_click(Vector2(1250, 384), MOUSE_BUTTON_RIGHT)
	assert_array(_doc().room.doors).is_empty()
	_drag(Vector2(1260, 330), Vector2(1250, 420))
	_panel.canvas.delete_selected()
	assert_array(_doc().room.doors).is_empty()
	assert_bool(_panel.door_section.visible).is_false()
	_doc().undo()
	assert_int(_doc().room.doors.size()).is_equal(1)
	_doc().undo()
	assert_array(_doc().room.doors).is_empty()
	_doc().undo()
	assert_int(_doc().room.doors.size()).is_equal(1)


func test_a_door_that_is_not_carved_is_flagged_and_carving_clears_its_strip_problem() -> void:
	_panel.create(A_ID, 40, 20)
	_doc().doors().add(RoomData.RIGHT, 320, 448, "east")
	_panel.refresh()
	assert_array(_panel.canvas.flagged_doors).contains(["east"])
	assert_bool(_panel.save_button.disabled).is_true()
	_panel.canvas.selected_door = 0
	_panel._on_carve_door()
	_panel.refresh()
	assert_array(_real()).is_empty()
	assert_array(_panel.canvas.flagged_doors).contains(["east"])
	assert_str(_panel.problems_list.get_item_text(0)).contains("no target yet")


func test_undoing_the_selected_door_away_deselects_it() -> void:
	_panel.create(A_ID, 40, 20)
	_tool(RoomCanvas.Tool.DOOR)
	_drag(Vector2(1260, 330), Vector2(1250, 420))
	assert_int(_panel.canvas.selected_door).is_equal(0)
	_doc().undo()
	assert_int(_panel.canvas.selected_door).is_equal(-1)
	assert_bool(_panel.door_section.visible).is_false()
	_panel.canvas.delete_selected()
	assert_array(_doc().room.doors).is_empty()
