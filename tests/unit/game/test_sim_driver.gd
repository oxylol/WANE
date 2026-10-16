extends GdUnitTestSuite
## Fixed-step driver (BUILD.md section 13: one step per 60 Hz tick).


func _driver() -> SimDriver:
	var d: SimDriver = auto_free(SimDriver.new())
	d.start(Scenario.make(1))
	return d


## A driver that has seen two seconds of exact 60 Hz frames and locked to the display.
func _locked_driver() -> SimDriver:
	var d: SimDriver = _driver()
	for _i: int in range(SimDriver.LOCK_FRAMES):
		d._process(1.0 / 60.0)
	assert_bool(d.is_locked()).is_true()
	return d


func test_sixty_hertz_frames_step_exactly_once_and_draw_the_newest_state() -> void:
	var d: SimDriver = _locked_driver()
	var start: int = d.sim.tick
	# Vsync jitter around 16.67 ms is one tick per frame, and each frame draws the tick it just
	# stepped (alpha 1): no added display latency.
	for delta: float in [0.0166, 0.0167, 0.01672, 0.01661, 0.0167]:
		d._process(delta)
		assert_float(d.alpha).is_equal(1.0)
	assert_int(d.sim.tick - start).is_equal(5)
	assert_int(d.recorder.replay.frame_count()).is_equal(d.sim.tick)


func test_high_refresh_steps_at_the_start_of_each_tick_and_interpolates() -> void:
	var d: SimDriver = _driver()
	d._process(1.0 / 120.0)
	assert_int(d.sim.tick).is_equal(1)
	assert_float(d.alpha).is_equal_approx(0.5, 0.001)
	d._process(1.0 / 120.0)
	assert_int(d.sim.tick).is_equal(1)
	assert_float(d.alpha).is_equal_approx(1.0, 0.001)
	for _i: int in range(118):
		d._process(1.0 / 120.0)
	assert_int(d.sim.tick).is_equal(60)
	assert_bool(d.is_locked()).is_false()


func test_off_sixty_displays_keep_real_speed() -> void:
	# 59 and 62 Hz are within the snap window and lock; the rounding is paid back so ten real
	# seconds are still 600 ticks (BUILD.md: deterministic 60 Hz simulation at any display rate).
	for hz: float in [59.0, 62.0, 61.5]:
		var d: SimDriver = _driver()
		for _i: int in range(int(hz * 10.0)):
			d._process(1.0 / hz)
		assert_bool(d.is_locked()).is_true()
		assert_int(d.sim.tick).is_between(599, 601)


func test_jittery_sixty_hertz_always_draws_the_newest_state_once_locked() -> void:
	# Ten minutes of 60 Hz with +-0.5 ms jitter: locked after two seconds, then every frame ends
	# on a tick (alpha 1), and the clock keeps real time.
	var d: SimDriver = _driver()
	var rng: Rng = Rng.seeded(3, 0)
	var below_one: int = 0
	var real: float = 0.0
	for i: int in range(36000):
		var delta: float = 1.0 / 60.0 + float(rng.between(-500, 500)) / 1000000.0
		d._process(delta)
		real += delta
		if i >= SimDriver.LOCK_FRAMES and d.alpha < 1.0:
			below_one += 1
	assert_int(below_one).is_equal(0)
	assert_int(d.sim.tick).is_between(roundi(real * 60.0) - 1, roundi(real * 60.0) + 1)


func test_one_odd_frame_does_not_shift_later_frames_off_the_tick() -> void:
	# A locked driver meets one frame outside the snap window (late, early, or a hitch of two
	# ticks plus a little), then ten minutes of 60 Hz with +-0.3 ms jitter: every frame,
	# the odd one included, draws the newest state, it never steps twice for the odd frame, and
	# the clock still keeps real time.
	for odd: float in [0.0007, 0.002, -0.0007, 1.0 / 60.0 + 0.0007]:
		var d: SimDriver = _locked_driver()
		var rng: Rng = Rng.seeded(5, 0)
		var real: float = SimDriver.LOCK_FRAMES / 60.0
		var tick0: int = d.sim.tick
		d._process(1.0 / 60.0 + odd)
		real += 1.0 / 60.0 + odd
		assert_int(d.sim.tick - tick0).is_equal(2 if odd > 0.01 else 1)
		var below_one: int = 0 if d.alpha == 1.0 else 1
		for _i: int in range(36000):
			var delta: float = 1.0 / 60.0 + float(rng.between(-300, 300)) / 1000000.0
			d._process(delta)
			real += delta
			if d.alpha < 1.0:
				below_one += 1
		assert_int(below_one).override_failure_message("odd frame %f" % odd).is_equal(0)
		assert_bool(d.is_locked()).is_true()
		var expected: int = roundi(real * 60.0)
		assert_int(d.sim.tick).is_between(expected - 1, expected + 1)


func test_hitch_of_whole_ticks_steps_them_and_draws_the_newest_state() -> void:
	var d: SimDriver = _locked_driver()
	var tick0: int = d.sim.tick
	d._process(2.0 / 60.0 + 0.0002)
	assert_int(d.sim.tick - tick0).is_equal(2)
	assert_float(d.alpha).is_equal(1.0)
	d._process(3.0 / 60.0 - 0.0002)
	assert_int(d.sim.tick - tick0).is_equal(5)
	assert_float(d.alpha).is_equal(1.0)


func test_59_94_hertz_keeps_real_speed_and_full_alpha() -> void:
	var d: SimDriver = _driver()
	var below_one: int = 0
	var frames: int = 3596
	for i: int in range(frames):
		d._process(1.0 / 59.94)
		if i >= SimDriver.LOCK_FRAMES and d.alpha < 1.0:
			below_one += 1
	assert_int(below_one).is_equal(0)
	# 60 real seconds is 3600 ticks, within one tick of rounding.
	assert_int(d.sim.tick).is_between(3599, 3601)


func test_variable_refresh_near_60_is_interpolated_without_judder() -> void:
	# Variable refresh at 55 to 66 fps, or 60 fps with +-1 ms of jitter: frame times land near a
	# tick only by chance, so the driver never locks and draws real time on every frame (the
	# drawn time moves exactly with the clock; no frame jumps by a tick).
	var ranges: Array[Vector2] = [
		Vector2(1.0 / 66.0, 1.0 / 55.0), Vector2(1.0 / 63.0, 1.0 / 57.0), Vector2(0.01567, 0.01767)
	]
	for r: Vector2 in ranges:
		var d: SimDriver = _driver()
		var rng: Rng = Rng.seeded(9, 0)
		var real: float = 0.0
		var judder: int = 0
		var steps_off: int = 0
		var prev_offset: float = 0.0
		for _i: int in range(3600):
			var delta: float = r.x + (r.y - r.x) * float(rng.between(0, 1000)) / 1000.0
			var tick0: int = d.sim.tick
			d._process(delta)
			real += delta
			var drawn: float = (d.sim.tick - 1 + d.alpha) / 60.0
			var offset: float = drawn - real
			if absf(offset - prev_offset) > 0.25 / 60.0:
				judder += 1
			prev_offset = offset
			var expected_steps: int = d.sim.tick - tick0
			if expected_steps > 2:
				steps_off += 1
		assert_bool(d.is_locked()).override_failure_message("locked on %s" % r).is_false()
		assert_int(judder).override_failure_message("judder on %s" % r).is_equal(0)
		assert_int(steps_off).is_equal(0)


func test_moving_to_a_high_refresh_display_unlocks() -> void:
	var d: SimDriver = _locked_driver()
	var tick0: int = d.sim.tick
	for _i: int in range(144 * 5):
		d._process(1.0 / 144.0)
	assert_bool(d.is_locked()).is_false()
	# Five real seconds are 300 ticks, within a tick.
	assert_int(d.sim.tick - tick0).is_between(299, 301)


func test_hitch_is_capped_instead_of_spiralling() -> void:
	var d: SimDriver = _driver()
	d._process(0.5)
	assert_int(d.sim.tick).is_equal(SimDriver.MAX_STEPS_PER_FRAME)
	assert_float(d.alpha).is_equal_approx(1.0, 0.0001)


func test_paused_driver_only_steps_on_request() -> void:
	var d: SimDriver = _driver()
	d._process(1.0 / 120.0)
	d.paused = true
	d._process(0.1)
	assert_int(d.sim.tick).is_equal(1)
	d.step_once()
	assert_int(d.sim.tick).is_equal(2)
	assert_float(d.alpha).is_equal(1.0)


func test_saved_session_replays() -> void:
	var d: SimDriver = _driver()
	for _i: int in range(130):
		d.step_once()
	var path: String = "user://test_driver_session.wrp"
	assert_int(d.save_replay(path)).is_equal(OK)
	var replay: Replay = ReplayFiles.load_file(path)
	assert_int(replay.frame_count()).is_equal(130)
	assert_bool(ReplayPlayer.verify(replay)).is_true()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_object(ReplayFiles.load_file(path)).is_null()


func test_variable_refresh_after_a_lock_unlocks_and_stops_juddering() -> void:
	# A steady 60 fps menu locks the driver; uncapped play at 57 to 63 fps follows. The driver
	# unlocks within a second, and from then on no frame jumps.
	var d: SimDriver = _locked_driver()
	var rng: Rng = Rng.seeded(17, 0)
	var real: float = d.sim.tick / 60.0
	var prev_offset: float = 0.0
	var judder: int = 0
	for i: int in range(3600):
		var delta: float = (
			1.0 / 63.0 + (1.0 / 57.0 - 1.0 / 63.0) * float(rng.between(0, 1000)) / 1000.0
		)
		d._process(delta)
		real += delta
		var offset: float = (d.sim.tick - 1 + d.alpha) / 60.0 - real
		if i >= 60 and absf(offset - prev_offset) > 0.25 / 60.0:
			judder += 1
		prev_offset = offset
	assert_bool(d.is_locked()).is_false()
	assert_int(judder).is_equal(0)


func test_a_new_session_keeps_the_display_lock() -> void:
	var d: SimDriver = _locked_driver()
	d.start(Scenario.make(2))
	d._process(1.0 / 60.0 + 0.0003)
	assert_bool(d.is_locked()).is_true()
	assert_int(d.sim.tick).is_equal(1)
	assert_float(d.alpha).is_equal(1.0)


func test_a_stutter_burst_costs_at_most_half_a_second_of_interpolation() -> void:
	# Steady 60 Hz with seven 20 ms frames every 20 s for ten minutes: each burst may unlock the
	# driver, but it relocks within RELOCK_FRAMES good frames.
	var d: SimDriver = _locked_driver()
	var interpolated: int = 0
	for second: int in range(600):
		for f: int in range(60):
			var burst: bool = second % 20 == 10 and f < 7
			d._process(0.020 if burst else 1.0 / 60.0)
			if d.alpha < 1.0:
				interpolated += 1
	assert_bool(d.is_locked()).is_true()
	assert_int(interpolated).is_less_equal(30 * (SimDriver.RELOCK_FRAMES + 8))


func test_jitter_just_past_the_snap_window_does_not_flap() -> void:
	# Locked at 60 Hz, then ten minutes of +-0.65 ms and +-0.7 ms jitter: misses are scattered,
	# not a burst, so the driver unlocks once and stays unlocked, with no frame jumping.
	for jitter_us: int in [650, 700]:
		var d: SimDriver = _locked_driver()
		var rng: Rng = Rng.seeded(23, 0)
		var real: float = d.sim.tick / 60.0
		var changes: int = 0
		var was_locked: bool = true
		var judder: int = 0
		var prev_offset: float = 0.0
		for i: int in range(36000):
			var delta: float = 1.0 / 60.0 + float(rng.between(-jitter_us, jitter_us)) / 1000000.0
			d._process(delta)
			real += delta
			if d.is_locked() != was_locked:
				changes += 1
				was_locked = d.is_locked()
			var offset: float = (d.sim.tick - 1 + d.alpha) / 60.0 - real
			if i >= 60 and absf(offset - prev_offset) > 0.25 / 60.0:
				judder += 1
			prev_offset = offset
		assert_int(changes).override_failure_message("+-%d us" % jitter_us).is_less_equal(1)
		assert_int(judder).override_failure_message("+-%d us" % jitter_us).is_equal(0)
