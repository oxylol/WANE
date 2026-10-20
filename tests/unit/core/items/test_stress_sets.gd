extends GdUnitTestSuite
## The two stress Votive sets (tests/votives/, docs/adr/0020 Decision 15): the gated set raises the
## spec's burst of 39 procs from a Taper hit or a pogo, once per cooldown however many dummies a
## swing lands on, and none from a spell tick; the storm set fires a sure chain on every event.

const GATED: Dictionary[String, int] = {
	"votive_test_stress_taper_a": 1,
	"votive_test_stress_taper_b": 1,
	"votive_test_stress_taper_c": 1,
}
const STORM: Dictionary[String, int] = {
	"votive_test_stress_arc_a": 1,
	"votive_test_stress_arc_b": 1,
	"votive_test_stress_arc_c": 1,
}
const EMBER: int = Kindling.EMBER


func test_a_taper_hit_fires_thirty_nine_procs_in_both_sets() -> void:
	for set_options: Dictionary[String, int] in [GATED, STORM]:
		var sim: Simulation = _sim(set_options)
		_raise(sim, ProcSource.TAPER, [0])
		assert_int(sim.procs.fired()).is_equal(39)
		assert_int(sim.procs.raised).is_equal(40)


func test_a_swing_on_two_dummies_starts_one_chain_in_the_gated_set_and_two_in_the_storm() -> void:
	var gated: Simulation = _sim(GATED)
	_raise(gated, ProcSource.TAPER, [0, 1])
	# 39 procs of the one chain, and the second root's three Votives roll and stand down.
	assert_int(gated.procs.fired()).is_equal(42)
	var storm: Simulation = _sim(STORM)
	_raise(storm, ProcSource.TAPER, [0, 1])
	assert_int(storm.procs.fired()).is_equal(78)


func test_the_cooldown_is_three_ticks() -> void:
	var sim: Simulation = _sim(GATED)
	var fired: Array[int] = []
	for tick: int in range(8):
		sim.procs.begin_tick(tick)
		var targets: Array[int] = []
		if tick == 0 or tick == 1 or tick == 3:
			targets.append(0)
		_resolve(sim, ProcSource.TAPER, targets)
		fired.append(sim.procs.fired())
	# Ticks 0 and 3 start a chain; tick 1 is inside the window (three inert rolls: 3 procs).
	assert_array(fired).is_equal([39, 3, 0, 39, 0, 0, 0, 0])


func test_a_pogo_starts_a_chain_and_a_spell_tick_does_not() -> void:
	var pogo: Simulation = _sim(GATED)
	_raise(pogo, ProcSource.POGO, [0], 1000)
	assert_int(pogo.procs.fired()).is_equal(39)
	for source: int in [ProcSource.KINDLE, ProcSource.RADIANCE]:
		var sim: Simulation = _sim(GATED)
		# A sure roll (the event's coefficient is 1000 here): three procs, none of which hits.
		_raise(sim, source, [0], 1000)
		assert_int(sim.procs.fired()).is_equal(3)
		assert_int(sim.procs.deepest()).is_equal(1)
		assert_int(sim.combat.enemies[0].hp).is_equal(200)


func _sim(options: Dictionary[String, int]) -> Simulation:
	var sc: Scenario = Scenario.make(1, "test/dummy_pair")
	sc.options = options
	return Simulation.new(sc)


func _raise(sim: Simulation, source: int, targets: Array[int], coefficient: int = -1) -> void:
	sim.procs.begin_tick(0)
	_resolve(sim, source, targets, coefficient)


func _resolve(sim: Simulation, source: int, targets: Array[int], coefficient: int = -1) -> void:
	for t: int in targets:
		var c: Vector2i = sim.combat.enemies[t].centre()
		sim.procs.raise(source, t, c.x, c.y, 10, EMBER, 0, coefficient)
	sim.procs.resolve(sim.combat, sim.player)
