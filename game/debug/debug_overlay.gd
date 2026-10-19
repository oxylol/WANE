class_name DebugOverlay
extends Node2D
## The F3 debug overlay, on every build (BUILD.md section 5: "A debug overlay (F3) shows
## hitboxes, state, frame counters and input history on every build, forever"; section 15: "The
## F3 overlay shows hitboxes, state, frame counter and input history in the build").
##
## In the world it draws the latest tick's boxes ([DebugBoxes]) and the camera's working (the
## 80 u margin, the dead zone and the focus). On screen it prints the tick, the driver's timing,
## the player's state, the current strike's frame, the camera, and the input history
## ([InputHistory]). It reads the simulation and never writes it. Text uses Godot's embedded
## default font (docs/LICENSES.md), never under 18 px (BUILD.md section 12).

const BOX_COLOURS: Dictionary[int, Color] = {
	DebugBoxes.COLLIDER: Color(1.0, 1.0, 1.0, 0.9),
	DebugBoxes.HURTBOX: Color(0.3, 1.0, 0.4, 0.9),
	DebugBoxes.STRIKE: Color(1.0, 0.45, 0.2, 0.9),
	DebugBoxes.POGO: Color(1.0, 0.9, 0.2, 0.9),
	DebugBoxes.EMBER: Color(1.0, 0.55, 0.15, 1.0),
	DebugBoxes.SOLID: Color(0.6, 0.75, 1.0, 0.9),
	DebugBoxes.HAZARD: Color(1.0, 0.2, 0.2, 0.9),
	DebugBoxes.CONTACT: Color(1.0, 1.0, 1.0, 1.0),
	DebugBoxes.ENEMY: Color(0.85, 0.6, 1.0, 0.9),
	DebugBoxes.ATTACK_WHITE: Color(1.0, 1.0, 1.0, 1.0),
	DebugBoxes.ATTACK_RED: Color(1.0, 0.1, 0.1, 1.0),
	DebugBoxes.SPELL: Color(1.0, 0.6, 0.1, 0.9),
	DebugBoxes.TRAIL: Color(1.0, 0.35, 0.05, 0.7),
	DebugBoxes.KILL_EMBER: Color(1.0, 0.75, 0.3, 1.0),
	DebugBoxes.ENEMY_DEAD: Color(0.55, 0.5, 0.6, 0.55),
}
## Boxes that are filled as well as outlined (the ones that hit something).
const FILLED: Array[int] = [
	DebugBoxes.STRIKE,
	DebugBoxes.POGO,
	DebugBoxes.HAZARD,
	DebugBoxes.CONTACT,
	DebugBoxes.ATTACK_WHITE,
	DebugBoxes.ATTACK_RED,
	DebugBoxes.SPELL,
	DebugBoxes.TRAIL,
]
const MARGIN := Color(1.0, 0.3, 0.3, 0.6)
## Violet, so the dead zone never reads as the hurtbox's green (task 5 review, L14).
const DEAD_ZONE := Color(0.75, 0.55, 1.0, 0.6)
const FOCUS := Color(1.0, 0.85, 0.3)

const TEXT := Color(0.95, 0.95, 0.9)
const SHADE := Color(0.0, 0.0, 0.0, 0.6)
const FONT_SIZE: int = 18
## A line of 18 px text: the embedded font's own height, so descenders never touch the next line.
const LINE_PX: int = 26
const PAD_PX: int = 12
## Where the text starts down the screen: below the HUD's hearts, Flame bar and Kindling
## (game/ui/hud.gd), which sit at the top left.
const TOP_PX: int = 168
## Width of the screen column the input history uses, from the right edge: room for a run with
## every button held (task 5 review, L17).
const HISTORY_COLUMN_PX: int = 400

var shown: bool = false
var history: InputHistory = InputHistory.new()
## The driver whose simulation it shows, or null when it watches a simulation stepped by a tool
## ([method attach_sim]: the filmed contact sheets).
var driver: SimDriver
var camera: GameCamera
## The boxes drawn on the latest redraw (for tests and tools).
var boxes: Array[DebugBoxes.Box] = []

var _hud: Node2D
var _sim: Simulation


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	layer.layer = 100
	add_child(layer)
	_hud = Node2D.new()
	layer.add_child(_hud)
	_hud.draw.connect(_draw_hud)
	visible = shown
	layer.visible = shown


## Watches [param p_driver]'s simulation and [param p_camera].
func attach(p_driver: SimDriver, p_camera: GameCamera) -> void:
	driver = p_driver
	_watch(driver.sim, p_camera)


## Watches [param sim], stepped by a tool rather than a driver (tools/replay/film.gd), and
## [param p_camera].
func attach_sim(sim: Simulation, p_camera: GameCamera) -> void:
	driver = null
	_watch(sim, p_camera)


func _watch(sim: Simulation, p_camera: GameCamera) -> void:
	_sim = sim
	camera = p_camera
	history.clear()
	if sim != null and sim.player != null:
		history.threshold = sim.player.p.stick_threshold


## The simulation shown: the driver's (it starts a new one on every session), or the one attached.
func shown_sim() -> Simulation:
	return driver.sim if driver != null else _sim


func toggle() -> void:
	set_shown(not shown)


func set_shown(on: bool) -> void:
	shown = on
	visible = on
	if _hud != null:
		(_hud.get_parent() as CanvasLayer).visible = on
	refresh()


## Takes the input of the tick just stepped (call after every tick, shown or not, so the
## history is complete when the overlay opens).
func capture() -> void:
	var sim: Simulation = shown_sim()
	if sim != null:
		history.push(sim.last_input, sim.tick - 1)


func refresh() -> void:
	if not shown:
		return
	queue_redraw()
	if _hud != null:
		_hud.queue_redraw()


func _draw() -> void:
	var sim: Simulation = shown_sim()
	if sim == null:
		return
	var view: Rect2 = camera.rig.view_rect() if camera != null else Rect2()
	boxes = DebugBoxes.collect(sim, view)
	var font: Font = ThemeDB.fallback_font
	for box: DebugBoxes.Box in boxes:
		var colour: Color = BOX_COLOURS[box.kind]
		if FILLED.has(box.kind):
			draw_rect(box.rect, Color(colour, 0.25))
		draw_rect(box.rect, colour, false, 2.0)
		if box.label != "" and not _label_repeats(box):
			draw_string(
				font,
				box.rect.position + Vector2(0, -4 - box.label_lift),
				box.label,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				FONT_SIZE,
				colour
			)
	if camera != null:
		var t: CameraTuning = camera.rig.tuning
		draw_rect(view.grow(-t.edge_margin_u), MARGIN, false, 2.0)
		var dead := Vector2(t.dead_zone_w_u, t.dead_zone_h_u)
		draw_rect(Rect2(camera.rig.anchor() - dead * 0.5, dead), DEAD_ZONE, false, 2.0)
		draw_circle(camera.rig.focus, 6.0, FOCUS)


## True if an earlier box this redraw has the same rectangle (the down-strike's box is its pogo
## box): its label is drawn once, with both names ([method DebugBoxes.collect] joins them).
func _label_repeats(box: DebugBoxes.Box) -> bool:
	for other: DebugBoxes.Box in boxes:
		if other == box:
			return false
		if other.rect == box.rect and other.label != "":
			return true
	return false


## The overlay's text, top to bottom. Frames are numbered as fixtures, trace.gd and film.gd number
## them: frame F is the state after input frame F (task 5 review, M11).
func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	var sim: Simulation = shown_sim()
	if sim == null:
		return lines
	if driver != null:
		var timing: String = (
			"locked to the display" if driver.is_locked() else "free, alpha %.2f" % driver.alpha
		)
		lines.append(
			(
				"frame %d%s   %d fps   %s"
				% [
					sim.tick - 1,
					"   PAUSED (F4 resume, F5 step, F6 ten)" if driver.paused else "",
					Engine.get_frames_per_second(),
					timing
				]
			)
		)
	else:
		lines.append("frame %d   (filmed frame by frame)" % (sim.tick - 1))
	var pl: Player = sim.player
	if pl == null:
		return lines
	lines.append_array(_player_lines(sim, pl))
	if camera != null:
		var rig: CameraRig = camera.rig
		lines.append(
			(
				"camera %.0f, %.0f   focus %.0f, %.0f%s   follow misses %d"
				% [
					rig.center.x,
					rig.center.y,
					rig.focus.x,
					rig.focus.y,
					"   gliding" if rig.gliding() else "",
					rig.follow_misses
				]
			)
		)
	return lines


func _player_lines(sim: Simulation, pl: Player) -> PackedStringArray:
	var lines: PackedStringArray = []
	var b: Body = pl.body
	lines.append(
		(
			"%s%s   facing %s   at %.1f, %.1f u   moving %.2f, %.2f u/tick"
			% [
				str(sim.probe("state")),
				" crouched" if pl.crouching else "",
				"right" if pl.facing > 0 else "left",
				float(b.x) / Fx.SUB,
				float(b.y) / Fx.SUB,
				float(b.vx) / Fx.SUB,
				float(b.vy) / Fx.SUB
			]
		)
	)
	var atk: AttackDef = pl.current_attack()
	if pl.action != Player.NO_ACTION and atk != null:
		var first: int = atk.startup + 1
		lines.append(
			(
				"strike %s frame %d of %d (active %d to %d)   next %s"
				% [
					atk.id,
					pl.action_frame,
					atk.startup + atk.active + atk.recovery,
					first,
					first + atk.active - 1,
					pl.chain_next
				]
			)
		)
	else:
		lines.append("strike none   next %s" % pl.chain_next)
	var air: String = "on the ground"
	if not b.on_ground:
		air = "airborne %d frame%s" % [pl.air_frames, "" if pl.air_frames == 1 else "s"]
	lines.append(
		(
			"dash frame %d, cooldown %d, carry %d   jump frame %d   %s"
			% [pl.dash_frame, pl.ground_dash_cooldown, pl.carry_frames, pl.jump_frame, air]
		)
	)
	(
		lines
		. append(
			(
				"air jumps %d   air dashes %d   wall %d for %d   invulnerable %s   ember %s, cooldown %d"
				% [
					pl.air_jumps_left,
					pl.air_dashes_left,
					pl.wall_side,
					pl.wall_frames,
					"yes" if pl.is_invulnerable() else "no",
					"out" if pl.toss.active else "held",
					pl.toss.cooldown
				]
			)
		)
	)
	lines.append(_combat_line(sim, pl))
	return lines


## Hearts, Flame, Kindling and its tier, the spell under way, hitstop and the knockback after a hit.
func _combat_line(sim: Simulation, pl: Player) -> String:
	var v: Vitals = pl.vitals
	var spell: String = "none"
	if pl.spell != PlayerSpells.NONE:
		spell = "%s frame %d" % [PlayerSpells.NAMES[pl.spell], pl.spell_frame]
	return (
		"hearts %d/%d   flame %d   kindling %d %s   spell %s   hitstop %d   knockback %d"
		% [
			v.hearts.current,
			v.hearts.max_hearts,
			v.flame.value,
			v.kindling.hits,
			str(sim.probe("tier")),
			spell,
			pl.freeze,
			pl.knock_left
		]
	)


func _draw_hud() -> void:
	var font: Font = ThemeDB.fallback_font
	var lines: PackedStringArray = hud_lines()
	var screen: Vector2 = get_viewport_rect().size
	var block_h: int = PAD_PX * 2 + LINE_PX * lines.size()
	_hud.draw_rect(Rect2(0, TOP_PX, screen.x - HISTORY_COLUMN_PX, block_h), SHADE)
	for i: int in range(lines.size()):
		var at := Vector2(PAD_PX, TOP_PX + PAD_PX + LINE_PX * (i + 1) - 6)
		_hud.draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
	var x0: float = screen.x - HISTORY_COLUMN_PX
	var rows: int = history.runs.size()
	_hud.draw_rect(Rect2(x0, 0, HISTORY_COLUMN_PX, PAD_PX * 2 + LINE_PX * (rows + 1)), SHADE)
	_hud.draw_string(
		font,
		Vector2(x0 + PAD_PX, PAD_PX + LINE_PX - 6),
		"input (newest first)",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		TEXT
	)
	for i: int in range(rows):
		var at := Vector2(x0 + PAD_PX, PAD_PX + LINE_PX * (i + 2) - 6)
		var text: String = InputHistory.describe(history.runs[i])
		_hud.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
