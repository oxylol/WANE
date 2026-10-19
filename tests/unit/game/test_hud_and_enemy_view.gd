extends GdUnitTestSuite
## The grey-box HUD (BUILD.md section 12's fallback; section 15: "the Flame bar visibly reacts")
## and the grey-box enemy view (section 6 hit feedback and the red/white telegraph cue).

const ROOM: String = """room test/inline
size 30 10
spawn 200 256
tiles
##############################
#............................#
#............................#
#............................#
#............................#
#............................#
#............................#
#............................#
##############################
##############################
end
"""

var _params: CombatParams


func before_test() -> void:
	_params = (load(CombatTuning.PATH) as CombatTuning).compile()


func _hud() -> Hud:
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	hud.vitals = Vitals.new(_params)
	return hud


func test_the_flame_bar_eases_to_a_gain_and_flashes_for_twelve_ticks() -> void:
	var hud: Hud = _hud()
	hud.on_tick()
	hud.vitals.flame.gain(33)
	var flashed: int = 0
	var filled: Array[float] = []
	for _i: int in range(20):
		hud.on_tick()
		filled.append(hud.shown_flame)
		if hud.gain_flash > 0:
			flashed += 1
	# The flash lasts GAIN_FLASH_TICKS counting the tick of the gain (task 6 review, L7: it was
	# one short); the fill climbs 4 a tick and settles on the value.
	assert_int(flashed).is_equal(Hud.GAIN_FLASH_TICKS)
	assert_float(filled[0]).is_equal(4.0)
	assert_float(filled[7]).is_equal(32.0)
	assert_float(filled[8]).is_equal(33.0)
	assert_float(filled[19]).is_equal(33.0)


func test_spending_flame_drains_the_bar_without_a_flash() -> void:
	var hud: Hud = _hud()
	hud.vitals.flame.gain(66)
	for _i: int in range(30):
		hud.on_tick()
	assert_bool(hud.vitals.flame.spend(33)).is_true()
	hud.on_tick()
	assert_int(hud.gain_flash).is_equal(0)
	assert_float(hud.shown_flame).is_equal(62.0)


func test_the_hud_draws_every_heart_and_tier() -> void:
	var hud: Hud = _hud()
	for hits: int in [0, 8, 20, 40]:
		hud.vitals.kindling.hits = hits
		hud.vitals.hearts.lose(1)
		hud.on_tick()
		await get_tree().process_frame
	assert_int(hud.vitals.hearts.current).is_equal(1)
	assert_int(hud.vitals.kindling.tier()).is_equal(Kindling.WHITE)


func test_hearts_are_hearts() -> void:
	# The polygon is closed-shape-sized: inside a box the heart's size, and wider than tall.
	var pts: PackedVector2Array = Hud._heart(Vector2.ZERO, Hud.HEART_PX)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p: Vector2 in pts:
		r = r.expand(p)
	assert_float(r.size.x).is_between(Hud.HEART_PX * 0.85, Hud.HEART_PX * 1.0)
	assert_float(r.size.y).is_less(r.size.x)
	assert_bool(Geometry2D.triangulate_polygon(pts).is_empty()).is_false()


func test_the_enemy_view_draws_every_state() -> void:
	var room: RoomData = RoomData.parse(ROOM)
	var world: CollisionWorld = room.build_world()
	var events := SimEvents.new()
	var def: EnemyDef = load("res://content/enemies/dummy.tres") as EnemyDef
	var list: Array[Enemy] = []
	for state: int in range(Enemy.STATE_NAMES.size()):
		var e := RoomData.RoomEntity.new()
		e.kind = "dummy"
		e.x_u = 120 + state * 120
		e.y_u = 256
		e.props = {"attack": "swing" if state % 2 == 0 else "red"}
		list.append(TrainingDummy.from_entity(e, def, _params, world, events))
	list[Enemy.TELEGRAPH].start_attack(def.attacks[0])
	list[Enemy.STRIKE].start_attack(def.attacks[0])
	for _i: int in range(def.attacks[0].telegraph + 1):
		list[Enemy.STRIKE].step(null)
	list[Enemy.STAGGER].stagger(30)
	list[Enemy.STUN].stun(30)
	list[Enemy.DEAD].take_hit(def.hp, 0, 0)
	assert_str(list[Enemy.STRIKE].state_name()).is_equal("strike")
	assert_bool(list[Enemy.DEAD].is_alive()).is_false()
	var sc: Scenario = Scenario.make(1)
	sc.room = "test/flat"
	var sim := Simulation.new(sc)
	sim.combat.enemies.assign(list)
	var view: EnemyView = auto_free(EnemyView.new())
	add_child(view)
	view.show_now(sim)
	await get_tree().process_frame
	assert_int(view.shown.size()).is_equal(Enemy.STATE_NAMES.size())
	assert_float(view.shown[Enemy.TELEGRAPH].telegraph).is_greater_equal(0.0)
	assert_bool(view.shown[Enemy.STRIKE].attack.size != Vector2.ZERO).is_true()
	assert_bool(view.shown[Enemy.DEAD].alive).is_false()
	assert_int(view.shown[Enemy.STUN].state).is_equal(Enemy.STUN)


func _shown(since_hit: int) -> EnemyView.Shown:
	var s := EnemyView.Shown.new()
	s.since_hit = since_hit
	return s


func test_the_enemy_flashes_for_the_tuned_frames_at_the_flash_setting() -> void:
	# Task 6 review, presentation M3: the view had a literal 2 and ignored the tuning and the
	# setting.
	var t: FeedbackTuning = (load(FeedbackTuning.PATH) as FeedbackTuning).duplicate()
	var view: EnemyView = auto_free(EnemyView.new())
	view.tuning = t
	view.flash_scale = 1.0
	for frames: int in [0, 1, 2, 3]:
		t.enemy_flash_frames = frames
		for since: int in range(5):
			var want: Color = EnemyView.HIT_FLASH if since < frames else EnemyView.BODY
			assert_that(view.body_colour(_shown(since), EnemyView.BODY)).is_equal(want)
	t.enemy_flash_frames = 2
	view.flash_scale = 0.5
	assert_that(view.body_colour(_shown(0), EnemyView.BODY)).is_equal(
		EnemyView.BODY.lerp(EnemyView.HIT_FLASH, 0.5)
	)
	assert_that(view.body_colour(_shown(2), EnemyView.BODY)).is_equal(EnemyView.BODY)
	assert_bool(view.shows_hit_outline(_shown(0))).is_false()


func test_at_a_flash_setting_of_zero_the_enemy_never_flashes_and_shows_an_outline() -> void:
	var t: FeedbackTuning = load(FeedbackTuning.PATH) as FeedbackTuning
	var view: EnemyView = auto_free(EnemyView.new())
	view.flash_scale = 0.0
	for since: int in range(5):
		assert_that(view.body_colour(_shown(since), EnemyView.BODY)).is_equal(EnemyView.BODY)
		assert_bool(view.shows_hit_outline(_shown(since))).is_equal(since < t.enemy_flash_frames)
	assert_bool(EnemyView.HIT_OUTLINE != EnemyView.WHITE_CUE).is_true()
	assert_bool(EnemyView.HIT_OUTLINE != EnemyView.RED_CUE).is_true()


func test_the_enemy_view_starts_at_the_default_flash_setting() -> void:
	var view: EnemyView = auto_free(EnemyView.new())
	var t: FeedbackTuning = load(FeedbackTuning.PATH) as FeedbackTuning
	assert_float(view.flash_scale).is_equal(t.flash_default_scale)
	assert_int(view.tuning.enemy_flash_frames).is_equal(2)


func _is_axis_aligned(pts: PackedVector2Array) -> bool:
	for i: int in range(pts.size() - 1):
		if pts[i].x != pts[i + 1].x and pts[i].y != pts[i + 1].y:
			return false
	return true


func test_unparryable_and_parryable_telegraphs_differ_in_shape_not_only_colour() -> void:
	# Task 6 review, presentation M5; BUILD.md section 12: "differ in shape and sound as well as
	# color ... a jagged outline".
	var box := Rect2(100, 200, 32, 64)
	for progress: float in [0.0, 0.5, 1.0]:
		var white_bar: PackedVector2Array = EnemyView.cue_bar(box, progress, true)
		var red_bar: PackedVector2Array = EnemyView.cue_bar(box, progress, false)
		assert_bool(white_bar == red_bar).is_false()
		assert_int(red_bar.size()).is_greater(white_bar.size())
		assert_bool(_is_axis_aligned(white_bar)).is_true()
		assert_bool(_is_axis_aligned(red_bar)).is_false()
	var white_line: PackedVector2Array = EnemyView.cue_outline(box, true)
	var red_line: PackedVector2Array = EnemyView.cue_outline(box, false)
	assert_bool(white_line == red_line).is_false()
	assert_int(white_line.size()).is_equal(5)
	assert_int(red_line.size()).is_greater(white_line.size() * 3)
	assert_bool(_is_axis_aligned(white_line)).is_true()
	assert_bool(_is_axis_aligned(red_line)).is_false()
	# The jagged outline is closed and pushes out of the box, not into it.
	assert_vector(red_line[0]).is_equal(red_line[red_line.size() - 1])
	var reach: Rect2 = box.grow(EnemyView.JAG_DEPTH_PX + 0.001)
	for p: Vector2 in red_line:
		assert_bool(reach.has_point(p)).is_true()
	# Nothing of the cue rises above the extent the F3 label is drawn clear of.
	for p: Vector2 in EnemyView.cue_bar(box, 1.0, false):
		assert_float(p.y).is_greater_equal(box.position.y - EnemyView.cue_extent_px())


func _sim_dummy(room_id: String) -> Simulation:
	var sc: Scenario = Scenario.make(1)
	sc.room = room_id
	return Simulation.new(sc)


func test_the_cue_and_the_swing_keep_their_look_through_the_landing_frame() -> void:
	# Task 6 review, presentation M5: on the landing tick, the last frame of the parry window,
	# the state is STRIKE and the cue used to be gone.
	for red: bool in [false, true]:
		var sim: Simulation = _sim_dummy("test/dummy_red" if red else "test/dummy_swing")
		var e: Enemy = sim.combat.enemies[0]
		var view: EnemyView = auto_free(EnemyView.new())
		var last_cue: int = -1
		var landing: int = -1
		for _i: int in range(90):
			sim.step(InputFrame.new())
			view.capture(sim)
			var s: EnemyView.Shown = view.shown[0]
			if s.telegraph >= 0.0:
				last_cue = sim.tick - 1
				assert_bool(s.parryable).is_equal(not red)
			if landing < 0 and e.attack_box().size != Vector2i.ZERO:
				landing = sim.tick - 1
				assert_int(e.state).is_equal(Enemy.STRIKE)
				assert_float(s.telegraph).is_equal(1.0)
				assert_vector(s.attack.size).is_not_equal(Vector2.ZERO)
		assert_int(landing).is_greater(0)
		# The cue shows up to and including the landing frame, then goes.
		assert_int(last_cue).is_equal(landing)
		# The live swing keeps the parryability on every active frame.
		var sim2: Simulation = _sim_dummy("test/dummy_red" if red else "test/dummy_swing")
		var view2: EnemyView = auto_free(EnemyView.new())
		var active: int = 0
		var swing_frames: int = 0
		for _i: int in range(90):
			sim2.step(InputFrame.new())
			view2.capture(sim2)
			var swing: EnemyAttack = sim2.combat.enemies[0].attack
			swing_frames = swing.active if swing != null else swing_frames
			if view2.shown[0].attack.size != Vector2.ZERO:
				active += 1
				assert_bool(view2.shown[0].parryable).is_equal(not red)
		assert_int(active).is_equal(swing_frames)
