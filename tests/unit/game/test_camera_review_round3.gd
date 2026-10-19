extends GdUnitTestSuite
## The camera review's third round (docs/adr/0011), one test or more per finding: moving on at
## once after a teleport (H1), steering onto a ledge late in a fall (H2), dropping into the space
## looked down at (M1), wall-jumping across a narrow shaft (M2) and a room with no border tiles
## (L1).

## The view sizes the game may run at: 16:9, 16:10, 4:3 and 21:9 (GameCamera shows a taller or
## wider screen more world, never less).
const VIEWS: Array[Vector2] = [
	Vector2(1920, 1080), Vector2(1920, 1200), Vector2(1920, 1440), Vector2(2520, 1080)
]
## The most the view may travel up in the 20 ticks after Ash drops off into a look (half a tile).
const DROP_RISE_U: float = 16.0


func _rig(view: Vector2 = VIEWS[0]) -> CameraRig:
	var rig := CameraRig.new(load(CameraRig.TUNING_PATH) as CameraTuning)
	rig.view_size = view
	return rig


func _play(path: String, view: Vector2 = VIEWS[0]) -> CameraRun:
	var run: CameraRun = CameraRun.play(path, _rig(view))
	assert_array(Array(run.errors)).is_empty()
	return run


## A run away from a lingering ember for [param n] ticks, a teleport to it, then [param onward]
## at once: a run, a dash or nothing across ("side_*"), or an up-dash or a jump ("up_*").
func _teleport_and_go(onward: String, n: int) -> String:
	var lines: PackedStringArray = ["fixture teleport_%s_%d" % [onward, n], "doc sweep"]
	lines.append("room test/camera")
	if onward.begins_with("side"):
		lines.append_array(["spawn 3000 3200", "frames %d" % (n + 90), "input", "  0 R toss"])
		lines.append_array(["  1..%d L" % n, "  %d toss" % (n + 1)])
		if onward == "side_run":
			lines.append("  %d..%d R" % [n + 2, n + 80])
		else:
			lines.append_array(["  %d R dash" % (n + 2), "  %d..%d R" % [n + 3, n + 80]])
	else:
		lines.append_array(["spawn 5400 960", "frames %d" % (n + 90), "input", "  0 U toss"])
		lines.append_array(["  1..12 R", "  %d toss" % n])
		if onward == "up_updash":
			lines.append("  %d U dash" % (n + 1))
		else:
			lines.append("  %d..%d jump" % [n + 1, n + 25])
	lines.append_array(["end", "expect", "end"])
	return "\n".join(lines) + "\n"


func test_moving_on_at_once_after_a_teleport_never_needs_the_backstop() -> void:
	# H1: a teleport that left Ash just outside the margin glided from the old view, which starts
	# at rest; a dash or an up-dash straight after it reached the margin first. Every distance
	# from a short hop to a long run, at 16:9, 4:3 and 21:9.
	var sweeps: Dictionary[String, Array] = {
		"side_run": range(30, 72, 2),
		"side_dash": range(30, 72, 2),
		"up_updash": range(14, 42, 2),
		"up_jump": range(14, 42, 2),
	}
	var problems: PackedStringArray = []
	for view: Vector2 in [VIEWS[0], VIEWS[2], VIEWS[3]]:
		for onward: String in sweeps:
			for n: int in sweeps[onward]:
				var fx: Fixture = Fixture.parse_text(_teleport_and_go(onward, n))
				var run: CameraRun = CameraRun.play_fixture(fx, _rig(view))
				assert_array(Array(run.errors)).is_empty()
				assert_int(run.first(SimEvents.TELEPORT)).is_greater(0)
				if run.rig.follow_misses > 0:
					problems.append("%s %d at %s: %d" % [onward, n, view, run.rig.follow_misses])
	if not problems.is_empty():
		fail("the margin had to move the view: " + ", ".join(problems))


func test_the_band_fixtures_cut_the_axis_and_never_need_the_backstop() -> void:
	for path: String in ["cam_teleport_band_dash", "cam_teleport_band_updash"]:
		var run: CameraRun = _play("res://tests/replay/camera/%s.fixture" % path)
		var at: int = run.first(SimEvents.TELEPORT)
		# The axis is cut: no interpolation across it.
		assert_vector(run.previous[at]).is_not_equal(run.centers[at - 1])
		assert_int(run.rig.follow_misses).is_equal(0)


func test_steering_onto_a_ledge_late_never_brings_the_view_back_up() -> void:
	# H2: the look used to assume the fall kept its speed across, so a ledge Ash steered onto
	# appeared a few ticks before the landing: the view overshot it and drifted back up 180 u.
	var run: CameraRun = _play("res://tests/replay/camera/cam_steer_onto_ledge_late.fixture")
	var land: int = run.first(SimEvents.LAND, 1)
	assert_int(land).is_greater(90)
	# The view never got past the ledge: at the landing its centre is above the feet ...
	assert_float(run.centers[land].y).is_less(run.subjects[land].box.end.y)
	# ... and it never comes back up.
	for f: int in range(land, run.centers.size()):
		assert_float(run.velocity(f).y).override_failure_message("tick %d" % f).is_greater_equal(
			0.0
		)


func test_a_fall_past_a_ledge_brakes_the_look_and_recovers() -> void:
	# The cost of H2's fix, by design: a ledge Ash could still steer onto counts as the landing,
	# so falling past one shortens the look until it is passed, and the look grows back after.
	var run: CameraRun = _play("res://tests/replay/camera/cam_fall_past_ledge.fixture")
	var shortest: float = INF
	var regrown: float = 0.0
	var passed: bool = false
	for f: int in range(60, run.subjects.size()):
		var s: CameraSubject = run.subjects[f]
		if s.ground_below < CameraSubject.NO_GROUND:
			shortest = minf(shortest, run.fall_looks[f])
		elif shortest < INF:
			passed = true
			regrown = maxf(regrown, run.fall_looks[f])
	assert_bool(passed).is_true()
	assert_float(regrown).is_greater(shortest + 100.0)
	assert_int(run.rig.follow_misses).is_equal(0)


func test_dropping_into_a_look_keeps_the_view_going_down() -> void:
	# M1: leaving the ground ended a look at once, so dropping through a one-way or walking off
	# into the space looked at swung the view up against Ash (33 to 50 u) before it followed.
	for path: String in ["cam_oneway_look_drop", "cam_look_walk_off"]:
		var run: CameraRun = _play("res://tests/replay/camera/%s.fixture" % path)
		var looked: int = -1
		for f: int in range(run.looks.size()):
			if looked < 0 and run.looks[f] >= 150.0:
				looked = f
		assert_int(looked).override_failure_message(path).is_greater(0)
		var off: int = looked
		while run.subjects[off].on_ground:
			off += 1
		var rise: float = 0.0
		for f: int in range(off, off + 20):
			rise += maxf(-run.velocity(f).y, 0.0)
		assert_float(rise).override_failure_message(path).is_less(DROP_RISE_U)


func test_wall_jumping_across_a_narrow_shaft_does_not_swing_the_lead() -> void:
	# M2: in a room wider than the view, each 108 u crossing committed the lead after 40 u and
	# added its swing to Ash's own speed, so the world shook sideways three times a second. A
	# crossing is shorter than the lead's whole swing now: across, the view moves no faster than
	# Ash.
	var run: CameraRun = _play("res://tests/replay/camera/cam_wide_shaft_jumps.fixture")
	for f: int in range(100, run.centers.size()):
		var moved: float = (
			run.subjects[f].box.get_center().x - run.subjects[f - 1].box.get_center().x
		)
		assert_float(absf(run.velocity(f).x)).override_failure_message("tick %d" % f).is_less_equal(
			absf(moved) + 0.001
		)


func test_a_room_without_border_tiles_never_needs_the_backstop() -> void:
	# L1: the eased bounds only approached the room's edge, so standing on the grid's own edge
	# (no border tiles) left Ash 0.2 u inside the margin on every tick.
	for view: Vector2 in VIEWS:
		var run: CameraRun = _play("res://tests/replay/camera/cam_noborder.fixture", view)
		assert_int(run.rig.follow_misses).override_failure_message(str(view)).is_equal(0)
		assert_float(run.gap(0)).is_greater_equal(80.0 - 0.001)
