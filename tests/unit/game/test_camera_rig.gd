extends GdUnitTestSuite
## The camera (BUILD.md section 5 feel rules: "The camera never fights the player. 60 u horizontal
## lead in the facing direction, dead zone of 40x30 u, vertical catches up at 0.08 lerp;
## look-down on crouch hold"; section 15: "The camera never shows the player within 80 units of
## the screen edge during normal play"; docs/adr/0011-camera.md).

## A room far bigger than the view, so its edges are out of play.
const BIG_ROOM := Rect2(-8000, -8000, 16000, 16000)
const FIXTURE_DIRS: Array[String] = [
	"res://tests/replay/movement",
	"res://tests/replay/tech",
	"res://tests/replay/physics",
	"res://tests/replay/camera",
	"res://tests/replay/doors",
	# Not tests/replay/zone1/bypass: a bounce during a teleport's glide jolts the view at 4:3
	# (PROGRESS.md, Blocked 3); the fixture moves up a directory when the camera is fixed.
	"res://tests/replay/zone1",
]
## The screen shapes the game may run at (16:9, 16:10, 4:3, 21:9): GameCamera gives the rig the
## real screen's shape, showing a taller or wider screen more world.
const VIEWS: Array[Vector2] = [
	Vector2(1920, 1080), Vector2(1920, 1200), Vector2(1920, 1440), Vector2(2520, 1080)
]
## The camera's speed never changes faster than this outside a teleport's glide (units per tick
## per tick): reaching dash speed takes at least 7 ticks, so it never jolts.
const MAX_ACCEL_U: float = 3.0
## Inside a glide (24 ticks, a smootherstep over at most a 400 u teleport).
const MAX_GLIDE_ACCEL_U: float = 5.0
## A tile: the most the view may move against the player's vertical motion in one stretch.
const TILE_U: float = 32.0


func _rig(view: Vector2 = VIEWS[0]) -> CameraRig:
	var rig := CameraRig.new(load(CameraRig.TUNING_PATH) as CameraTuning)
	rig.view_size = view
	return rig


func _play(path: String, view: Vector2 = VIEWS[0]) -> CameraRun:
	var run: CameraRun = CameraRun.play(path, _rig(view))
	assert_array(Array(run.errors)).is_empty()
	return run


## A subject standing (or not) with its feet at [param bottom] and its centre at [param x].
func _subject(x: float, bottom: float, facing: int = 1, supported: bool = true) -> CameraSubject:
	var s := CameraSubject.new()
	s.box = Rect2(x - 10, bottom - 44, 20, 44)
	s.stand_height = 44.0
	s.facing = facing
	s.supported = supported
	s.on_ground = supported
	s.ground_below = 0.0 if supported else CameraSubject.NO_GROUND
	return s


func test_the_lead_puts_the_camera_ahead_of_a_standing_player() -> void:
	var rig: CameraRig = _rig()
	rig.reset(_subject(1000, 2000), BIG_ROOM)
	assert_float(rig.center.x).is_equal(1060.0)
	for _i: int in range(60):
		rig.step(_subject(1000, 2000), BIG_ROOM)
	assert_float(rig.center.x).is_equal(1060.0)


func test_running_the_camera_keeps_pace_with_the_focus_at_the_dead_zone_edge() -> void:
	var rig: CameraRig = _rig()
	rig.reset(_subject(1000, 2000), BIG_ROOM)
	var x: float = 1000.0
	for _i: int in range(120):
		x += 9.0
		rig.step(_subject(x, 2000), BIG_ROOM)
	# Focus (x + 60) at the dead zone's right edge (centre + 20): the player 40 u behind centre.
	assert_float(rig.center.x).is_equal(x + 40.0)
	rig.step(_subject(x + 9.0, 2000), BIG_ROOM)
	assert_float(rig.center.x - rig.previous.x).is_equal(9.0)


func test_turning_around_swings_the_lead_smoothly() -> void:
	var rig: CameraRig = _rig()
	rig.reset(_subject(1000, 2000), BIG_ROOM)
	for _i: int in range(60):
		rig.step(_subject(1000, 2000, -1), BIG_ROOM)
		assert_float(absf(rig.center.x - rig.previous.x)).is_less_equal(4.0)
	# Lead -60 and the dead zone's 20: focus 940, centre 960.
	assert_float(rig.center.x).is_equal(960.0)


func test_the_lead_never_pulls_the_camera_against_the_players_motion() -> void:
	var rig: CameraRig = _rig()
	rig.reset(_subject(1000, 2000), BIG_ROOM)
	# Facing left while carried right at 2 u a tick (a wall-kick's first frames).
	var x: float = 1000.0
	for _i: int in range(40):
		x += 2.0
		rig.step(_subject(x, 2000, -1), BIG_ROOM)
		assert_float(rig.center.x - rig.previous.x).is_greater_equal(0.0)


func test_stepping_down_catches_up_at_eight_percent_outside_the_dead_zone() -> void:
	var rig: CameraRig = _rig()
	rig.reset(_subject(1000, 2000), BIG_ROOM)
	var y0: float = rig.center.y
	# Standing 115 u lower at once: 100 u beyond the 15 u half dead zone. The speed builds at no
	# more than 3 u per tick per tick, then the lerp takes over: each tick covers 8% of what is
	# left.
	var speeds: Array[float] = []
	for _i: int in range(300):
		var before_y: float = rig.center.y
		rig.step(_subject(1000, 2115), BIG_ROOM)
		speeds.append(rig.center.y - before_y)
		var left: float = y0 + 100.0 - rig.center.y
		if speeds.size() > 6 and left > 1.0:
			assert_float(speeds[-1]).is_equal_approx((left + speeds[-1]) * 0.08, 0.001)
	assert_float(speeds[0]).is_equal_approx(3.0, 0.001)
	assert_float(rig.center.y).is_equal_approx(y0 + 100.0, 0.01)


func test_landing_higher_eases_the_rest_up_before_the_lerp() -> void:
	var rig: CameraRig = _rig()
	rig.reset(_subject(1000, 2000), BIG_ROOM)
	var y0: float = rig.center.y
	var speeds: Array[float] = []
	# A tick in the air, then standing 160 u higher: a landing (walking up continuous ground
	# carries the rest at once instead; ADR-0011).
	rig.step(_subject(1000, 1880, 1, false), BIG_ROOM)
	assert_float(rig.center.y).is_equal(y0)
	for _i: int in range(300):
		rig.step(_subject(1000, 1840), BIG_ROOM)
		speeds.append(rig.center.y - rig.previous.y)
	# The first tick moves the camera less than a unit: no jolt on landing.
	assert_float(absf(speeds[0])).is_less(1.0)
	for i: int in range(1, speeds.size()):
		assert_float(absf(speeds[i] - speeds[i - 1])).is_less_equal(MAX_ACCEL_U)
		assert_float(speeds[i]).is_less_equal(0.0)
	assert_float(rig.center.y).is_equal_approx(y0 - 145.0, 0.01)


func test_crouch_held_looks_down_after_a_delay() -> void:
	var rig: CameraRig = _rig()
	rig.reset(_subject(1000, 2000), BIG_ROOM)
	var y0: float = rig.center.y
	var crouched: CameraSubject = _subject(1000, 2000)
	crouched.looking_down = true
	crouched.box = Rect2(990, 1972, 20, 28)
	for _i: int in range(19):
		rig.step(crouched, BIG_ROOM)
	assert_float(rig.center.y).is_equal(y0)
	for _i: int in range(400):
		rig.step(crouched, BIG_ROOM)
	# Looked exactly 200 u down (the look is added after the dead zone): the player on the view's
	# upper third. Letting go returns the view exactly where it was.
	assert_float(rig.center.y).is_equal_approx(y0 + 200.0, 0.01)
	for _i: int in range(400):
		rig.step(_subject(1000, 2000), BIG_ROOM)
	assert_float(rig.center.y).is_equal_approx(y0, 0.01)


func test_the_view_stays_within_the_room_grown_by_the_margin_and_centres_a_small_one() -> void:
	var rig: CameraRig = _rig()
	var room := Rect2(0, 0, 8000, 4000)
	# Against the left wall: the view may show up to the margin's 80 u beyond the room, and eases
	# toward that bound rather than stopping dead (here it has eased within 1 u of it).
	rig.reset(_subject(42, 900, -1), room)
	assert_float(rig.view_rect().position.x).is_between(-80.0, -79.0)
	var small := Rect2(0, 0, 1280, 640)
	rig.reset(_subject(640, 600), small)
	assert_float(rig.center.x).is_equal(640.0)
	assert_float(rig.center.y).is_equal(320.0)


func test_running_into_a_room_edge_eases_the_view_to_a_stop() -> void:
	var rig: CameraRig = _rig()
	var room := Rect2(0, 0, 4000, 2000)
	rig.reset(_subject(1000, 1800), room)
	var x: float = 1000.0
	var last: float = 0.0
	for _i: int in range(400):
		x = minf(x + 9.0, 3958.0)
		rig.step(_subject(x, 1800), room)
		var v: float = rig.center.x - rig.previous.x
		# Never faster than the player, and, once up to speed, never braking harder than 1 u per
		# tick per tick as the edge nears.
		assert_float(v).is_less_equal(9.0 + 0.001)
		if last > 0.0:
			assert_float(last - v).is_less_equal(1.0)
		last = v
	assert_float(rig.view_rect().end.x).is_between(4079.0, 4080.0)
	assert_int(rig.follow_misses).is_zero()


func test_jumps_inside_the_window_do_not_move_the_camera() -> void:
	var run: CameraRun = _play("res://tests/replay/camera/cam_jumps_flat.fixture")
	# Two full jumps in place and the first of the running jumps: frames 0 to 147.
	for f: int in range(148):
		assert_float(run.velocity(f).y).is_equal(0.0)


func test_a_long_fall_looks_ahead_and_lands_without_overshooting() -> void:
	var run: CameraRun = _play("res://tests/replay/camera/cam_long_drop.fixture")
	var land: int = run.first(SimEvents.LAND, 1)
	assert_int(land).is_greater(60)
	var at_terminal: int = 0
	var checked: int = 0
	for f: int in range(land):
		var s: CameraSubject = run.subjects[f]
		at_terminal = at_terminal + 1 if s.vy >= 25.0 else 0
		# Ten ticks into terminal velocity, until the ground comes within reach of the look-ahead,
		# the view holds at least 0.45 s of fall (675 u) below the feet.
		if at_terminal >= 10 and s.ground_below >= 500.0:
			assert_float(run.view(f).end.y - s.box.end.y).is_greater_equal(675.0)
			checked += 1
	assert_int(checked).is_greater(10)
	# The camera never moves back up after the fall: it settles onto the landing from above.
	for f: int in range(land, run.centers.size()):
		assert_float(run.velocity(f).y).is_greater_equal(0.0)


func test_a_climb_moves_the_camera_steadily() -> void:
	var run: CameraRun = _play("res://tests/replay/camera/cam_shaft_climb.fixture")
	var kicks: Array[int] = _kicks(run)
	var top: int = run.first(SimEvents.LAND, 1)
	assert_int(kicks.size()).is_greater(10)
	assert_int(top).is_greater(kicks[10])
	assert_int(run.first(SimEvents.AIR_JUMP)).is_equal(-1)
	# Once the climb is under way, the camera rises at 6 to 8.5 u a tick to the last kick: it keeps
	# the climb's average pace and never pumps with the kicks. The presses come every 24 ticks,
	# the kick climb's period, so every one finds the wall (camera review 6, L1).
	for f: int in range(kicks[3], kicks[kicks.size() - 1]):
		assert_float(run.velocity(f).y).override_failure_message("frame %d" % f).is_between(
			-8.5, -6.0
		)


func test_a_climb_after_a_slide_takes_up_its_pace_again_without_pumping() -> void:
	# Presses 23 ticks apart against the climb's 24: one of them, on a tick with no wall in reach,
	# spends the air jump, and Ash slides down the wall a tick or two before the next kick. From
	# that kick the view rises again at once and never stops or sinks; its speed swings between
	# 3 and 8.5 u a tick for three kicks (the view lagged the slide and catches up within its
	# acceleration), then settles into the steady climb's 6 to 8.5 (ADR-0011; camera review 6, L1).
	for view: Vector2 in VIEWS:
		var run: CameraRun = _play("res://tests/replay/camera/cam6_climb_after_slide.fixture", view)
		var kicks: Array[int] = _kicks(run)
		var top: int = run.first(SimEvents.LAND, 1)
		var last: int = -1
		for k: int in kicks:
			if k < top:
				last = k
		var slid: int = -1
		for f: int in range(last):
			if run.subjects[f].walled and run.subjects[f].vy > 0.0:
				slid = f
		var later: Array[int] = []
		for k: int in kicks:
			if k > slid:
				later.append(k)
		assert_int(run.first(SimEvents.AIR_JUMP)).is_less(slid)
		assert_int(later.size()).is_greater(8)
		for f: int in range(later[0] + 1, last):
			var band: Vector2 = Vector2(-8.5, -6.0) if f >= later[3] else Vector2(-8.6, -3.0)
			(
				assert_float(run.velocity(f).y)
				. override_failure_message("%s: frame %d" % [view, f])
				. is_between(band.x, band.y)
			)


func _kicks(run: CameraRun) -> Array[int]:
	var kicks: Array[int] = []
	for f: int in range(run.events.size()):
		if run.events[f].has(SimEvents.WALL_KICK):
			kicks.append(f)
	return kicks


func test_a_teleport_glides_instead_of_cutting() -> void:
	var run: CameraRun = _play("res://tests/replay/camera/cam_teleport.fixture")
	var at: int = run.first(SimEvents.TELEPORT)
	assert_int(at).is_equal(45)
	# Starts and ends at rest, and arrives where the follow puts it, in 24 ticks.
	assert_float(absf(run.velocity(at).x)).is_less(4.0)
	assert_float(absf(run.velocity(at + 23).x)).is_less(4.0)
	for f: int in range(at + 24, run.centers.size()):
		assert_float(run.velocity(f).x).is_equal(0.0)
	assert_float(run.centers[at + 24].x).is_equal(run.subjects[at + 24].box.get_center().x + 60.0)


func test_a_hazard_respawn_cuts_to_the_player() -> void:
	var run: CameraRun = _play("res://tests/replay/camera/cam_hazard.fixture")
	var hit: int = run.first(SimEvents.HAZARD)
	assert_int(hit).is_greater(0)
	# No interpolation across the cut: the frame drawn is the new view, whatever alpha is.
	assert_vector(run.previous[hit]).is_equal(run.centers[hit])


func test_every_fixture_keeps_the_player_clear_and_the_camera_smooth() -> void:
	var paths: Array[String] = []
	for dir: String in FIXTURE_DIRS:
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".fixture"):
				paths.append(dir.path_join(f))
	assert_int(paths.size()).is_greater(200)
	# Every fixture is checked at every screen shape, and every one that breaks a rule is
	# reported, not just the first.
	var problems: PackedStringArray = []
	for view: Vector2 in VIEWS:
		for path: String in paths:
			var run: CameraRun = _play(path, view)
			var problem: String = _first_problem(run)
			# The backstop keeps the player clear of the margin whatever the follow does, so the
			# real check is that it never had to.
			if problem == "" and run.rig.follow_misses > 0:
				problem = "the margin had to move the view %d times" % run.rig.follow_misses
			if problem != "":
				problems.append("%s at %s: %s" % [path.get_file(), view, problem])
	if not problems.is_empty():
		fail("\n".join(problems))


## The first tick that breaks a camera rule, described, or "".
func _first_problem(run: CameraRun) -> String:
	for f: int in range(1, run.centers.size()):
		var s: CameraSubject = run.subjects[f]
		if s.respawned or s.teleported or s.entered:
			continue
		var moved: float = s.box.get_center().x - run.subjects[f - 1].box.get_center().x
		var glide: bool = run.gliding[f] or run.gliding[f - 1]
		if not glide and moved * run.velocity(f).x < -0.001:
			return "frame %d: the camera moves against the player" % f
		# Horizontally the view moves with the player, plus at most the lead's swing: it never
		# outruns the player (ADR-0011: the horizontal follow is rigid by design).
		var lead_swing: float = float(run.rig.tuning.lead_speed_u)
		if not glide and absf(run.velocity(f).x) > absf(moved) + lead_swing + 0.001:
			return "frame %d: the camera outruns the player across" % f
		var problem: String = _vertical_speed_problem(run, f, glide)
		if problem != "":
			return "frame %d: %s" % [f, problem]
	if run.longest_run_against() >= TILE_U:
		return "the view moves %.0f u against the player" % run.longest_run_against()
	return ""


## Vertically the view changes speed by at most MAX_ACCEL_U a tick (MAX_GLIDE_ACCEL_U in a
## glide), except that a view outrunning the player may slow at once to the player's own speed
## (ADR-0011).
func _vertical_speed_problem(run: CameraRun, f: int, glide: bool) -> String:
	var v: float = run.velocity(f).y
	var was: float = run.velocity(f - 1).y
	var limit: float = MAX_GLIDE_ACCEL_U if glide else MAX_ACCEL_U
	var lo: float = was - limit
	var hi: float = was + limit
	var player_vy: float = run.subjects[f].vy
	if was > 0.0 and player_vy < was:
		lo = minf(lo, player_vy)
	elif was < 0.0 and player_vy > was:
		hi = maxf(hi, player_vy)
	if v < lo - 0.001 or v > hi + 0.001:
		return "vertical speed changes from %.2f to %.2f u in a tick" % [was, v]
	return ""
