extends SceneTree
## Films replay fixtures through the game's own views (the grey-box room, the player and the
## camera) and writes a filmstrip: a row of frames per fixture, one every few ticks, each the
## full 1920 x 1080 view scaled down, with the camera drawn over it: the 80 u margin (red), the
## dead zone around the point the follow holds to (green) and the focus it aims at, that point
## plus the looks (yellow); a white ring marks the player, who is small at sheet scale. This is
## what the player sees, so it is how camera changes are judged
## (CLAUDE.md working method: "play the fixture and capture a contact sheet").
##
## It renders, so it needs a display; headless machines run it under a virtual one:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 --script tools/replay/film.gd -- \
##     <out.png> [--every N] [--from F] [--frames K] [--scale S] <fixture>...
##
## Options apply to the fixtures after them: --every N films every N-th tick (default 10),
## --from F starts at tick F and --frames K films K frames (default 12) per fixture, --scale S
## divides the frame size (default 6). Frame numbers are drawn top left, the fixture's number
## at the start of its row.
##
## Each row ends with the player's track on screen over every tick of the fixture: where the
## centre of the player's box sat across the view (blue) and down it (orange), from the view's
## left or top edge (top of the chart) to its right or bottom edge (bottom), two pixels a tick.
## The shaded bands are where the box's centre would bring its edge to the 80 u margin: the
## darker inner band across the view (blue), the whole band down it (orange). The filmed ticks
## are marked white.

const MARGIN := Color(1.0, 0.3, 0.3, 0.9)
const DEAD_ZONE := Color(0.4, 1.0, 0.5, 0.9)
const FOCUS := Color(1.0, 0.85, 0.3)
const RING := Color(1.0, 1.0, 1.0, 0.85)
const GAP_PX: int = 4
const TRACK_X := Color(0.35, 0.7, 1.0)
const TRACK_Y := Color(1.0, 0.6, 0.25)
const BAND := Color(0.5, 0.15, 0.15, 0.5)
const TRACK_PX_PER_TICK: int = 2

var _rows: Array[Image] = []


## Draws the camera's working over the world.
class Overlay:
	extends Node2D

	var rig: CameraRig
	var player: Rect2 = Rect2()

	func _draw() -> void:
		var t: CameraTuning = rig.tuning
		var view: Rect2 = rig.view_rect()
		draw_rect(view.grow(-t.edge_margin_u), MARGIN, false, 3.0)
		var dead := Vector2(t.dead_zone_w_u, t.dead_zone_h_u)
		draw_rect(Rect2(rig.anchor() - dead * 0.5, dead), DEAD_ZONE, false, 3.0)
		draw_circle(rig.focus, 7.0, FOCUS)
		if player.size != Vector2.ZERO:
			draw_arc(player.get_center(), 64.0, 0.0, TAU, 48, RING, 8.0)


func _initialize() -> void:
	_film.call_deferred()


func _film() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: film.gd -- <out.png> [options] <fixture>...")
		quit(2)
		return
	var every: int = 10
	var from: int = 0
	var count: int = 12
	var shrink: int = 6
	var i: int = 1
	while i < args.size():
		var a: String = args[i]
		var has_value: bool = i + 1 < args.size()
		if a == "--every" and has_value:
			every = maxi(1, args[i + 1].to_int())
			i += 2
		elif a == "--from" and has_value:
			from = maxi(0, args[i + 1].to_int())
			i += 2
		elif a == "--frames" and has_value:
			count = maxi(1, args[i + 1].to_int())
			i += 2
		elif a == "--scale" and has_value:
			shrink = maxi(1, args[i + 1].to_int())
			i += 2
		else:
			var row: Image = await _film_one(a, every, from, count, shrink)
			if row == null:
				quit(1)
				return
			_rows.append(row)
			i += 1
	var img: Image = ContactSheet.sheet(_rows, 1)
	var err: Error = img.save_png(args[0])
	print("wrote %s (%dx%d): %s" % [args[0], img.get_width(), img.get_height(), error_string(err)])
	quit(0 if err == OK else 1)


func _film_one(path: String, every: int, from: int, count: int, shrink: int) -> Image:
	var fx: Fixture = Fixture.parse_file(path)
	var sim := Simulation.new(fx.scenario)
	var problems: PackedStringArray = fx.errors.duplicate()
	problems.append_array(sim.load_errors)
	for p: String in problems:
		printerr("%s: %s" % [path, p])
	if not problems.is_empty() or sim.player == null:
		return null
	var stage := Node2D.new()
	var room_view := RoomView.new()
	var player_view := PlayerView.new()
	var camera := GameCamera.new()
	var overlay := Overlay.new()
	overlay.rig = camera.rig
	for n: Node in [room_view, player_view, overlay, camera]:
		stage.add_child(n)
	root.add_child(stage)
	camera.make_current()
	room_view.show_world(sim.world)
	player_view.begin(sim)
	camera.begin(sim)
	var frames: Array[Image] = []
	var labels: Array[int] = []
	var track := PackedVector2Array()
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		player_view.capture(sim)
		camera.step(sim)
		var view: Rect2 = camera.rig.view_rect()
		var b: Body = sim.player.body
		var centre := Vector2(float(b.x) / Fx.SUB, float(b.y - b.height / 2) / Fx.SUB)
		track.append((centre - view.position) / view.size)
		if f < from or (f - from) % every != 0 or frames.size() >= count:
			continue
		overlay.player = Rect2(
			Vector2(float(b.left()), float(b.top())) / Fx.SUB,
			Vector2(float(b.right() - b.left()), float(b.height)) / Fx.SUB
		)
		room_view.refresh()
		player_view.show_at(1.0)
		camera.show_at(1.0)
		overlay.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot: Image = root.get_viewport().get_texture().get_image()
		shot.resize(
			shot.get_width() / shrink, shot.get_height() / shrink, Image.INTERPOLATE_BILINEAR
		)
		frames.append(shot)
		labels.append(f)
	var tuning: CameraTuning = camera.rig.tuning
	var view_size: Vector2 = camera.rig.view_size
	stage.queue_free()
	await process_frame
	if frames.is_empty():
		printerr("%s: no frame to film from tick %d (it has %d)" % [path, from, fx.frame_total])
		return null
	print("%d: %s, %d frames" % [_rows.size() + 1, fx.name, frames.size()])
	var pb: Body = sim.player.body
	var half := Vector2(float(pb.half_w), float(pb.height) * 0.5) / Fx.SUB
	var bands: Vector2 = (Vector2.ONE * tuning.edge_margin_u + half) / view_size
	var track_img: Image = _track(track, labels, frames[0].get_height(), bands)
	return _strip(frames, labels, _rows.size() + 1, track_img)


## The player's track on screen (see the description at the top), [param h] pixels tall.
## [param bands] is where the box's centre puts its edge at the margin, as a fraction of the view
## across and down.
func _track(track: PackedVector2Array, filmed: Array[int], h: int, bands: Vector2) -> Image:
	var img := Image.create_empty(
		maxi(1, track.size() * TRACK_PX_PER_TICK), h, false, Image.FORMAT_RGBA8
	)
	img.fill(ContactSheet.BG)
	var bx: int = roundi(bands.x * h)
	var by: int = roundi(bands.y * h)
	for band: int in [by, bx]:
		img.fill_rect(Rect2i(0, 0, img.get_width(), band), BAND)
		img.fill_rect(Rect2i(0, h - band, img.get_width(), band), BAND)
	for f: int in filmed:
		img.fill_rect(Rect2i(f * TRACK_PX_PER_TICK, 0, 1, h), ContactSheet.GRID.lightened(0.2))
	for f: int in range(track.size()):
		var p: Vector2 = track[f].clamp(Vector2.ZERO, Vector2.ONE)
		var x: int = f * TRACK_PX_PER_TICK
		img.fill_rect(Rect2i(x, roundi(p.x * (h - 2)), TRACK_PX_PER_TICK, 2), TRACK_X)
		img.fill_rect(Rect2i(x, roundi(p.y * (h - 2)), TRACK_PX_PER_TICK, 2), TRACK_Y)
	return img


## A row of [param frames], each labelled with its tick, [param number] at the start and
## [param track] at the end.
func _strip(frames: Array[Image], labels: Array[int], number: int, track: Image) -> Image:
	var fw: int = frames[0].get_width()
	var fh: int = frames[0].get_height()
	var head: int = 56
	var img := Image.create_empty(
		head + frames.size() * (fw + GAP_PX) + track.get_width(), fh, false, Image.FORMAT_RGBA8
	)
	img.fill(ContactSheet.BG)
	ContactSheet.digits(img, Vector2i(8, 8), number, ContactSheet.TEXT, 4)
	for k: int in range(frames.size()):
		var shot: Image = frames[k]
		shot.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(head + k * (fw + GAP_PX), 0)
		img.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), at)
		ContactSheet.digits(img, at + Vector2i(4, 4), labels[k], ContactSheet.TEXT, 2)
	var end := Vector2i(head + frames.size() * (fw + GAP_PX), 0)
	img.blit_rect(track, Rect2i(Vector2i.ZERO, track.get_size()), end)
	return img
