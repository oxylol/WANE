extends GdUnitTestSuite
## The player's state hash covers every field that can influence a future tick (CLAUDE.md rule 4:
## a desync is a P0 bug), and the tuning added for the task-3 review compiles and validates
## (docs/adr/0010).

## Fields that are not state: the compiled tuning and the strikes looked up in it, the shared
## world and event list, and the components hashed on their own (the body, the ember toss and the
## vitals: the vitals' own audit is tests/unit/core/combat/test_combat_hash.gd; the run's Votives,
## tests/unit/core/items/test_proc_bus.gd).
const NOT_STATE: Array[String] = [
	"procs",
	"p",
	"kit",
	"combat",
	"attacks",
	"charged_attack",
	"down_attack",
	"world",
	"events",
	"body",
	"toss",
	"vitals",
]
const MOVEMENT_PATH: String = "res://content/wicks/ash/movement.tres"


func _player() -> Player:
	var sc: Scenario = Scenario.make(1)
	sc.room = "test/flat"
	return Simulation.new(sc).player


func _hash(pl: Player) -> int:
	var h := StateHasher.new()
	pl.hash_into(h)
	return h.value()


## Values to try in place of [param old], one per part of it that must reach the hash (both
## components of a vector); empty for a type the audit does not know.
func _changes(old: Variant) -> Array[Variant]:
	match typeof(old):
		TYPE_INT:
			var i: int = old
			return [i + 7]
		TYPE_BOOL:
			var b: bool = old
			return [not b]
		TYPE_STRING:
			var s: String = old
			return [s + "x"]
		TYPE_VECTOR2I:
			var v: Vector2i = old
			return [v + Vector2i(7, 0), v + Vector2i(0, 7)]
	return []


func test_every_player_field_is_in_the_state_hash() -> void:
	var pl: Player = _player()
	var checked: int = 0
	var props := pl.get_property_list()
	for i: int in range(props.size()):
		var usage: int = props[i]["usage"]
		var field: String = props[i]["name"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or NOT_STATE.has(field):
			continue
		var old: Variant = pl.get(field)
		var changes: Array[Variant] = _changes(old)
		if changes.is_empty():
			fail("field '%s' has a type the hash audit does not know" % field)
			return
		for changed: Variant in changes:
			var hash_was: int = _hash(pl)
			pl.set(field, changed)
			var hash_now: int = _hash(pl)
			pl.set(field, old)
			if hash_now == hash_was:
				fail("Player.%s is not part of the state hash" % field)
				return
		checked += 1
	assert_int(checked).is_greater(30)


func test_ember_toss_fields_are_in_the_state_hash() -> void:
	var toss: EmberToss = _player().toss
	var props := toss.get_property_list()
	for i: int in range(props.size()):
		var usage: int = props[i]["usage"]
		var field: String = props[i]["name"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var old: Variant = toss.get(field)
		var changes: Array[Variant] = _changes(old)
		assert_bool(changes.is_empty()).is_false()
		for changed: Variant in changes:
			var h1 := StateHasher.new()
			toss.hash_into(h1)
			toss.set(field, changed)
			var h2 := StateHasher.new()
			toss.hash_into(h2)
			toss.set(field, old)
			if h2.value() == h1.value():
				fail("EmberToss.%s is not part of the state hash" % field)
				return


func test_teleport_offsets_are_nearest_first_with_straight_lines_first() -> void:
	var offsets: PackedInt32Array = KitTuning.fit_offsets(24)
	assert_int(offsets.size()).is_equal(49 * 49 * 2)
	assert_int(offsets[0]).is_equal(0)
	assert_int(offsets[1]).is_equal(0)
	# The first ring: up, then left, right, down (up before down, left before right).
	assert_int(offsets[3]).is_equal(-Fx.SUB)
	assert_int(offsets[4]).is_equal(-Fx.SUB)
	assert_int(offsets[6]).is_equal(Fx.SUB)
	assert_int(offsets[9]).is_equal(Fx.SUB)
	# Every straight-line offset comes before every diagonal one, each group nearest first.
	var diagonal_seen: bool = false
	var last: int = 0
	for i: int in range(0, offsets.size(), 2):
		var x: int = offsets[i] / Fx.SUB
		var y: int = offsets[i + 1] / Fx.SUB
		var on_axis: bool = x == 0 or y == 0
		if not on_axis and not diagonal_seen:
			diagonal_seen = true
			last = 0
		assert_bool(on_axis and diagonal_seen).is_false()
		var d: int = x * x + y * y
		assert_int(d).is_greater_equal(last)
		last = d


func test_new_tuning_validates() -> void:
	var m: MovementTuning = load(MOVEMENT_PATH) as MovementTuning
	assert_array(m.validate()).is_empty()
	assert_int(m.pogo_chain_frame).is_equal(6)
	var bad: MovementTuning = m.duplicate() as MovementTuning
	bad.dash_buffer_frames = InputRing.HISTORY + 1
	assert_array(bad.validate()).is_not_empty()
	bad = m.duplicate() as MovementTuning
	bad.wall_coyote_frames = -1
	assert_array(bad.validate()).is_not_empty()
	var k: KitTuning = load("res://content/wicks/ash/kit.tres") as KitTuning
	assert_array(k.validate()).is_empty()
	var bad_k: KitTuning = k.duplicate() as KitTuning
	bad_k.toss_buffer_frames = 0
	assert_array(bad_k.validate()).is_not_empty()


func test_the_apex_hang_starts_half_a_gravity_step_before_its_band() -> void:
	var p: MovementParams = (load(MOVEMENT_PATH) as MovementTuning).compile()
	# The frame that centres the apex in the four-frame hang (docs/adr/0010).
	assert_int(p.apex_hang_start).is_equal(p.apex_hang_speed + p.gravity_rise / 2)
