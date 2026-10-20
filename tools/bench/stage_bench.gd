extends SceneTree
## Where a stress-room tick goes (BUILD.md section 13, "Frame budget": input + simulation step 3.0
## ms; docs/adr/0020 Decision 15). Plays the stress run (or the storm run with --storm) with
## [method Simulation.step]'s own stages timed one by one: the player's step, the 200 enemies'
## steps, combat's resolution (hit boxes, damage, procs) and the state hash tick. Each stage's time
## on a tick is the least over --repeats runs (the replay fixes the work; the excess is the
## machine's), as in the gate. Reports p50, p99 and max per stage, and the mean of each stage over
## the ticks at or above the total's 99th percentile, which is what the gate is judged on.
## The stage list copies [method Simulation.step]; if that changes, change it here.
##
##   godot --headless --path . --script tools/bench/stage_bench.gd [-- --storm --repeats N]

const RUN: String = "res://tests/perf/stress_run.fixture"
const STORM: String = "res://tests/perf/storm_run.fixture"
const STAGES: Array[String] = ["player", "enemies", "combat", "hash", "total"]
const P99: int = 990


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var repeats: int = 3
	var at: int = args.find("--repeats")
	if at >= 0 and at + 1 < args.size():
		repeats = maxi(1, int(args[at + 1]))
	var fx: Fixture = Fixture.parse_file(STORM if args.has("--storm") else RUN)
	var budget: PerfBudget = load(PerfBudget.PATH) as PerfBudget
	var best: Array[PackedInt32Array] = []
	for _s: int in range(STAGES.size()):
		best.append(PackedInt32Array())
	var procs: PackedInt32Array = PackedInt32Array()
	for r: int in range(repeats):
		var run_procs: PackedInt32Array = PackedInt32Array()
		var run: Array[PackedInt32Array] = _play(fx, run_procs)
		if r == 0:
			procs = run_procs
		for s: int in range(STAGES.size()):
			PerfStats.fold_min(best[s], run[s])
	var from: int = budget.warmup_ticks
	var order: PackedInt32Array = PerfStats.sorted_from(best[4], from)
	var cut: int = PerfStats.percentile(order, P99)
	print(
		(
			"%s: %d ticks, best of %d, first %d not counted; stage times in ms"
			% [fx.name, fx.frame_total, repeats, from]
		)
	)
	print("  stage      p50     p99     max    mean   mean of the p99 ticks")
	for s: int in range(STAGES.size()):
		var sorted: PackedInt32Array = PerfStats.sorted_from(best[s], from)
		var sum: int = 0
		var hot_sum: int = 0
		var hot_n: int = 0
		for i: int in range(from, best[s].size()):
			sum += best[s][i]
			if best[4][i] >= cut:
				hot_sum += best[s][i]
				hot_n += 1
		var line: String = (
			"  %-8s %6s  %6s  %6s  %6s  %6s"
			% [
				STAGES[s],
				PerfStats.ms(PerfStats.percentile(sorted, 500)),
				PerfStats.ms(PerfStats.percentile(sorted, P99)),
				PerfStats.ms(sorted[sorted.size() - 1]),
				PerfStats.ms(sum / maxi(1, best[s].size() - from)),
				PerfStats.ms(hot_sum / maxi(1, hot_n)),
			]
		)
		print(line)
	var quiet_sum: int = 0
	var quiet_n: int = 0
	var proc_sum: int = 0
	var proc_n: int = 0
	for i: int in range(from, best[2].size()):
		if procs[i] == 0:
			quiet_sum += best[2][i]
			quiet_n += 1
		else:
			proc_sum += best[2][i]
			proc_n += 1
	print(
		(
			"  combat on a tick with no proc: mean %s ms (%d ticks); with procs: mean %s ms (%d ticks)"
			% [
				PerfStats.ms(quiet_sum / maxi(1, quiet_n)),
				quiet_n,
				PerfStats.ms(proc_sum / maxi(1, proc_n)),
				proc_n
			]
		)
	)
	quit(0)


## One run: per stage, the microseconds of each tick; [param procs] gets the procs
## fired on each tick.
func _play(fx: Fixture, procs: PackedInt32Array) -> Array[PackedInt32Array]:
	var sim := Simulation.new(fx.scenario)
	var out: Array[PackedInt32Array] = []
	for _s: int in range(STAGES.size()):
		var a: PackedInt32Array = PackedInt32Array()
		a.resize(fx.frame_total)
		out.append(a)
	procs.resize(fx.frame_total)
	for i: int in range(fx.frame_total):
		var frame: InputFrame = fx.input_frame(i)
		var t0: int = Time.get_ticks_usec()
		sim.events.clear()
		sim.procs.begin_tick(sim.tick)
		sim.last_input = frame
		if sim.player != null and sim.player.freeze > 0:
			sim.input.merge(frame)
		else:
			sim.input.push(frame)
		if sim.player != null:
			sim.player.step(sim.input)
		var t1: int = Time.get_ticks_usec()
		for e: Enemy in sim.combat.enemies:
			e.step(sim.player)
		var t2: int = Time.get_ticks_usec()
		sim.combat.resolve(sim.player, sim.input)
		sim._take_door()
		var t3: int = Time.get_ticks_usec()
		sim.tick += 1
		if sim.tick % Simulation.HASH_INTERVAL == 0:
			sim.hash_ticks.append(sim.tick)
			sim.hash_values.append(sim.state_hash())
		var t4: int = Time.get_ticks_usec()
		out[0][i] = t1 - t0
		out[1][i] = t2 - t1
		out[2][i] = t3 - t2
		out[3][i] = t4 - t3
		out[4][i] = t4 - t0
		procs[i] = sim.procs.fired()
	return out
