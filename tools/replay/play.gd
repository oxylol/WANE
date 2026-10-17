extends SceneTree
## Plays replay fixtures and writes a contact sheet (CLAUDE.md working method: "play the fixture
## and capture a contact sheet"). One panel per fixture: the room around the player's whole path,
## the player's box every few frames coloured by state, its foot point every frame, and the frame
## number at every event (jump, land, dash, pogo, wall-kick and the rest).
##
##   godot --headless --path . --script tools/replay/play.gd -- <out.png> [options] <fixture>...
##
## Options, read in order with the fixtures:
##   --every N                       draw the box every N frames (default 6)
##   --set <res path>:<prop>=<int>   change a tuning value for the fixtures that follow (to show
##                                   a feel-log "before" next to its "after")
##   --plot                          add a last panel: every run's height over time, overlaid
##
## States: ground blue, air yellow, dash magenta, wall green. Event frames are drawn white; the
## ember is orange; a solid broken during the run is outlined. In the
## plot, run 1 is blue, 2 orange, 3 green, 4 pink; ticks mark events.

const STATE_COLOURS: Dictionary[String, Color] = {
	"ground": Color(0.35, 0.7, 1.0),
	"air": Color(1.0, 0.85, 0.35),
	"dash": Color(1.0, 0.35, 0.85),
	"wall": Color(0.4, 1.0, 0.5),
}
const EVENT_KINDS: Array[String] = [
	"jump",
	"air_jump",
	"wall_jump",
	"wall_kick",
	"land",
	"dash",
	"pogo",
	"ledge_grab",
	"teleport",
	"ignite",
	"hazard",
	"wall_cling",
	"attack",
	"toss",
]
const RUN_COLOURS: Array[Color] = [
	Color(0.35, 0.7, 1.0), Color(1.0, 0.6, 0.25), Color(0.45, 1.0, 0.5), Color(1.0, 0.45, 0.8)
]
const EMBER := Color(1.0, 0.55, 0.15)
const MARGIN_U: int = 40
const MIN_REGION: Vector2i = Vector2i(400, 200)
const MAX_WIDTH_PX: int = 1920
## Plot scale: pixels per frame and per unit of height.
const PLOT_PX_PER_FRAME: int = 6
const PLOT_PX_PER_UNIT: int = 2

## Every run so far, for the plot.
var _runs: Array[Run] = []
## Resources changed by --set, held so the resource cache keeps the changed copies.
var _held: Array[Resource] = []


class Sample:
	var box: Rect2i
	var foot: Vector2i
	## The ember (Ash's toss), if it is out.
	var ember: bool = false
	var ember_at: Vector2i
	var state: String = ""
	var events: PackedStringArray = PackedStringArray()


class Run:
	var samples: Array[Sample] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: play.gd -- <out.png> [options] <fixture>...")
		quit(2)
		return
	var out: String = args[0]
	var every: int = 6
	var plot: bool = false
	var panels: Array[Image] = []
	var i: int = 1
	while i < args.size():
		var a: String = args[i]
		if a == "--every" and i + 1 < args.size():
			every = maxi(1, args[i + 1].to_int())
			i += 2
		elif a == "--set" and i + 1 < args.size():
			if not _set_tuning(args[i + 1]):
				quit(2)
				return
			i += 2
		elif a == "--plot":
			plot = true
			i += 1
		else:
			var panel: Image = _play(a, every, panels.size() + 1)
			if panel == null:
				quit(1)
				return
			panels.append(panel)
			i += 1
	if plot:
		panels.append(_plot_panel(panels.size() + 1))
	var img: Image = ContactSheet.sheet(panels, 1)
	var err: Error = img.save_png(out)
	print("wrote %s (%dx%d): %s" % [out, img.get_width(), img.get_height(), error_string(err)])
	quit(0 if err == OK else 1)


## Applies "res://path.tres:property=value" to the loaded (cached) resource, so the next
## simulations built from that path use it.
func _set_tuning(spec: String) -> bool:
	var colon: int = spec.rfind(":")
	var eq: int = spec.find("=", colon)
	if colon <= 0 or eq < 0:
		printerr("--set needs <res path>:<property>=<int>, got '%s'" % spec)
		return false
	var res: Resource = load(spec.substr(0, colon))
	var prop: String = spec.substr(colon + 1, eq - colon - 1)
	if res == null or not prop in res:
		printerr("--set: no property '%s' on %s" % [prop, spec.substr(0, colon)])
		return false
	res.set(prop, spec.substr(eq + 1).to_int())
	_held.append(res)
	print("set %s" % spec)
	return true


## Runs one fixture and draws its panel, labelled [param label].
func _play(path: String, every: int, label: int) -> Image:
	var fx: Fixture = Fixture.parse_file(path)
	for e: String in fx.errors:
		printerr("%s: %s" % [path, e])
	var sim := Simulation.new(fx.scenario)
	for e: String in sim.load_errors:
		printerr("%s: %s" % [path, e])
	if not fx.errors.is_empty() or not sim.load_errors.is_empty() or sim.player == null:
		return null
	var samples: Array[Sample] = []
	var bounds := Rect2i()
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		var b: Body = sim.player.body
		var s := Sample.new()
		s.box = ContactSheet.box_rect(b.x, b.y, b.half_w, b.height)
		s.foot = Vector2i(Fx.div_floor(b.x, Fx.SUB), Fx.div_floor(b.y, Fx.SUB))
		s.state = str(sim.probe("state"))
		s.ember = sim.player.toss.active
		s.ember_at = Vector2i(
			Fx.div_floor(sim.player.toss.x, Fx.SUB), Fx.div_floor(sim.player.toss.y, Fx.SUB)
		)
		for kind: String in EVENT_KINDS:
			if sim.events.has(kind):
				s.events.append(kind)
		samples.append(s)
		bounds = s.box if f == 0 else bounds.merge(s.box)
	var run := Run.new()
	run.samples = samples
	_runs.append(run)
	var room_px := Vector2i(sim.world.grid.width, sim.world.grid.height) * TileGrid.TILE
	var region: Rect2i = bounds.grow(MARGIN_U)
	var short: Vector2i = (MIN_REGION - region.size).max(Vector2i.ZERO)
	region = region.grow_individual(
		short.x / 2, short.y / 2, short.x - short.x / 2, short.y - short.y / 2
	)
	region = region.intersection(Rect2i(Vector2i.ZERO, room_px))
	var scale: int = clampi(MAX_WIDTH_PX / maxi(1, region.size.x), 1, 3)
	var cs := ContactSheet.new(sim.world, scale)
	var img: Image = cs.room_image(region)
	for k: int in range(samples.size()):
		var s: Sample = samples[k]
		cs.fill(img, region, Rect2i(s.foot - Vector2i(0, 1), Vector2i(1, 1)), Color(1, 1, 1, 0.6))
		if s.ember:
			cs.fill(img, region, Rect2i(s.ember_at - Vector2i(1, 1), Vector2i(3, 3)), EMBER)
		var eventful: bool = not s.events.is_empty()
		if k % every == 0 or eventful or k == samples.size() - 1:
			var col: Color = STATE_COLOURS.get(s.state, Color.GRAY)
			cs.outline(img, region, s.box, Color.WHITE if eventful else col)
			if eventful:
				var at: Vector2i = (s.box.position - region.position) * scale + Vector2i(0, -14)
				ContactSheet.digits(img, at, k, Color.WHITE, 2)
	ContactSheet.digits(img, Vector2i(8, 8), label, ContactSheet.TEXT, 4)
	print("%d: %s, %d frames" % [label, fx.name, fx.frame_total])
	return img


## Height over time for every run so far, overlaid: one pixel column per frame step, the feet's
## height above the run's lowest point upward, ticks and frame numbers at events.
func _plot_panel(label: int) -> Image:
	var frames: int = 0
	var lowest: int = -(1 << 30)
	var highest: int = 1 << 30
	for run: Run in _runs:
		frames = maxi(frames, run.samples.size())
		for sample: Sample in run.samples:
			lowest = maxi(lowest, sample.foot.y)
			highest = mini(highest, sample.foot.y)
	var pad: int = 24
	var w: int = frames * PLOT_PX_PER_FRAME + pad * 2
	var h: int = maxi(120, (lowest - highest) * PLOT_PX_PER_UNIT + pad * 2)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(ContactSheet.BG)
	# Gridlines every 32 u (a tile) and every 10 frames.
	var y_u: int = 0
	while lowest - y_u >= highest:
		var py: int = h - pad - y_u * PLOT_PX_PER_UNIT
		img.fill_rect(Rect2i(pad, py, w - pad * 2, 1), ContactSheet.GRID.lightened(0.15))
		y_u += TileGrid.TILE
	for f: int in range(0, frames, 10):
		img.fill_rect(Rect2i(pad + f * PLOT_PX_PER_FRAME, pad, 1, h - pad * 2), ContactSheet.GRID)
	for r: int in range(_runs.size()):
		var col: Color = RUN_COLOURS[r % RUN_COLOURS.size()]
		var run: Run = _runs[r]
		for f: int in range(run.samples.size()):
			var sample: Sample = run.samples[f]
			var px := Vector2i(
				pad + f * PLOT_PX_PER_FRAME, h - pad - (lowest - sample.foot.y) * PLOT_PX_PER_UNIT
			)
			img.fill_rect(Rect2i(px - Vector2i(1, 1), Vector2i(3, 3)), col)
			if not sample.events.is_empty():
				img.fill_rect(Rect2i(px.x, px.y + 4, 1, 8), Color.WHITE)
	ContactSheet.digits(img, Vector2i(8, 8), label, ContactSheet.TEXT, 4)
	return img
