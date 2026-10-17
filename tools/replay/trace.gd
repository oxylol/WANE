extends SceneTree
## Prints a frame-by-frame table of probe values for a fixture, for tuning and debugging.
##
##   godot --headless --path . --script tools/replay/trace.gd -- <fixture path> <key>...
##
## Positions and velocities print in units (sub-pixels / 256, two decimals).

const UNIT_KEYS: Array[String] = ["x", "y", "vx", "vy", "nudge_x", "nudge_y", "ember_x", "ember_y"]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: trace.gd -- <fixture path> <key>...")
		quit(2)
		return
	var fx: Fixture = Fixture.parse_file(args[0])
	for e: String in fx.errors:
		printerr("parse: %s" % e)
	var sim := Simulation.new(fx.scenario)
	for e: String in sim.load_errors:
		printerr("load: %s" % e)
	var keys: PackedStringArray = args.slice(1)
	print("frame  input        " + "  ".join(keys))
	for i: int in range(fx.frame_total):
		var frame: InputFrame = fx.input_frame(i)
		sim.step(frame)
		var cells: PackedStringArray = []
		for key: String in keys:
			var v: Variant = sim.probe(key)
			if typeof(v) == TYPE_INT and UNIT_KEYS.has(key):
				var iv: int = v
				cells.append("%.2f" % (float(iv) / float(Fx.SUB)))
			else:
				cells.append(str(v))
		print("%5d  %-12s %s" % [i, frame.describe(), "  ".join(cells)])
	quit(0)
