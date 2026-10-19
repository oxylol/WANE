extends SceneTree
## Renders the room editor's panel on a room to a PNG, to look at it (needs a display: run it
## under xvfb with the opengl3 driver, see tools/README.md).
##
## godot --path . --rendering-driver opengl3 --script tools/room_editor/screenshot.gd -- \
##     <out.png> <room id> [door <name> | dummy | solid]
##
## The room is opened as the editor opens it; with `door <name>` that door is selected, with
## `dummy` a training dummy with properties is added (not saved) and selected, with `solid` a
## tagged box is. Nothing is written but the PNG.

const SIZE := Vector2i(1700, 900)


func _initialize() -> void:
	_shoot.call_deferred()


func _shoot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <out.png> <room id> [door <name> | dummy | solid]")
		quit(2)
		return
	root.size = SIZE
	var panel := RoomEditorPanel.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.build()
	panel.open(RoomData.path_for(args[1]))
	_select(panel, args.slice(2))
	await RenderingServer.frame_post_draw
	panel.canvas.fit()
	panel.refresh()
	for _k: int in range(4):
		await RenderingServer.frame_post_draw
	var err: Error = root.get_viewport().get_texture().get_image().save_png(args[0])
	quit(0 if err == OK else 1)


func _select(panel: RoomEditorPanel, what: PackedStringArray) -> void:
	if what.is_empty():
		return
	var doc: RoomDocument = panel.document
	var canvas: RoomCanvas = panel.canvas
	if what[0] == "door":
		for i: int in range(doc.room.doors.size()):
			if doc.room.doors[i].name == what[1]:
				canvas.select_door(i)
	elif what[0] == "dummy":
		var props: Dictionary[String, String] = {"attack": "1", "period": "60", "facing": "1"}
		var at := Vector2i(doc.room.spawn_x_u + 256, doc.room.spawn_y_u)
		canvas.select_entity(doc.objects().add_entity("dummy", at.x, at.y, props))
	elif what[0] == "solid":
		var base := Rect2i(doc.room.spawn_x_u + 320, doc.room.spawn_y_u - 96, 64, 96)
		canvas.select_solid(doc.objects().add_solid(base, "pogo"))
