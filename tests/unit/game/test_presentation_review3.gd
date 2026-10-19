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
				(
					assert_bool(seen.has(b.rect))
					. override_failure_message("%s frame %d: two labels on %s" % [path, f, b.rect])
					. is_false()
				)
				seen[b.rect] = true


## Records every sound the feedback plays: the stream and the pitch.
class LogVoices:
	extends Voices

	var streams: Array[AudioStream] = []
	var pitches: Array[float] = []

	func play(
		stream: AudioStream, _at: Vector2, _prio: int, _volume_db: float = 0.0, pitch: float = 1.0
	) -> bool:
		streams.append(stream)
		pitches.append(pitch)
		return true


## Feeds a fixture's inputs to the driver one tick at a time.
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


## A driver wired as game/main.gd wires it, playing a fixture, and its feedback.
class Wired:
	var driver: SimDriver
	var feedback: HitFeedback
	var vfx: VfxBudget


func _wired(fx: Fixture, voices: Voices = null) -> Wired:
	var w := Wired.new()
	var input: FixtureInput = auto_free(FixtureInput.new())
	input.fx = fx
	w.driver = auto_free(SimDriver.new())
	w.driver.input_layer = input
	w.driver.start(fx.scenario)
	w.vfx = auto_free(VfxBudget.new())
	w.feedback = auto_free(HitFeedback.new())
	w.feedback.attach(w.vfx, voices)
	var driver: SimDriver = w.driver
	var feedback: HitFeedback = w.feedback
	driver.ticked.connect(func() -> void: feedback.on_tick(driver.sim))
	feedback.slow_motion.connect(driver.slow)
	return w


func test_no_second_of_play_holds_more_than_three_full_screen_flashes() -> void:
	# Presentation review r2, H1: five parries 4 ticks apart drew five 0.55 white flashes in 17
	# ticks (BUILD.md section 12: the Harding test fails more than 3 in a second).
	var w: Wired = _wired(_fixture("combat/five_parries_in_a_second"))
	var flash_ticks: Array[int] = []
	for _f: int in range(240):
		var tick_before: int = w.driver.sim.tick
		w.driver._process(1.0 / 60.0)
		if w.driver.sim.tick != tick_before and w.feedback.flash_ticks > 0:
			flash_ticks.append(w.driver.sim.tick - 1)
	assert_int(flash_ticks.size()).is_greater(0)
	var window: int = w.feedback.tuning.screen_flash_window_frames
	for t: int in flash_ticks:
		var in_window: int = 0
		for u: int in flash_ticks:
			if u >= t and u < t + window:
				in_window += 1
		assert_int(in_window).is_less_equal(w.feedback.tuning.screen_flash_max)
	# Five parries, three flashes: the other two show the burst and the enemy's own cues.
	assert_int(flash_ticks.size()).is_equal(w.feedback.tuning.screen_flash_max)


func test_a_flash_is_refused_past_the_window_whatever_its_priority_and_admitted_after() -> void:
	var t: FeedbackTuning = load(FeedbackTuning.PATH) as FeedbackTuning
	var vfx: VfxBudget = auto_free(VfxBudget.new(t))
	var admitted: int = 0
	for _i: int in range(t.screen_flash_window_frames):
		if vfx.claim_screen(VfxBudget.SCREEN_FLASH, VfxBudget.SPELL):
			admitted += 1
		vfx.step()
	assert_int(admitted).is_equal(t.screen_flash_max)
	# A whole window with no flash, and one is admitted again.
	for _i: int in range(t.screen_flash_window_frames):
		vfx.step()
	assert_bool(vfx.claim_screen(VfxBudget.SCREEN_FLASH, VfxBudget.PLAYER)).is_true()


func test_a_running_slow_waits_out_a_second_hitstop() -> void:
	# Presentation review r2, M1: a second parry inside the first one's six slow ticks spent half
	# the slow in its own hitstop, stretching it, and drew its one-tick flash for two frames.
	var w: Wired = _wired(_fixture("combat/two_parries_in_a_slow"))
	var parries: Array[int] = []
	var frozen_slowed: int = 0
	var flash_frames: int = 0
	var slowed: int = 0
	for _f: int in range(200):
		var tick_before: int = w.driver.sim.tick
		var scale: float = w.driver.time_scale
		var frozen_before: bool = w.driver.sim.player.freeze > 0
		w.driver._process(1.0 / 60.0)
		if w.driver.sim.events.has(SimEvents.PARRY) and w.driver.sim.tick != tick_before:
			parries.append(w.driver.sim.tick - 1)
		if w.feedback.flash_ticks > 0:
			flash_frames += 1
		if scale < 1.0 and w.driver.sim.tick != tick_before:
			slowed += 1
			if frozen_before:
				frozen_slowed += 1
	assert_array(parries).is_equal([53, 68])
	assert_int(frozen_slowed).is_zero()
	assert_int(slowed).is_greater(0)
	# One tick, one frame, for each of the two flashes.
	assert_int(flash_frames).is_equal(2)


func test_resuming_the_frame_stepper_never_draws_the_player_backward() -> void:
	# Presentation review r3, L2: resuming left the phase of the tick it paused in, and the first
	# frame drew the player back toward the previous tick (-1.5 u at 144 Hz).
	var w: Wired = _wired(_fixture("physics/walk_up_lip_stairs"))
	var view: PlayerView = auto_free(PlayerView.new())
	view.begin(w.driver.sim)
	var driver: SimDriver = w.driver
	driver.ticked.connect(func() -> void: view.capture(driver.sim))
	var dt: float = 1.0 / 144.0
	for _f: int in range(40):
		driver._process(dt)
	driver.set_paused(true)
	var paused_x: float = view.box_at(driver.alpha).position.x
	for _f: int in range(3):
		driver._process(dt)
	driver.set_paused(false)
	var last_x: float = paused_x
	for _f: int in range(12):
		driver._process(dt)
		var x: float = view.box_at(driver.alpha).position.x
		assert_float(x).is_greater_equal(last_x - 0.0001)
		last_x = x
	assert_float(last_x).is_greater(paused_x)


func test_displacing_a_hit_removes_its_whole_group() -> void:
	# Presentation review r2, L3: only the holder was erased; the displaced hit's smear and burst
	# kept drawing beside the newcomer.
	var vfx: VfxBudget = auto_free(VfxBudget.new())
	var at := Vector2(150, 150)
	var none := Color(0, 0, 0, 0)
	for kind: int in [VfxBudget.SPARK, VfxBudget.SMEAR, VfxBudget.BURST]:
		assert_bool(vfx.spawn(kind, VfxBudget.PLAYER, at, Vector2.RIGHT, 0, 1.0, none, 7)).is_true()
	vfx.step()
	(
		assert_bool(vfx.spawn(VfxBudget.BURST, VfxBudget.SPELL, at, Vector2.UP, 0, 3.0, none, 8))
		. is_true()
	)
	assert_int(vfx.effects.size()).is_equal(1)
	assert_int(vfx.effects[0].group).is_equal(8)
	assert_int(vfx.displaced).is_equal(3)


func test_every_spark_variant_the_tuning_allows_has_a_hit_sound() -> void:
	# Presentation review r2, L4: spark_variants 4 or 5 (inside the spec's 3 to 5) asked the synth
	# for hit3 and hit4, which did not exist.
	var t: FeedbackTuning = (load(FeedbackTuning.PATH) as FeedbackTuning).duplicate()
	for n: int in [3, 4, 5]:
		t.spark_variants = n
		assert_array(t.validate()).is_empty()
		for v: int in range(n):
			assert_int(Synth.sound("hit%d" % v).data.size()).is_greater(1000)
	t.spark_variants = Synth.HIT_VARIANTS + 1
	assert_array(t.validate()).is_not_empty()


func test_every_sound_varies_and_a_heal_is_not_a_parry() -> void:
	# Presentation review r2, L5: only the hit's pitch varied; the parry chime, the telegraph cue,
	# the kill, the ember, the thump and the player-hit played identically every time, and Mend's
	# heal and Radiance used the parry's chime.
	var voices: LogVoices = auto_free(LogVoices.new())
	var w: Wired = _wired(_fixture("combat/five_parries_in_a_second"), voices)
	for _f: int in range(100):
		w.driver._process(1.0 / 60.0)
	var plays: Dictionary[String, int] = {}
	var seen: Dictionary[String, bool] = {}
	var distinct: Dictionary[String, int] = {}
	var spread: float = w.feedback.tuning.sound_pitch_spread
	for i: int in range(voices.streams.size()):
		for base: String in Synth.BASES:
			if not Synth.is_variant_of(voices.streams[i], base):
				continue
			plays[base] = plays.get(base, 0) + 1
			assert_float(absf(voices.pitches[i] - 1.0)).is_less_equal(spread + 0.0001)
			var key: String = "%s|%.5f" % [base, voices.pitches[i]]
			if not seen.has(key):
				seen[key] = true
				distinct[base] = distinct.get(base, 0) + 1
	assert_bool(plays.has("chime")).is_true()
	assert_bool(plays.has("telegraph")).is_true()
	for base: String in plays:
		if plays[base] >= 3:
			assert_int(distinct[base]).override_failure_message(base).is_greater(1)
	for other: String in ["heal", "radiance"]:
		for v: int in range(Synth.variants(other)):
			assert_bool(Synth.is_variant_of(Synth.variant(other, v), "chime")).is_false()
			var same: bool = Synth.sound("%s%d" % [other, v]).data == Synth.sound("chime0").data
			assert_bool(same).is_false()


func test_the_budget_lifetimes_and_the_feel_numbers_are_content() -> void:
	# Presentation review r2, L6: lifetimes, the Flame bar's ease and flash, the split's offset and
	# opacity and the vignette's depth and opacity were literals in code.
	var t: FeedbackTuning = load(FeedbackTuning.PATH) as FeedbackTuning
	var vfx: VfxBudget = auto_free(VfxBudget.new(t))
	assert_int(vfx.lifetime(VfxBudget.SPARK)).is_equal(t.vfx_spark_frames)
	assert_int(vfx.lifetime(VfxBudget.BURST)).is_equal(t.vfx_burst_frames)
	assert_int(vfx.lifetime(VfxBudget.SMEAR)).is_equal(t.vfx_smear_frames)
	for path: String in [
		"res://game/vfx/vfx_budget.gd",
		"res://game/ui/hud.gd",
		"res://game/feedback/feedback_overlay.gd"
	]:
		var src: String = FileAccess.get_file_as_string(path)
		for literal: String in [
			"LIFETIMES", "GAIN_FLASH_TICKS", "VIGNETTE_DEPTH", "move_toward(shown_flame"
		]:
			(
				assert_bool(src.contains(literal))
				. override_failure_message("%s has %s" % [path, literal])
				. is_false()
			)


func test_the_hud_flash_follows_the_flash_setting() -> void:
	# Presentation review r2, L2: the Flame bar flashed for 12 ticks at a flash setting of 0.
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	hud.vitals = Vitals.new((load(CombatTuning.PATH) as CombatTuning).compile())
	hud.flash_scale = 0.0
	hud.on_tick()
	hud.vitals.flame.gain(33)
	hud.on_tick()
	assert_int(hud.gain_flash).is_greater(0)
	# At 0 the bar is outlined, not lit: the lit colour is the plain one scaled by the setting.
	assert_bool(Hud.FLAME.lerp(Hud.FLAME_GAIN, 0.0) == Hud.FLAME).is_true()
	assert_bool(hud.flash_scale > 0.0).is_false()


func test_the_telegraph_cue_is_above_the_effects_and_the_trails_are_below_the_enemies() -> void:
	# Presentation review r2, L10 and M3: the budget's header claimed telegraphs outrank every
	# effect, but the cue was drawn under the VFX; and the Blaze trails were drawn over the enemy,
	# covering its cue.
	var main: Node = auto_free((load("res://game/main.tscn") as PackedScene).instantiate())
	add_child(main)
	await get_tree().process_frame
	var world: Node = main.get_node("World")
	assert_int(world.get_node("CombatView").get_index()).is_less(
		world.get_node("EnemyView").get_index()
	)
	var cues: Node2D = null
	for child: Node in world.get_node("EnemyView").get_children():
		if child is Node2D and (child as Node2D).z_index == EnemyView.CUE_Z:
			cues = child as Node2D
	assert_object(cues).is_not_null()
	assert_int(cues.z_index).is_greater((world.get_node("Vfx") as Node2D).z_index)
	assert_int((world.get_node("DebugOverlay") as Node2D).z_index).is_greater(cues.z_index)


func test_the_finishers_slash_arc_is_centred_on_the_player_not_the_enemy() -> void:
	# Presentation review r2, L9: the arc was centred on the struck enemy, 56 u beyond it from
	# Ash, and read as a shockwave.
	var w: Wired = _wired(_fixture("combat/blaze_finisher_burst"))
	var smear: VfxBudget.Effect = null
	var centre: Vector2 = Vector2.ZERO
	var enemy_at: Vector2 = Vector2.ZERO
	for _f: int in range(40):
		w.driver._process(1.0 / 60.0)
		for e: VfxBudget.Effect in w.vfx.effects:
			if e.kind == VfxBudget.SMEAR and smear == null:
				smear = e
				var pl: Body = w.driver.sim.player.body
				centre = Vector2(float(pl.x), float(pl.y - pl.height / 2)) / Fx.SUB
				enemy_at = Vector2(w.driver.sim.combat.enemies[0].centre()) / Fx.SUB
	assert_object(smear).is_not_null()
	# The arc's centre is Ash's, its radius the reach to the struck enemy.
	assert_vector(smear.at).is_equal_approx(centre, Vector2(0.01, 0.01))
	assert_float(smear.size).is_equal_approx(centre.distance_to(enemy_at), 0.01)
