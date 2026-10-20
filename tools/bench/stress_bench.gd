extends SceneTree
## The performance gate's CPU half (BUILD.md section 13: "Performance | a stress room (200
## enemies, 40 procs, Pitch lighting) ..." and the frame budget's "Input + simulation step 3.0
## ms"; docs/adr/0020). Plays the stress room's scripted run (tests/perf/stress_run.fixture: Ash
## runs, dashes, strikes, pogoes and casts through 200 training dummies, 150 of them walking, with
## the stress Votive set stacked: 39 procs a Taper hit) and times every tick's input plus
## [method Simulation.step], then plays the zone 1 loop (tests/replay/zone1/zone1_loop.fixture)
## six times through on one simulation, 20,766 ticks (5.8 minutes), for the checklist's
## 5-minute spike line.
##
## A tick's time is the least over the repeated runs (the replay fixes a tick's work; the excess is
## the machine's); the first warm-up ticks are played and not counted. The gates are in
## content/perf/budget.tres ([PerfBudget]): the stress run's 99th percentile and worst tick, the
## zone loop's worst tick, and minimums on what the stress run did (procs, hits, kills, walkers) so
## that a gate cannot pass on a scenario that stopped being one. Exit status 1 over any of them.
## What it cannot measure: the lighting pass and the GPU stages (no lighting pass exists in
## Phase 1, and CI has no GPU: PROGRESS.md, Blocked 2).
##
##   godot --headless --path . --script tools/bench/stress_bench.gd [-- options]
##
## Options: --quiet (the gate lines only), --report <path> (the full report to a file too),
## --repeats N (override the budget's), --only stress|zone, --worst N (ticks listed, default 8).

const STRESS_FIXTURE: String = "res://tests/perf/stress_run.fixture"
const STORM_FIXTURE: String = "res://tests/perf/storm_run.fixture"
const ZONE_FIXTURE: String = "res://tests/replay/zone1/zone1_loop.fixture"
const P99: int = 990
## Event flags on a tick, for the worst-tick list.
const F_HASH: int = 1
const F_DOOR: int = 2
const F_DEATH: int = 4
const F_HURT: int = 8
const F_CAST: int = 16
const FLAG_NAMES: Dictionary[int, String] = {
	F_HASH: "hash tick", F_DOOR: "door", F_DEATH: "death", F_HURT: "hurt", F_CAST: "cast"
}

var _lines: PackedStringArray = PackedStringArray()
var _quiet: bool = false
var _failures: PackedStringArray = PackedStringArray()


## What happened on each tick of one run, and its totals.
class Facts:
	extends RefCounted
	var procs: PackedInt32Array = PackedInt32Array()
	var kills: PackedInt32Array = PackedInt32Array()
	var hits: PackedInt32Array = PackedInt32Array()
	var flags: PackedInt32Array = PackedInt32Array()
	var total_procs: int = 0
	var total_hits: int = 0
	var total_kills: int = 0
	var deaths: int = 0
	var hurt_ticks: int = 0
	var door_ticks: int = 0
	var end_hash: int = 0
	var load_errors: PackedStringArray = PackedStringArray()
	var enemies: int = 0
	var walkers: int = 0

	func _init(ticks: int) -> void:
		for a: PackedInt32Array in [procs, kills, hits, flags]:
			a.resize(ticks)

	func begin(sim: Simulation) -> void:
		load_errors = sim.load_errors
		enemies = sim.combat.enemies.size()
		for e: Enemy in sim.combat.enemies:
			var d: TrainingDummy = e as TrainingDummy
			if d != null and d.patrol_dir != 0:
				walkers += 1

	func add(i: int, sim: Simulation) -> void:
		var f: int = 0
		var ev: SimEvents = sim.events
		for k: int in range(ev.kinds.size()):
			match ev.kinds[k]:
				SimEvents.HIT:
					hits[i] += 1
				SimEvents.KILL:
					kills[i] += 1
				SimEvents.ROOM:
					f |= F_DOOR
				SimEvents.DEATH:
					f |= F_DEATH
				SimEvents.PLAYER_HIT:
					f |= F_HURT
				SimEvents.CAST:
					f |= F_CAST
		if sim.tick % Simulation.HASH_INTERVAL == 0:
			f |= F_HASH
		flags[i] = f
		procs[i] = sim.procs.fired()
		total_procs += procs[i]
		total_hits += hits[i]
		total_kills += kills[i]
		if f & F_DEATH:
			deaths += 1
		if f & F_HURT:
			hurt_ticks += 1
		if f & F_DOOR:
			door_ticks += 1


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_quiet = args.has("--quiet")
	var budget: PerfBudget = load(PerfBudget.PATH) as PerfBudget
	if budget == null:
		printerr("no perf budget at %s" % PerfBudget.PATH)
		quit(1)
		return
	for problem: String in budget.validate():
		_fail("budget: %s" % problem)
	var repeats: int = _arg_int(args, "--repeats", budget.repeats)
	var only: String = _arg_str(args, "--only", "")
	var worst: int = _arg_int(args, "--worst", 8)
	if only != "zone":
		_stress(budget, repeats, worst)
		_storm(budget, repeats)
	if only != "stress":
		_zone(budget, repeats)
	_say(_frame_budget_line(budget), false)
	var report: String = _arg_str(args, "--report", "")
	if report != "":
		_write_report(report)
	if _failures.is_empty():
		print("PERF GATE PASSED")
		quit(0)
	else:
		print("PERF GATE FAILED: %d over budget" % _failures.size())
		for f: String in _failures:
			print("  " + f)
		quit(1)


func _frame_budget_line(b: PerfBudget) -> String:
	var stages: Dictionary[String, int] = {
		"sprites": b.sprite_us,
		"lighting": b.lighting_us,
		"VFX": b.vfx_us,
		"post": b.post_us,
		"audio and UI": b.audio_ui_us,
		"headroom": b.headroom_us,
	}
	var parts: PackedStringArray = []
	for stage: String in stages:
		parts.append("%s %s" % [stage, PerfStats.ms(stages[stage])])
	var text: String = "frame budget (section 13): input + simulation %s ms is gated above; "
	text += "%s ms; the %s ms (reference PC) and %s ms (Deck) 99th-percentile frame "
	text += "need a GPU runner (PROGRESS.md, Blocked 2)"
	return (
		text
		% [
			PerfStats.ms(b.sim_p99_us),
			", ".join(parts),
			PerfStats.ms(b.reference_p99_us),
			PerfStats.ms(b.deck_p99_us),
		]
	)


func _stress(budget: PerfBudget, repeats: int, worst: int) -> void:
	var fx: Fixture = Fixture.parse_file(STRESS_FIXTURE)
	for e: String in fx.errors:
		_fail("stress fixture: %s" % e)
	var best: PackedInt32Array = PackedInt32Array()
	var runs: Array[PackedInt32Array] = []
	var facts: Facts = null
	var hash_seen: int = 0
	for r: int in range(repeats):
		var run_facts: Facts = Facts.new(fx.frame_total) if r == 0 else null
		var run: BenchRun = _play(fx, fx.frame_total, run_facts)
		PerfStats.fold_min(best, run.us)
		runs.append(run.us)
		if r == 0:
			facts = run_facts
			hash_seen = run.end_hash
		elif run.end_hash != hash_seen:
			_fail(
				(
					"stress run desync: run %d ended on hash %d, run 1 on %d"
					% [r + 1, run.end_hash, hash_seen]
				)
			)
	for e: String in facts.load_errors:
		_fail("stress run load error: %s" % e)
	var sorted: PackedInt32Array = PerfStats.sorted_from(best, budget.warmup_ticks)
	var p50: int = PerfStats.percentile(sorted, 500)
	var p99: int = PerfStats.percentile(sorted, P99)
	var top: int = sorted[sorted.size() - 1]
	_say(
		(
			"stress room: %d enemies (%d walking), %d ticks, best of %d runs, first %d ticks not counted"
			% [facts.enemies, facts.walkers, fx.frame_total, repeats, budget.warmup_ticks]
		),
		false
	)
	_say(
		(
			"  procs fired %d, hits %d, kills %d, player deaths %d, end hash %d"
			% [facts.total_procs, facts.total_hits, facts.total_kills, facts.deaths, hash_seen]
		),
		false
	)
	_say(
		(
			"stress input + step: p50 %s ms, p99 %s ms (gate %s), max %s ms (gate %s)"
			% [
				PerfStats.ms(p50),
				PerfStats.ms(p99),
				PerfStats.ms(budget.sim_p99_us),
				PerfStats.ms(top),
				PerfStats.ms(budget.sim_max_us),
			]
		),
		true
	)
	_say_single_passes(runs, facts, budget)
	if p99 > budget.sim_p99_us:
		_fail("stress p99 %s ms over %s ms" % [PerfStats.ms(p99), PerfStats.ms(budget.sim_p99_us)])
	if top > budget.sim_max_us:
		_fail("stress max %s ms over %s ms" % [PerfStats.ms(top), PerfStats.ms(budget.sim_max_us)])
	_warm_up(best, facts, budget.warmup_ticks, budget.sim_max_us)
	_minimum("procs fired", facts.total_procs, budget.min_procs)
	_minimum("hits", facts.total_hits, budget.min_hits)
	_minimum("kills", facts.total_kills, budget.min_kills)
	_minimum("walking enemies", facts.walkers, budget.min_walkers)
	if not _quiet:
		_say("  slowest ticks (tick, ms, what happened):", false)
		for i: int in PerfStats.worst(best, budget.warmup_ticks, worst):
			_say(
				(
					"    %5d  %6s  procs %3d, hits %2d, kills %d%s"
					% [
						i,
						PerfStats.ms(best[i]),
						facts.procs[i],
						facts.hits[i],
						facts.kills[i],
						_flags(facts.flags[i])
					]
				),
				false
			)


## What one run alone read, beside the gate's best-of-runs figure (docs/adr/0020 Decision 18): the
## least time of each tick is the code's cost and is what is gated, but a player gets one run, so
## the report names each run's own 99th percentile and worst tick, how many of its ticks were over
## the gate's p99 (more than 1% of the counted ticks is a failing run), and how many of the counted
## ticks hold the state hash (one in [constant Simulation.HASH_INTERVAL] is more than the 1% the
## percentile leaves, so the 99th percentile falls among them). Not gated.
func _say_single_passes(runs: Array[PackedInt32Array], facts: Facts, budget: PerfBudget) -> void:
	var from: int = budget.warmup_ticks
	var counted: int = facts.flags.size() - from
	var p99s: PackedStringArray = []
	for us: int in PerfStats.p99_each(runs, from):
		p99s.append(PerfStats.ms(us))
	var tops: PackedStringArray = []
	for us: int in PerfStats.max_each(runs, from):
		tops.append(PerfStats.ms(us))
	var overs: PackedStringArray = []
	for run: PackedInt32Array in runs:
		overs.append(str(PerfStats.count_over(run, from, budget.sim_p99_us)))
	var hashed: int = 0
	for i: int in range(from, facts.flags.size()):
		if facts.flags[i] & F_HASH:
			hashed += 1
	_say(
		(
			(
				"  single runs (what a player gets; not gated): p99 %s ms, worst %s ms, ticks over %s ms "
				+ "%s of %d counted (1%% is %d); state-hash ticks %d (%.1f%%); run 1 also records the facts"
			)
			% [
				" / ".join(p99s),
				" / ".join(tops),
				PerfStats.ms(budget.sim_p99_us),
				" / ".join(overs),
				counted,
				counted / 100,
				hashed,
				float(hashed) * 100.0 / float(maxi(counted, 1)),
			]
		),
		true
	)


## The proc storm (docs/adr/0020, Decision 15): the same room and inputs with the storm Votive
## set, which fires a sure chain on every proc event, so one area hit on a crowd raises hundreds of
## procs on a tick. Measured and reported with the same least-of-runs method; never gated, because
## it is not the workload section 13 names ("40 procs") and the threshold is not to be bent to it.
## The line says what a proc costs, so a Votive design can be weighed against the budget.
func _storm(budget: PerfBudget, repeats: int) -> void:
	var fx: Fixture = Fixture.parse_file(STORM_FIXTURE)
	for e: String in fx.errors:
		_fail("storm fixture: %s" % e)
	var best: PackedInt32Array = PackedInt32Array()
	var facts: Facts = null
	for r: int in range(repeats):
		var run_facts: Facts = Facts.new(fx.frame_total) if r == 0 else null
		var run: BenchRun = _play(fx, fx.frame_total, run_facts)
		PerfStats.fold_min(best, run.us)
		if r == 0:
			facts = run_facts
	var sorted: PackedInt32Array = PerfStats.sorted_from(best, budget.warmup_ticks)
	var peak: int = 0
	var proc_ticks: int = 0
	for n: int in facts.procs:
		peak = maxi(peak, n)
		proc_ticks += 1 if n > 0 else 0
	_say(
		(
			"proc storm (not gated): %d ticks, %d procs fired (most on a tick %d, %d ticks with any)"
			% [fx.frame_total, facts.total_procs, peak, proc_ticks]
		),
		false
	)
	_say(
		(
			"  storm input + step: p50 %s ms, p99 %s ms, max %s ms (the gated workload is above)"
			% [
				PerfStats.ms(PerfStats.percentile(sorted, 500)),
				PerfStats.ms(PerfStats.percentile(sorted, P99)),
				PerfStats.ms(sorted[sorted.size() - 1])
			]
		),
		true
	)
	var proc_us: int = _cost_per_proc(best, facts, budget.warmup_ticks)
	_say("  cost per proc on a tick that fires 100 or more: about %d us" % proc_us, false)


## The cost of one proc, estimated from the storm run: the mean extra time of ticks that fired 100
## procs or more over the mean of ticks that fired none, per proc.
func _cost_per_proc(best: PackedInt32Array, facts: Facts, from: int) -> int:
	var quiet_sum: int = 0
	var quiet_n: int = 0
	var burst_sum: int = 0
	var burst_procs: int = 0
	var burst_n: int = 0
	for i: int in range(from, best.size()):
		if facts.procs[i] == 0:
			quiet_sum += best[i]
			quiet_n += 1
		elif facts.procs[i] >= 100:
			burst_sum += best[i]
			burst_procs += facts.procs[i]
			burst_n += 1
	if quiet_n == 0 or burst_n == 0:
		return 0
	return (burst_sum - burst_n * (quiet_sum / quiet_n)) / burst_procs


## The warm-up ticks are played and left out of the percentile; the biggest early bursts are in
## them (the stress pin's 117-proc hit on tick 2 and its 39-proc hit on tick 6), so their cost is
## reported here and held to the worst-tick gate (the p99 leaves them out, the 20 ms spike line
## does not: it is about every tick the player could meet).
func _warm_up(best: PackedInt32Array, facts: Facts, warmup: int, max_us: int) -> void:
	var count: int = mini(warmup, best.size())
	if count == 0:
		return
	var worst_tick: int = PerfStats.worst(best.slice(0, count), 0, 1)[0]
	var peak_procs: int = 0
	for i: int in range(count):
		peak_procs = maxi(peak_procs, facts.procs[i])
	_say(
		(
			(
				"  warm-up (first %d ticks, out of the percentile): worst %s ms at tick %d, "
				+ "most procs on a tick %d"
			)
			% [count, PerfStats.ms(best[worst_tick]), worst_tick, peak_procs]
		),
		false
	)
	if best[worst_tick] > max_us:
		_fail(
			(
				"stress warm-up tick %d: %s ms over %s ms"
				% [worst_tick, PerfStats.ms(best[worst_tick]), PerfStats.ms(max_us)]
			)
		)


## The checklist's 5-minute zone 1 run: the 60-second loop played [member PerfBudget.zone_passes]
## times through on one simulation (a fresh one each pass would hide state that builds up), the
## whole run repeated [member PerfBudget.repeats] times and each tick's time the least of them.
func _zone(budget: PerfBudget, repeats: int) -> void:
	var fx: Fixture = Fixture.parse_file(ZONE_FIXTURE)
	for e: String in fx.errors:
		_fail("zone fixture: %s" % e)
	var ticks: int = budget.zone_passes * fx.frame_total
	var best: PackedInt32Array = PackedInt32Array()
	var facts: Facts = null
	var hash_seen: int = 0
	for r: int in range(repeats):
		var run_facts: Facts = Facts.new(ticks) if r == 0 else null
		var run: BenchRun = _play(fx, ticks, run_facts)
		PerfStats.fold_min(best, run.us)
		if r == 0:
			facts = run_facts
			hash_seen = run.end_hash
		elif run.end_hash != hash_seen:
			_fail(
				(
					"zone run desync: run %d ended on hash %d, run 1 on %d"
					% [r + 1, run.end_hash, hash_seen]
				)
			)
	for e: String in facts.load_errors:
		_fail("zone loop load error: %s" % e)
	var sorted: PackedInt32Array = PerfStats.sorted_from(best, 0)
	var top: int = sorted[sorted.size() - 1]
	_say(
		(
			(
				"zone 1 loop x%d on one simulation (%d ticks), best of %d runs: "
				+ "p50 %s ms, p99 %s ms, max %s ms (gate %s)"
			)
			% [
				budget.zone_passes,
				best.size(),
				repeats,
				PerfStats.ms(PerfStats.percentile(sorted, 500)),
				PerfStats.ms(PerfStats.percentile(sorted, P99)),
				PerfStats.ms(top),
				PerfStats.ms(budget.zone_max_us),
			]
		),
		true
	)
	var by_pass: PackedStringArray = PackedStringArray()
	var trouble: PackedStringArray = PackedStringArray()
	for p: int in range(budget.zone_passes):
		var from: int = p * fx.frame_total
		var pass_sorted: PackedInt32Array = PerfStats.sorted_from(
			best.slice(from, from + fx.frame_total), 0
		)
		by_pass.append(PerfStats.ms(pass_sorted[pass_sorted.size() - 1]))
		var hurt: int = 0
		var died: int = 0
		for i: int in range(from, from + fx.frame_total):
			hurt += 1 if facts.flags[i] & F_HURT else 0
			died += 1 if facts.flags[i] & F_DEATH else 0
		trouble.append("%d/%d" % [hurt, died])
	_say("  worst tick by pass (ms): %s" % ", ".join(by_pass), false)
	# The route holds while Kindling is below White; later passes are play, not the route (the
	# 10th white hit, Combat._white_charges, adds hitstop the route does not allow for), so the
	# hurt and death counts by pass say how far the loop held (ADR-0020 Decision 14).
	_say(
		(
			"  ticks hurt/deaths by pass: %s; door crossings %d, end hash %d"
			% [", ".join(trouble), facts.door_ticks, hash_seen]
		),
		false
	)
	if top > budget.zone_max_us:
		_fail(
			"zone loop max %s ms over %s ms" % [PerfStats.ms(top), PerfStats.ms(budget.zone_max_us)]
		)


## Plays [param fx] for [param ticks] ticks on one simulation (see [BenchRun]); with
## [param facts] it also records what happened (outside the timing).
func _play(fx: Fixture, ticks: int, facts: Facts) -> BenchRun:
	if facts == null:
		return BenchRun.play(fx, ticks)
	return BenchRun.play(fx, ticks, facts.begin, facts.add)


func _minimum(what: String, got: int, wanted: int) -> void:
	if got < wanted:
		_fail("stress run did too little: %s %d, at least %d wanted" % [what, got, wanted])


func _flags(f: int) -> String:
	var out: String = ""
	for bit: int in FLAG_NAMES:
		if f & bit:
			out += ", " + FLAG_NAMES[bit]
	return out


func _fail(message: String) -> void:
	_failures.append(message)
	_say("FAIL " + message, true)


## Prints [param line] unless the run is quiet (a gate line, [param gate], prints always).
func _say(line: String, gate: bool) -> void:
	_lines.append(line)
	if gate or not _quiet:
		print(line)


func _write_report(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write %s" % path)
		return
	f.store_string("\n".join(_lines) + "\n")
	f.close()


func _arg_int(args: PackedStringArray, key: String, fallback: int) -> int:
	var s: String = _arg_str(args, key, "")
	return s.to_int() if s.is_valid_int() else fallback


func _arg_str(args: PackedStringArray, key: String, fallback: String) -> String:
	var i: int = args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback
