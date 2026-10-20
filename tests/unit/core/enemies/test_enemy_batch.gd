extends GdUnitTestSuite
## The batched enemies (docs/adr/0020 Decision 15, [EnemyBatch]) against the reference loop:
## `CollisionWorld.patrol_walk` and `patrol_many` natively against their GDScript references on
## random worlds, and whole simulations with the batch on and off, the state hashed after every
## tick. A desync is a P0 (CLAUDE.md rule 4).

const U: int = Fx.SUB
const SEED: int = 20261022
const STRESS: String = "res://tests/perf/stress_run.fixture"
const MIX: String = "res://tests/replay/combat/batch_mix_runs.fixture"
## Ticks of the stress run played with the batch on and off (it holds 200 enemies, striking and
## pogoing from the first tick on).
const STRESS_TICKS: int = 700

var _saved_mode: NativeBackend.Mode = NativeBackend.Mode.AUTO


func before_test() -> void:
	_saved_mode = NativeBackend.mode()


func after_test() -> void:
	NativeBackend.configure(_saved_mode)
	EnemyBatch.enabled = true


# --- the native calls against the reference ----------------------------------------------------


func test_patrol_walk_and_patrol_many_give_the_references_answer() -> void:
	if not NativeBackend.available():
		assert_int(NativeBackend.mode()).is_not_equal(NativeBackend.Mode.ON)
		return
	var rng: Rng = Rng.seeded(SEED, 1)
	var met: Dictionary[String, int] = {}
	for room: int in range(60):
		var grid: TileGrid = null
		match room % 3:
			0:
				grid = RandomWorlds.flat_grid(rng)
			1:
				grid = RandomWorlds.ramp_grid(rng)
			_:
				grid = RandomWorlds.soup_grid(rng)
		_play_room(grid, rng, met, "room %d" % room)
	# The play met what the batch is for: turns at ledges, at walls, falls, landings.
	for key: String in ["ledge", "wall", "fell", "landed", "stood", "walked"]:
		assert_int(met.get(key, 0)).is_greater(0)


func _play_room(grid: TileGrid, rng: Rng, met: Dictionary[String, int], label: String) -> void:
	var specs: Array[Rect2i] = RandomWorlds.box_specs(rng, rng.below(3))
	var worlds: Array[CollisionWorld] = []
	# 0: the reference, 1: the native call on its own, 2: the native batch.
	for style: int in range(3):
		var w := CollisionWorld.new(grid.copy())
		w.native = NativeWorld.create(true) if style > 0 else null
		for s: Rect2i in specs:
			w.solids.append(SolidBox.make(s.position.x, s.position.y, s.end.x, s.end.y))
		worlds.append(w)
	var count: int = 12
	var bodies: Array[Array] = []
	var dirs: Array[Array] = []
	for _style: int in range(3):
		var body_list: Array[Body] = []
		bodies.append(body_list)
		var dir_list: Array[int] = []
		dirs.append(dir_list)
	var kinds: PackedInt64Array = PackedInt64Array()
	var steps: PackedInt64Array = PackedInt64Array()
	var drops: PackedInt64Array = PackedInt64Array()
	for k: int in range(count):
		var start: Body = _start(worlds[0], rng)
		var dir: int = 1 if rng.below(2) == 0 else -1
		kinds.append(rng.below(4))
		steps.append(
			rng.between(1, 4) * U + rng.below(U) if rng.below(4) > 0 else rng.between(5, 40) * U
		)
		drops.append(rng.between(4, 40) * U)
		for style: int in range(3):
			var b := Body.make(start.x, start.y, start.half_w, start.height)
			worlds[style].refresh_ground(b)
			bodies[style].append(b)
			dirs[style].append(dir)
	for tick: int in range(120):
		# Kinds: 0 a stander (refreshes), 1 and 3 a walker that turns, 2 one that walks off ledges.
		for style: int in range(3):
			var body_list: Array[Body] = bodies[style]
			var dir_list: Array[int] = dirs[style]
			_tick(worlds[style], body_list, dir_list, kinds, steps, drops, style == 2, met)
		for k: int in range(count):
			var ref_body: Body = bodies[0][k]
			var ref_dir: int = dirs[0][k]
			var single_body: Body = bodies[1][k]
			var single_dir: int = dirs[1][k]
			var many_body: Body = bodies[2][k]
			var many_dir: int = dirs[2][k]
			var diff: String = _differ(ref_body, single_body, ref_dir, single_dir)
			if diff == "":
				diff = _differ(ref_body, many_body, ref_dir, many_dir)
				if diff != "":
					diff = "batch: " + diff
			if diff != "":
				fail("%s tick %d body %d: %s" % [label, tick, k, diff])
				return


func _tick(
	w: CollisionWorld,
	bodies: Array[Body],
	dirs: Array[int],
	kinds: PackedInt64Array,
	steps: PackedInt64Array,
	drops: PackedInt64Array,
	batched: bool,
	met: Dictionary[String, int]
) -> void:
	var ops: PackedInt64Array = PackedInt64Array()
	var queued: Array[int] = []
	for k: int in range(bodies.size()):
		var b: Body = bodies[k]
		if not b.on_ground or b.vy < 0:
			# In the air: gravity, as the enemy's own move does it.
			b.vy = mini(b.vy + Fx.accel(2400), Fx.speed(900))
			w.move_y(b, b.vy)
			if b.on_ground:
				b.vy = 0
				met["landed"] = met.get("landed", 0) + 1
			continue
		var dir: int = dirs[k]
		if not batched:
			if kinds[k] == 0:
				w.refresh_ground(b)
				met["stood"] = met.get("stood", 0) + 1
				continue
			var flags: int = w.patrol_walk(b, dir, steps[k], drops[k], kinds[k] == 2)
			_after_walk(b, dirs, k, flags, met)
			continue
		ops.append_array(
			PackedInt64Array(
				[_patrol_kind(kinds[k]), b.x, b.y, b.half_w, b.height, dir, steps[k], drops[k]]
			)
		)
		queued.append(k)
	if not batched or queued.is_empty():
		return
	var out: PackedInt64Array = w.patrol_many(ops, queued.size())
	for n: int in range(queued.size()):
		var k: int = queued[n]
		var b: Body = bodies[k]
		var at: int = CollisionWorld.PATROL_OUT * n
		b.x = out[at]
		b.y = out[at + 1]
		var contact: int = out[at + 2]
		b.on_ground = (contact & 1) != 0
		b.on_slope = (contact & 2) != 0
		b.ground_tile = (contact >> 2) - 1
		if kinds[k] == 0:
			met["stood"] = met.get("stood", 0) + 1
			continue
		b.clear_contacts()
		_after_walk(b, dirs, k, out[at + 3], met)


func _after_walk(
	b: Body, dirs: Array[int], k: int, flags: int, met: Dictionary[String, int]
) -> void:
	if (flags & CollisionWorld.PATROL_LEDGE) != 0:
		dirs[k] = -dirs[k]
		met["ledge"] = met.get("ledge", 0) + 1
	if (flags & CollisionWorld.PATROL_WALL) != 0:
		dirs[k] = -dirs[k]
		met["wall"] = met.get("wall", 0) + 1
	met["walked"] = met.get("walked", 0) + 1
	if not b.on_ground:
		met["fell"] = met.get("fell", 0) + 1


func _patrol_kind(kind: int) -> int:
	if kind == 0:
		return CollisionWorld.PATROL_REFRESH
	return CollisionWorld.PATROL_FALLS if kind == 2 else CollisionWorld.PATROL_TURNS


func _start(w: CollisionWorld, rng: Rng) -> Body:
	var half_w: int = [10 * U, 16 * U, 5 * U][rng.below(3)]
	var height: int = [44 * U, 64 * U, 28 * U][rng.below(3)]
	var best: Body = null
	for _try: int in range(60):
		var x: int = rng.between(40, w.grid.width * 32 - 40) * U + rng.below(U)
		var b := Body.make(x, rng.between(32, (w.grid.height - 1) * 32) * U, half_w, height)
		best = b
		if w.body_fits(b.x, b.y, b.half_w, b.height) or rng.below(12) == 0:
			return b
	return best


func _differ(a: Body, b: Body, dir_a: int, dir_b: int) -> String:
	for field: String in [
		"x",
		"y",
		"vy",
		"on_ground",
		"on_slope",
		"ground_tile",
		"hit_wall",
		"hit_ceiling",
		"nudge_x",
		"nudge_y"
	]:
		if a.get(field) != b.get(field):
			return "%s reference %s, native %s" % [field, str(a.get(field)), str(b.get(field))]
	if dir_a != dir_b:
		return "dir reference %d, native %d" % [dir_a, dir_b]
	return ""


# --- whole simulations -------------------------------------------------------------------------


func test_the_batched_enemies_hash_as_the_reference_loop_every_tick() -> void:
	if not NativeBackend.available():
		assert_int(NativeBackend.mode()).is_not_equal(NativeBackend.Mode.ON)
		return
	for path: String in [MIX, STRESS]:
		var fx: Fixture = Fixture.parse_file(path)
		assert_array(fx.errors).is_empty()
		var ticks: int = mini(fx.frame_total, STRESS_TICKS if path == STRESS else 900)
		NativeBackend.configure(NativeBackend.Mode.ON)
		EnemyBatch.enabled = false
		var reference := Simulation.new(fx.scenario)
		EnemyBatch.enabled = true
		var batched := Simulation.new(fx.scenario)
		for i: int in range(ticks):
			EnemyBatch.enabled = false
			reference.step(fx.input_frame(i))
			EnemyBatch.enabled = true
			batched.step(fx.input_frame(i))
			if reference.state_hash() != batched.state_hash():
				fail("%s: the batched enemies desynced at tick %d" % [path, i + 1])
				return
		assert_int(reference.enemy_batch.sent).is_equal(0)
		assert_int(batched.enemy_batch.sent).is_greater(ticks)


func test_without_the_native_sweep_the_batch_is_the_reference_loop() -> void:
	NativeBackend.configure(NativeBackend.Mode.OFF)
	var fx: Fixture = Fixture.parse_file(MIX)
	var sim := Simulation.new(fx.scenario)
	for i: int in range(120):
		sim.step(fx.input_frame(i))
	assert_object(sim.world.native).is_null()
	assert_int(sim.enemy_batch.sent).is_equal(0)
