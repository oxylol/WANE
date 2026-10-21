extends SceneTree
## Renders a window of a room's grey-box drawing (tiles and solid boxes, as RoomView draws them)
## lit by the lighting pass to a PNG, to look at (needs a display: run it under xvfb with the
## opengl3 driver). BUILD.md section 10: judge it lit, at Dusk and at Pitch, never flat.
##
## godot --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1600x900 \
##     --script tools/replay/room_shot.gd -- <out.png> <room id>:<x>:<y>:<w>:<h> \
##     [--dark dusk|pitch] [--ember <x>:<y>]
##
## The spec is a room id and the window of it to show, in units. The Dark is held at the word's
## level (Dusk unless --dark says Pitch) and the ember stands at --ember (units; the window's centre
## unless given), frozen at tick 0 so a picture is reproducible ([method LightField.freeze]); no
## player is drawn. Nothing is written but the PNG.

const WIDTH: int = 1600
## Frames drawn before the picture is taken, once the room's distance field is baked.
const SETTLE_FRAMES: int = 4


func _initialize() -> void:
	_shoot.call_deferred()


func _shoot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var w: PackedStringArray = args[1].split(":") if args.size() >= 2 else PackedStringArray()
	var dark: String = _arg(args, "--dark", LightWord.DUSK)
	var ember_arg: PackedStringArray = _arg(args, "--ember", "").split(":", false)
	var ember_ok: bool = ember_arg.is_empty() or ember_arg.size() == 2
	if w.size() != 5 or not LightWord.is_word(dark) or not ember_ok:
		printerr(
			"usage: -- <out.png> <room id>:<x>:<y>:<w>:<h> [--dark dusk|pitch] [--ember <x>:<y>]"
		)
		quit(2)
		return
	var room: RoomData = RoomData.load_id(w[0])
	for e: String in room.errors:
		printerr("%s: %s" % [w[0], e])
	if not room.errors.is_empty():
		quit(1)
		return
	var window := Rect2(float(w[1]), float(w[2]), float(w[3]), float(w[4]))
	var zoom: float = WIDTH / window.size.x
	root.size = Vector2i(WIDTH, ceili(window.size.y * zoom))
	# The window through the view's own transform, as a camera would place it, so the lighting pass
	# sees the room in world units (its distance field and the shadow buffer are placed by it).
	root.canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, -window.position * zoom)
	var world: CollisionWorld = room.build_world()
	var view := RoomView.new()
	root.add_child(view)
	view.show_world(world, room.doors)
	var field := LightField.new()
	root.add_child(field)
	field.show_world(world, room.id)
	await field.settle()
	var ember: Vector2 = window.get_center()
	if ember_arg.size() == 2:
		ember = Vector2(float(ember_arg[0]), float(ember_arg[1]))
	field.freeze(0, field.tuning.dark_factor(LightWord.level_for(dark)))
	field.present(0, 0.0, ember)
	for _k: int in range(SETTLE_FRAMES):
		await RenderingServer.frame_post_draw
	var err: Error = root.get_viewport().get_texture().get_image().save_png(args[0])
	print("wrote %s (%s, ember at %s): %s" % [args[0], dark, ember, error_string(err)])
	quit(0 if err == OK else 1)


static func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i: int = args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback
