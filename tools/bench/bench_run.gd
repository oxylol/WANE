class_name BenchRun
extends RefCounted
## One timed play of a replay fixture for the perf bench (`tools/bench/stress_bench.gd`; docs/adr/0020).
## A run is one [Simulation] stepped for [member ticks] ticks. When that is more than the fixture's
## length the fixture's input starts over from its first frame and the simulation carries on, so
## state that grows pass after pass (an event list, a trail list, a leak) shows in the later
## passes. The checklist's "5-minute zone 1 run" is this: the 60-second loop five times through
## on one simulation, not five fresh simulations.

## Microseconds of each tick's input plus [method Simulation.step].
var us: PackedInt32Array = PackedInt32Array()
## The simulation after the last tick.
var sim: Simulation
## [method Simulation.state_hash] after the last tick.
var end_hash: int = 0


## Plays [param fx] for [param ticks] ticks from a fresh simulation. [param on_start] (if valid)
## is called with the simulation before the first tick and [param on_tick] with the tick's index
## and the simulation after each one, both outside the timing.
static func play(
	fx: Fixture, ticks: int, on_start: Callable = Callable(), on_tick: Callable = Callable()
) -> BenchRun:
	var run := BenchRun.new()
	run.sim = Simulation.new(fx.scenario)
	run.us.resize(ticks)
	if on_start.is_valid():
		on_start.call(run.sim)
	for i: int in range(ticks):
		var frame: InputFrame = fx.looped_input_frame(i)
		var t0: int = Time.get_ticks_usec()
		run.sim.step(frame)
		run.us[i] = Time.get_ticks_usec() - t0
		if on_tick.is_valid():
			on_tick.call(i, run.sim)
	run.end_hash = run.sim.state_hash()
	return run
