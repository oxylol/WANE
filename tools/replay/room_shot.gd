extends SceneTree
## Renders a window of a room's grey-box drawing (tiles and solid boxes, as RoomView draws them)
## to a PNG, to look at (needs a display: run it under xvfb with the opengl3 driver).
##
## godot --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1600x900 \
##     --script tools/replay/room_shot.gd -- <out.png> <room id>:<x>:<y>:<w>:<h>
##
## The spec is a room id and the window of it to show, in units. Nothing is written but the PNG.

const WIDTH: int = 1600


func _initialize() -> void:
	_shoot.call_deferred()


func _shoot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("usage: -- <out.png> <room id>:<x>:<y>:<w>:<h>")
		quit(2)
		return
	var w: PackedStringArray = args[1].split(":")
	var window := Rect2(float(w[1]), float(w[2]), float(w[3]), float(w[4]))
	var zoom: float = WIDTH / window.size.x
	root.size = Vector2i(WIDTH, ceili(window.size.y * zoom))
	var room: RoomData = RoomData.load_id(w[0])
	var view := RoomView.new()
	var holder := Node2D.new()
	holder.scale = Vector2(zoom, zoom)
	holder.position = -window.position * zoom
	holder.add_child(view)
	root.add_child(holder)
	view.show_world(room.build_world(), room.doors)
	for _k: int in range(4):
		await RenderingServer.frame_post_draw
	var err: Error = root.get_viewport().get_texture().get_image().save_png(args[0])
	quit(0 if err == OK else 1)
