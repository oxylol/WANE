extends GdUnitTestSuite
## Every field of combat's state reaches the state hash (CLAUDE.md rule 4: a desync is a P0 bug;
## docs/adr/0013): the player's vitals, every enemy, the kill embers, the fire trails and the
## combat's own fields. Each field is changed in turn, and the hash must change with it.

## Fields that are not state: compiled tuning, the shared world and event list, the body (hashed
## through its position fields), the lists audited item by item, and the training dummy's room
## marker settings and the gravity compiled from its content, which never change in a run and are
## content (the room and the enemy's numbers are in the content fingerprint), and a solid
## dummy's blocker, a box in the world's solids (which the simulation hashes) that follows the body.
## The proc bus is hashed on its own (tests/unit/core/items/test_proc_bus.gd); combat's query cells
## are rebuilt from the enemies every tick they are asked for.
const NOT_STATE: Array[String] = [
	"procs",
	"_cells",
	"_indexed",
	"params",
	"_params",
	"world",
	"events",
	"def",
	"body",
	"attack",
	"enemies",
	"embers",
	"trails",
	"period",
	"attacks_on",
	"red",
	"respawn_frames",
	"blocker",
	"_gravity",
	"_terminal",
]


func _sim(room_id: String) -> Simulation:
	var sc: Scenario = Scenario.make(1)
	sc.room = room_id
	return Simulation.new(sc)


func _changes(old: Variant) -> Array[Variant]:
	match typeof(old):
		TYPE_INT:
			var i: int = old
			return [i + 7]
		TYPE_BOOL:
			var b: bool = old
			return [not b]
		TYPE_VECTOR2I:
			var v: Vector2i = old
			return [v + Vector2i(7, 0), v + Vector2i(0, 7)]
		TYPE_PACKED_INT32_ARRAY:
			var arr: PackedInt32Array = old
			var longer: PackedInt32Array = arr.duplicate()
			longer.append(7)
			return [longer]
		TYPE_RECT2I:
			var r: Rect2i = old
			return [
				Rect2i(r.position + Vector2i(7, 0), r.size),
				Rect2i(r.position + Vector2i(0, 7), r.size),
				Rect2i(r.position, r.size + Vector2i(7, 0)),
				Rect2i(r.position, r.size + Vector2i(0, 7)),
			]
	return []


## Fails unless changing each script field of [param obj] changes [param hash_of]'s value.
func _audit(obj: Object, hash_of: Callable, label: String) -> int:
	var checked: int = 0
	var props := obj.get_property_list()
	for i: int in range(props.size()):
		var usage: int = props[i]["usage"]
		var field: String = props[i]["name"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or NOT_STATE.has(field):
			continue
		var old: Variant = obj.get(field)
		var changes: Array[Variant] = _changes(old)
		if changes.is_empty():
			fail("%s.%s has a type the hash audit does not know" % [label, field])
			return checked
		for changed: Variant in changes:
			var was: int = hash_of.call()
			obj.set(field, changed)
			var now: int = hash_of.call()
			obj.set(field, old)
			if now == was:
				fail("%s.%s is not part of the state hash" % [label, field])
				return checked
		checked += 1
	return checked


func test_the_vitals_are_in_the_player_hash() -> void:
	var sim: Simulation = _sim("test/dummy")
	var v: Vitals = sim.player.vitals
	var h: Callable = func() -> int: return sim.state_hash()
	assert_int(_audit(v.hearts, h, "Hearts")).is_equal(2)
	assert_int(_audit(v.flame, h, "Flame")).is_equal(2)
	assert_int(_audit(v.kindling, h, "Kindling")).is_equal(1)


func test_every_enemy_field_is_in_the_hash() -> void:
	var sim: Simulation = _sim("test/dummy_swing")
	var e: Enemy = sim.combat.enemies[0]
	# Put an attack under way, so the attack's index is hashed as something other than none.
	e.start_attack(e.def.find_attack("swing"))
	var h: Callable = func() -> int: return sim.state_hash()
	assert_int(_audit(e, h, "TrainingDummy")).is_greater_equal(22)
	for field: String in ["x", "y", "vx", "vy"]:
		var old: int = e.body.get(field)
		var was: int = sim.state_hash()
		e.body.set(field, old + 7)
		var now: int = sim.state_hash()
		e.body.set(field, old)
		if field == "vx":
			# An enemy's own horizontal speed is its knockback (knock_vx); the body's vx is unused.
			continue
		assert_int(now).override_failure_message("enemy body.%s" % field).is_not_equal(was)


func test_combat_effects_are_in_the_hash() -> void:
	var sim: Simulation = _sim("test/dummy")
	var c: Combat = sim.combat
	c.embers.append(KillEmber.new(Vector2i(100, 200), 16))
	c.trails.append(FireTrail.new(Rect2i(1, 2, 3, 4), 10, 5))
	var h: Callable = func() -> int: return sim.state_hash()
	assert_int(_audit(c, h, "Combat")).is_equal(1)
	assert_int(_audit(c.embers[0], h, "KillEmber")).is_equal(4)
	assert_int(_audit(c.trails[0], h, "FireTrail")).is_equal(3)
