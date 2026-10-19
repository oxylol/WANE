extends GdUnitTestSuite
## Hit-feedback presentation (BUILD.md section 6, "Hit feedback"; section 10, the VFX budget;
## section 11, the 24-voice priority system; CLAUDE.md rule 7).


func _tuning() -> FeedbackTuning:
	return load(FeedbackTuning.PATH) as FeedbackTuning


func test_shake_runs_along_the_hit_and_fades() -> void:
	var shake := ScreenShake.new(_tuning())
	shake.scale = 1.0
	shake.add(Vector2(1, 0), 4.0, 8)
	var first: Vector2 = shake.offset()
	assert_float(first.y).is_equal(0.0)
	assert_float(first.x).is_equal_approx(4.0, 0.0001)
	var peaks: Array[float] = []
	for _i: int in range(8):
		peaks.append(absf(shake.offset().x))
		shake.step()
	assert_bool(shake.is_shaking()).is_false()
	assert_vector(shake.offset()).is_equal(Vector2.ZERO)
	assert_float(peaks[4]).is_less(peaks[0])


func test_shake_at_the_default_fifty_percent_never_exceeds_three_units() -> void:
	var t: FeedbackTuning = _tuning()
	var shake := ScreenShake.new(t)
	assert_float(shake.scale).is_equal(0.5)
	# Everything at once, all along one line: the worst case.
	shake.add(Vector2.RIGHT, t.player_hit_shake_u, t.player_hit_shake_frames)
	shake.add(Vector2.RIGHT, t.charged_shake_u, t.charged_shake_frames)
	shake.add(Vector2.RIGHT, t.parry_shake_u, t.parry_shake_frames)
	for _i: int in range(10):
		assert_float(shake.offset().length()).is_less_equal(3.0 + 0.0001)
		shake.step()


func test_one_bright_effect_per_cell_per_three_ticks_the_more_important_wins() -> void:
	var vfx: VfxBudget = auto_free(VfxBudget.new(_tuning()))
	assert_bool(vfx.spawn(VfxBudget.SPARK, VfxBudget.PROC, Vector2(10, 10))).is_true()
	# Same 100 u cell, same tick: a proc spark is refused, a hit spark replaces it.
	assert_bool(vfx.spawn(VfxBudget.SPARK, VfxBudget.PROC, Vector2(60, 60))).is_false()
	assert_bool(vfx.spawn(VfxBudget.SPARK, VfxBudget.HIT, Vector2(60, 60))).is_true()
	assert_int(vfx.effects.size()).is_equal(1)
	assert_int(vfx.effects[0].priority).is_equal(VfxBudget.HIT)
	# Another cell is free.
	assert_bool(vfx.spawn(VfxBudget.SPARK, VfxBudget.PROC, Vector2(160, 10))).is_true()
	# Three ticks later the first cell is free again.
	for _i: int in range(3):
		vfx.step()
	assert_bool(vfx.spawn(VfxBudget.SPARK, VfxBudget.PROC, Vector2(10, 10))).is_true()


func test_embers_and_telegraphs_are_not_held_to_the_cell_rule() -> void:
	var vfx: VfxBudget = auto_free(VfxBudget.new(_tuning()))
	vfx.spawn(VfxBudget.SPARK, VfxBudget.PLAYER, Vector2(10, 10))
	assert_bool(vfx.spawn(VfxBudget.EMBER, VfxBudget.PROC, Vector2(12, 12))).is_true()
	(
		assert_bool(vfx.spawn(VfxBudget.TELEGRAPH, VfxBudget.TELEGRAPH_PRIORITY, Vector2(14, 14)))
		. is_true()
	)


func test_the_capacity_displaces_the_least_important_or_refuses() -> void:
	var t: FeedbackTuning = _tuning().duplicate()
	t.vfx_capacity = 3
	var vfx: VfxBudget = auto_free(VfxBudget.new(t))
	for i: int in range(3):
		vfx.spawn(VfxBudget.EMBER, VfxBudget.PROC, Vector2(i * 10, 0))
	assert_bool(vfx.spawn(VfxBudget.EMBER, VfxBudget.PROC, Vector2(50, 0))).is_false()
	assert_bool(vfx.spawn(VfxBudget.EMBER, VfxBudget.PLAYER, Vector2(50, 0))).is_true()
	assert_int(vfx.effects.size()).is_equal(3)
	assert_int(vfx.displaced).is_equal(1)
	assert_int(vfx.refused).is_equal(1)


func test_effects_live_under_ten_ticks() -> void:
	var vfx: VfxBudget = auto_free(VfxBudget.new(_tuning()))
	for kind: int in [VfxBudget.SPARK, VfxBudget.BURST, VfxBudget.SMEAR, VfxBudget.EMBER]:
		assert_int(vfx.lifetime(kind)).is_less(10)
	vfx.spawn(VfxBudget.BURST, VfxBudget.HIT, Vector2.ZERO)
	for _i: int in range(vfx.lifetime(VfxBudget.BURST)):
		vfx.step()
	assert_int(vfx.effects.size()).is_zero()


func test_radiances_ring_lives_its_tuned_lifetime_and_reaches_its_tuned_radius() -> void:
	# The ring is a spell's, not a proc's: its lifetime and reach are content, not the sub-10
	# frame proc rule's.
	var t: FeedbackTuning = _tuning()
	var vfx: VfxBudget = auto_free(VfxBudget.new(t))
	assert_bool(vfx.spawn(VfxBudget.RING, VfxBudget.PLAYER, Vector2(10, 10))).is_true()
	for _i: int in range(t.radiance_ring_frames - 1):
		vfx.step()
	assert_int(vfx.effects.size()).is_equal(1)
	vfx.step()
	assert_int(vfx.effects.size()).is_zero()
	assert_float(t.radiance_ring_radius_u).is_equal(640.0)
	assert_int(t.radiance_ring_frames).is_equal(18)


func test_synth_sounds_are_made_once_and_never_silent() -> void:
	for base: String in Synth.BASES:
		for v: int in range(Synth.variants(base)):
			var id: String = "%s%d" % [base, v]
			var wav: AudioStreamWAV = Synth.sound(id)
			assert_int(wav.data.size()).override_failure_message(id).is_greater(1000)
			assert_object(Synth.sound(id)).is_same(wav)
	assert_bool(Synth.sound("hit0").data == Synth.sound("hit1").data).is_false()


func test_voices_cut_the_least_important_furthest_quietest_sound() -> void:
	var t: FeedbackTuning = _tuning().duplicate()
	t.voice_cap = 3
	var voices: Voices = auto_free(Voices.new(t))
	add_child(voices)
	voices.listener = Vector2.ZERO
	var s: AudioStreamWAV = Synth.sound("chime0")
	assert_bool(voices.play(s, Vector2(100, 0), Voices.HIT)).is_true()
	assert_bool(voices.play(s, Vector2(900, 0), Voices.HIT)).is_true()
	assert_bool(voices.play(s, Vector2(50, 0), Voices.PLAYER)).is_true()
	# Full: a proc sound is dropped; a hit sound nearer than the far hit takes its voice.
	assert_bool(voices.play(s, Vector2(10, 0), Voices.PROC)).is_false()
	assert_bool(voices.play(s, Vector2(20, 0), Voices.HIT)).is_true()
	assert_int(voices.stolen).is_equal(1)
	assert_int(voices.dropped).is_equal(1)
	var positions: Array[float] = []
	for p: Node in voices.get_children():
		positions.append((p as AudioStreamPlayer2D).position.x)
	assert_bool(positions.has(900.0)).is_false()


func _sim_with(kind: String, value: int) -> Simulation:
	var sim := Simulation.new(Scenario.make(1, "", ""))
	sim.step(InputFrame.new())
	sim.events.add(kind, Fx.units(500), Fx.units(300), value)
	return sim


func test_a_hit_event_value_carries_its_kind_and_direction() -> void:
	for kind: int in [HitKind.LIGHT, HitKind.FINISHER, HitKind.CHARGED, HitKind.POGO]:
		for dx: int in [-1, 0, 1]:
			for dy: int in [-1, 0, 1]:
				var v: int = HitKind.encode(kind, dx, dy)
				assert_int(HitKind.kind_of(v)).is_equal(kind)
				assert_vector(HitKind.dir_of(v)).is_equal(Vector2i(dx, dy))


func test_a_parry_flashes_once_chimes_slows_time_and_shakes_along_the_hit() -> void:
	var fb: HitFeedback = auto_free(HitFeedback.new(_tuning()))
	var vfx: VfxBudget = auto_free(VfxBudget.new(_tuning()))
	fb.attach(vfx, null)
	var slowed: Array[float] = []
	fb.slow_motion.connect(func(s: float, t: int) -> void: slowed.append_array([s, float(t)]))
	fb.on_tick(_sim_with(SimEvents.PARRY, HitKind.encode(HitKind.PARRY, 1, 0)))
	assert_int(fb.flash_ticks).is_equal(1)
	assert_array(slowed).is_equal([0.5, 6.0])
	assert_float(fb.shake_offset().y).is_equal(0.0)
	assert_float(fb.shake_offset().x).is_greater(0.0)
	assert_int(vfx.effects.size()).is_greater(0)


func test_flashes_set_to_zero_never_flash() -> void:
	var fb: HitFeedback = auto_free(HitFeedback.new(_tuning()))
	fb.flash_scale = 0.0
	fb.on_tick(_sim_with(SimEvents.PARRY, HitKind.encode(HitKind.PARRY, 1, 0)))
	fb.on_tick(_sim_with(SimEvents.HIT, HitKind.encode(HitKind.CHARGED, 1, 0)))
	assert_int(fb.flash_ticks).is_zero()
	assert_int(fb.chroma_ticks).is_zero()


func test_a_light_hit_does_not_shake_and_a_finisher_does() -> void:
	var fb: HitFeedback = auto_free(HitFeedback.new(_tuning()))
	fb.on_tick(_sim_with(SimEvents.HIT, HitKind.encode(HitKind.LIGHT, 1, 0)))
	assert_bool(fb.shake.is_shaking()).is_false()
	fb.on_tick(_sim_with(SimEvents.HIT, HitKind.encode(HitKind.FINISHER, -1, 0)))
	assert_bool(fb.shake.is_shaking()).is_true()
	assert_float(fb.shake_offset().x).is_less(0.0)


func test_a_player_hit_pulses_the_vignette_and_rumbles() -> void:
	var fb: HitFeedback = auto_free(HitFeedback.new(_tuning()))
	var rumbles: Array[float] = []
	fb.rumble.connect(func(s: float, ms: int) -> void: rumbles.append_array([s, float(ms)]))
	fb.on_tick(_sim_with(SimEvents.PLAYER_HIT, HitKind.encode(HitKind.LIGHT, -1, 0)))
	assert_int(fb.vignette_ticks).is_equal(20)
	assert_array(rumbles).is_equal([0.6, 100.0])
	# A charged kill slows time to 0.8 for 8 ticks.
	var slowed: Array[float] = []
	fb.slow_motion.connect(func(s: float, t: int) -> void: slowed.append_array([s, float(t)]))
	fb.on_tick(_sim_with(SimEvents.KILL, HitKind.encode(HitKind.CHARGED, 1, 0)))
	assert_array(slowed).is_equal([0.8, 8.0])
