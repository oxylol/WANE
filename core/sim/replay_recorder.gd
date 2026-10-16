class_name ReplayRecorder
extends RefCounted
## Records a run as it is played: the scenario once, then every input frame the simulation
## consumed, then the simulation's hash log (BUILD.md section 13, layer 5: "the replay recorder
## (seed plus input stream plus periodic state hashes)").
##
## Built before the first enemy (CLAUDE.md rule 4) and attached to every simulation the game
## runs, so any session can be saved and replayed.

var replay: Replay = Replay.new()


func _init(scenario: Scenario) -> void:
	replay.scenario = scenario.copy()


## Records the frame that was just passed to [method Simulation.step].
func record(frame: InputFrame) -> void:
	replay.frames.append(frame.pack())


## The replay so far: every hash [param sim] has recorded (each 60th tick) plus the hash of the
## final tick, so even a replay shorter than a second, and the last frames of any replay, are
## verified. The recorder can keep recording afterwards.
func finish(sim: Simulation) -> Replay:
	var out := Replay.new()
	out.scenario = replay.scenario.copy()
	out.sim_version = Simulation.VERSION
	out.content_hash = sim.content_hash
	out.frames = replay.frames.duplicate()
	out.hash_ticks = sim.hash_ticks.duplicate()
	out.hash_values = sim.hash_values.duplicate()
	if sim.tick > 0 and (out.hash_ticks.is_empty() or out.hash_ticks[-1] != sim.tick):
		out.hash_ticks.append(sim.tick)
		out.hash_values.append(sim.state_hash())
	return out
