extends GdUnitTestSuite
## The camera review's fifth round (docs/adr/0011), on the review's own fixtures
## (tests/replay/camera/cam5_*), at all four screen shapes: the fall look past a landing the probe
## missed (H1), the view sinking while Ash rises (H2), the look-down pumping (H3), the stop at
## every hop's apex (M1), a borderless top and a teleport by a borderless side needing the
## backstop (M2, M3), the drop over a climbed wall with no look (M4) and the lead stuck after a
## wall-jump (L1). The camera rig's suite plays these fixtures too, under every rule it checks.

const VIEWS: Array[Vector2] = [
	Vector2(1920, 1080), Vector2(1920, 1200), Vector2(1920, 1440), Vector2(2520, 1080)
]
const DIR: String = "res://tests/replay/camera/"


func _run(fixture_name: String, view: Vector2) -> CameraRun:
	var rig := CameraRig.new(load(CameraRig.TUNING_PATH) as CameraTuning)
	rig.view_size = view
	var run: CameraRun = CameraRun.play(DIR + fixture_name + ".fixture", rig)
	assert_array(Array(run.errors)).is_empty()
	return run


## The most any fall's look reached below where that fall landed.
func _look_past_landing(run: CameraRun) -> float:
	var worst: float = 0.0
	var start: int = -1
	for f: int in range(run.subjects.size()):
		var s: CameraSubject = run.subjects[f]
		if s.teleported or s.respawned:
			start = -1
			continue
		if s.supported:
			if start >= 0 and run.events[f].has(SimEvents.LAND):
				for k: int in range(start, f):
					var past: float = run.subjects[k].box.end.y + run.fall_looks[k] - s.box.end.y
					if run.fall_looks[k] > 0.0:
						worst = maxf(worst, past)
			start = -1
		elif start < 0:
			start = f
	return worst


## The most the view came back up after a landing while Ash stood where it landed.
func _comeback(run: CameraRun) -> float:
	var worst: float = 0.0
	for f: int in range(run.subjects.size()):
		if not run.events[f].has(SimEvents.LAND):
			continue
		var feet: float = run.subjects[f].box.end.y
		var lowest: float = run.centers[f].y
		var k: int = f + 1
		while (
			k < run.subjects.size()
			and run.subjects[k].on_ground
			and absf(run.subjects[k].box.end.y - feet) < 0.5
			and not run.subjects[k].looking_down
			and run.looks[k] <= 0.0
			and not run.gliding[k]
		):
			lowest = maxf(lowest, run.centers[k].y)
			worst = maxf(worst, lowest - run.centers[k].y)
			k += 1
	return worst


func test_a_fall_look_never_runs_past_a_landing_the_player_steered_or_carried_onto() -> void:
	# H1: reversing back onto a ledge, and a fall beside a wall that ends in a notch. The probe
	# now sums air control as the player moves, adds the ledge-grab and keeps the speed past a wall
	# that ends.
	for fixture_name: String in ["cam5_reverse_onto_ledge", "cam5_notch_landing"]:
		for view: Vector2 in VIEWS:
			var run: CameraRun = _run(fixture_name, view)
			var where: String = "%s at %s" % [fixture_name, view]
			assert_float(_look_past_landing(run)).override_failure_message(where).is_less_equal(
				48.0
			)
			assert_float(_comeback(run)).override_failure_message(where).is_less_equal(1.0)


func test_the_view_never_sinks_while_ash_rises() -> void:
	# H2: an air jump just above the floor at the end of a fall, and a jump buffered onto the
	# landing after a climb and a drop.
	for fixture_name: String in ["cam5_air_jump_above_floor", "cam5_climb_drop_buffered_jump"]:
		for view: Vector2 in VIEWS:
			var run: CameraRun = _run(fixture_name, view)
			for f: int in range(1, run.subjects.size()):
				var s: CameraSubject = run.subjects[f]
				if s.supported or s.vy >= 0.0 or run.gliding[f] or s.teleported:
					continue
				(
					assert_float(run.velocity(f).y)
					. override_failure_message("%s at %s: frame %d" % [fixture_name, view, f])
					. is_less_equal(0.001)
				)


func test_a_look_down_held_through_a_drop_never_pumps() -> void:
	# H3: down held through the drop and the landing: the view rose 90 u and sank 116 u.
	for view: Vector2 in VIEWS:
		var run: CameraRun = _run("cam_look_drop_64_hold", view)
		var pump: float = 0.0
		var low: float = -INF
		for f: int in range(run.subjects.size()):
			if run.subjects[f].looking_down and (f == 0 or run.subjects[f - 1].looking_down):
				low = maxf(low, run.centers[f].y)
				pump = maxf(pump, low - run.centers[f].y)
			else:
				low = run.centers[f].y if run.subjects[f].looking_down else -INF
		assert_float(pump).override_failure_message(str(view)).is_less_equal(2.0)


func test_hops_up_a_staircase_never_stop_the_view_dead() -> void:
	# M1: the view's rise went from 9 u a tick to nothing at every apex.
	var accel: float = float((load(CameraRig.TUNING_PATH) as CameraTuning).vertical_accel_milli_u)
	for fixture_name: String in ["cam5_staircase_hops", "cam5_look_then_jump_drift"]:
		for view: Vector2 in VIEWS:
			var run: CameraRun = _run(fixture_name, view)
			for f: int in range(2, run.subjects.size()):
				if run.gliding[f] or run.gliding[f - 1] or run.subjects[f].supported:
					continue
				var change: float = absf(run.velocity(f).y - run.velocity(f - 1).y)
				var player: float = run.subjects[f].vy
				var was: float = run.velocity(f - 1).y
				# The one exception: slowing at once to the player's own speed (a landing). A jump
				# out of the look-down, the view still sinking into it, stops the view within the
				# limit and never snaps it into a rise (frame 60 of the drift fixture: from 1.85 u
				# a tick down to 14.3 up, before the fix).
				var to_player: bool = absf(run.velocity(f).y - player) < 0.001
				if was * run.velocity(f).y >= 0.0 and to_player:
					continue
				(
					assert_float(change)
					. override_failure_message("%s at %s: frame %d" % [fixture_name, view, f])
					. is_less_equal(accel / 1000.0 + 0.001)
				)


func test_borderless_edges_never_need_the_backstop() -> void:
	# M2: a jump, the air jump and an up-dash into a borderless top; M3: a teleport by a
	# borderless side, then a dash toward it.
	for fixture_name: String in ["cam5_borderless_top_up_dash", "cam5_teleport_borderless_side"]:
		for view: Vector2 in VIEWS:
			var run: CameraRun = _run(fixture_name, view)
			(
				assert_int(run.rig.follow_misses)
				. override_failure_message("%s at %s" % [fixture_name, view])
				. is_equal(0)
			)


func test_a_drop_over_a_climbed_wall_looks_ahead_as_an_open_drop_does() -> void:
	# M4: the look started only below the eased rest, which lags a climb: Ash fell 250 u with none
	# and saw 442 u below the feet at terminal speed against 630 u in the open.
	for view: Vector2 in VIEWS:
		var climb: float = _least_below_at_terminal(_run("cam5_climb_drop", view))
		var open: float = _least_below_at_terminal(_run("cam5_open_drop", view))
		assert_float(climb).override_failure_message(str(view)).is_greater_equal(open * 0.9)


func _least_below_at_terminal(run: CameraRun) -> float:
	var least: float = INF
	for f: int in range(run.subjects.size()):
		var s: CameraSubject = run.subjects[f]
		if s.supported or s.vy < 24.9:
			continue
		least = minf(least, run.view(f).end.y - s.box.end.y)
	return least


func test_the_lead_turns_with_a_long_drift_after_a_wall_jump() -> void:
	# L1: the lead pointed back at the wall for the 136 ticks of a 1220 u drift. It turns once
	# Ash is lead_wall_release_u from the wall, then commits as any turn does.
	var tuning: CameraTuning = load(CameraRig.TUNING_PATH) as CameraTuning
	for view: Vector2 in VIEWS:
		var run: CameraRun = _run("cam5_wall_jump_long_drift", view)
		var stale: int = 0
		var longest: int = 0
		for f: int in range(1, run.subjects.size()):
			var s: CameraSubject = run.subjects[f]
			var moved: float = s.box.get_center().x - run.subjects[f - 1].box.get_center().x
			if moved * s.facing > 3.0 and run.leads[f] != signi(s.facing):
				stale += 1
				longest = maxi(longest, stale)
			else:
				stale = 0
		# Within the release distance at Ash's drift speed, plus the commit.
		var limit: int = ceili(tuning.lead_wall_release_u / 9.0) + tuning.lead_commit_frames
		assert_int(longest).override_failure_message(str(view)).is_less_equal(limit)
