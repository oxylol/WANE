extends GdUnitTestSuite
## The grey-box player's landing squash and apex stretch (BUILD.md section 5 Landing: "a 3 f squash
## animation that does not block input"; section 10 Animation: squash on landing, 3 f, 110% wide;
## stretch at jump apex, 2 f, 94% wide; section 15: "Landing squash and jump stretch are visible
## and do not block any input"). Drawn only: the view reads the core's events and never writes it.

const JUMP_FIXTURE: String = "res://tests/replay/movement/jump_full.fixture"
const CEILING_FIXTURE: String = "res://tests/replay/movement/jump_ceiling_bump.fixture"


func _view() -> PlayerView:
	var view := PlayerView.new()
	auto_free(view)
	return view


func _tuning() -> PlayerViewTuning:
	return load(PlayerViewTuning.PATH) as PlayerViewTuning


## The tick on which [param kind] first happens in the fixture at [param path].
func _first_tick(path: String, kind: String) -> int:
	var fx: Fixture = Fixture.parse_file(path)
	var sim := Simulation.new(fx.scenario)
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		if sim.events.has(kind):
			return f
	return -1


## The first tick whose vertical speed is no longer upward after a rise.
func _apex_tick(path: String) -> int:
	var fx: Fixture = Fixture.parse_file(path)
	var sim := Simulation.new(fx.scenario)
	var rose: bool = false
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		if sim.player.body.vy < 0:
			rose = true
		elif rose:
			return f
	return -1


func test_the_view_never_changes_the_simulation() -> void:
	var fx: Fixture = Fixture.parse_file(JUMP_FIXTURE)
	var bare := Simulation.new(fx.scenario)
	var watched := Simulation.new(fx.scenario)
	var view: PlayerView = _view()
	view.begin(watched)
	for f: int in range(fx.frame_total):
		bare.step(fx.input_frame(f))
		watched.step(fx.input_frame(f))
		view.capture(watched)
		var scaled: Rect2 = view.drawn_box_at(0.5)
		assert_bool(scaled.size.x > 0.0).is_true()
		assert_int(watched.player.body.x).is_equal(bare.player.body.x)
		assert_int(watched.player.body.y).is_equal(bare.player.body.y)
		assert_int(watched.player.body.vy).is_equal(bare.player.body.vy)
	assert_int(watched.state_hash()).is_equal(bare.state_hash())


func test_the_landing_squashes_for_three_frames_from_the_landing_tick() -> void:
	var land: int = _first_tick(JUMP_FIXTURE, SimEvents.LAND)
	assert_int(land).is_greater(0)
	var tuning: PlayerViewTuning = _tuning()
	var view: PlayerView = _view()
	var fx: Fixture = Fixture.parse_file(JUMP_FIXTURE)
	var sim := Simulation.new(fx.scenario)
	view.begin(sim)
	var wide: float = float(tuning.landing_squash_width_percent) / 100.0
	for f: int in range(land + tuning.landing_squash_frames + 2):
		sim.step(fx.input_frame(f))
		view.capture(sim)
		var age: int = f - land
		if age < 0:
			if view.scale_at(1.0).x < 1.0:
				continue
			assert_float(view.scale_at(1.0).x).is_equal(1.0)
		elif age == 0:
			# The drawn player is not squashed before the landing tick is reached; at its end it is
			# squashed all the way: wide and, the area kept, low.
			assert_float(view.scale_at(0.0).x).is_equal(1.0)
			assert_float(view.scale_at(1.0).x).is_equal_approx(wide, 0.005)
			assert_float(view.scale_at(1.0).y).is_equal_approx(1.0 / wide, 0.005)
		elif age < tuning.landing_squash_frames:
			var s: float = view.scale_at(1.0).x
			assert_bool(s > 1.0 and s < wide).is_true()
		else:
			assert_float(view.scale_at(1.0).x).is_equal(1.0)
			assert_float(view.scale_at(1.0).y).is_equal(1.0)


func test_a_small_step_down_does_not_squash() -> void:
	# A landing under the minimum impact (walking off a lip) is no landing the player would see.
	var view: PlayerView = _view()
	var sim := Simulation.new(Scenario.make(1, "test/flat"))
	view.begin(sim)
	sim.events.add(SimEvents.LAND, 0, 0, Fx.speed(_tuning().landing_min_impact_ups - 1))
	view.capture(sim)
	assert_float(view.scale_at(1.0).x).is_equal(1.0)


func test_the_squash_grows_with_the_impact() -> void:
	var tuning: PlayerViewTuning = _tuning()
	var sim := Simulation.new(Scenario.make(1, "test/flat"))
	var weak: PlayerView = _view()
	var strong: PlayerView = _view()
	weak.begin(sim)
	strong.begin(sim)
	var mid: int = (tuning.landing_min_impact_ups + tuning.landing_full_impact_ups) / 2
	sim.events.add(SimEvents.LAND, 0, 0, Fx.speed(mid))
	weak.capture(sim)
	sim.events.clear()
	sim.events.add(SimEvents.LAND, 0, 0, Fx.speed(tuning.landing_full_impact_ups * 2))
	strong.capture(sim)
	var w: float = weak.scale_at(1.0).x
	var s: float = strong.scale_at(1.0).x
	assert_bool(w > 1.0 and w < s).is_true()
	assert_float(s).is_equal_approx(float(tuning.landing_squash_width_percent) / 100.0, 0.005)


func test_a_full_jump_lands_with_the_full_squash() -> void:
	# The doc's 110% is the squash of an ordinary jump's landing, so that jump must reach it.
	var land: int = _first_tick(JUMP_FIXTURE, SimEvents.LAND)
	var fx: Fixture = Fixture.parse_file(JUMP_FIXTURE)
	var sim := Simulation.new(fx.scenario)
	var view: PlayerView = _view()
	view.begin(sim)
	for f: int in range(land + 1):
		sim.step(fx.input_frame(f))
		view.capture(sim)
	var wide: float = float(_tuning().landing_squash_width_percent) / 100.0
	assert_float(view.scale_at(1.0).x).is_equal_approx(wide, 0.005)


func test_the_apex_stretches_for_two_frames() -> void:
	var apex: int = _apex_tick(JUMP_FIXTURE)
	assert_int(apex).is_greater(0)
	var tuning: PlayerViewTuning = _tuning()
	var view: PlayerView = _view()
	var fx: Fixture = Fixture.parse_file(JUMP_FIXTURE)
	var sim := Simulation.new(fx.scenario)
	view.begin(sim)
	var narrow: float = float(tuning.apex_stretch_width_percent) / 100.0
	var deepest: float = 1.0
	for f: int in range(apex + tuning.apex_stretch_frames + 2):
		sim.step(fx.input_frame(f))
		view.capture(sim)
		var x: float = view.scale_at(1.0).x
		if f < apex:
			assert_float(x).is_equal(1.0)
		elif f - apex < tuning.apex_stretch_frames:
			for a: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				deepest = minf(deepest, view.scale_at(a).x)
		else:
			assert_float(x).is_equal(1.0)
	# Tall and narrow, at the doc's 94% wide at its deepest, with the area kept.
	assert_float(deepest).is_equal_approx(narrow, 0.01)
	var k: Vector2 = view.scale_at(1.0)
	assert_float(k.x * k.y).is_equal_approx(1.0, 0.001)


func test_a_head_bump_is_no_apex() -> void:
	# Hitting a ceiling stops the rise; that is not the top of a jump, so nothing stretches
	# around the bump.
	var view: PlayerView = _view()
	var fx: Fixture = Fixture.parse_file(CEILING_FIXTURE)
	var sim := Simulation.new(fx.scenario)
	view.begin(sim)
	var bump: int = -1
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		view.capture(sim)
		if bump < 0 and sim.player.body.hit_ceiling:
			bump = f
		if bump >= 0 and f <= bump + 3:
			assert_float(view.scale_at(0.5).x).is_equal(1.0)
	assert_int(bump).is_greater(0)


func test_the_scaled_box_keeps_the_feet_and_the_centre() -> void:
	var view: PlayerView = _view()
	var sim := Simulation.new(Scenario.make(1, "test/flat"))
	view.begin(sim)
	sim.events.add(SimEvents.LAND, 0, 0, Fx.speed(_tuning().landing_full_impact_ups))
	view.capture(sim)
	var plain: Rect2 = view.box_at(1.0)
	var drawn: Rect2 = view.drawn_box_at(1.0)
	assert_float(drawn.end.y).is_equal_approx(plain.end.y, 0.001)
	assert_float(drawn.get_center().x).is_equal_approx(plain.get_center().x, 0.001)
	assert_bool(drawn.size.x > plain.size.x and drawn.size.y < plain.size.y).is_true()


func test_a_door_or_a_teleport_clears_the_squash() -> void:
	var view: PlayerView = _view()
	var sim := Simulation.new(Scenario.make(1, "test/flat"))
	view.begin(sim)
	sim.events.add(SimEvents.LAND, 0, 0, Fx.speed(_tuning().landing_full_impact_ups))
	view.capture(sim)
	sim.events.clear()
	sim.events.add(SimEvents.ROOM, 0, 0, 0)
	view.capture(sim)
	assert_float(view.scale_at(1.0).x).is_equal(1.0)
