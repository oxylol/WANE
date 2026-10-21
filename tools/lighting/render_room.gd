extends SceneTree
## Renders a room (or a fixture's frame) lit by the lighting pass at chosen Dark factors, through
## the game's own scene (CLAUDE.md working method, step 5: look at it; BUILD.md section 10,
## Lighting: judge every render at Dusk and at Pitch). The tick and the Dark are frozen
## ([method LightField.freeze]) so a render is reproducible (docs/adr/0023 Decision 6.3).
##
## It renders, so it needs a display; headless machines run it under a virtual one:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 --script tools/lighting/render_room.gd -- \
##     <out prefix> (--room <room id> | --fixture <path>) [--tick N] [--dark dusk|pitch|both|F] \
##     [--scale S] [--debug]
##
## Writes <out prefix>_dusk.png and <out prefix>_pitch.png (or _dark<F>.png for a factor F), each
## the 1920 x 1080 view divided by --scale (default 1). --room starts Ash at the room's spawn;
## --fixture plays the fixture's scenario and input for --tick ticks (default: all of it).
## --debug also writes the shadow buffer (_shadow.png: R the ember, G, B, A the other casters) and
## the room's distance field (_sdf.png, grey, wall interiors blue, 0.0 on the zero contour).
##
## A room that is not there, or does not load, is an error: the problems are printed, the exit
## status is 1 and no picture is written (the first fix round's room pictures were an empty world
## because "zone1/01" is not a room id; the ids are the file names under content/rooms/zone1/).
## A usage mistake exits 2.

const SCENE: String = "res://game/main.tscn"
const SETTLE: int = 3

var _out: String = ""
var _scale: int = 1
var _debug: bool = false
var _factors: Array[float] = []
var _names: Array[String] = []


## The scripted player: the fixture's input for the tick being stepped.
class ScriptedInput:
	extends InputLayer
	var fixture: Fixture
	var index: int = 0

	func poll() -> InputFrame:
		return fixture.input_frame(index) if fixture != null else InputFrame.new()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: render_room.gd -- <out prefix> (--room id | --fixture path) [options]")
		quit(2)
		return
	_out = args[0]
	var room: String = _arg(args, "--room", "")
	var fixture_path: String = _arg(args, "--fixture", "")
	if (room == "") == (fixture_path == ""):
		printerr("render_room: give exactly one of --room <room id> and --fixture <path>")
		quit(2)
		return
	var tick: int = int(_arg(args, "--tick", "-1"))
	_scale = maxi(1, int(_arg(args, "--scale", "1")))
	_debug = args.has("--debug")
	var dark: String = _arg(args, "--dark", "both")
	var tuning := load(LightingTuning.PATH) as LightingTuning
	if dark == "both" or dark == "dusk":
		_factors.append(tuning.dark_factor(LightWord.DUSK_LEVEL))
		_names.append("dusk")
	if dark == "both" or dark == "pitch":
		_factors.append(tuning.dark_factor(LightWord.PITCH_LEVEL))
		_names.append("pitch")
	if dark.is_valid_float():
		_factors.append(dark.to_float())
		_names.append("dark%s" % dark)
	if _factors.is_empty():
		printerr("render_room: --dark is dusk, pitch, both or a number, not '%s'" % dark)
		quit(2)
		return
	var fixture: Fixture = null
	if fixture_path != "":
		fixture = Fixture.parse_file(fixture_path)
		for e: String in fixture.errors:
			printerr("%s: %s" % [fixture_path, e])
		if not fixture.errors.is_empty():
			quit(1)
			return
		Main.scenario_override = fixture.scenario.copy()
	else:
		Main.scenario_override = Scenario.make(1, room)
	Main.lighting_word = LightWord.DUSK
	_run.call_deferred(fixture, tick)


func _run(fixture: Fixture, tick: int) -> void:
	var main := (load(SCENE) as PackedScene).instantiate() as Main
	main.save_on_exit = false
	root.add_child(main)
	var driver: SimDriver = main.get_node("SimDriver")
	driver.set_process(false)
	var problems: PackedStringArray = _load_problems(driver.sim)
	if not problems.is_empty():
		for problem: String in problems:
			printerr("render_room: %s" % problem)
		quit(1)
		return
	var input := ScriptedInput.new()
	input.fixture = fixture
	driver.input_layer = input
	var total: int = 0
	if fixture != null:
		total = fixture.frame_total if tick < 0 else mini(tick, fixture.frame_total)
	for i: int in range(total):
		input.index = i
		driver.step_once()
	driver.alpha = 1.0
	var field: LightField = main.lighting
	await field.settle()
	for k: int in range(_factors.size()):
		field.freeze(driver.sim.tick, _factors[k])
		for s: int in range(SETTLE):
			await RenderingServer.frame_post_draw
		var shot: Image = root.get_viewport().get_texture().get_image()
		if _scale > 1:
			shot.resize(
				shot.get_width() / _scale, shot.get_height() / _scale, Image.INTERPOLATE_BILINEAR
			)
		var path: String = "%s_%s.png" % [_out, _names[k]]
		print(
			(
				"wrote %s (%dx%d): %s"
				% [path, shot.get_width(), shot.get_height(), error_string(shot.save_png(path))]
			)
		)
	if _debug:
		_dump(field)
	quit(0)


## What is wrong with the room [param sim] started in: anything it failed to load, no room named,
## or no Ash to stand in it. Empty when the picture will show the room that was asked for.
static func _load_problems(sim: Simulation) -> PackedStringArray:
	var problems: PackedStringArray = sim.load_errors.duplicate()
	if sim.scenario.room == "":
		problems.append("the scenario names no room, so there is no world to draw")
	elif sim.room.id != sim.scenario.room:
		problems.append("started in '%s', not in '%s'" % [sim.room.id, sim.scenario.room])
	if sim.player == null:
		problems.append("no player: the room has no spawn")
	return problems


func _dump(field: LightField) -> void:
	var buf: Image = field.shadow_buffer().texture().get_image()
	print("wrote %s_shadow.png: %s" % [_out, error_string(buf.save_png(_out + "_shadow.png"))])
	var sdf: RoomSdf = field.shown_field()
	if sdf == null or sdf.image == null:
		return
	var w: int = sdf.size_px.x
	var h: int = sdf.size_px.y
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y: int in range(h):
		for x: int in range(w):
			var d: float = sdf.image.get_pixel(x, y).r
			var v: float = clampf(1.0 - absf(d) / 160.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(v * 0.3, v * 0.3, 1.0) if d < 0.0 else Color(v, v, v))
	print("wrote %s_sdf.png: %s" % [_out, error_string(img.save_png(_out + "_sdf.png"))])


static func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i: int = args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback
