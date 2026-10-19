extends GdUnitTestSuite
## Combat's presentation (docs/adr/0013): the F3 overlay's combat boxes and line, the combat view's
## world objects, the hit feedback's answers to the new events, the flash's opacity and the main
## scene's wiring. It all reads the simulation and never writes it.

const S: int = InputFrame.STICK_MAX


func _sim(room_id: String, options: Dictionary[String, int] = {}) -> Simulation:
	var sc: Scenario = Scenario.make(1)
	sc.room = room_id
	for key: String in options:
		sc.options[key] = options[key]
	return Simulation.new(sc)


func _in(pressed: int = 0, x: int = 0, y: int = 0) -> InputFrame:
	return InputFrame.make(pressed, pressed, x * S, y * S)


func _kinds(boxes: Array[DebugBoxes.Box]) -> Array[int]:
	var out: Array[int] = []
	for b: DebugBoxes.Box in boxes:
		out.append(b.kind)
	return out


func test_the_overlay_shows_each_enemy_and_its_live_attack_white_or_red() -> void:
	for red: bool in [false, true]:
		var sim: Simulation = _sim("test/dummy_red" if red else "test/dummy_swing")
		var boxes: Array[DebugBoxes.Box] = DebugBoxes.collect(sim, Rect2())
		assert_array(_kinds(boxes)).contains([DebugBoxes.ENEMY])
		while sim.tick < 54:
			sim.step(_in())
			boxes = DebugBoxes.collect(sim, Rect2())
			var live: bool = sim.combat.enemies[0].attack_box().size != Vector2i.ZERO
			var want: int = DebugBoxes.ATTACK_RED if red else DebugBoxes.ATTACK_WHITE
			var other: int = DebugBoxes.ATTACK_WHITE if red else DebugBoxes.ATTACK_RED
			assert_bool(_kinds(boxes).has(want)).is_equal(live)
			assert_bool(_kinds(boxes).has(other)).is_false()
		assert_int(sim.tick - 1).is_equal(53)


func test_the_overlay_names_a_telegraph_and_when_it_lands() -> void:
	var sim: Simulation = _sim("test/dummy_swing")
	while sim.tick < 40:
		sim.step(_in())
	var label: String = ""
	for b: DebugBoxes.Box in DebugBoxes.collect(sim, Rect2()):
		if b.kind == DebugBoxes.ENEMY:
			label = b.label
	# Frame 39 is the swing's frame 11; it lands on its frame 25.
	assert_str(label).contains("telegraph").contains("swing lands in 14")


func test_the_overlay_draws_kindles_cone_once_labelled_and_the_trails() -> void:
	var sim: Simulation = _sim("test/dummy", {"flame": 33, "kindling": 20})
	sim.step(_in(InputFrame.SPELL))
	while sim.player.spell_frame <= sim.player.kit.kindle_startup:
		sim.step(_in())
	var cone: int = 0
	var labels: int = 0
	for b: DebugBoxes.Box in DebugBoxes.collect(sim, Rect2()):
		if b.kind == DebugBoxes.SPELL:
			cone += 1
			labels += 1 if b.label != "" else 0
	assert_int(cone).is_equal(3)
	assert_int(labels).is_equal(1)
	var trails: Simulation = _sim("test/dummy", {"kindling": 20})
	trails.step(_in(InputFrame.ATTACK))
	trails.step(_in())
	trails.step(_in())
	assert_array(_kinds(DebugBoxes.collect(trails, Rect2()))).contains([DebugBoxes.TRAIL])


func test_the_overlay_text_carries_the_vitals_and_the_spell() -> void:
	var sim: Simulation = _sim("test/flat", {"flame": 33, "hearts": 4, "kindling": 9})
	sim.step(_in(InputFrame.MEND))
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	overlay.attach_sim(sim, null)
	var text: String = "\n".join(overlay.hud_lines())
	assert_str(text).contains("hearts 4/5").contains("flame 0").contains("kindling 9 flame")
	assert_str(text).contains("spell mend frame 1")


func test_the_combat_view_follows_the_drawn_player() -> void:
	var view: CombatView = auto_free(CombatView.new())
	var pv: PlayerView = auto_free(PlayerView.new())
	add_child(pv)
	add_child(view)
	view.player_view = pv
	var cone_sim: Simulation = _sim("test/dummy", {"flame": 33})
	pv.begin(cone_sim)
	cone_sim.step(_in(InputFrame.SPELL))
	for i: int in range(5):
		cone_sim.step(_in())
		pv.capture(cone_sim)
		view.capture(cone_sim)
	assert_int(view._cone.size()).is_equal(3)
	# Relative to the player's centre, so the cone moves with the drawn (interpolated) player.
	assert_float(view._cone[0].position.x).is_equal_approx(0.0, 0.001)


func test_hazards_radiance_and_tiers_answer_in_the_feedback() -> void:
	var fb: HitFeedback = auto_free(HitFeedback.new())
	var vfx: VfxBudget = auto_free(VfxBudget.new())
	fb.attach(vfx, null)
	var sim: Simulation = _sim("test/flat", {"kindling": 8})
	sim.events.add(SimEvents.HAZARD, 0, 0)
	sim.events.add(SimEvents.HIT, 0, 0, HitKind.encode(HitKind.LIGHT, 1, 0, Kindling.FLAME))
	fb.on_tick(sim)
	assert_int(fb.vignette_ticks).is_equal(fb.tuning.vignette_frames)
	var spark: VfxBudget.Effect = null
	for e: VfxBudget.Effect in vfx.effects:
		if e.kind == VfxBudget.SPARK:
			spark = e
	assert_object(spark).is_not_null()
	# Kindling Flame: hit sparks turn orange.
	assert_that(spark.colour).is_equal(HitFeedback.SPARK_TINTS[Kindling.FLAME])
	sim.events.clear()
	sim.events.add(SimEvents.RADIANCE, Fx.units(900), 0)
	fb.on_tick(sim)
	assert_int(fb.flash_ticks).is_greater(0)
	# The ring is the budget's too, not drawn by the combat view (CLAUDE.md rule 7).
	var ring: VfxBudget.Effect = null
	for e: VfxBudget.Effect in vfx.effects:
		if e.kind == VfxBudget.RING:
			ring = e
	assert_object(ring).is_not_null()
	assert_int(ring.life).is_equal(fb.tuning.radiance_ring_frames)


func test_a_charged_kill_slows_time_and_a_light_kill_does_not() -> void:
	var fb: HitFeedback = auto_free(HitFeedback.new())
	var slows: Array[float] = []
	fb.slow_motion.connect(func(scale: float, _ticks: int) -> void: slows.append(scale))
	var sim: Simulation = _sim("test/flat")
	sim.events.add(SimEvents.KILL, 0, 0, HitKind.encode(HitKind.LIGHT, 1, 0))
	fb.on_tick(sim)
	assert_array(slows).is_empty()
	sim.events.clear()
	sim.events.add(SimEvents.KILL, 0, 0, HitKind.encode(HitKind.CHARGED, 1, 0))
	fb.on_tick(sim)
	assert_array(slows).contains_exactly([fb.tuning.charged_kill_time_scale])


func test_the_full_screen_flash_lets_the_frame_show_through() -> void:
	var tuning: FeedbackTuning = load(FeedbackTuning.PATH) as FeedbackTuning
	assert_float(tuning.flash_alpha).is_between(0.3, 0.8)
	assert_array(Array(tuning.validate())).is_empty()


func test_the_main_scene_carries_combats_views_and_feedback() -> void:
	var main: Node = auto_free((load("res://game/main.tscn") as PackedScene).instantiate())
	for path: String in [
		"World/EnemyView",
		"World/CombatView",
		"World/Vfx",
		"World/Voices",
		"HitFeedback",
		"Hud",
		"FeedbackOverlay",
	]:
		assert_object(main.get_node_or_null(path)).override_failure_message(path).is_not_null()


## Records the tick every telegraph sound is played on (CLAUDE.md rule 7: through the voices).
class LogVoices:
	extends Voices

	var tick: int = 0
	## Tick and sound id of each telegraph sound played.
	var cues: Array[Vector2i] = []
	var other: int = 0

	func play(
		stream: AudioStream, _at: Vector2, _prio: int, _volume_db: float = 0.0, _pitch: float = 1.0
	) -> bool:
		if Synth.is_variant_of(stream, "telegraph"):
			cues.append(Vector2i(tick, 0))
		elif Synth.is_variant_of(stream, "telegraph_red"):
			cues.append(Vector2i(tick, 1))
		else:
			other += 1
		return true


## Steps [param room_id] with an attack press on [param press] (or none), feeding the hit feedback,
## and returns [first cue tick, red?, first tick the swing's box is live, the sound count].
func _cue_run(room_id: String, press: int) -> Array[int]:
	var sim: Simulation = _sim(room_id)
	var fb: HitFeedback = auto_free(HitFeedback.new())
	var voices: LogVoices = auto_free(LogVoices.new())
	fb.attach(null, voices)
	var landing: int = -1
	for f: int in range(80):
		sim.step(_in(InputFrame.ATTACK if f == press else 0))
		voices.tick = f
		fb.on_tick(sim)
		# The swing lands on the tick its box is live, or a parry or a hit says it did (a parry
		# staggers the enemy on that very tick, so the box is already gone).
		var lands: bool = sim.combat.enemies[0].attack_box().size != Vector2i.ZERO
		lands = lands or sim.events.has(SimEvents.PARRY) or sim.events.has(SimEvents.PLAYER_HIT)
		if landing < 0 and lands:
			landing = f
	var first: Vector2i = voices.cues[0] if not voices.cues.is_empty() else Vector2i(-1, -1)
	return [first.x, first.y, landing, voices.cues.size()]


func test_the_telegraph_sound_plays_exactly_twenty_frames_before_the_swing_lands() -> void:
	# Task 6 review, presentation M4; BUILD.md section 11: "every telegraph has a sound 20 f
	# before the hit". The sound used to play when the 24 f telegraph began, and 26 f before the
	# hit when the enemy was struck during it. Presses at 27 to 31 strike it before the cue (the
	# hitstop holds the telegraph back), 35 and 45 after the cue (the swing is committed).
	for room_id: String in ["test/dummy_swing", "test/dummy_red"]:
		for press: int in [-1, 24, 27, 28, 29, 30, 31, 33, 34, 35, 45]:
			var run: Array[int] = _cue_run(room_id, press)
			var label: String = "%s, attack pressed on %d" % [room_id, press]
			assert_int(run[3]).override_failure_message(label + ": one cue").is_equal(1)
			var red: int = 1 if room_id.ends_with("red") else 0
			assert_int(run[1]).override_failure_message(label).is_equal(red)
			assert_int(run[2] - run[0]).override_failure_message(label).is_equal(20)


func test_the_cue_is_not_late_when_the_enemy_is_struck_after_it() -> void:
	# Struck on the cue's tick or after: the committed swing still lands 20 ticks after the cue,
	# and the cue itself falls where an unstruck swing's does.
	var calm: Array[int] = _cue_run("test/dummy_swing", -1)
	assert_int(calm[0]).is_equal(33)
	assert_int(calm[2]).is_equal(53)
	var struck: Array[int] = _cue_run("test/dummy_swing", 35)
	assert_int(struck[0]).is_equal(33)
	assert_int(struck[2]).is_equal(53)
	# Struck before it, the hitstop pushes the telegraph and the cue back together.
	var early: Array[int] = _cue_run("test/dummy_swing", 28)
	assert_int(early[0]).is_greater(33)


func _label_ticks(label: String) -> int:
	var at: int = label.find("lands in ")
	return int(label.substr(at + "lands in ".length()))


func test_the_overlay_counts_down_to_the_landing_through_the_enemys_hitstop() -> void:
	# Task 6 review, presentation L4: struck during its telegraph the dummy showed "lands in 16"
	# for three ticks in a row.
	for press: int in [-1, 28, 31, 35]:
		var sim: Simulation = _sim("test/dummy_swing")
		var labels: Dictionary[int, int] = {}
		var landing: int = -1
		var struck: int = 0 if press < 0 else 1000
		for f: int in range(70):
			sim.step(_in(InputFrame.ATTACK if f == press else 0))
			if sim.events.has(SimEvents.HIT) and struck == 1000:
				struck = f
			# Before the hit nothing can tell the countdown a hitstop is coming.
			for b: DebugBoxes.Box in DebugBoxes.collect(sim, Rect2()):
				if b.kind == DebugBoxes.ENEMY and b.label.contains("lands in") and f >= struck:
					labels[f] = _label_ticks(b.label)
			if landing < 0 and sim.combat.enemies[0].attack_box().size != Vector2i.ZERO:
				landing = f
		assert_int(labels.size()).is_greater(10)
		for f: int in labels:
			(
				assert_int(f + labels[f])
				. override_failure_message("press %d, frame %d" % [press, f])
				. is_equal(landing)
			)


func test_a_dead_enemy_is_an_outline_not_a_hurtbox() -> void:
	# Task 6 review, presentation L5: F3 drew a full-size hurtbox for a corpse that nothing hits.
	var fx: Fixture = Fixture.parse_file(
		"res://tests/replay/combat/kill_ember_reaches_the_player.fixture"
	)
	var sim := Simulation.new(fx.scenario)
	var saw_dead: bool = false
	for f: int in range(8):
		sim.step(fx.input_frame(f))
		var boxes: Array[DebugBoxes.Box] = DebugBoxes.collect(sim, Rect2())
		var e: Enemy = sim.combat.enemies[0]
		var hurt: int = 0
		var dead: int = 0
		for b: DebugBoxes.Box in boxes:
			hurt += 1 if b.kind == DebugBoxes.ENEMY else 0
			if b.kind == DebugBoxes.ENEMY_DEAD:
				dead += 1
				assert_str(b.label).contains("dead")
		assert_int(hurt).is_equal(1 if e.is_alive() else 0)
		assert_int(dead).is_equal(0 if e.is_alive() else 1)
		assert_bool(e.hurtbox().size == Vector2i.ZERO).is_equal(not e.is_alive())
		saw_dead = saw_dead or not e.is_alive()
	assert_bool(saw_dead).is_true()
	assert_bool(DebugOverlay.BOX_COLOURS.has(DebugBoxes.ENEMY_DEAD)).is_true()
	assert_bool(DebugOverlay.FILLED.has(DebugBoxes.ENEMY_DEAD)).is_false()
	var dead_colour: Color = DebugOverlay.BOX_COLOURS[DebugBoxes.ENEMY_DEAD]
	assert_bool(dead_colour != DebugOverlay.BOX_COLOURS[DebugBoxes.ENEMY]).is_true()


func test_the_enemy_label_is_drawn_above_the_telegraph_bar() -> void:
	# Task 6 review, core L3: the rising bar struck through the start of the label.
	for room_id: String in ["test/dummy_swing", "test/dummy_red"]:
		var sim: Simulation = _sim(room_id)
		var lifted: int = 0
		for _f: int in range(70):
			sim.step(_in())
			var e: Enemy = sim.combat.enemies[0]
			for b: DebugBoxes.Box in DebugBoxes.collect(sim, Rect2()):
				if b.kind != DebugBoxes.ENEMY:
					continue
				if EnemyView.cue_progress(e) >= 0.0:
					lifted += 1
					# The label's baseline is 4 u above its lift; the bar's highest point at full
					# height is the cue's extent above the box.
					var baseline: float = b.rect.position.y - 4.0 - b.label_lift
					var highest: float = b.rect.position.y
					for p: Vector2 in EnemyView.cue_bar(b.rect, 1.0, e.attack.parryable):
						highest = minf(highest, p.y)
					assert_float(baseline).is_less(highest)
				else:
					# Clear of the health and poise bars (presentation review r3, L1).
					assert_float(b.label_lift).is_equal(
						EnemyView.BARS_GAP_PX + DebugBoxes.LABEL_CLEAR_U
					)
		# 24 telegraph frames and the landing frame.
		assert_int(lifted).is_equal(25)


func test_sparks_are_tinted_by_the_tier_the_hit_used() -> void:
	# Task 6 review, presentation L3: the hit that takes Kindling from 7 to 8 deals Ember damage
	# and used to show the Flame spark.
	for kindling: int in [7, 8]:
		var sim: Simulation = _sim("test/dummy", {"kindling": kindling})
		var fb: HitFeedback = auto_free(HitFeedback.new())
		var vfx: VfxBudget = auto_free(VfxBudget.new())
		fb.attach(vfx, null)
		var tint: Color = Color(0, 0, 0, 0)
		var dealt: int = 0
		var hp: int = sim.combat.enemies[0].hp
		for f: int in range(12):
			sim.step(_in(InputFrame.ATTACK if f == 0 else 0))
			fb.on_tick(sim)
			if sim.events.has(SimEvents.HIT):
				dealt = hp - sim.combat.enemies[0].hp
				for e: VfxBudget.Effect in vfx.effects:
					if e.kind == VfxBudget.SPARK:
						tint = e.colour
				break
		# 7 hits: Ember (10 damage, white spark), though the hit makes it 8 and Flame. 8 hits:
		# Flame (11 damage, orange spark).
		var tier: int = Kindling.EMBER if kindling == 7 else Kindling.FLAME
		assert_int(dealt).is_equal(10 if kindling == 7 else 11)
		assert_that(tint).is_equal(HitFeedback.SPARK_TINTS[tier])
