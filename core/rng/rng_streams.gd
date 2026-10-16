class_name RngStreams
extends RefCounted
## The run's split random streams (BUILD.md section 13: "a seeded RNG with split streams (loot,
## spawns, VFX, AI)"; ADR-0005). Each stream is an independent [Rng] derived from the run seed,
## so drawing more numbers in one system never shifts the results of another: adding a hit spark
## variant cannot change which Votive drops.
##
## [constant PROCS] is a fifth stream for Votive proc rolls, kept apart from loot so that what a
## run finds never depends on how often its items fired. Presentation never draws from these
## streams; the core hands it per-event seeds drawn from [constant VFX].

const LOOT: int = 0
const SPAWNS: int = 1
const VFX: int = 2
const AI: int = 3
const PROCS: int = 4
const COUNT: int = 5
const NAMES: Array[String] = ["loot", "spawns", "vfx", "ai", "procs"]

var seed_value: int = 0
var _streams: Array[Rng] = []


func _init(run_seed: int = 0) -> void:
	seed_value = run_seed
	_streams.clear()
	for stream_id: int in range(COUNT):
		_streams.append(Rng.seeded(run_seed, stream_id))


func stream(stream_id: int) -> Rng:
	return _streams[stream_id]


func loot() -> Rng:
	return _streams[LOOT]


func spawns() -> Rng:
	return _streams[SPAWNS]


func vfx() -> Rng:
	return _streams[VFX]


func ai() -> Rng:
	return _streams[AI]


func procs() -> Rng:
	return _streams[PROCS]


func hash_into(h: StateHasher) -> void:
	h.add_int(seed_value)
	for r: Rng in _streams:
		r.hash_into(h)
