extends SceneTree
## Films replay fixtures through the game's own views (the grey-box room, the enemies, combat's
## objects and hit feedback, the player, the HUD and the camera) and writes a filmstrip: a row of
## frames per fixture, one every few ticks, each the full 1920 x 1080 view scaled down, with the
## camera drawn over it: the 80 u margin (red), the dead zone around the point the follow holds
## to (green) and the focus it aims at, that point plus the looks (yellow); a white ring marks
## the player, who is small at sheet scale. This is what the player sees, so it is how camera and
## combat changes are judged
## (CLAUDE.md working method: "play the fixture and capture a contact sheet").
##
## It renders, so it needs a display; headless machines run it under a virtual one:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 --script tools/replay/film.gd -- \
##     <out.png> [--every N] [--from F] [--frames K] [--scale S] [--overlay on] [--zoom Z] \
##     [--set <res path>:<prop>=<int>] <fixture>...
##
## Options apply to the fixtures after them: --every N films every N-th tick (default 10),
## --from F starts at tick F and --frames K films K frames (default 12) per fixture, --scale S
## divides the frame size (default 6), and --overlay on|off draws the game's own F3 overlay
## (docs/adr/0012: the boxes, the state, the tick and the input history) instead of the camera's
## working: the frame-stepped contact sheet of CLAUDE.md's working method, step 5. With the overlay
## on, --zoom Z (default 1) magnifies the world Z times around the player so the boxes can be read
## against each other at sheet size; the overlay's text stays on the screen. --set changes a
## tuning value for the fixtures after it, as in play.gd. --lighting pitch|off films the fixtures
## after it under the Phase 1 stand-in Pitch lighting (game/lighting) or unlit; by default a
## fixture's own `lighting` word decides. Frame numbers are drawn top left, the
## fixture's number at the start of its row.
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

## What the run measured (tools/ci/timing_log.gd, docs/adr/0025).
var timing: TimingLog = TimingLog.new("tools/replay/film.gd")
## --lighting's word for the fixtures after it; "" lets the fixture's own word decide.
var _lighting: String = ""
var _rows: Array[Image] = []
## Resources changed by --set, held so the resource cache keeps the changed copies.
var _held: Array[Resource] = []


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
	var f3: bool = false
	var zoom: float = 1.0
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
		elif a == "--overlay" and has_value:
			f3 = args[i + 1] == "on"
			i += 2
		elif a == "--set" and has_value:
			if not TuningOverride.apply(args[i + 1], _held):
				quit(2)
				return
			i += 2
		elif a == "--lighting" and has_value:
			_lighting = args[i + 1]
			i += 2
		elif a == "--zoom" and has_value:
			zoom = maxf(1.0, args[i + 1].to_float())
			i += 2
		else:
			var opts := Vector2(float(shrink), zoom if f3 else 1.0)
			var began_usec: int = Time.get_ticks_usec()
			var row: Image = await _film_one(a, every, from, count, opts, f3)
			if row == null:
				quit(1)
				return
			_rows.append(row)
			# Filming time depends on what is filmed, so the options are part of the series.
			var variant: String = (
				"every=%d frames=%d scale=%d overlay=%s zoom=%s lighting=%s"
				% [every, count, shrink, "on" if f3 else "off", opts.y, _lighting]
			)
			var seconds: float = float(Time.get_ticks_usec() - began_usec) / 1000000.0
			timing.add("film", "film", a.get_file().get_basename(), seconds, variant)
			i += 1
	var img: Image = ContactSheet.sheet(_rows, 1)
	var err: Error = img.save_png(args[0])
	print("wrote %s (%dx%d): %s" % [args[0], img.get_width(), img.get_height(), error_string(err)])
	if err == OK:
		timing.flush()
	quit(0 if err == OK else 1)


## Films one fixture; [param opts] is the shrink (x) and the zoom around the player (y).
func _film_one(path: String, every: int, from: int, count: int, opts: Vector2, f3: bool) -> Image:
	var shrink: int = int(opts.x)
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
	var enemy_view := EnemyView.new()
	var combat_view := CombatView.new()
	var player_view := PlayerView.new()
	var vfx := VfxBudget.new()
	var feedback := HitFeedback.new()
	var hud := Hud.new()
	var screen := FeedbackOverlay.new()
	var camera := GameCamera.new()
	var overlay := Overlay.new()
	overlay.rig = camera.rig
	var debug := DebugOverlay.new()
	# The drawer filmed, and the one left off the stage (freed by hand at the end).
	var drawer: Node2D = debug
	var spare: Node2D = overlay
	if not f3:
		drawer = overlay
		spare = debug
	# The main scene's order: the fire trails are under the enemies, not over them.
	for n: Node in [room_view, combat_view, enemy_view, player_view, vfx, drawer, camera]:
		stage.add_child(n)
	for n: Node in [feedback, hud, screen]:
		stage.add_child(n)
	var rig: LightingRig = null
	if LightingRig.asks_for_pitch(_lighting if _lighting != "" else fx.lighting):
		rig = LightingRig.new()
		stage.add_child(rig)
	root.add_child(stage)
	camera.make_current()
	room_view.show_world(sim.world, sim.room.doors)
	if rig != null:
		rig.show_world(sim.world)
	combat_view.player_view = player_view
	feedback.attach(vfx, null)
	hud.vitals = sim.player.vitals
	hud.spell_costs = [
		sim.player.kit.kindle_cost, sim.player.kit.mend_cost, sim.player.kit.radiance_cost
	]
	screen.feedback = feedback
	enemy_view.capture(sim)
	player_view.begin(sim)
	camera.begin(sim)
	debug.attach_sim(sim, camera)
	debug.set_shown(f3)
	var frames: Array[Image] = []
	var labels: Array[int] = []
	var track := PackedVector2Array()
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		if sim.events.has(SimEvents.ROOM):
			room_view.show_world(sim.world, sim.room.doors)
			if rig != null:
				rig.show_world(sim.world)
		player_view.capture(sim)
		enemy_view.capture(sim)
		combat_view.capture(sim)
		feedback.on_tick(sim)
		hud.on_tick(sim.events)
		camera.step(sim)
		debug.capture()
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
		if rig != null:
			rig.follow(player_view.box_at(1.0).get_center(), float(every) / 60.0)
		enemy_view.show_at(1.0)
		combat_view.show_at(1.0)
		camera.show_at(1.0)
		camera.offset = feedback.shake_offset()
		if opts.y > 1.0:
			camera.zoom *= opts.y
			camera.position = overlay.player.get_center()
		overlay.queue_redraw()
		debug.refresh()
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
	spare.free()
	await process_frame
	if frames.is_empty():
		printerr("%s: no frame to film from tick %d (it has %d)" % [path, from, fx.frame_total])
		return null
	print("%d: %s, %d frames" % [_rows.size() + 1, fx.name, frames.size()])
	var pb: Body = sim.player.body
	var half := Vector2(float(pb.half_w), float(pb.height) * 0.5) / Fx.SUB
	var bands: Vector2 = (Vector2.ONE * tuning.edge_margin_u + half) / view_size
	var track_img: Image = _track(track, labels, frames[0].get_height(), bands)
	var drawn: Array[int] = []
	if not f3:
		drawn = labels
	return _strip(frames, drawn, _rows.size() + 1, track_img)


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
## One fixture's row; [param labels] are drawn over the frames unless empty (the F3 overlay
## prints the tick itself).
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
		if not labels.is_empty():
			ContactSheet.digits(img, at + Vector2i(4, 4), labels[k], ContactSheet.TEXT, 2)
	var end := Vector2i(head + frames.size() * (fw + GAP_PX), 0)
	img.blit_rect(track, Rect2i(Vector2i.ZERO, track.get_size()), end)
	return img
