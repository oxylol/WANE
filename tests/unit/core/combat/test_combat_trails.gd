extends GdUnitTestSuite
## The Blaze trails in a crowd (core/combat/combat.gd _trails; docs/adr/0020): from
## [constant Combat.CELL_QUERY_MIN] enemies the trails ask the query cells which enemies could be in
## the fire, and burn exactly the enemies, in exactly the order, that testing every enemy against
## every trail burns (hits, kills, embers and all).


func _crowd(rng: Rng, count: int) -> Simulation:
	var sim := Simulation.new(Scenario.make(1, "test/dummy"))
	var first: Enemy = sim.combat.enemies[0]
	sim.combat.enemies.clear()
	for i: int in range(count):
		var x: int = Fx.units(rng.between(100, 600))
		var y: int = Fx.units(rng.between(200, 400))
		var e := Enemy.new(first.def, sim.combat_params, sim.world, sim.events, x, y)
		if rng.below(6) == 0:
			e.take_damage(e.hp)
		elif rng.below(5) == 0:
			e.hp = 3
		sim.combat.enemies.append(e)
	return sim


func _trail_boxes(rng: Rng, count: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for _i: int in range(count):
		out.append(
			Rect2i(
				Fx.units(rng.between(80, 600)),
				Fx.units(rng.between(150, 400)),
				Fx.units(rng.between(20, 160)),
				Fx.units(rng.between(20, 120))
			)
		)
	return out


func _events(sim: Simulation) -> String:
	var out: PackedStringArray = []
	for i: int in range(sim.events.count()):
		out.append(
			(
				"%s@%d,%d=%d"
				% [sim.events.kinds[i], sim.events.xs[i], sim.events.ys[i], sim.events.values[i]]
			)
		)
	return ",".join(out)


func test_trails_in_a_crowd_burn_what_testing_every_enemy_burns() -> void:
	assert_int(Combat.CELL_QUERY_MIN).is_greater(0)
	var rng: Rng = Rng.seeded(12, 3)
	var burned: int = 0
	for _trial: int in range(40):
		var count: int = rng.between(Combat.CELL_QUERY_MIN, 150)
		var seed_state: PackedInt64Array = rng.get_state()
		var cells_sim: Simulation = _crowd(rng, count)
		rng.set_state(seed_state)
		var naive_sim: Simulation = _crowd(rng, count)
		var boxes: Array[Rect2i] = _trail_boxes(rng, rng.between(1, 6))
		for sim: Simulation in [cells_sim, naive_sim]:
			sim.events.clear()
			for k: int in range(boxes.size()):
				sim.combat.trails.append(FireTrail.new(boxes[k], 10, 1 + k % 3))
		cells_sim.combat._trails(cells_sim.player)
		for t: FireTrail in naive_sim.combat.trails:
			for i: int in range(naive_sim.combat.enemies.size()):
				naive_sim.combat._burn(naive_sim.player, t, i)
		assert_str(_events(cells_sim)).is_equal(_events(naive_sim))
		burned += cells_sim.events.count()
		for i: int in range(count):
			assert_int(cells_sim.combat.enemies[i].hp).is_equal(naive_sim.combat.enemies[i].hp)
			assert_array(Array(cells_sim.combat.enemies[i].trail_burned)).is_equal(
				Array(naive_sim.combat.enemies[i].trail_burned)
			)
	assert_int(burned).is_greater(50)
