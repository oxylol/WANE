extends GdUnitTestSuite
## The camera review's fourth round (docs/adr/0011), one sweep or more per finding: falls beside a
## wall and down shafts (H1), dropping onto near ground after a look (H2), a room edge with no
## border tiles above or below (H3), wall-jumping up shafts of every width (M1), running off the
## top after a climb (M2), a long 45-degree climb (L1) and the commit distance as content (L2).
## Round 3's tests each pinned the one geometry that showed its bug (L3); these sweep the
## dimension the bug lives in.

## The view sizes the game may run at: 16:9, 16:10, 4:3 and 21:9.
const VIEWS: Array[Vector2] = [
	Vector2(1920, 1080), Vector2(1920, 1200), Vector2(1920, 1440), Vector2(2520, 1080)
]
## Floating-point slack for comparisons of view travel: views are float32 vectors, which at
## y = 4096 u resolve 0.0005 u (camera review 5, L2: a 3 u change measured 3.000244).
const EPS: float = 0.001
## The most the view may travel up while Ash drops onto ground after a look (rounding only).
const DROP_RISE_U: float = 1.0


func _rig(view: Vector2, tuning: CameraTuning = null) -> CameraRig:
	var rig := CameraRig.new(
		tuning if tuning != null else load(CameraRig.TUNING_PATH) as CameraTuning
	)
	rig.view_size = view
	return rig


## A fixture in [param room] from ([param x], [param y]) for [param frames] ticks with the given
## input lines.
func _fixture(room: String, x: int, y: int, frames: int, inputs: PackedStringArray = []) -> Fixture:
	var text: String = (
		"fixture sweep\ndoc sweep\nroom test/%s\nspawn %d %d\nframes %d\ninput\n"
		% [room, x, y, frames]
	)
	text += "\n".join(inputs) + "\nend\nexpect\nend\n"
	return Fixture.parse_text(text)


func _run(fx: Fixture, view: Vector2) -> CameraRun:
	var run: CameraRun = CameraRun.play_fixture(fx, _rig(view))
	assert_array(Array(run.errors)).is_empty()
	return run


## Wall-jumps up the [param n]-tile shaft of cam_shaft_w[param n] from its floor, starting flush
## against the left wall so that every tick from the first cling is a crossing or a cling.
func _shaft_jumps(n: int) -> Fixture:
	return Fixture.parse_text(ShaftJumps.fixture_text("test/cam_shaft_w%d" % n, 1643, 2176, 330))


func _deepest_fall_look(run: CameraRun) -> float:
	var deepest: float = 0.0
	for v: float in run.fall_looks:
		deepest = maxf(deepest, v)
	return deepest


func test_a_fall_beside_a_wall_looks_as_far_ahead_as_one_in_the_open() -> void:
	# H1: walls inside the steering envelope counted as ground, so a fall along a wall had no
	# look at all and needed the backstop at the landing; a ledge behind a wall counted too.
	# Falls with the box 0 to 200 u from a tall wall, a drop from a cling, and a fall flush
	# against a one-tile wall with ledges behind it, against the same fall in the open.
	var problems: PackedStringArray = []
	for view: Vector2 in VIEWS:
		var open: float = _deepest_fall_look(_run(_fixture("cam_wells", 1248, 320, 260), view))
		var cases: Dictionary[String, Fixture] = {}
		for d: int in [0, 10, 20, 40, 70, 100, 150, 200]:
			cases["%d u from the wall" % d] = _fixture("cam_wells", 650 + d, 320, 260)
		cases["the cling drop"] = Fixture.parse_file(
			"res://tests/replay/camera/cam_cling_drop.fixture"
		)
		cases["the ledge behind a wall"] = _fixture("cam_wall_ledge", 682, 320, 260)
		for label: String in cases:
			var run: CameraRun = _run(cases[label], view)
			var look: float = _deepest_fall_look(run)
			if look < open - EPS or run.rig.follow_misses > 0:
				problems.append(
					(
						"%s at %s: look %.1f of %.1f, %d backstop moves"
						% [label, view, look, open, run.rig.follow_misses]
					)
				)
	if not problems.is_empty():
		fail("\n".join(problems))


func test_a_fall_down_a_shaft_of_any_width_looks_as_far_ahead_as_one_in_the_open() -> void:
	# H1: the look capped at 250 u in a 128 u shaft and 425 u in a 256 u one. Shafts 3 to 9
	# tiles wide (96 to 288 u), fallen down the middle.
	var problems: PackedStringArray = []
	for view: Vector2 in VIEWS:
		for n: int in range(3, 10):
			var room: String = "cam_shaft_w%d" % n
			var open: float = _deepest_fall_look(_run(_fixture(room, 400, 300, 120), view))
			var run: CameraRun = _run(_fixture(room, 1632 + 16 * n, 300, 120), view)
			var look: float = _deepest_fall_look(run)
			if look < open - EPS or run.rig.follow_misses > 0:
				problems.append(
					(
						"%d u shaft at %s: look %.1f of %.1f, %d backstop moves"
						% [n * 32, view, look, open, run.rig.follow_misses]
					)
				)
	if not problems.is_empty():
		fail("\n".join(problems))


func test_a_fall_along_a_wall_lands_with_the_view_as_one_in_the_open_does() -> void:
	# H1: falling along a wall onto a shelf, the view was still moving at 22 u a tick at the
	# landing and travelled 250 u more while Ash stood; in the open it travels about 50.
	for view: Vector2 in VIEWS:
		var travels: Array[float] = []
		for path: String in ["cam_cling_drop_mid", "cam_open_drop_mid"]:
			var run: CameraRun = _run(
				Fixture.parse_file("res://tests/replay/camera/%s.fixture" % path), view
			)
			var land: int = run.first(SimEvents.LAND, 40)
			assert_int(land).override_failure_message(path).is_greater(0)
			var travel: float = 0.0
			for f: int in range(land + 1, run.centers.size()):
				travel += absf(run.velocity(f).y)
			travels.append(travel)
		assert_float(travels[0]).override_failure_message(str(view)).is_less_equal(
			travels[1] + 16.0
		)


func test_dropping_onto_near_ground_after_a_look_never_swings_the_view_up() -> void:
	# H2: the look collapsed to the near ground in a tick while the view already showed past it,
	# so the view rose 69 u against a 64 u drop. Drops of 64 to 256 u from a one-way after a
	# 60-tick look, letting go of down or holding it.
	var drops: Dictionary[int, int] = {64: 288, 96: 832, 128: 1376, 192: 1920, 256: 2464}
	var problems: PackedStringArray = []
	for view: Vector2 in VIEWS:
		for depth: int in drops:
			for hold: bool in [false, true]:
				var inputs: PackedStringArray = ["  0..59 D", "  60 D jump"]
				if hold:
					inputs.append("  61..200 D")
				var run: CameraRun = _run(
					_fixture("cam_drops", drops[depth], 960, 220, inputs), view
				)
				assert_int(run.first(SimEvents.DROP_THROUGH)).is_equal(60)
				var off: int = 60
				while run.subjects[off].on_ground:
					off += 1
				var rise: float = 0.0
				var f: int = off
				while f < run.subjects.size() and not run.subjects[f].on_ground:
					rise += maxf(-run.velocity(f).y, 0.0)
					f += 1
				if rise >= DROP_RISE_U:
					problems.append(
						"%d u%s at %s: rose %.1f u" % [depth, " held" if hold else "", view, rise]
					)
	if not problems.is_empty():
		fail("\n".join(problems))


func test_a_room_edge_without_border_tiles_never_needs_the_backstop_vertically() -> void:
	# H3: the eased bound was approached exponentially, so a fall onto the grid's own bottom edge
	# or a climb into its top reached the margin 13 to 20 u before the view caught up.
	for view: Vector2 in VIEWS:
		for path: String in ["cam_noborder_fall", "cam_noborder_fall_side", "cam_noceiling_climb"]:
			var run: CameraRun = _run(
				Fixture.parse_file("res://tests/replay/camera/%s.fixture" % path), view
			)
			(
				assert_int(run.rig.follow_misses)
				. override_failure_message("%s at %s" % [path, view])
				. is_equal(0)
			)


func test_wall_jumping_up_a_shaft_of_any_width_never_outruns_ash_across() -> void:
	# M1: in shafts wider than 140 u each crossing committed the lead and added its swing to
	# Ash's own speed. A wall contact suspends the commit until Ash lands, so inside a shaft the
	# view moves across no faster than Ash, whatever the shaft's width (3 to 9 tiles).
	var problems: PackedStringArray = []
	for n: int in range(3, 10):
		var left: float = 1632.0
		var right: float = left + 32.0 * n
		var fx: Fixture = _shaft_jumps(n)
		for view: Vector2 in VIEWS:
			var run: CameraRun = _run(fx, view)
			var contact: int = run.first(SimEvents.WALL_CLING)
			assert_int(contact).is_between(1, 20)
			for f: int in range(contact, run.centers.size()):
				var b: Rect2 = run.subjects[f].box
				if b.position.x < left or b.end.x > right or b.end.y < 256.0:
					continue
				var moved: float = b.get_center().x - run.subjects[f - 1].box.get_center().x
				if absf(run.velocity(f).x) > absf(moved) + EPS:
					problems.append("%d u shaft at %s: tick %d" % [n * 32, view, f])
					break
			# Every width really is crossed, wall to wall, many times (the narrow ones are climbed
			# out of; from 6 tiles a wall jump no longer gains height, so Ash stays inside).
			var jumps: int = 0
			for kinds: PackedStringArray in run.events:
				jumps += kinds.count(SimEvents.WALL_JUMP)
			assert_int(jumps).override_failure_message("%d u shaft" % (n * 32)).is_greater(5)
	if not problems.is_empty():
		fail("the view outran Ash across: " + ", ".join(problems))


func test_the_view_never_rises_while_ash_falls_after_a_climb() -> void:
	# M2: climbing out of a shaft leaves the view behind; running off the top, the view kept
	# easing up at 5 u a tick while Ash fell. The adopted fixture and every shaft width. Falling at
	# or below the last support the view never rises; above it (the way down of a kick or hop
	# that lands higher) its rise only shrinks, by at least the acceleration limit a tick (camera
	# review 5, M1: stopping it dead there made a staircase stutter).
	var fixtures: Array[Fixture] = [
		Fixture.parse_file("res://tests/replay/camera/cam_shaft_climb_out.fixture")
	]
	for n: int in range(3, 10):
		fixtures.append(_shaft_jumps(n))
	var problems: PackedStringArray = []
	for fx: Fixture in fixtures:
		for view: Vector2 in VIEWS:
			var run: CameraRun = _run(fx, view)
			var accel: float = run.rig.tuning.vertical_accel_milli_u / 1000.0
			for f: int in range(1, run.centers.size()):
				var s: CameraSubject = run.subjects[f]
				var v: float = run.velocity(f).y
				var above: bool = s.box.end.y < run.supports[f - 1] - 0.5
				var shrinks: bool = v >= minf(run.velocity(f - 1).y + accel, 0.0) - EPS
				if above and run.velocity(f - 1).y < 0.0 and shrinks:
					continue
				if not s.supported and s.vy > 0.0 and v < -EPS:
					problems.append(
						(
							"%s at %s: tick %d rises %.2f"
							% [fx.scenario.room, view, f, run.velocity(f).y]
						)
					)
					break
	if not problems.is_empty():
		fail("\n".join(problems))


func test_a_long_45_degree_climb_keeps_its_headroom() -> void:
	# L1: the rest rose at 8 u a tick while Ash climbed at 9, so on a long ramp the view fell
	# behind until the window stopped it (the top gap shrank from 334 to 181 u). Once the climb
	# is under way the view keeps pace with it: the top gap holds steady up to the crest.
	for view: Vector2 in VIEWS:
		var run: CameraRun = _run(
			Fixture.parse_file("res://tests/replay/camera/cam_ramp_up.fixture"), view
		)
		var crest: int = 0
		for f: int in range(run.subjects.size()):
			if run.subjects[f].box.end.y < run.subjects[crest].box.end.y:
				crest = f
		assert_int(crest).is_greater(200)
		var lo: float = INF
		var hi: float = -INF
		# The lerp's lag settles within about 100 ticks of the foot, and the room's top bound
		# reaches the view in the last 30 before the crest; between, a 1 u drift a tick (the
		# bug) would show as 60 u.
		for f: int in range(crest - 90, crest - 30):
			var top: float = run.subjects[f].box.position.y - run.view(f).position.y
			lo = minf(lo, top)
			hi = maxf(hi, top)
		assert_float(hi - lo).override_failure_message(str(view)).is_less_equal(1.0)


func test_the_commit_distance_is_tuned_in_content() -> void:
	# L2: the commit distance was twice the lead, a literal in code. It is lead_commit_u now:
	# turning and walking away commits the lead once Ash has gone that far.
	var base: CameraTuning = load(CameraRig.TUNING_PATH) as CameraTuning
	assert_int(base.lead_commit_u).is_equal(120)
	var committed: Array[int] = []
	for distance: int in [40, 120]:
		var tuning: CameraTuning = base.duplicate() as CameraTuning
		tuning.lead_commit_u = distance
		tuning.lead_commit_frames = 1000
		var rig: CameraRig = _rig(VIEWS[0], tuning)
		var room := Rect2(-8000, -8000, 16000, 16000)
		rig.reset(_subject(1000.0, 1), room)
		var at: int = -1
		for t: int in range(1, 40):
			rig.step(_subject(1000.0 - 9.0 * t, -1), room)
			if at < 0 and rig._lead_dir < 0:
				at = t
		committed.append(at)
	# The turn starts on the first tick facing away (x 991): 45 u on is the first step past 40,
	# 126 u the first past 120.
	assert_array(committed).is_equal([6, 15])


func _subject(x: float, facing: int) -> CameraSubject:
	var s := CameraSubject.new()
	s.box = Rect2(x - 10, 1956, 20, 44)
	s.stand_height = 44.0
	s.facing = facing
	s.supported = true
	s.on_ground = true
	s.ground_below = 0.0
	return s
