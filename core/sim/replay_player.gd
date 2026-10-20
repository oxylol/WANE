class_name ReplayPlayer
extends RefCounted
## Plays a [Replay] back into a fresh [Simulation] and checks every recorded state hash. A
## mismatch is a desync, which is a P0 bug (CLAUDE.md rule 4). A replay is only accepted if it
## carries exactly the hashes a recording makes (every 60th tick and the final tick); a replay
## recorded by a different simulation version is reported as such, not as a desync.

enum Status { PLAYING, OK, DESYNC, MALFORMED, VERSION_MISMATCH, CONTENT_MISMATCH }

var status: Status = Status.PLAYING
## Tick of the first hash that did not match, or -1.
var desync_tick: int = -1
var expected_hash: int = 0
var actual_hash: int = 0
## Hashes that were checked.
var checked: int = 0
var sim: Simulation

var _replay: Replay
var _next_frame: int = 0
var _next_hash: int = 0


## Builds a simulation from the replay's scenario (with [param cache], if given: [SimCache]).
## Advance it with [method step_frame] (for a viewer) or [method run_to_end] (for verification).
func _init(replay: Replay, cache: SimCache = null) -> void:
	_replay = replay
	sim = Simulation.new(replay.scenario, cache)
	if replay.sim_version != Simulation.VERSION:
		status = Status.VERSION_MISMATCH
	elif replay.content_hash != sim.content_hash:
		status = Status.CONTENT_MISMATCH
	elif not _schedule_is_complete():
		status = Status.MALFORMED


func done() -> bool:
	return _next_frame >= _replay.frame_count()


## Steps one recorded frame and checks its hash if one was recorded at the new tick.
func step_frame() -> void:
	if done():
		return
	sim.step(_replay.frame(_next_frame))
	_next_frame += 1
	_check_hash()
	if done() and status == Status.PLAYING:
		status = Status.OK


## Plays every remaining frame. Returns true only if the replay reproduced bit-for-bit.
func run_to_end() -> bool:
	if status != Status.PLAYING:
		return false
	while not done():
		step_frame()
	if _replay.frame_count() == 0:
		status = Status.OK
	return status == Status.OK


## Convenience: true if [param replay] reproduces exactly.
static func verify(replay: Replay) -> bool:
	return ReplayPlayer.new(replay).run_to_end()


## A one-line explanation of [member status].
func describe() -> String:
	match status:
		Status.OK:
			return "reproduced bit-for-bit (%d hashes)" % checked
		Status.DESYNC:
			return (
				"DESYNC at tick %d: expected %08x, got %08x"
				% [desync_tick, expected_hash, actual_hash]
			)
		Status.MALFORMED:
			return "malformed: the hash list is not every 60th tick plus the final tick"
		Status.VERSION_MISMATCH:
			return (
				"recorded by simulation version %d; this build is version %d"
				% [_replay.sim_version, Simulation.VERSION]
			)
		Status.CONTENT_MISMATCH:
			return (
				"recorded with different content (%08x; this build has %08x)"
				% [_replay.content_hash, sim.content_hash]
			)
	return "playing"


func _schedule_is_complete() -> bool:
	var n: int = _replay.frame_count()
	var want: PackedInt32Array = PackedInt32Array()
	for t: int in range(Simulation.HASH_INTERVAL, n + 1, Simulation.HASH_INTERVAL):
		want.append(t)
	if n > 0 and (want.is_empty() or want[-1] != n):
		want.append(n)
	return _replay.hash_ticks == want and _replay.hash_values.size() == want.size()


func _check_hash() -> void:
	while _next_hash < _replay.hash_ticks.size() and _replay.hash_ticks[_next_hash] <= sim.tick:
		var at: int = _replay.hash_ticks[_next_hash]
		var want: int = _replay.hash_values[_next_hash]
		var got: int = sim.hash_at(at) if at % Simulation.HASH_INTERVAL == 0 else sim.state_hash()
		checked += 1
		if got != want and desync_tick < 0:
			desync_tick = at
			expected_hash = want
			actual_hash = got
			status = Status.DESYNC
		_next_hash += 1
