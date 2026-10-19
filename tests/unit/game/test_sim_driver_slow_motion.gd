extends GdUnitTestSuite
## Slow motion in the fixed-step driver (BUILD.md section 6, hit feedback: "slow-motion 0.8x for
## 8 f on kill", "time to 0.5x for 6 f").


func _driver() -> SimDriver:
	var d: SimDriver = auto_free(SimDriver.new())
	d.start(Scenario.make(1))
	return d


func _locked_driver() -> SimDriver:
	var d: SimDriver = _driver()
	for _i: int in range(SimDriver.LOCK_FRAMES):
		d._process(1.0 / 60.0)
	assert_bool(d.is_locked()).is_true()
	return d


func test_charged_kill_slow_motion_takes_ten_frames_on_a_locked_display() -> void:
	# "slow-motion 0.8x for 8 f on kill": eight ticks over ten 60 Hz frames, each frame drawing
	# 0.8 of a tick further on; the frame after them steps once and draws the newest state.
	var d: SimDriver = _locked_driver()
	var start: int = d.sim.tick
	d.slow(0.8, 8)
	var drawn: Array[float] = []
	for _i: int in range(10):
		d._process(1.0 / 60.0)
		assert_bool(d.slowing()).is_equal(_i < 9)
		drawn.append(d.sim.tick - start - 1 + d.alpha)
	for i: int in range(10):
		assert_float(drawn[i]).is_equal_approx(0.8 * (i + 1), 0.0001)
	assert_int(d.sim.tick - start).is_equal(8)
	assert_float(d.alpha).is_equal(1.0)
	d._process(1.0 / 60.0)
	assert_int(d.sim.tick - start).is_equal(9)
	assert_float(d.alpha).is_equal(1.0)
	assert_bool(d.is_locked()).is_true()


func test_parry_slow_motion_takes_twelve_frames_and_ends_on_a_tick() -> void:
	var d: SimDriver = _locked_driver()
	var start: int = d.sim.tick
	d.slow(0.5, 6)
	for _i: int in range(12):
		d._process(1.0 / 60.0)
	assert_int(d.sim.tick - start).is_equal(6)
	assert_bool(d.slowing()).is_false()
	for _i: int in range(5):
		d._process(1.0 / 60.0)
		assert_float(d.alpha).is_equal(1.0)
	assert_int(d.sim.tick - start).is_equal(11)


func test_slow_motion_on_a_high_refresh_display_is_smooth_and_keeps_real_speed_after() -> void:
	var d: SimDriver = _driver()
	for _i: int in range(240):
		d._process(1.0 / 144.0)
	var start: float = d.sim.tick - 1 + d.alpha
	d.slow(0.5, 6)
	var last: float = start
	var frames: int = 0
	while d.slowing():
		d._process(1.0 / 144.0)
		var now: float = d.sim.tick - 1 + d.alpha
		# Each 144 Hz frame moves 60 / 144 * 0.5 of a tick, give or take the frame that ends it.
		assert_float(now - last).is_between(0.2, 0.42)
		last = now
		frames += 1
	# Six ticks at half speed are 0.2 s: 28.8 frames.
	assert_int(frames).is_between(28, 30)
	var resumed: float = last
	for _i: int in range(144):
		d._process(1.0 / 144.0)
	assert_float(d.sim.tick - 1 + d.alpha - resumed).is_equal_approx(60.0, 0.01)


func test_overlapping_slows_keep_the_slower_scale_and_the_longer_remainder() -> void:
	var d: SimDriver = _locked_driver()
	var start: int = d.sim.tick
	d.slow(0.8, 8)
	d._process(1.0 / 60.0)
	d.slow(0.5, 6)
	assert_float(d.time_scale).is_equal(0.5)
	d.slow(0.8, 2)
	assert_float(d.time_scale).is_equal(0.5)
	var frames: int = 0
	var last: float = d.sim.tick - 1 + d.alpha
	var biggest: float = 0.0
	while d.slowing():
		d._process(1.0 / 60.0)
		var now: float = d.sim.tick - 1 + d.alpha
		biggest = maxf(biggest, now - last)
		last = now
		frames += 1
	# Seven slow ticks were left after the first frame, at 0.5x: fourteen frames. The first frame's
	# 0.2 of a tick leaves the slow off the tick, so it ends one frame later by stepping the first
	# real-speed tick, and that frame moves a little more than a tick at most.
	assert_int(frames).is_equal(15)
	assert_int(d.sim.tick - start).is_equal(9)
	assert_float(biggest).is_less_equal(1.25)
	d._process(1.0 / 60.0)
	assert_float(d.alpha).is_equal(1.0)
	assert_bool(d.is_locked()).is_true()


func test_slow_ignores_bad_values_and_a_new_session_clears_it() -> void:
	var d: SimDriver = _locked_driver()
	d.slow(1.0, 8)
	d.slow(0.0, 8)
	d.slow(0.5, 0)
	assert_bool(d.slowing()).is_false()
	d.slow(0.5, 6)
	d.start(Scenario.make(3))
	assert_bool(d.slowing()).is_false()
	d._process(1.0 / 60.0)
	assert_int(d.sim.tick).is_equal(1)


func test_slow_motion_never_changes_the_simulation() -> void:
	# The same inputs reach the same state whether the ticks came slowly or not.
	var a: SimDriver = _locked_driver()
	var b: SimDriver = _locked_driver()
	a.slow(0.5, 30)
	while a.sim.tick < b.sim.tick + 40:
		a._process(1.0 / 60.0)
	while b.sim.tick < a.sim.tick:
		b._process(1.0 / 60.0)
	assert_int(a.sim.state_hash()).is_equal(b.sim.state_hash())


func test_a_slow_asked_for_inside_the_hitstop_starts_when_the_hitstop_ends() -> void:
	# Task 6 review, presentation M2: the parry's 6 slow ticks were spent inside its own 12 f of
	# hitstop, where nothing moves, so the slow motion was never seen (docs/adr/0013).
	var d: SimDriver = _locked_driver()
	var start: int = d.sim.tick
	d.sim.player.freeze = 5
	d.slow(0.5, 6)
	assert_bool(d.slowing()).is_false()
	for i: int in range(4):
		d._process(1.0 / 60.0)
		assert_bool(d.slowing()).override_failure_message("frozen tick %d" % i).is_false()
	d._process(1.0 / 60.0)
	# The freeze is over: the slow begins now and runs its six ticks.
	assert_int(d.sim.player.freeze).is_zero()
	assert_bool(d.slowing()).is_true()
	assert_int(d.sim.tick - start).is_equal(5)
	for _i: int in range(12):
		d._process(1.0 / 60.0)
	assert_int(d.sim.tick - start).is_equal(11)
	assert_bool(d.slowing()).is_false()


func test_a_slow_with_no_hitstop_starts_at_once() -> void:
	var d: SimDriver = _locked_driver()
	assert_int(d.sim.player.freeze).is_zero()
	d.slow(0.5, 6)
	assert_bool(d.slowing()).is_true()


func test_held_slows_merge_and_a_new_session_drops_them() -> void:
	var d: SimDriver = _locked_driver()
	d.sim.player.freeze = 2
	d.slow(0.8, 8)
	d.slow(0.5, 6)
	d._process(1.0 / 60.0)
	d._process(1.0 / 60.0)
	assert_bool(d.slowing()).is_true()
	assert_float(d.time_scale).is_equal(0.5)
	var e: SimDriver = _locked_driver()
	e.sim.player.freeze = 2
	e.slow(0.5, 6)
	e.start(Scenario.make(3))
	for _i: int in range(4):
		e._process(1.0 / 60.0)
	assert_bool(e.slowing()).is_false()


class FixtureInput:
	extends InputLayer

	var fx: Fixture
	var t: int = 0

	func poll() -> InputFrame:
		var f: InputFrame = fx.input_frame(t) if t < fx.frame_total else InputFrame.new()
		t += 1
		return f

	func reset() -> void:
		pass


func test_the_parrys_slow_ticks_are_ticks_where_things_move() -> void:
	# The real thing, wired as game/main.gd wires it: a parry's slowed ticks all come after its
	# 12 f of hitstop, and the world moves on them.
	var fx: Fixture = Fixture.parse_file(
		"res://tests/replay/combat/parry_window_first_frame.fixture"
	)
	var input: FixtureInput = auto_free(FixtureInput.new())
	input.fx = fx
	var d: SimDriver = auto_free(SimDriver.new())
	d.input_layer = input
	d.start(fx.scenario)
	var fb: HitFeedback = auto_free(HitFeedback.new())
	d.ticked.connect(func() -> void: fb.on_tick(d.sim))
	fb.slow_motion.connect(d.slow)
	var parry_tick: int = -1
	var slowed: Array[int] = []
	var moved_on_slowed: int = 0
	var frozen_slowed: int = 0
	var last := Vector2i(-1, -1)
	for _frame: int in range(90):
		var tick_before: int = d.sim.tick
		var scale: float = d.time_scale
		d._process(1.0 / 60.0)
		var pos := Vector2i(d.sim.player.body.x, d.sim.combat.enemies[0].body.x)
		if parry_tick < 0 and d.sim.events.has(SimEvents.PARRY):
			parry_tick = d.sim.tick - 1
		if scale < 1.0 and d.sim.tick != tick_before:
			slowed.append(d.sim.tick - 1)
			if d.sim.player.freeze > 0:
				frozen_slowed += 1
			if pos != last:
				moved_on_slowed += 1
		last = pos
	assert_int(parry_tick).is_greater(0)
	assert_int(slowed.size()).is_equal(6)
	# Hitstop: ticks parry + 1 to parry + 12 are frozen; the slow takes the six ticks after.
	assert_int(slowed[0]).is_greater(parry_tick + d.sim.combat_params.hitstop_parry)
	assert_int(frozen_slowed).is_zero()
	assert_int(moved_on_slowed).is_greater(0)
