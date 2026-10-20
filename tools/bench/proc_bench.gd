extends SceneTree
## The proc event bus's cost (docs/adr/0015; BUILD.md section 13 frame budget: input + simulation
## 3.0 ms a tick), in a room of 200 training dummies, as the stress room will drive it (section 13:
## "200 enemies, 40 procs"):
## - raising a proc event no Votive listens for (the run with no proc Votives: every Taper hit,
##   pogo, Kindle tick and Radiance reach still raises one);
## - each Votive listening: one event rolled by K Votives whose chance has a fraction (one PROCS
##   draw each) and which almost never fire, per event and per Votive;
## - a proc that fires and lands a hit, chain included: the stress set's burst (three Votives at a
##   sure chance arcing to the nearest dummy, 39 procs from one Taper hit), per burst and per proc;
## - a tick of 40 events each rolled by 40 Votives, the stress room's worst case for listening;
## - the parts of a proc's cost: a PROCS draw, combat's query cells built once a tick, one nearest
##   enemy query, one proc hit.
## The dummies never die or stagger here (their health and poise are out of reach), so every burst
## does the same work.
##
##   godot --headless --path . --script tools/bench/proc_bench.gd

const ENEMIES: int = 200
const SPACING_U: int = 40
const REPS: int = 200
const IDLE_SOURCE: String = (
	"extends VotiveListener\n\n\nfunc on_proc(_api: ProcApi) -> void:\n" + "\tpass\n"
)
const STRESS: Array[String] = [
	"res://tests/votives/stress_arc_a.tres",
	"res://tests/votives/stress_arc_b.tres",
	"res://tests/votives/stress_arc_c.tres",
]
## The ticks the reps of a bench are apart: further than any Votive's internal cooldown, so every
## rep fires what it measures.
const TICK_GAP: int = 1000


func _initialize() -> void:
	print("proc bus, %d dummies; microseconds" % ENEMIES)
	var none: float = _raise_unheard()
	print("raise, no Votive listening          %8.2f per event" % none)
	for k: int in [1, 10, 40]:
		var per_event: float = _listening(k, 40)
		print(
			(
				"40 events, %2d Votives listening      %8.2f per event, %6.2f per Votive"
				% [k, per_event, per_event / k]
			)
		)
	var burst: float = _burst()
	print(
		"stress burst (39 procs, chained)    %8.2f per burst, %6.2f per proc" % [burst, burst / 39]
	)
	_parts()
	quit(0)


func _parts() -> void:
	var sim: Simulation = _sim()
	var c: Vector2i = sim.combat.enemies[0].centre()
	var r: Rng = sim.rng.procs()
	var start: int = Time.get_ticks_usec()
	for _i: int in range(REPS * 10):
		r.below(ProcBus.PPM)
	print(
		(
			"a PROCS draw                        %8.2f"
			% (float(Time.get_ticks_usec() - start) / (REPS * 10))
		)
	)
	start = Time.get_ticks_usec()
	for _i: int in range(REPS):
		sim.combat._cells.build(sim.combat.enemies)
	print(
		"query cells, built once a tick      %8.2f" % (float(Time.get_ticks_usec() - start) / REPS)
	)
	sim.combat._indexed = true
	start = Time.get_ticks_usec()
	for _i: int in range(REPS):
		sim.combat.nearest_enemy(c, Fx.units(160), 0)
	print(
		"nearest enemy within 160 u          %8.2f" % (float(Time.get_ticks_usec() - start) / REPS)
	)
	start = Time.get_ticks_usec()
	for _i: int in range(REPS):
		sim.combat.proc_hit(sim.player, 1, 1)
		sim.events.clear()
	print(
		"a proc hit                          %8.2f" % (float(Time.get_ticks_usec() - start) / REPS)
	)


## A simulation in a room of [constant ENEMIES] dummies standing [constant SPACING_U] apart.
func _sim() -> Simulation:
	var sim := Simulation.new(Scenario.make(1, "test/dummy"))
	var first: Enemy = sim.combat.enemies[0]
	_tough(first)
	var x: int = first.body.x
	for i: int in range(1, ENEMIES):
		sim.combat.enemies.append(
			Enemy.new(
				first.def,
				sim.combat_params,
				sim.world,
				sim.events,
				x + Fx.units(SPACING_U * (i % 40)),
				first.body.y - Fx.units(80 * (i / 40))
			)
		)
		_tough(sim.combat.enemies[i])
	return sim


## Health and poise no bench reaches: every burst does the same work.
static func _tough(e: Enemy) -> void:
	e.max_hp = 1 << 40
	e.hp = e.max_hp
	e.max_poise = 1 << 40
	e.poise = e.max_poise


func _idle(index: int) -> Votive:
	var script := GDScript.new()
	script.source_code = IDLE_SOURCE
	script.reload()
	var c := StackingCurve.new()
	c.kind = StackingCurve.CHANCE
	# 0.1% a stack: almost never fires, always draws.
	c.first_stack = 1
	c.per_stack = 1
	var v := Votive.new()
	v.id = "idle_%d" % index
	v.display_name = v.id
	v.curve = c
	v.listens_to = PackedStringArray(["hit"])
	v.listener = script
	return v


func _raise_unheard() -> float:
	var sim: Simulation = _sim()
	var bus: ProcBus = sim.procs
	var c: Vector2i = sim.combat.enemies[0].centre()
	var n: int = REPS * 40
	var start: int = Time.get_ticks_usec()
	for i: int in range(REPS):
		bus.begin_tick(i * TICK_GAP)
		for k: int in range(40):
			bus.raise(ProcSource.TAPER, k, c.x, c.y, 10, Kindling.EMBER)
		bus.resolve(sim.combat, sim.player)
	return float(Time.get_ticks_usec() - start) / n


## Microseconds per event for [param events] events a tick rolled by [param k] idle Votives.
func _listening(k: int, events: int) -> float:
	var sim: Simulation = _sim()
	var bus: ProcBus = sim.procs
	for i: int in range(k):
		bus.give(_idle(i), 1)
	var c: Vector2i = sim.combat.enemies[0].centre()
	var start: int = Time.get_ticks_usec()
	for rep: int in range(REPS):
		bus.begin_tick(rep * TICK_GAP)
		for e: int in range(events):
			bus.raise(ProcSource.TAPER, e, c.x, c.y, 10, Kindling.EMBER)
		bus.resolve(sim.combat, sim.player)
	return float(Time.get_ticks_usec() - start) / (REPS * events)


## Microseconds per burst: one Taper hit's event resolved through the stress set's chains.
func _burst() -> float:
	var sim: Simulation = _sim()
	var bus: ProcBus = sim.procs
	for path: String in STRESS:
		bus.give(load(path) as Votive, 1)
	var fired: int = 0
	var start: int = Time.get_ticks_usec()
	for r: int in range(REPS):
		var c: Vector2i = sim.combat.enemies[r % ENEMIES].centre()
		bus.begin_tick(r * TICK_GAP)
		bus.raise(ProcSource.TAPER, r % ENEMIES, c.x, c.y, 10, Kindling.EMBER)
		bus.resolve(sim.combat, sim.player)
		fired += bus.fired()
		sim.events.clear()
	var us: float = float(Time.get_ticks_usec() - start) / REPS
	if fired != REPS * 39:
		printerr("expected 39 procs a burst, got %d in %d bursts" % [fired, REPS])
	return us
