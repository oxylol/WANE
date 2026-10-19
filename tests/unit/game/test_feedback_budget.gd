extends GdUnitTestSuite
## How one hit's feedback fares in the VFX budget (BUILD.md section 6, hit feedback; section 10,
## "one bright thing per 100x100 u region per 3 frames"; CLAUDE.md rule 7): a finisher's arc and
## burst survive the hit's own spark, a burn never displaces a Taper spark, every effect is
## drawn from its first tick, the flash setting scales opacity and not duration, and the
## screen-space effects are admitted by the budget. Task 6 review, presentation H1, L1, L2, M6.


## A hit feedback and the budget it feeds.
class Fed:
	extends RefCounted

	var fb: HitFeedback
	var vfx: VfxBudget


func _tuning() -> FeedbackTuning:
	return load(FeedbackTuning.PATH) as FeedbackTuning


func _sim_with(kind: String, value: int) -> Simulation:
	var sim := Simulation.new(Scenario.make(1, "", ""))
	sim.step(InputFrame.new())
	sim.events.add(kind, Fx.units(500), Fx.units(300), value)
	return sim


func _kept(vfx: VfxBudget) -> Array[int]:
	var kinds: Array[int] = []
	for e: VfxBudget.Effect in vfx.effects:
		kinds.append(e.kind)
	return kinds


func _fed(sim: Simulation) -> Fed:
	var fed := Fed.new()
	fed.fb = auto_free(HitFeedback.new(_tuning()))
	fed.vfx = auto_free(VfxBudget.new(_tuning()))
	fed.fb.attach(fed.vfx, null)
	fed.fb.on_tick(sim)
	return fed


func test_a_finisher_keeps_its_spark_its_smear_and_its_burst() -> void:
	# Task 6 review, presentation H1: the hit's own spark took the cell and the budget refused
	# the arc and the burst.
	var vfx: VfxBudget = _fed(_sim_with(SimEvents.HIT, HitKind.encode(HitKind.FINISHER, 1, 0))).vfx
	assert_array(_kept(vfx)).contains_exactly_in_any_order(
		[VfxBudget.SPARK, VfxBudget.SMEAR, VfxBudget.BURST]
	)
	assert_int(vfx.refused).is_zero()


func test_a_charged_hit_keeps_its_spark_and_its_burst() -> void:
	var vfx: VfxBudget = _fed(_sim_with(SimEvents.HIT, HitKind.encode(HitKind.CHARGED, 1, 0))).vfx
	assert_array(_kept(vfx)).contains_exactly_in_any_order([VfxBudget.SPARK, VfxBudget.BURST])
	assert_int(vfx.refused).is_zero()


func test_a_stagger_keeps_its_burst_beside_the_hit_that_broke_the_poise() -> void:
	var sim: Simulation = _sim_with(SimEvents.HIT, HitKind.encode(HitKind.LIGHT, 1, 0))
	sim.events.add(SimEvents.STAGGER, Fx.units(500), Fx.units(300), 0)
	var vfx: VfxBudget = _fed(sim).vfx
	assert_array(_kept(vfx)).contains_exactly_in_any_order([VfxBudget.SPARK, VfxBudget.BURST])
	assert_int(vfx.refused).is_zero()


func test_two_hits_in_one_cell_are_still_one_bright_thing() -> void:
	# The group shares a cell only with itself: a second hit's spark is still refused or
	# replaces by priority.
	var sim: Simulation = _sim_with(SimEvents.HIT, HitKind.encode(HitKind.FINISHER, 1, 0))
	sim.events.add(SimEvents.HIT, Fx.units(520), Fx.units(310), HitKind.encode(HitKind.LIGHT, 1, 0))
	var vfx: VfxBudget = _fed(sim).vfx
	assert_int(vfx.refused).is_equal(1)
	assert_array(_kept(vfx)).contains_exactly_in_any_order(
		[VfxBudget.SPARK, VfxBudget.SMEAR, VfxBudget.BURST]
	)


func test_a_burn_never_displaces_a_taper_spark_in_either_order() -> void:
	var burn: int = HitKind.encode(HitKind.BURN, 0, 0)
	var taper: int = HitKind.encode(HitKind.LIGHT, 1, 0)
	for burn_first: bool in [true, false]:
		var sim: Simulation = _sim_with(SimEvents.HIT, burn if burn_first else taper)
		sim.events.add(SimEvents.HIT, Fx.units(500), Fx.units(300), taper if burn_first else burn)
		var vfx: VfxBudget = _fed(sim).vfx
		assert_int(vfx.effects.size()).is_equal(1)
		assert_int(vfx.effects[0].kind).is_equal(VfxBudget.SPARK)
		assert_int(vfx.effects[0].priority).is_equal(VfxBudget.PLAYER)
	assert_bool(VfxBudget.BURN < VfxBudget.HIT).is_true()
	assert_bool(VfxBudget.BURN > VfxBudget.PROC).is_true()


func test_a_burn_spark_is_ranked_below_the_players() -> void:
	var vfx: VfxBudget = _fed(_sim_with(SimEvents.HIT, HitKind.encode(HitKind.BURN, 0, 0))).vfx
	assert_int(vfx.effects[0].priority).is_equal(VfxBudget.BURN)
	# Burn trails at a finisher do not hide it either.
	var sim: Simulation = _sim_with(SimEvents.HIT, HitKind.encode(HitKind.FINISHER, 1, 0))
	for _i: int in range(4):
		sim.events.add(
			SimEvents.HIT, Fx.units(500), Fx.units(300), HitKind.encode(HitKind.BURN, 0, 0)
		)
	var finisher: VfxBudget = _fed(sim).vfx
	assert_array(_kept(finisher)).contains([VfxBudget.SMEAR, VfxBudget.BURST])


func test_an_effect_is_drawn_from_its_first_tick_and_lives_its_whole_lifetime() -> void:
	# Task 6 review, presentation L1: the feedback aged every effect before its first draw, so it
	# started at age 1 and lived one tick short.
	var fed: Fed = _fed(_sim_with(SimEvents.HIT, HitKind.encode(HitKind.LIGHT, 1, 0)))
	var fb: HitFeedback = fed.fb
	var vfx: VfxBudget = fed.vfx
	var spark: VfxBudget.Effect = vfx.effects[0]
	assert_int(spark.age).is_zero()
	var drawn: int = 1
	var quiet := Simulation.new(Scenario.make(1, "", ""))
	for _i: int in range(20):
		quiet.step(InputFrame.new())
		fb.on_tick(quiet)
		if vfx.effects.has(spark):
			drawn += 1
	assert_int(drawn).is_equal(vfx.lifetime(VfxBudget.SPARK))


func test_a_one_tick_effect_is_drawn_once() -> void:
	var vfx: VfxBudget = auto_free(VfxBudget.new(_tuning()))
	var fb: HitFeedback = auto_free(HitFeedback.new(_tuning()))
	fb.attach(vfx, null)
	vfx.spawn(VfxBudget.EMBER, VfxBudget.PLAYER, Vector2.ZERO)
	assert_int(vfx.effects.size()).is_equal(1)
	fb.on_tick(Simulation.new(Scenario.make(1, "", "")))
	assert_int(vfx.effects.size()).is_zero()


func test_the_flash_setting_scales_the_opacity_never_the_duration() -> void:
	# Task 6 review, presentation L2: roundi(1 * scale) made the flash vanish below 50%.
	var t: FeedbackTuning = _tuning()
	for scale: float in [0.01, 0.25, 0.49, 0.5, 0.75, 1.0]:
		var fb: HitFeedback = auto_free(HitFeedback.new(t))
		fb.flash_scale = scale
		var overlay: FeedbackOverlay = auto_free(FeedbackOverlay.new())
		overlay.feedback = fb
		var sim: Simulation = _sim_with(SimEvents.PARRY, HitKind.encode(HitKind.PARRY, 1, 0))
		sim.events.add(
			SimEvents.HIT, Fx.units(900), Fx.units(300), HitKind.encode(HitKind.CHARGED, 1, 0)
		)
		fb.on_tick(sim)
		assert_int(fb.flash_ticks).is_equal(t.parry_flash_frames)
		assert_int(fb.chroma_ticks).is_equal(t.chromatic_frames)
		assert_float(overlay.flash_opacity()).is_equal_approx(scale * t.flash_alpha, 0.00001)
		fb.on_tick(Simulation.new(Scenario.make(1, "", "")))
		assert_int(fb.flash_ticks).is_zero()
		assert_float(overlay.flash_opacity()).is_zero()


func test_the_screen_flash_is_admitted_once_per_window_by_the_budget() -> void:
	var t: FeedbackTuning = _tuning()
	var vfx: VfxBudget = auto_free(VfxBudget.new(t))
	assert_bool(vfx.claim_screen(VfxBudget.SCREEN_FLASH, VfxBudget.PLAYER)).is_true()
	# The chromatic split shares the bright slot; the same priority is refused.
	assert_bool(vfx.claim_screen(VfxBudget.SCREEN_SPLIT, VfxBudget.PLAYER)).is_false()
	assert_bool(vfx.claim_screen(VfxBudget.SCREEN_FLASH, VfxBudget.HIT)).is_false()
	assert_int(vfx.refused).is_equal(2)
	for _i: int in range(t.vfx_screen_frames - 1):
		vfx.step()
		assert_bool(vfx.claim_screen(VfxBudget.SCREEN_FLASH, VfxBudget.PLAYER)).is_false()
	vfx.step()
	assert_bool(vfx.claim_screen(VfxBudget.SCREEN_FLASH, VfxBudget.PLAYER)).is_true()
	# A more important flash takes the slot; the vignette is a dark edge and always shows.
	assert_bool(vfx.claim_screen(VfxBudget.SCREEN_SPLIT, VfxBudget.PLAYER)).is_false()
	assert_bool(vfx.claim_screen(VfxBudget.SCREEN_VIGNETTE, VfxBudget.PROC)).is_true()
	var low: VfxBudget = auto_free(VfxBudget.new(t))
	assert_bool(low.claim_screen(VfxBudget.SCREEN_FLASH, VfxBudget.PROC)).is_true()
	assert_bool(low.claim_screen(VfxBudget.SCREEN_FLASH, VfxBudget.PLAYER)).is_true()
	assert_int(low.displaced).is_equal(1)


func test_a_second_parry_flash_inside_the_window_is_not_drawn() -> void:
	var fed: Fed = _fed(_sim_with(SimEvents.PARRY, HitKind.encode(HitKind.PARRY, 1, 0)))
	var fb: HitFeedback = fed.fb
	assert_int(fb.flash_ticks).is_equal(1)
	fb.on_tick(_sim_with(SimEvents.PARRY, HitKind.encode(HitKind.PARRY, 1, 0)))
	assert_int(fb.flash_ticks).is_zero()
	var vfx: VfxBudget = fed.vfx
	assert_int(vfx.refused).is_greater(0)
	# The window passes.
	for _i: int in range(_tuning().vfx_screen_frames):
		fb.on_tick(Simulation.new(Scenario.make(1, "", "")))
	fb.on_tick(_sim_with(SimEvents.PARRY, HitKind.encode(HitKind.PARRY, 1, 0)))
	assert_int(fb.flash_ticks).is_equal(1)


func test_radiances_ring_and_burst_are_one_bright_thing_in_the_budget() -> void:
	var vfx: VfxBudget = _fed(_sim_with(SimEvents.RADIANCE, 0)).vfx
	assert_array(_kept(vfx)).contains_exactly_in_any_order([VfxBudget.BURST, VfxBudget.RING])
	assert_int(vfx.refused).is_zero()


func test_radiances_burst_and_ring_outrank_a_spark_in_their_cell() -> void:
	var fed: Fed = _fed(_sim_with(SimEvents.HIT, HitKind.encode(HitKind.LIGHT, 1, 0)))
	var fb: HitFeedback = fed.fb
	var vfx: VfxBudget = fed.vfx
	fb.on_tick(_sim_with(SimEvents.RADIANCE, 0))
	assert_array(_kept(vfx)).contains([VfxBudget.BURST, VfxBudget.RING])
	assert_array(_kept(vfx)).not_contains([VfxBudget.SPARK])
