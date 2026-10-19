extends GdUnitTestSuite
## The proc event bus (docs/adr/0015): how a Votive's chance composes with the event's coefficient
## and the Flame tier's bonus (the ADR's worked table), the split past 100%, the order and number
## of PROCS draws, the chain's depth, the run's Votives and their state in the hash.

const PPM: int = StackingCurve.PPM
const CHAIN: String = "res://tests/votives/chain_spark.tres"
const TALLY: String = "res://tests/votives/tally.tres"
const EMBER: int = Kindling.EMBER
const FLAME: int = Kindling.FLAME
const WHITE: int = Kindling.WHITE
## Rows of four: stacks, coefficient per-mille, Kindling tier, chance in parts per million, for a
## 10%-a-stack Votive: BUILD.md section 6 and section 8's examples, and the Flame tier's relative
## +10% (docs/adr/0015's worked table).
const TABLE: Array[int] = [
	1,
	1000,
	EMBER,
	100000,
	1,
	500,
	EMBER,
	50000,
	1,
	800,
	EMBER,
	80000,
	1,
	300,
	EMBER,
	30000,
	1,
	200,
	EMBER,
	20000,
	1,
	1000,
	FLAME,
	110000,
	1,
	500,
	FLAME,
	55000,
	1,
	1000,
	WHITE,
	110000,
	9,
	1000,
	FLAME,
	990000,
	10,
	1000,
	EMBER,
	1000000,
	10,
	1000,
	FLAME,
	1100000,
	10,
	800,
	EMBER,
	800000,
	10,
	800,
	FLAME,
	880000,
	10,
	500,
	EMBER,
	500000,
	15,
	1000,
	EMBER,
	1500000,
	15,
	500,
	EMBER,
	750000,
	15,
	500,
	FLAME,
	825000,
	20,
	500,
	EMBER,
	1000000,
	50,
	200,
	EMBER,
	1000000,
]


func _bus() -> ProcBus:
	return ProcBus.new(ProcTuning.new(), SimEvents.new(), Rng.seeded(1, RngStreams.PROCS))


func _sim(options: Dictionary[String, int], room: String = "test/dummy") -> Simulation:
	var sc: Scenario = Scenario.make(1, room)
	sc.options = options
	return Simulation.new(sc)


## A Votive made here, with a listener from [param source] (a script extending VotiveListener).
static func votive(
	votive_id: String, kind: int, per: int, trigger: String, source: String
) -> Votive:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	var c := StackingCurve.new()
	c.kind = kind
	c.first_stack = per
	c.per_stack = per
	var v := Votive.new()
	v.id = votive_id
	v.display_name = votive_id
	v.curve = c
	v.listens_to = PackedStringArray([trigger])
	v.listener = script
	return v


func test_the_worked_table_of_chances() -> void:
	for i: int in range(0, TABLE.size(), 4):
		var bus: ProcBus = _bus()
		bus.give(load(CHAIN) as Votive, TABLE[i])
		var got: int = bus.chance_ppm(0, TABLE[i + 1], TABLE[i + 2])
		(
			assert_int(got)
			. override_failure_message("row %s gave %d" % [str(TABLE.slice(i, i + 4)), got])
			. is_equal(TABLE[i + 3])
		)


## "A 10% proc Votive on a 0.5-coefficient hit is a 5% chance."
func test_the_doc_example_is_five_percent() -> void:
	var bus: ProcBus = _bus()
	bus.give(load(CHAIN) as Votive, 1)
	var kindle: int = ProcTuning.new().kindle_permille
	assert_int(bus.chance_ppm(0, kindle, EMBER)).is_equal(PPM / 20)


func test_a_whole_chance_draws_nothing_and_a_fraction_draws_once() -> void:
	for stacks: int in [10, 20, 5, 15]:
		var sim: Simulation = _sim({"votive_test_chain_spark": stacks})
		var procs_rng: Rng = sim.rng.procs()
		var start: PackedInt64Array = procs_rng.get_state()
		var c: Vector2i = sim.combat.enemies[0].centre()
		# A Kindle tick's event at depth 2: its procs fire at level 3, and their hits raise
		# nothing, so this counts only the bus's draws for one event.
		sim.procs.raise(ProcSource.TAPER, 0, c.x, c.y, 10, EMBER, 2)
		sim.procs.resolve(sim.combat, sim.player)
		var fresh := Rng.new()
		fresh.set_state(start)
		var chance: int = stacks * 100000
		if chance % PPM != 0:
			fresh.below(PPM)
		assert_array(Array(procs_rng.get_state())).is_equal(Array(fresh.get_state()))


func test_the_split_fires_the_whole_millions_and_rolls_the_rest() -> void:
	# Seed 1's first PROCS draw is 20,548 of a million (tools/replay/proc_seeds.gd): under any
	# remainder here, so 15 stacks fire twice; 25 stacks, three times.
	var rows: Array[int] = [15, 2, 25, 3, 10, 1]
	for i: int in range(0, rows.size(), 2):
		var stacks: int = rows[i]
		var want: int = rows[i + 1]
		var sim: Simulation = _sim({"votive_test_chain_spark": stacks})
		var c: Vector2i = sim.combat.enemies[0].centre()
		sim.procs.begin_tick()
		sim.procs.raise(ProcSource.TAPER, 0, c.x, c.y, 10, EMBER, 2)
		sim.procs.resolve(sim.combat, sim.player)
		assert_int(sim.procs.fired()).is_equal(want)


func test_no_listener_queues_nothing() -> void:
	var bus: ProcBus = _bus()
	bus.raise(ProcSource.TAPER, 0, 0, 0, 10, EMBER)
	assert_int(bus.raised).is_equal(1)
	assert_int(bus._queued).is_equal(0)


func test_an_event_at_the_chain_depth_is_not_queued() -> void:
	var bus: ProcBus = _bus()
	bus.give(load(CHAIN) as Votive, 10)
	var depth: int = bus.tuning.chain_depth
	bus.raise(ProcSource.VOTIVE, 0, 0, 0, 1, EMBER, depth - 1, 1000)
	assert_int(bus._queued).is_equal(1)
	bus.raise(ProcSource.VOTIVE, 0, 0, 0, 1, EMBER, depth, 1000)
	assert_int(bus._queued).is_equal(1)
	assert_int(bus.raised).is_equal(2)


func test_a_chain_fires_three_levels_and_stops() -> void:
	var sim: Simulation = _sim({"votive_test_chain_spark": 10})
	var c: Vector2i = sim.combat.enemies[0].centre()
	sim.procs.begin_tick()
	sim.procs.raise(ProcSource.TAPER, 0, c.x, c.y, 10, EMBER)
	sim.procs.resolve(sim.combat, sim.player)
	assert_array(Array(sim.procs.fired_levels)).is_equal([1, 2, 3])
	assert_int(sim.procs.raised).is_equal(4)
	assert_int(sim.combat.enemies[0].hp).is_equal(197)
	# The queue is drained and the bus holds nothing of the tick's world.
	assert_int(sim.procs._queued).is_equal(0)
	assert_object(sim.procs._combat).is_null()
	assert_object(sim.procs._proc_api._bus).is_null()


func test_votives_fire_in_run_order() -> void:
	var sim: Simulation = _sim(
		{"votive_test_tally": 1, "votive_test_chain_spark": 10, "votive_test_coin": 1}
	)
	# Run order is the order of the option keys.
	var ids: Array[String] = []
	for v: Votive in sim.procs.votives:
		ids.append(v.id)
	assert_array(ids).is_equal(["test_chain_spark", "test_coin", "test_tally"])
	var c: Vector2i = sim.combat.enemies[0].centre()
	sim.procs.begin_tick()
	sim.procs.raise(ProcSource.TAPER, 0, c.x, c.y, 10, EMBER, 2)
	sim.procs.resolve(sim.combat, sim.player)
	assert_array(Array(sim.procs.fired_slots)).is_equal([0, 1, 2])


func test_give_adds_stacks_to_a_votive_held() -> void:
	var bus: ProcBus = _bus()
	assert_bool(bus.give(load(CHAIN) as Votive, 2)).is_true()
	assert_bool(bus.give(load(TALLY) as Votive, 1)).is_true()
	assert_bool(bus.give(load(CHAIN) as Votive, 3)).is_true()
	assert_int(bus.votives.size()).is_equal(2)
	assert_int(bus.stacks_of("test_chain_spark")).is_equal(5)
	assert_int(bus.chance_ppm(0, 1000, EMBER)).is_equal(500000)
	assert_bool(bus.give(load(CHAIN) as Votive, 0)).is_false()
	assert_bool(bus.give(null, 1)).is_false()
	assert_int(bus.stacks_of("nothing")).is_equal(0)


func test_run_votives_change_the_standing_numbers() -> void:
	var bus: ProcBus = _bus()
	var source: String = (
		"extends VotiveListener\n\n\nfunc on_run(api: RunApi) -> void:\n"
		+ "\tapi.add_run_speed_permille(api.value())\n\tapi.add_max_hearts(-api.stacks())\n"
		+ "\tapi.remove_dash_cooldown()\n"
	)
	bus.give(votive("swift", StackingCurve.LINEAR, 80, "run", source), 2)
	var mods: RunMods = bus.run_mods()
	assert_int(mods.run_speed_permille).is_equal(160)
	assert_int(mods.max_hearts_delta).is_equal(-2)
	assert_bool(mods.dash_free).is_true()
	assert_object(bus._run_api._bus).is_null()


func test_blade_votives_add_damage() -> void:
	var bus: ProcBus = _bus()
	var source: String = (
		"extends VotiveListener\n\n\nfunc on_blade_hit(api: BladeHitApi) -> void:\n"
		+ "\tif api.source() == ProcSource.POGO:\n\t\tapi.add_damage(api.value())\n"
	)
	bus.give(votive("pogo_spike", StackingCurve.LINEAR, 4, "blade_hit", source), 2)
	assert_int(bus.blade_bonus(ProcSource.POGO, 0)).is_equal(8)
	assert_int(bus.blade_bonus(ProcSource.TAPER, 0)).is_equal(0)


func test_the_state_hash_covers_the_votives() -> void:
	var sim: Simulation = _sim({"votive_test_tally": 1})
	var base: int = sim.state_hash()
	sim.procs.stacks[0] += 1
	assert_int(sim.state_hash()).is_not_equal(base)
	sim.procs.stacks[0] -= 1
	assert_int(sim.state_hash()).is_equal(base)
	sim.procs._set_counter_of(0, 2)
	assert_int(sim.state_hash()).is_not_equal(base)
	sim.procs._set_counter_of(0, 0)
	sim.procs.give(load(CHAIN) as Votive, 1)
	assert_int(sim.state_hash()).is_not_equal(base)


## Every ProcBus field is state in the hash, state derived from it, or this tick's scratch.
func test_every_bus_field_is_accounted_for() -> void:
	var hashed: Array[String] = ["votives", "stacks", "counters"]
	var not_state: Array[String] = [
		"tuning",
		"events",
		"rng",
		"raised",
		"fired_slots",
		"fired_levels",
		"_listeners",
		"_values",
		"_hit_slots",
		"_blade_slots",
		"_bounce_slots",
		"_run_slots",
		"_coefficients",
		"_queue",
		"_queued",
		"_combat",
		"_player",
		"_event",
		"_proc_api",
		"_blade_api",
		"_bounce_api",
		"_run_api",
	]
	var props: Array[Dictionary] = _bus().get_property_list()
	for i: int in range(props.size()):
		var usage: int = props[i]["usage"]
		var field: String = props[i]["name"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		(
			assert_bool(hashed.has(field) or not_state.has(field))
			. override_failure_message(
				"ProcBus.%s is neither hashed nor listed as not state" % field
			)
			. is_true()
		)


func test_a_proc_hit_needs_a_living_enemy() -> void:
	var sim: Simulation = _sim({"votive_test_chain_spark": 10})
	assert_int(sim.combat.proc_hit(sim.player, 5, 3)).is_equal(-1)
	assert_int(sim.combat.proc_hit(null, 0, 3)).is_equal(-1)
	assert_int(sim.combat.proc_hit(sim.player, 0, 3)).is_equal(3)
	sim.combat.enemies[0].take_damage(1000)
	assert_int(sim.combat.proc_hit(sim.player, 0, 3)).is_equal(-1)
	# Outside a resolve the bus acts on nothing.
	assert_bool(sim.procs._proc_hit(0, 1)).is_false()
	assert_int(sim.procs._stun_within(100, 10)).is_equal(0)
	assert_int(sim.procs._nearest_enemy(100, false)).is_equal(-1)


func test_nearest_enemy_and_stun_reach() -> void:
	var sim: Simulation = _sim({}, "test/dummy_pair")
	var near: Vector2i = sim.combat.enemies[0].centre()
	var reach: int = Fx.units(100)
	assert_int(sim.combat.nearest_enemy(near, reach, -1)).is_equal(0)
	assert_int(sim.combat.nearest_enemy(near, reach, 0)).is_equal(1)
	assert_int(sim.combat.nearest_enemy(near, Fx.units(10), 0)).is_equal(-1)
	assert_int(sim.combat.stun_within(near, Fx.units(10), 20)).is_equal(1)
	assert_int(sim.combat.enemies[0].state).is_equal(Enemy.STUN)
	assert_int(sim.combat.enemies[1].state).is_equal(Enemy.IDLE)
	assert_int(sim.combat.stun_within(near, Fx.units(100), 20)).is_equal(2)
	# A stun never shortens one running, and the dead are not stunned.
	var e: Enemy = sim.combat.enemies[0]
	e.stun(5)
	assert_int(e._stagger_left).is_equal(20)
	e.stun(40)
	assert_int(e._stagger_left).is_equal(40)
	e.take_damage(1000)
	e.stun(10)
	assert_int(e.state).is_equal(Enemy.DEAD)


func test_a_scenario_names_votives_by_option() -> void:
	var sim: Simulation = _sim({"votive_test_nothing_here": 1})
	assert_array(Array(sim.load_errors)).is_not_empty()
	sim = _sim({"votive_test_chain_spark": 0})
	assert_array(Array(sim.load_errors)).is_not_empty()
	sim = _sim({"votive_test_chain_spark": 2})
	assert_array(Array(sim.load_errors)).is_empty()
	assert_int(sim.probe("votive.test_chain_spark")).is_equal(2)
	assert_int(sim.probe("proc.test_tally")).is_equal(0)
	assert_object(sim.probe("proc.test_misspelt")).is_null()
	assert_object(sim.probe("votive.not an id")).is_null()
	# The game boots with none.
	assert_int(Simulation.new(Scenario.make(1, "test/dummy")).procs.votives.size()).is_zero()
