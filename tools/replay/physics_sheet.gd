extends SceneTree
## Contact sheet of the physics sweep's behaviours (Phase 1 task 2; docs/adr/0008): each panel is
## one scenario with the box drawn every few ticks (older positions fainter) and its foot point's
## path, so crests, lifts, ducks and drops can be checked by eye.
##
##   godot --headless --path . --script tools/replay/physics_sheet.gd -- <out.png>

const U: int = Fx.SUB
const SCALE: int = 2
## Ash's movement tuning: the drops fall a tick at a time under its fall gravity and terminal
## speed, the way the player falls.
const MOVEMENT_PATH: String = "res://content/wicks/ash/movement.tres"

var _panels: Array[Image] = []
var _gravity: int = 0
var _terminal: int = 0
var _problems: PackedStringArray = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "physics_sheet.png"
	var movement: MovementTuning = load(MOVEMENT_PATH) as MovementTuning
	_gravity = Fx.accel(movement.gravity_fall_ups2)
	_terminal = Fx.speed(movement.terminal_ups)
	_crest_walk()
	_crest_landings()
	_ramp_flight()
	_corner_lift()
	_duck_and_nudge()
	_drop_through()
	_door_on_ramp()
	_solid_top_to_slope()
	_sunk_box()
	_lips()
	_far_edge()
	for problem: String in _problems:
		printerr("problem: %s" % problem)
	var img: Image = ContactSheet.sheet(_panels, 1)
	var err: Error = img.save_png(out)
	print("wrote %s (%dx%d): %s" % [out, img.get_width(), img.get_height(), error_string(err)])
	quit(0 if err == OK and _problems.is_empty() else 1)


## A world from map rows with the game's world tuning; rows that break the geometry rules are
## reported and fail the run, as the room editor would refuse them (so are panels whose box does
## not end where the panel says it does).
func _world(rows: Array[String]) -> CollisionWorld:
	var grid: TileGrid = TileGrid.from_rows(PackedStringArray(rows))
	_problems.append_array(grid.validate())
	var w := CollisionWorld.new(grid)
	(load(WorldTuning.PATH) as WorldTuning).apply(w)
	return w


## Falls [param b] from rest a tick at a time until it lands, recording each position.
func _fall(w: CollisionWorld, b: Body, path: Array[Vector2i]) -> void:
	var vy: int = 0
	for _i: int in range(200):
		vy = mini(vy + _gravity, _terminal)
		w.move_y(b, vy)
		path.append(Vector2i(b.x, b.y))
		if b.on_ground:
			return


## Draws a recorded path: boxes every [param every] samples, older ones fainter, the foot point
## path as dots, and [param label] (a number) in the corner.
func _panel(
	w: CollisionWorld, region: Rect2i, path: Array[Vector2i], every: int, label: int
) -> void:
	var first := Body.make(path[0].x, path[0].y, 10 * U, 44 * U)
	if _embedded(w, first):
		_problems.append("panel %d: the box starts inside something solid" % label)
	var cs := ContactSheet.new(w, SCALE)
	var img: Image = cs.room_image(region)
	for i: int in range(path.size()):
		var p: Vector2i = path[i]
		var foot := Vector2i(Fx.div_floor(p.x, U), Fx.div_floor(p.y, U))
		cs.fill(img, region, Rect2i(foot - Vector2i(0, 1), Vector2i(1, 1)), Color(1.0, 0.8, 0.3))
		if i % every == 0 or i == path.size() - 1:
			var age: float = float(i) / maxf(1.0, float(path.size() - 1))
			var col := Color(0.35, 0.75, 1.0).lerp(Color(1.0, 0.95, 0.6), age)
			col.a = 1.0
			cs.outline(img, region, ContactSheet.box_rect(p.x, p.y, 10 * U, 44 * U), col)
	ContactSheet.digits(img, Vector2i(8, 8), label, ContactSheet.TEXT, 4)
	_panels.append(img)


## True if [param b]'s upper body (above its foot zone) overlaps a wall, slope or solid box, or
## any of it overlaps a solid box.
func _embedded(w: CollisionWorld, b: Body) -> bool:
	if w.region_blocked(b.left(), b.right(), b.top(), b.y - b.half_w):
		return true
	for sb: SolidBox in w.solids:
		if sb.enabled and sb.overlaps(b.left(), b.right(), b.top(), b.y):
			return true
	return false


## 1: walking a continuous ground of crests, peaks and a valley at run speed, there and back
## (the way back retraces the way there exactly, so its boxes sit on the first ones).
func _crest_walk() -> void:
	var w: CollisionWorld = _world(_crest_rows())
	var b := Body.make(48 * U, 100 * U, 10 * U, 44 * U)
	_fall(w, b, [])
	var path: Array[Vector2i] = [Vector2i(b.x, b.y)]
	for dir: int in [1, -1]:
		for _i: int in range(96):
			w.walk(b, dir * 9 * U)
			path.append(Vector2i(b.x, b.y))
	_panel(w, Rect2i(0, 120, 960, 140), path, 6, 1)


## 2: dropped from rest at every 12 u across the crests, falling a tick at a time: where the box
## comes to rest (on the slope under its centre, never hovering on a plateau's edge).
func _crest_landings() -> void:
	var w: CollisionWorld = _world(_crest_rows())
	var path: Array[Vector2i] = []
	for x_u: int in range(48, 900, 12):
		var b := Body.make(x_u * U, 160 * U, 10 * U, 44 * U)
		_fall(w, b, [])
		path.append(Vector2i(b.x, b.y))
	_panel(w, Rect2i(0, 120, 960, 140), path, 1, 2)


## 3: a level dash (20 u a tick, move_x then move_y(0), as an air dash moves) into the foot of
## a ramp two tile rows tall rides up it and onto the plateau at full speed: the crest and the
## wall under the next row's slope stop only the upper body. Every tick's box is drawn.
func _ramp_flight() -> void:
	var w: CollisionWorld = _world(
		[
			"..............",
			"..............",
			"..............",
			"......./######",
			"....../#######",
			"##############",
		]
	)
	var b := Body.make(40 * U, 160 * U, 10 * U, 44 * U)
	var path: Array[Vector2i] = [Vector2i(b.x, b.y)]
	for _i: int in range(12):
		b.clear_contacts()
		w.move_x(b, 20 * U)
		w.move_y(b, 0)
		if b.hit_wall != 0 or b.x != path[path.size() - 1].x + 20 * U:
			_problems.append("panel 3: the dash was stopped at (%d, %d)" % [b.x, b.y])
		path.append(Vector2i(b.x, b.y))
	_panel(w, Rect2i(0, 40, 448, 140), path, 1, 3)


## 4: falling past a ledge corner: lifted onto it.
func _corner_lift() -> void:
	var w: CollisionWorld = _world(
		["..........", "..........", "..........", ".....#####", ".....#####", "##########"]
	)
	var b := Body.make(100 * U, 72 * U, 10 * U, 44 * U)
	var path: Array[Vector2i] = [Vector2i(b.x, b.y)]
	var vy: int = 0
	for _i: int in range(16):
		b.clear_contacts()
		w.move_x(b, 6 * U, 8 * U, 6 * U)
		if b.on_ground:
			w.walk(b, 0)
		else:
			vy = mini(vy + _gravity, _terminal)
			w.move_y(b, vy, 6 * U)
		path.append(Vector2i(b.x, b.y))
	_panel(w, Rect2i(0, 0, 320, 192), path, 1, 4)


## 5: a dash just under a ceiling corner ducks beneath it; a jump just beside one slides round.
func _duck_and_nudge() -> void:
	var w: CollisionWorld = _world(
		["#####.....", "#####.....", "..........", "..........", "##########"]
	)
	w.solids.append(SolidBox.make(200 * U, 0, 320 * U, 66 * U))
	var b := Body.make(40 * U, 108 * U, 10 * U, 44 * U)
	var path: Array[Vector2i] = [Vector2i(b.x, b.y)]
	for _i: int in range(12):
		w.move_x(b, 20 * U, 8 * U, 6 * U)
		path.append(Vector2i(b.x, b.y))
	var c := Body.make(166 * U, 128 * U, 10 * U, 44 * U)
	for _i: int in range(6):
		w.move_y(c, -12 * U, 6 * U)
		path.append(Vector2i(c.x, c.y))
	_panel(w, Rect2i(0, 0, 320, 160), path, 1, 5)


## 6: crouch-dropping through a one-way platform, and refused beside a wall.
func _drop_through() -> void:
	var w: CollisionWorld = _world(
		["..........", "..........", "..#=====..", "..#.......", "##########"]
	)
	var path: Array[Vector2i] = []
	for x_u: int in [98, 160]:
		var b := Body.make(x_u * U, 64 * U, 10 * U, 44 * U)
		w.refresh_ground(b)
		path.append(Vector2i(b.x, b.y))
		if w.drop_through(b):
			_fall(w, b, path)
	_panel(w, Rect2i(0, 0, 320, 160), path, 1, 6)


## 7: walking up a ramp into a closed door (a solid box), then back down away from it.
func _door_on_ramp() -> void:
	var w: CollisionWorld = _world(
		[
			"..........",
			"..........",
			"....../###",
			"...../####",
			"..../#####",
			"##########",
		]
	)
	w.solids.append(SolidBox.make(186 * U, 20 * U, 194 * U, 90 * U))
	var b := Body.make(60 * U, 120 * U, 10 * U, 44 * U)
	_fall(w, b, [])
	var path: Array[Vector2i] = [Vector2i(b.x, b.y)]
	for dir: int in [1, -1]:
		for _i: int in range(14):
			w.walk(b, dir * 9 * U)
			path.append(Vector2i(b.x, b.y))
	_panel(w, Rect2i(0, 0, 320, 192), path, 2, 7)


## 8: walking along a solid box's top onto the slope that rises out of it, and back.
func _solid_top_to_slope() -> void:
	var w: CollisionWorld = _world(["..........", "..........", "..#\\......", "##########"])
	w.solids.append(SolidBox.make(96 * U, 86 * U, 250 * U, 120 * U))
	var b := Body.make(200 * U, 86 * U, 10 * U, 44 * U)
	w.refresh_ground(b)
	var path: Array[Vector2i] = [Vector2i(b.x, b.y)]
	for dir: int in [-1, 1]:
		for _i: int in range(20):
			w.walk(b, dir * 6 * U)
			path.append(Vector2i(b.x, b.y))
	_panel(w, Rect2i(0, 0, 320, 128), path, 2, 8)


## 9: a solid box (a door left open as a floor) 4 u under a ramp's crest, its top meeting the
## ramp flush where the ramp is 4 u under the crest (ADR-0008 decision 12: a top never lies just
## under the ground): walking down onto it and back up again, along its top and up the ramp onto
## the plateau.
func _sunk_box() -> void:
	var w: CollisionWorld = _world(["..........", "..........", "...../####", "##########"])
	w.solids.append(SolidBox.make(40 * U, 68 * U, 188 * U, 128 * U))
	var b := Body.make(260 * U, 64 * U, 10 * U, 44 * U)
	w.refresh_ground(b)
	var path: Array[Vector2i] = [Vector2i(b.x, b.y)]
	for dir: int in [-1, 1]:
		for _i: int in range(18):
			b.clear_contacts()
			w.walk(b, dir * 9 * U)
			path.append(Vector2i(b.x, b.y))
	if b.y != 64 * U or b.x < 250 * U:
		_problems.append("panel 9: the walk back up stopped at (%d, %d)" % [b.x, b.y])
	_panel(w, Rect2i(0, 0, 320, 128), path, 2, 9)


## 10: walking over lips of solid boxes with the ground corner correction (8 u): a floor laid 1 u
## below the tiles beside it, a box 8 u proud of the floor (stepped up), and a box 9 u above
## that (a wall); then back down the same lips, stepped down on the ground.
func _lips() -> void:
	var w: CollisionWorld = _world(
		[
			"....................",
			"....................",
			".....###############",
			"####################"
		]
	)
	w.solids.append(SolidBox.make(0, 65 * U, 160 * U, 96 * U))
	w.solids.append(SolidBox.make(320 * U, 56 * U, 480 * U, 64 * U))
	w.solids.append(SolidBox.make(480 * U, 47 * U, 560 * U, 64 * U))
	var b := Body.make(60 * U, 65 * U, 10 * U, 44 * U)
	w.refresh_ground(b)
	var path: Array[Vector2i] = [Vector2i(b.x, b.y)]
	for _i: int in range(52):
		b.clear_contacts()
		w.walk(b, 9 * U, 8 * U)
		path.append(Vector2i(b.x, b.y))
	if b.x != 470 * U or b.y != 56 * U:
		_problems.append(
			"panel 10: expected to stop at the 9 u box at x 470, got (%d, %d)" % [b.x, b.y]
		)
	for _i: int in range(52):
		b.clear_contacts()
		w.walk(b, -9 * U, 8 * U)
		path.append(Vector2i(b.x, b.y))
		if not b.on_ground:
			_problems.append("panel 10: walking back down left the ground at (%d, %d)" % [b.x, b.y])
	_panel(w, Rect2i(0, 0, 640, 128), path, 3, 10)


## 11: the player's hop off a ledge's far edge (the fixture far_edge_landing_lands, played through
## the simulation from the hop): on tick 25 the box comes down with 8.6 of its 20 u over the far
## end, lands where its straight path meets the ledge (CollisionWorld.landing_contact; the box
## drawn green), then walks the rest of the tick's step off it. Moving across before falling
## would carry it past the edge first. The panel fails unless that landing happens off the
## ledge's end.
func _far_edge() -> void:
	var fx: Fixture = Fixture.parse_file(
		"res://tests/replay/physics/far_edge_landing_lands.fixture"
	)
	var sim := Simulation.new(fx.scenario)
	_problems.append_array(fx.errors)
	_problems.append_array(sim.load_errors)
	var b: Body = sim.player.body
	var edge: int = 608 * U
	var path: Array[Vector2i] = []
	var contact := Vector2i(-1, -1)
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		if f >= 18 and f <= 31:
			path.append(Vector2i(b.x, b.y))
		var ev: SimEvents = sim.events
		for i: int in range(ev.count()):
			# The landing tick's step ends off the ledge: only a landing at the far edge does that.
			if ev.kinds[i] == SimEvents.LAND and b.x >= edge and f >= 18:
				contact = Vector2i(ev.xs[i], ev.ys[i])
	if contact.x < 0 or contact.y != 448 * U or contact.x - 10 * U >= edge:
		_problems.append("panel 11: the box never touched down on the ledge's far edge")
	var w: CollisionWorld = sim.world
	var region := Rect2i(448, 320, 320, 224)
	_panel(w, region, path, 1, 11)
	if contact.x >= 0:
		var cs := ContactSheet.new(w, SCALE)
		var box: Rect2i = ContactSheet.box_rect(contact.x, contact.y, 10 * U, 44 * U)
		cs.outline(_panels[-1], region, box, Color(0.3, 1.0, 0.4), 2)


func _crest_rows() -> Array[String]:
	return [
		"##############################",
		"#............................#",
		"#............................#",
		"#............................#",
		"#............................#",
		"#............................#",
		"#..../###\\...ab##cd../\\......#",
		"#########################\\/###",
		"##############################",
	]
