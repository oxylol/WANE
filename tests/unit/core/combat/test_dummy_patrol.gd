extends GdUnitTestSuite
## The walking dummy (docs/adr/0020): `patrol=1` makes a training dummy walk at the speed in
## content/enemies/dummy.tres, turn at a wall and at a ledge, walk off a ledge and fall with
## `fall=1`, stand still to swing, and come back as it was. A dummy without the marker is the
## standing dummy it always was.

const DUMMY_PATH: String = "res://content/enemies/dummy.tres"
## A floor with a wall at each end and, 6 tiles from the west wall, a drop of 3 tiles to a second
## floor (the east half's floor is higher: a ledge to walk off from the east side).
const ROOM: String = """room test/inline
size 40 12
spawn 200 256
tiles
########################################
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#.....................#################
#.....................#################
#######################################
########################################
end
"""

var _world: CollisionWorld
var _events: SimEvents
var _params: CombatParams
var _def: DummyDef


func before_test() -> void:
	var room: RoomData = RoomData.parse(ROOM)
	assert_array(room.errors).is_empty()
	_world = room.build_world()
	_events = SimEvents.new()
	_params = (load(CombatTuning.PATH) as CombatTuning).compile()
	_def = load(DUMMY_PATH) as DummyDef


func _dummy(x_u: int, y_u: int, props: Dictionary[String, String]) -> TrainingDummy:
	var e := RoomData.RoomEntity.new()
	e.kind = "dummy"
	e.x_u = x_u
	e.y_u = y_u
	e.props = props
	return TrainingDummy.from_entity(e, _def, _params, _world, _events)


func _run(d: TrainingDummy, ticks: int) -> void:
	for _i: int in range(ticks):
		d.step(null)


func test_a_dummy_without_the_marker_stands() -> void:
	var d: TrainingDummy = _dummy(400, 256, {})
	_run(d, 120)
	assert_int(d.body.x).is_equal(Fx.units(400))
	assert_int(d.patrol_dir).is_equal(0)


func test_a_walking_dummy_walks_at_the_content_speed() -> void:
	var d: TrainingDummy = _dummy(700, 256, {"patrol": "1", "facing": "1"})
	var step: int = Fx.speed(_def.patrol_speed_ups)
	assert_int(step).is_greater(0)
	_run(d, 10)
	assert_int(d.body.x).is_equal(Fx.units(700) + 10 * step)
	assert_int(d.facing).is_equal(1)


func test_it_turns_at_a_wall_and_walks_back() -> void:
	var d: TrainingDummy = _dummy(1200, 256, {"patrol": "1", "facing": "1"})
	var step: int = Fx.speed(_def.patrol_speed_ups)
	var east_wall: int = Fx.units(39 * 32) - d.body.half_w
	var reached: bool = false
	for _i: int in range(600):
		d.step(null)
		reached = reached or d.body.x == east_wall
	assert_bool(reached).is_true()
	assert_int(d.patrol_dir).is_equal(-1)
	assert_bool(d.body.x < east_wall - step).is_true()


func test_it_turns_at_a_ledge_unless_told_to_fall() -> void:
	# On the high east floor, walking west toward the 3-tile drop at x 704.
	var turner: TrainingDummy = _dummy(900, 256, {"patrol": "1", "facing": "-1"})
	var faller: TrainingDummy = _dummy(900, 256, {"patrol": "1", "facing": "-1", "fall": "1"})
	var edge: int = Fx.units(22 * 32)
	_run(turner, 300)
	assert_bool(turner.body.left() >= edge).is_true()
	assert_int(turner.body.y).is_equal(Fx.units(256))
	assert_bool(turner.body.on_ground).is_true()
	_run(faller, 300)
	assert_bool(faller.body.y > Fx.units(256)).is_true()
	assert_bool(faller.body.x < edge).is_true()


func test_it_stands_for_a_swing_facing_the_player_and_walks_on_after() -> void:
	var d: TrainingDummy = _dummy(
		500, 256, {"patrol": "1", "facing": "-1", "attack": "1", "period": "5"}
	)
	var swing: EnemyAttack = _def.find_attack("swing")
	var held_at: int = -1
	var swings: int = 0
	var walked_after: bool = false
	for i: int in range(5 + swing.total() + 20):
		var x_before: int = d.body.x
		d.step(null)
		if d.state != Enemy.IDLE:
			if held_at < 0:
				held_at = d.body.x
				swings += 1
				if swings == 1:
					assert_int(i).is_equal(4)
			assert_int(d.body.x).is_equal(held_at)
		else:
			if swings > 0 and d.body.x != x_before:
				walked_after = true
			held_at = -1
	assert_int(swings).is_greater(0)
	assert_bool(walked_after).is_true()


func test_a_killed_walker_comes_back_at_rest_on_its_marker() -> void:
	var d: TrainingDummy = _dummy(900, 256, {"patrol": "1", "fall": "1", "facing": "-1"})
	_run(d, 200)
	assert_bool(d.body.x < Fx.units(900)).is_true()
	d.take_damage(d.hp)
	var ticks: int = 0
	while not d.is_alive() and ticks < 2 * _def.respawn_frames:
		d.step(null)
		ticks += 1
	assert_bool(d.is_alive()).is_true()
	assert_int(d.body.x).is_equal(Fx.units(900))
	assert_int(d.body.y).is_equal(Fx.units(256))
	assert_int(d.body.vy).is_equal(0)


func test_walking_is_state_and_two_runs_agree() -> void:
	var a: TrainingDummy = _dummy(700, 256, {"patrol": "1", "facing": "1"})
	var b: TrainingDummy = _dummy(700, 256, {"patrol": "1", "facing": "1"})
	_run(a, 90)
	_run(b, 90)
	var ha := StateHasher.new()
	var hb := StateHasher.new()
	a.hash_into(ha)
	b.hash_into(hb)
	assert_int(ha.value()).is_equal(hb.value())
	var hc := StateHasher.new()
	a.patrol_dir = -a.patrol_dir
	a.hash_into(hc)
	assert_int(hc.value()).is_not_equal(hb.value())


func test_the_numbers_are_content_and_validated() -> void:
	assert_array(Array(_def.validate())).is_empty()
	var bad: DummyDef = _def.duplicate() as DummyDef
	bad.patrol_speed_ups = 0
	assert_array(Array(bad.validate())).is_not_empty()
	bad = _def.duplicate() as DummyDef
	bad.patrol_drop_u = 0
	assert_array(Array(bad.validate())).is_not_empty()
