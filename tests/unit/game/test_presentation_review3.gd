extends GdUnitTestSuite
## Presentation review 3 (the F3 overlay, the drawn player's death cut, the stair ease): each
## finding's repro as a test that failed before the fix. It all reads the simulation and never
## writes it.


func _fixture(id: String) -> Fixture:
	var fx: Fixture = Fixture.parse_file("res://tests/replay/%s.fixture" % id)
	assert_array(fx.errors).is_empty()
	return fx


func _of(boxes: Array[DebugBoxes.Box], kind: int) -> Array[DebugBoxes.Box]:
	var out: Array[DebugBoxes.Box] = []
	for b: DebugBoxes.Box in boxes:
		if b.kind == kind:
			out.append(b)
	return out


func _labelled(boxes: Array[DebugBoxes.Box], kind: int, text: String) -> DebugBoxes.Box:
	for b: DebugBoxes.Box in _of(boxes, kind):
		if b.label.contains(text):
			return b
	return null


## Steps [param fx] to frame [param to] and returns the simulation, feeding [param memory].
func _play(fx: Fixture, to: int, memory: DebugBoxes.Memory = null) -> Simulation:
	var sim := Simulation.new(fx.scenario)
	for f: int in range(to + 1):
		sim.step(fx.input_frame(f))
		if memory != null and f < to:
			memory.note(sim)
	return sim


func test_a_lethal_hit_cuts_the_drawn_player_to_the_spawn_and_is_marked_where_it_landed() -> void:
	# Presentation review r3, M2: at more than 60 Hz the drawn player slid across the room from
	# the death to the spawn, and the overlay drew the red swing touching nothing.
	var fx: Fixture = _fixture("combat/death_far_from_the_spawn")
	var sim := Simulation.new(fx.scenario)
	var view: PlayerView = auto_free(PlayerView.new())
	view.begin(sim)
	for f: int in range(131):
		sim.step(fx.input_frame(f))
		view.capture(sim)
	var before_x: float = view.box_at(1.0).get_center().x
	sim.step(fx.input_frame(131))
	view.capture(sim)
	assert_bool(sim.events.has(SimEvents.DEATH)).is_true()
	for alpha: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		assert_float(view.box_at(alpha).get_center().x).is_equal_approx(100.0, 0.001)
	assert_float(absf(before_x - 100.0)).is_greater(400.0)
	# The overlay: the hurtbox that took the lethal hit, where Ash stood, and the hit's point.
	var boxes: Array[DebugBoxes.Box] = DebugBoxes.collect(sim, Rect2())
	var lethal: DebugBoxes.Box = _labelled(boxes, DebugBoxes.CONTACT, "lethal hit")
	assert_object(lethal).is_not_null()
	assert_float(lethal.rect.get_center().x).is_equal_approx(before_x, 12.0)
	assert_object(_labelled(boxes, DebugBoxes.CONTACT, "hit")).is_not_null()
	assert_int(_of(boxes, DebugBoxes.ATTACK_RED).size()).is_equal(1)


func test_a_parry_marks_the_swing_that_was_parried_and_the_window_is_labelled() -> void:
	# Presentation review r3, M1: the parry tick's swing box was never drawn on any frame (a parry
	# staggers the enemy, which clears its attack), and nothing showed the parry window.
	var fx: Fixture = _fixture("combat/parry_window_first_frame")
	var memory := DebugBoxes.Memory.new()
	var window_ticks: int = 0
	var sim := Simulation.new(fx.scenario)
	var parry_seen: bool = false
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		var boxes: Array[DebugBoxes.Box] = DebugBoxes.collect(sim, Rect2(), memory)
		if _labelled(boxes, DebugBoxes.ENEMY, "PARRY WINDOW OPEN") != null:
			window_ticks += 1
		if sim.events.has(SimEvents.PARRY):
			parry_seen = true
			assert_object(_labelled(boxes, DebugBoxes.CONTACT, "parry")).is_not_null()
			var swing: DebugBoxes.Box = _labelled(boxes, DebugBoxes.ATTACK_WHITE, "parried")
			assert_object(swing).is_not_null()
			var at := Vector2(float(sim.events.xs[0]), float(sim.events.ys[0])) / Fx.SUB
			assert_bool(swing.rect.has_point(at)).is_true()
		memory.note(sim)
	assert_bool(parry_seen).is_true()
	# The window is the parry window's frames before the landing.
	assert_int(window_ticks).is_equal(sim.combat.params.parry_window_frames)


func test_a_blaze_finisher_draws_its_burst_and_a_burning_enemy_says_so() -> void:
	# Presentation review r3, M3: the burst's damage to the far dummy had no box or cause.
	var fx: Fixture = _fixture("combat/blaze_finisher_burst")
	var sim: Simulation = _play(fx, 17)
	var boxes: Array[DebugBoxes.Box] = DebugBoxes.collect(sim, Rect2())
	var burst: DebugBoxes.Box = _labelled(boxes, DebugBoxes.BURST, "burst 96 u")
	assert_object(burst).is_not_null()
	assert_float(burst.rect.size.x).is_equal_approx(192.0, 0.01)
	var far: Enemy = sim.combat.enemies[1]
	assert_bool(burst.rect.intersects(DebugBoxes.units(far.hurtbox()))).is_true()
	assert_object(_labelled(boxes, DebugBoxes.CONTACT, "burn")).is_not_null()
	# No burst off Blaze.
	var light: Fixture = _fixture("combat/side1_hits_dummy_once")
	var lit: Simulation = Simulation.new(light.scenario)
	for f: int in range(light.frame_total):
		lit.step(light.input_frame(f))
		assert_array(_of(DebugBoxes.collect(lit, Rect2()), DebugBoxes.BURST)).is_empty()
	# Burning is in the label while it lasts.
	var burning: int = 0
	var ignite: Fixture = _fixture("combat/kindle_reaches_a_far_dummy")
	var s2 := Simulation.new(ignite.scenario)
	for f: int in range(ignite.frame_total):
		s2.step(ignite.input_frame(f))
		for b: DebugBoxes.Box in _of(DebugBoxes.collect(s2, Rect2()), DebugBoxes.ENEMY):
			if b.label.contains("burning"):
				burning += 1
	assert_int(burning).is_greater(0)


func test_every_enemy_label_is_clear_of_the_health_and_poise_bars() -> void:
	# Presentation review r3, L1: an 18 px label drawn 4 u above the box covered both bars
	# (16 and 12 u above the box) in every state but the telegraph.
	var fx: Fixture = _fixture("combat/parry_window_first_frame")
	var sim := Simulation.new(fx.scenario)
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		for b: DebugBoxes.Box in _of(DebugBoxes.collect(sim, Rect2()), DebugBoxes.ENEMY):
			# The label's descenders (about a quarter of its height) end above the highest bar.
			var baseline: float = b.rect.position.y - 4.0 - b.label_lift
			assert_float(baseline + DebugOverlay.FONT_SIZE * 0.25).is_less_equal(
				b.rect.position.y - EnemyView.BARS_GAP_PX
			)


func test_the_enemy_box_is_a_hairline_so_the_white_cue_outline_shows() -> void:
	# Presentation review r3, L8: a 2 px violet box drawn over the white 3 px cue outline made
	# the parryable cue read lavender in every F3 sheet.
	assert_float(DebugOverlay.ENEMY_LINE_PX).is_less(EnemyView.CUE_OUTLINE_PX)


func test_the_overlay_collects_once_a_tick_and_draws_no_label_twice() -> void:
	# Presentation review r3, L3: collect and an all-pairs label check ran on every display frame
	# (5.5 ms with 200 enemies).
	var fx: Fixture = _fixture("physics/walk_up_lip_stairs")
	var sim := Simulation.new(fx.scenario)
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	add_child(overlay)
	overlay.attach_sim(sim, null)
	overlay.set_shown(true)
	sim.step(fx.input_frame(0))
	overlay.capture()
	overlay.refresh()
	await await_idle_frame()
	var first: Array[DebugBoxes.Box] = overlay.boxes
	assert_array(first).is_not_empty()
	overlay.refresh()
	await await_idle_frame()
	assert_bool(overlay.boxes == first).is_true()
	sim.step(fx.input_frame(1))
	overlay.capture()
	overlay.refresh()
	await await_idle_frame()
	assert_bool(overlay.boxes == first).is_false()
	# No two labelled boxes share a rectangle (a down-strike's box that is its pogo box is labelled
	# once, with both names), so the overlay has no repeat to scan for.
	for path: String in ["movement/pogo_hitbox_frames", "combat/pogo_off_the_dummy"]:
		var pogo: Fixture = _fixture(path)
		var ps := Simulation.new(pogo.scenario)
		for f: int in range(pogo.frame_total):
			ps.step(pogo.input_frame(f))
			var seen: Dictionary[Rect2, bool] = {}
			for b: DebugBoxes.Box in DebugBoxes.collect(ps, Rect2()):
				if b.label == "":
					continue
				assert_bool(seen.has(b.rect)).override_failure_message(
					"%s frame %d: two labels on %s" % [path, f, b.rect]
				).is_false()
				seen[b.rect] = true
