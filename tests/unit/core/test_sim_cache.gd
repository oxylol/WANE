extends GdUnitTestSuite
## A simulation built with a [SimCache] is the simulation built without one (docs/adr/0006,
## Shards): the same content fingerprint, the same load errors, the same state at every tick, and,
## through the fixture runner, the same result line for every kind of fixture.

const STEPS: int = 40
## One fixture in this many of the whole suite goes through the runner in the comparison below
## (the simulations of all of them are compared in the first test).
const RUNNER_EVERY: int = 9


func _suite() -> Array[String]:
	return FileWalk.find(FixtureRunner.FIXTURE_ROOT, [".fixture"])


## One scenario of each distinct shape in the suite: room, Wick, option names, spawn set or not.
func _scenarios() -> Array[Scenario]:
	var seen: Dictionary[String, bool] = {}
	var out: Array[Scenario] = []
	for path: String in _suite():
		var sc: Scenario = Fixture.parse_file(path).scenario
		var shape: String = "%s|%s|%s|%s" % [sc.room, sc.wick, sc.sorted_option_keys(), sc.spawn_x]
		if not seen.has(shape):
			seen[shape] = true
			out.append(sc)
	return out


func _drive(sim: Simulation) -> void:
	for i: int in range(STEPS):
		var pressed: int = InputFrame.JUMP if i == 6 or i == 22 else 0
		var held: int = InputFrame.JUMP if i >= 6 and i < 12 else 0
		sim.step(InputFrame.make(held, pressed, 127 if i % 16 < 12 else -127, 0))


func _assert_same(fresh: Simulation, cached: Simulation, label: String) -> void:
	assert_int(cached.content_hash).override_failure_message(label).is_equal(fresh.content_hash)
	assert_array(Array(cached.load_errors)).override_failure_message(label).is_equal(
		Array(fresh.load_errors)
	)
	assert_array(cached.rooms.order).override_failure_message(label).is_equal(fresh.rooms.order)
	assert_int(cached.state_hash()).override_failure_message(label).is_equal(fresh.state_hash())
	_drive(fresh)
	_drive(cached)
	assert_int(cached.state_hash()).override_failure_message(label).is_equal(fresh.state_hash())
	assert_array(Array(cached.hash_values)).override_failure_message(label).is_equal(
		Array(fresh.hash_values)
	)


func test_every_scenario_shape_of_the_suite_builds_the_same_with_a_cache() -> void:
	var cache := SimCache.new()
	var scenarios: Array[Scenario] = _scenarios()
	assert_int(scenarios.size()).is_greater(20)
	# Twice over one cache: the first build fills it, the second is served from it.
	for round_number: int in range(2):
		for sc: Scenario in scenarios:
			var label: String = "round %d, room '%s', wick '%s'" % [round_number, sc.room, sc.wick]
			_assert_same(Simulation.new(sc), Simulation.new(sc, cache), label)


func test_a_room_that_does_not_load_reports_the_same_errors_from_a_cache() -> void:
	var sc: Scenario = Scenario.make(3, "test/no_such_room_anywhere")
	var fresh := Simulation.new(sc)
	assert_array(Array(fresh.load_errors)).is_not_empty()
	var cache := SimCache.new()
	for _i: int in range(2):
		var cached := Simulation.new(sc, cache)
		assert_array(Array(cached.load_errors)).is_equal(Array(fresh.load_errors))
		assert_int(cached.content_hash).is_equal(fresh.content_hash)


func test_a_cache_hands_out_one_parse_of_a_room_and_one_room_set() -> void:
	var cache := SimCache.new()
	var start: String = Simulation.new(Scenario.make(1, "zone1/01_dash_slash")).room.id
	assert_str(start).is_not_empty()
	assert_object(cache.room_set(start)).is_same(cache.room_set(start))
	assert_object(cache.room(start)).is_same(cache.room(start))
	assert_object(cache.room_set(start).rooms[start]).is_same(cache.room(start))
	assert_object(cache.load_content(WorldTuning.PATH).res).is_same(
		cache.load_content(WorldTuning.PATH).res
	)


func test_a_cache_digests_only_what_it_loaded_and_digests_it_as_a_build_does() -> void:
	var cache := SimCache.new()
	var loaded: SimCache.Loaded = cache.load_content(CombatTuning.PATH)
	assert_object(loaded.res).is_not_null()
	var direct := StateHasher.new()
	ContentHash.add_resource(direct, loaded.res)
	for _i: int in range(2):
		var through := StateHasher.new()
		cache.add_resource(through, loaded.res)
		assert_int(through.value()).is_equal(direct.value())
	# A resource it did not load is digested as it stands.
	var mine := CombatTuning.new()
	var h1 := StateHasher.new()
	var h2 := StateHasher.new()
	ContentHash.add_resource(h1, mine)
	cache.add_resource(h2, mine)
	assert_int(h2.value()).is_equal(h1.value())
	var none1 := StateHasher.new()
	var none2 := StateHasher.new()
	ContentHash.add_resource(none1, null)
	cache.add_resource(none2, null)
	assert_int(none2.value()).is_equal(none1.value())


func test_the_fixture_runner_gives_the_same_result_with_a_cache() -> void:
	var paths: Array[String] = _suite()
	var cache := SimCache.new()
	var runner := FixtureRunner.new()
	var checked: int = 0
	for i: int in range(0, paths.size(), RUNNER_EVERY):
		var fresh: FixtureRunner.Result = runner.run_fixture(Fixture.parse_file(paths[i]), true)
		var cached: FixtureRunner.Result = runner.run_fixture(
			Fixture.parse_file(paths[i]), true, cache
		)
		assert_bool(cached.passed).is_equal(fresh.passed)
		assert_array(Array(cached.messages)).is_equal(Array(fresh.messages))
		assert_str(cached.hash_line).is_equal(fresh.hash_line)
		assert_int(cached.frames).is_equal(fresh.frames)
		checked += 1
	assert_int(checked).is_greater(40)
