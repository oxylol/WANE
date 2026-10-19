extends GdUnitTestSuite
## The training dummy and the reactions every enemy shares (BUILD.md section 6, "Enemy-side
## rules"; Phase 1 task 6: "a grey-box training dummy with poise").

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

var _world: CollisionWorld
var _events: SimEvents
var _params: CombatParams
var _def: EnemyDef


func before_test() -> void:
	var room: RoomData = RoomData.parse(ROOM)
	assert_array(room.errors).is_empty()
	_world = room.build_world()
	_events = SimEvents.new()
	_params = (load(CombatTuning.PATH) as CombatTuning).compile()
	_def = load("res://content/enemies/dummy.tres") as EnemyDef


func _dummy(props: Dictionary[String, String] = {}) -> TrainingDummy:
	var e := RoomData.RoomEntity.new()
	e.kind = "dummy"
	e.x_u = 480
	e.y_u = 256
	e.props = props
	return TrainingDummy.from_entity(e, _def, _params, _world, _events)


func test_it_stands_on_the_floor_and_holds_still() -> void:
	var d: TrainingDummy = _dummy()
	for _i: int in range(120):
		d.step(null)
	assert_int(d.body.y).is_equal(Fx.units(256))
	assert_int(d.body.x).is_equal(Fx.units(480))
	assert_int(d.state).is_equal(Enemy.IDLE)


func test_poise_breaks_after_three_ten_damage_hits_and_resets() -> void:
	var d: TrainingDummy = _dummy()
	assert_bool(d.take_hit(10, 0, 0)).is_false()
	assert_bool(d.take_hit(10, 0, 0)).is_false()
	assert_int(d.state).is_equal(Enemy.IDLE)
	d.take_hit(10, 0, 0)
	assert_int(d.state).is_equal(Enemy.STAGGER)
	assert_int(d.poise).is_equal(30)
	for _i: int in range(30):
		d.step(null)
	assert_int(d.state).is_equal(Enemy.IDLE)


func test_knockback_pushes_it_and_bleeds_off() -> void:
	var d: TrainingDummy = _dummy()
	d.take_hit(10, Fx.speed(120), 0)
	var x0: int = d.body.x
	for _i: int in range(60):
		d.step(null)
	assert_int(d.body.x).is_greater(x0)
	assert_int(d.knock_vx).is_equal(0)


func test_hitstop_holds_it_still() -> void:
	var d: TrainingDummy = _dummy()
	d.take_hit(10, Fx.speed(120), 0)
	d.freeze = 2
	var x0: int = d.body.x
	d.step(null)
	d.step(null)
	assert_int(d.body.x).is_equal(x0)
	d.step(null)
	assert_int(d.body.x).is_greater(x0)


func test_a_kill_comes_back_after_the_respawn_time() -> void:
	var d: TrainingDummy = _dummy()
	assert_bool(d.take_hit(500, 0, 0)).is_true()
	assert_bool(d.is_alive()).is_false()
	assert_object(d.hurtbox()).is_equal(Rect2i())
	for _i: int in range(d.respawn_frames):
		d.step(null)
	assert_bool(d.is_alive()).is_true()
	assert_int(d.hp).is_equal(_def.hp)


func test_with_attacks_on_it_telegraphs_for_at_least_twenty_ticks_then_swings() -> void:
	var d: TrainingDummy = _dummy({"attack": "1", "period": "10"})
	var telegraph_at: int = -1
	var lands_at: int = -1
	for t: int in range(80):
		_events.clear()
		d.step(null)
		if telegraph_at < 0 and _events.has(SimEvents.TELEGRAPH):
			telegraph_at = t
		if lands_at < 0 and d.lands_now():
			lands_at = t
	assert_int(telegraph_at).is_equal(9)
	assert_int(lands_at - telegraph_at).is_equal(24)


func test_the_swing_box_is_live_on_its_four_active_frames_in_front() -> void:
	var d: TrainingDummy = _dummy({"attack": "1", "period": "1"})
	d.facing = 1
	var live: Array[int] = []
	for t: int in range(60):
		d.step(null)
		var box: Rect2i = d.attack_box()
		if box.size != Vector2i.ZERO:
			live.append(t)
			assert_int(box.position.x).is_equal(d.body.x)
			assert_int(box.size.x).is_equal(Fx.units(64))
	assert_int(live.size()).is_equal(4)


func test_a_parry_staggers_and_knocks_it_back() -> void:
	var d: TrainingDummy = _dummy({"attack": "1", "period": "1"})
	for _i: int in range(25):
		d.step(null)
	assert_int(d.state).is_equal(Enemy.STRIKE)
	d.parried(1)
	assert_int(d.state).is_equal(Enemy.STAGGER)
	assert_object(d.attack_box()).is_equal(Rect2i())
	var x0: int = d.body.x
	for _i: int in range(39):
		d.step(null)
	assert_int(d.state).is_equal(Enemy.STAGGER)
	assert_int(d.body.x).is_greater(x0)
	d.step(null)
	assert_int(d.state).is_equal(Enemy.IDLE)


func test_a_red_dummy_swings_the_unparryable_attack() -> void:
	var d: TrainingDummy = _dummy({"attack": "1", "period": "1", "red": "1"})
	d.step(null)
	assert_bool(d.attack.parryable).is_false()


func test_its_state_is_in_the_hash() -> void:
	var a: TrainingDummy = _dummy()
	var b: TrainingDummy = _dummy()
	var ha := StateHasher.new()
	var hb := StateHasher.new()
	a.hash_into(ha)
	b.hash_into(hb)
	assert_int(ha.value()).is_equal(hb.value())
	b.take_hit(1, 0, 0)
	hb = StateHasher.new()
	b.hash_into(hb)
	assert_int(ha.value()).is_not_equal(hb.value())


func test_a_solid_dummy_stops_a_body_that_runs_into_it() -> void:
	var d: TrainingDummy = _dummy({"solid": "1"})
	var b: Body = Body.make(Fx.units(300), Fx.units(256), Fx.units(10), Fx.units(48))
	_world.refresh_ground(b)
	_world.move_x(b, Fx.units(400))
	assert_int(b.right()).is_equal(d.body.left())
	assert_int(b.hit_wall).is_equal(1)


func test_a_dummy_that_is_not_solid_is_walked_through() -> void:
	var _d: TrainingDummy = _dummy()
	var b: Body = Body.make(Fx.units(300), Fx.units(256), Fx.units(10), Fx.units(48))
	_world.refresh_ground(b)
	_world.move_x(b, Fx.units(400))
	assert_int(b.x).is_equal(Fx.units(700))


func test_a_solid_dummy_is_out_of_the_way_while_dead_and_after_it_comes_back_waits_for_the_player() -> void:
	var d: TrainingDummy = _dummy({"solid": "1"})
	assert_bool(d.blocker.enabled).is_true()
	d.take_hit(500, 0, 0)
	d.step(null)
	assert_bool(d.blocker.enabled).is_false()
	var inside: Body = Body.make(d.body.x, Fx.units(256), Fx.units(10), Fx.units(48))
	for _i: int in range(d.respawn_frames):
		d.step(null)
	assert_bool(d.is_alive()).is_true()
	d.sync_blocker(inside)
	assert_bool(d.blocker.enabled).is_false()
	d.sync_blocker(null)
	assert_bool(d.blocker.enabled).is_true()


func test_a_solid_dummys_body_follows_its_knockback_and_is_not_blocked_by_itself() -> void:
	var d: TrainingDummy = _dummy({"solid": "1"})
	d.take_hit(10, Fx.speed(120), 0)
	var x0: int = d.body.x
	for _i: int in range(30):
		d.step(null)
	assert_int(d.body.x).is_greater(x0)
	assert_int(d.blocker.left).is_equal(d.body.left())
	assert_int(d.blocker.right).is_equal(d.body.right())
