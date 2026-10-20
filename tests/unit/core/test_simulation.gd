extends GdUnitTestSuite
## Simulation loop (CLAUDE.md rules 1 to 4).


func test_tick_counts_steps_and_hashes_every_60() -> void:
	var sim := Simulation.new(Scenario.make(1))
	for _i: int in range(150):
		sim.step(InputFrame.new())
	assert_int(sim.tick).is_equal(150)
	assert_array(Array(sim.hash_ticks)).is_equal([60, 120])
	assert_int(sim.hash_at(60)).is_equal(sim.hash_values[0])
	assert_int(sim.hash_at(61)).is_equal(-1)


func test_identical_runs_hash_identically_and_inputs_matter() -> void:
	# Before the player exists, an input lives in the state only while it is in the input ring
	# (the current frame plus 8), so compare three frames after the press.
	var a := Simulation.new(Scenario.make(9))
	var b := Simulation.new(Scenario.make(9))
	var c := Simulation.new(Scenario.make(9))
	for i: int in range(33):
		var f := InputFrame.make(
			InputFrame.JUMP if i == 30 else 0, InputFrame.JUMP if i == 30 else 0, 0, 0
		)
		a.step(f)
		b.step(f)
		c.step(InputFrame.new())
	assert_int(a.state_hash()).is_equal(b.state_hash())
	assert_int(a.state_hash()).is_not_equal(c.state_hash())


func test_seed_changes_hash() -> void:
	var a := Simulation.new(Scenario.make(1))
	var b := Simulation.new(Scenario.make(2))
	assert_int(a.state_hash()).is_not_equal(b.state_hash())


func test_scenario_is_copied() -> void:
	var s: Scenario = Scenario.make(3)
	var sim := Simulation.new(s)
	s.seed_value = 4
	assert_int(sim.scenario.seed_value).is_equal(3)


func test_probe() -> void:
	# No player, so nothing consumes the attack press the probes read.
	var sim := Simulation.new(Scenario.make(1, "", ""))
	sim.step(InputFrame.make(InputFrame.ATTACK, InputFrame.ATTACK, -127, 64))
	sim.step(InputFrame.make(InputFrame.ATTACK, 0, -127, 64))
	assert_int(sim.probe("tick")).is_equal(2)
	assert_int(sim.probe("held.attack")).is_equal(1)
	assert_int(sim.probe("press_age.attack")).is_equal(1)
	assert_int(sim.probe("press_age.jump")).is_equal(-1)
	assert_int(sim.probe("stick_x")).is_equal(-127)
	assert_int(sim.probe("stick_y")).is_equal(64)
	assert_object(sim.probe("no_such_key")).is_null()
	assert_object(sim.probe("held.nothing")).is_null()


## What [method Simulation.probe] answered for a key before the player's keys were tried first.
func _probe_in_the_old_order(sim: Simulation, key: String) -> Variant:
	if key.begins_with("enemy"):
		return EnemyProbe.read(sim.combat, key)
	if key.begins_with("proc.") or key.begins_with("votive."):
		return sim._probe_votive(key)
	var value: Variant = sim._probe_input(key)
	if value == null and sim.player != null:
		value = PlayerProbe.read(sim.player, sim.events, key)
	return value


func test_the_players_keys_are_answered_as_they_were_when_the_prefixes_came_first() -> void:
	# The keys with no dot and "event.<name>" skip the checks for enemy, proc, votive and input keys.
	var keys: Array[String] = [
		"x",
		"y",
		"vx",
		"vy",
		"state",
		"action",
		"chain",
		"spell",
		"tier",
		"ground",
		"hearts",
		"flame",
		"air_frames",
		"dash_frame",
		"facing",
		"since_bounce",
		"nope",
		"",
		"enemy",
		"enemyx",
		"proc",
		"votive",
		"held",
		"event",
		"event.",
		"event.dash",
		"event.hazard",
		"event.nope",
		"enemy.hp",
		"enemy.state",
		"enemy9.hp",
		"enemy.nope",
		"proc.a",
		"votive.a",
		"proc.",
		"held.jump",
		"held.nothing",
		"press_age.attack",
		"press_age.",
		"x.y",
		"a.b.c",
	]
	for scenario: Scenario in [
		Scenario.make(5, "test/dummy"), Scenario.make(5, "test/dummy", ""), Scenario.make(5)
	]:
		var sim := Simulation.new(scenario)
		for i: int in range(24):
			sim.step(
				InputFrame.make(
					InputFrame.DASH if i == 8 else 0, InputFrame.DASH if i == 8 else 0, 127, 0
				)
			)
			for key: String in keys:
				(
					assert_that(sim.probe(key))
					. override_failure_message("%s, '%s' after tick %d" % [scenario.room, key, i])
					. is_equal(_probe_in_the_old_order(sim, key))
				)
