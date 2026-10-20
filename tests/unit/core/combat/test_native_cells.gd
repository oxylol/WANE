extends GdUnitTestSuite
## The native query cells (docs/adr/0020 Decision 15, native/src/cells.cpp) against the GDScript
## [EnemyCells] they answer for: the same centres, and for every question the same answer, on
## random crowds (alive and dead, spread over a few cells or over the whole room, standing on the
## same spot), after kills, and with a brute force written from the questions' definitions as a
## third opinion.

const U: int = Fx.SUB
const SEED: int = 20261023
const DUMMY_PATH: String = "res://content/enemies/dummy.tres"

var _world: CollisionWorld
var _params: CombatParams
var _def: DummyDef


func before_test() -> void:
	_world = CollisionWorld.new(TileGrid.new())
	_params = (load(CombatTuning.PATH) as CombatTuning).compile()
	_def = load(DUMMY_PATH) as DummyDef


func test_native_cells_answer_as_the_reference_does() -> void:
	if not NativeBackend.available():
		assert_int(NativeBackend.mode()).is_not_equal(NativeBackend.Mode.ON)
		return
	var rng: Rng = Rng.seeded(SEED, 1)
	var asked: int = 0
	for round_n: int in range(150):
		var crowd: Array[Enemy] = _crowd(rng, round_n)
		var reference := EnemyCells.new(false)
		var native := EnemyCells.new(true)
		assert_object(native.native).is_not_null()
		reference.build(crowd)
		native.build(crowd)
		assert_array(Array(native.centres)).is_equal(Array(reference.centres))
		assert_int(native.reach_x).is_equal(reference.reach_x)
		assert_int(native.reach_y).is_equal(reference.reach_y)
		for step: int in range(30):
			if step % 6 == 5 and not crowd.is_empty():
				# A kill during the resolve: the enemy's state and the cells' kill, as Combat does.
				var k: int = rng.below(crowd.size())
				crowd[k].state = Enemy.DEAD
				reference.kill(k)
				native.kill(k)
			asked += _ask(rng, crowd, reference, native, "round %d step %d" % [round_n, step])
	assert_int(asked).is_greater(3000)


func _ask(rng: Rng, crowd: Array[Enemy], ref: EnemyCells, nat: EnemyCells, label: String) -> int:
	var at := Vector2i(rng.between(-200, 4600) * U + rng.below(U), rng.between(-100, 1200) * U)
	if not crowd.is_empty() and rng.below(3) == 0:
		at = crowd[rng.below(crowd.size())].centre() + Vector2i(rng.between(-20, 20), 0)
	var radius: int = [0, 1, 40 * U, 96 * U, 128 * U, 300 * U][rng.below(6)] + rng.below(50)
	var skip: int = rng.between(-1, crowd.size())
	var want: PackedInt32Array = _brute_within(crowd, at, radius, skip)
	var got_ref: PackedInt32Array = ref.within(crowd, at, radius, skip)
	got_ref.sort()
	var got_nat: PackedInt32Array = nat.within(crowd, at, radius, skip)
	assert_array(Array(got_ref)).override_failure_message("%s: reference within" % label).is_equal(
		Array(want)
	)
	assert_array(Array(got_nat)).override_failure_message("%s: native within" % label).is_equal(
		Array(want)
	)
	var near_want: int = _brute_nearest(crowd, at, radius, skip)
	(
		assert_int(ref.nearest(crowd, at, radius, skip))
		. override_failure_message("%s: reference nearest" % label)
		. is_equal(near_want)
	)
	(
		assert_int(nat.nearest(crowd, at, radius, skip))
		. override_failure_message("%s: native nearest" % label)
		. is_equal(near_want)
	)
	var l: int = at.x
	var t: int = at.y
	var box := Rect2i(l, t, rng.between(1, 200) * U, rng.between(1, 120) * U)
	if not crowd.is_empty() and rng.below(2) == 0:
		# A box whose grown edge falls exactly on an enemy's centre: the cells' bounds are
		# inclusive on every side.
		var c: Vector2i = crowd[rng.below(crowd.size())].centre()
		var w: int = rng.between(1, 200) * U
		var h: int = rng.between(1, 120) * U
		match rng.below(4):
			0:
				box = Rect2i(c.x + ref.reach_x, c.y - rng.below(h), w, h)
			1:
				box = Rect2i(c.x - ref.reach_x - w, c.y - rng.below(h), w, h)
			2:
				box = Rect2i(c.x - rng.below(w), c.y + ref.reach_y, w, h)
			_:
				box = Rect2i(c.x - rng.below(w), c.y - ref.reach_y - h, w, h)
	var touch_ref: PackedInt32Array = ref.touching(box)
	touch_ref.sort()
	var touch_nat: PackedInt32Array = nat.touching(box)
	assert_array(Array(touch_nat)).override_failure_message("%s: touching" % label).is_equal(
		Array(touch_ref)
	)
	# The cells find a superset of the enemies whose colliders meet the box.
	for k: int in range(crowd.size()):
		if crowd[k].body.left() < box.end.x and crowd[k].body.right() > box.position.x:
			if crowd[k].body.top() < box.end.y and crowd[k].body.y > box.position.y:
				(
					assert_bool(touch_nat.has(k))
					. override_failure_message("%s: touching missed enemy %d" % [label, k])
					. is_true()
				)
	return 3


func _crowd(rng: Rng, round_n: int) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var count: int = [0, 1, 2, 7, 40, 200][round_n % 6]
	# Some crowds huddle (many in one cell, some on one spot), some spread over the room.
	var spread: int = [30, 150, 4000][round_n % 3]
	for _k: int in range(count):
		var e := TrainingDummy.new(_def, _params, _world, SimEvents.new(), 0, 0)
		e.body.x = rng.between(0, spread) * U + rng.below(U)
		e.body.y = rng.between(0, 900) * U + rng.below(U)
		if rng.below(8) == 0 and not out.is_empty():
			e.body.x = out[0].body.x
			e.body.y = out[0].body.y
		e.body.half_w = [10, 16, 5][rng.below(3)] * U
		e.body.height = [44, 64, 28][rng.below(3)] * U
		if rng.below(5) == 0:
			e.state = Enemy.DEAD
		out.append(e)
	return out


func _brute_within(crowd: Array[Enemy], at: Vector2i, radius: int, skip: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: int in range(crowd.size()):
		var d: Vector2i = crowd[k].centre() - at
		if k != skip and crowd[k].state != Enemy.DEAD and d.x * d.x + d.y * d.y <= radius * radius:
			out.append(k)
	return out


func _brute_nearest(crowd: Array[Enemy], at: Vector2i, radius: int, skip: int) -> int:
	var best: int = -1
	var best_d: int = 0
	for k: int in _brute_within(crowd, at, radius, skip):
		var d: Vector2i = crowd[k].centre() - at
		var dd: int = d.x * d.x + d.y * d.y
		if best < 0 or dd < best_d:
			best = k
			best_d = dd
	return best
