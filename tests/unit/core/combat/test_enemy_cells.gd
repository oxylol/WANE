extends GdUnitTestSuite
## Combat's query cells (core/combat/enemy_cells.gd; docs/adr/0015) answer exactly what a scan of
## every enemy answers: the living enemies within a radius, the skipped one left out, wherever the
## enemies and the question stand (off the room's edges too), and the nearest with ties to the lower
## index.


func _sim() -> Simulation:
	return Simulation.new(Scenario.make(1, "test/dummy"))


## [param count] enemies scattered by [param rng] over a field reaching past the origin, some dead.
func _scatter(sim: Simulation, count: int, rng: Rng) -> Array[Enemy]:
	var first: Enemy = sim.combat.enemies[0]
	var out: Array[Enemy] = []
	for i: int in range(count):
		var x: int = Fx.units(rng.between(-300, 1700))
		var y: int = Fx.units(rng.between(-200, 900))
		var e := Enemy.new(first.def, sim.combat_params, sim.world, sim.events, x, y)
		if rng.below(5) == 0:
			e.take_damage(e.hp)
		out.append(e)
	return out


func _scan(enemies: Array[Enemy], at: Vector2i, radius: int, skip: int) -> Array[int]:
	var out: Array[int] = []
	for k: int in range(enemies.size()):
		var d: Vector2i = enemies[k].centre() - at
		if k != skip and enemies[k].is_alive() and d.x * d.x + d.y * d.y <= radius * radius:
			out.append(k)
	return out


func test_the_cells_answer_as_a_scan_does() -> void:
	var sim: Simulation = _sim()
	var rng: Rng = Rng.seeded(5, 0)
	for trial: int in range(20):
		var enemies: Array[Enemy] = _scatter(sim, rng.between(0, 120), rng)
		var cells := EnemyCells.new()
		cells.build(enemies)
		for _q: int in range(20):
			var at := Vector2i(Fx.units(rng.between(-500, 2000)), Fx.units(rng.between(-400, 1100)))
			var radius: int = Fx.units(rng.between(0, 400))
			var skip: int = rng.between(-1, maxi(enemies.size() - 1, -1))
			var got: Array[int] = []
			for k: int in cells.within(enemies, at, radius, skip):
				got.append(k)
			got.sort()
			assert_array(got).override_failure_message("trial %d" % trial).is_equal(
				_scan(enemies, at, radius, skip)
			)


func test_the_nearest_goes_to_the_lower_index_on_a_tie() -> void:
	var sim: Simulation = _sim()
	var first: Enemy = sim.combat.enemies[0]
	var x: int = first.body.x
	var y: int = first.body.y
	sim.combat.enemies.clear()
	for dx_u: int in [40, -40, 40, 80]:
		sim.combat.enemies.append(
			Enemy.new(first.def, sim.combat_params, sim.world, sim.events, x + Fx.units(dx_u), y)
		)
	var at := Vector2i(x, y - first.body.height / 2)
	assert_int(sim.combat.nearest_enemy(at, Fx.units(200), -1)).is_equal(0)
	assert_int(sim.combat.nearest_enemy(at, Fx.units(200), 0)).is_equal(1)
	assert_int(sim.combat.nearest_enemy(at, Fx.units(39), -1)).is_equal(-1)


func test_no_enemies_no_answer() -> void:
	var cells := EnemyCells.new()
	var none: Array[Enemy] = []
	cells.build(none)
	assert_int(cells.within(none, Vector2i.ZERO, Fx.units(100), -1).size()).is_zero()
