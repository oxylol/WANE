class_name Simulation
extends RefCounted
## The deterministic simulation (BUILD.md section 13, layer 2; CLAUDE.md rules 1 to 4).
##
## Constructed from a [Scenario], stepped exactly once per 60 Hz tick with one [InputFrame], and
## hashed every [constant HASH_INTERVAL] ticks. Nothing outside [method step] changes its state.
## Presentation reads it; tools probe it by name with [method probe].

## Ticks between recorded state hashes.
const HASH_INTERVAL: int = 60
## Simulation version. Bump it in the same commit as any change that moves a golden hash
## (tools/replay/bless.gd refuses to re-bless otherwise), so old replays report "recorded by an
## older build" instead of a desync.
const VERSION: int = 1

var scenario: Scenario
## Ticks completed. The input applied by the n-th call to [method step] is input frame n - 1,
## and after that call [member tick] is n.
var tick: int = 0
var rng: RngStreams
## Player one's input buffer.
var input: InputRing
## Ticks and values of every recorded state hash, in order.
var hash_ticks: PackedInt32Array = PackedInt32Array()
var hash_values: PackedInt64Array = PackedInt64Array()
## Fingerprint of the content this simulation was built from ([ContentHash]); rooms and Wicks
## join it as they arrive (Phase 1 tasks 2 and 3).
var content_hash: int = 0
## Problems found while building the simulation (a missing room, invalid content). A simulation
## with load errors still runs, but tools must treat it as a failure.
var load_errors: PackedStringArray = PackedStringArray()


func _init(p_scenario: Scenario) -> void:
	scenario = p_scenario.copy()
	rng = RngStreams.new(scenario.seed_value)
	input = InputRing.new()
	content_hash = StateHasher.new().value()


## Advances the world by one tick with [param frame] as player one's input.
func step(frame: InputFrame) -> void:
	input.push(frame)
	tick += 1
	if tick % HASH_INTERVAL == 0:
		hash_ticks.append(tick)
		hash_values.append(state_hash())


## Hash of every piece of state that can influence a future tick.
func state_hash() -> int:
	var h := StateHasher.new()
	h.add_int(tick)
	scenario.hash_into(h)
	rng.hash_into(h)
	input.hash_into(h)
	return h.value()


## The recorded hash at [param at_tick], or -1 if none was recorded there.
func hash_at(at_tick: int) -> int:
	var i: int = hash_ticks.find(at_tick)
	return hash_values[i] if i >= 0 else -1


## Named read-only view of the state, for replay fixtures and the F3 overlay. Returns an int or a
## String, or null for an unknown key. Keys are listed in tests/replay/README.md.
func probe(key: String) -> Variant:
	var value: Variant = null
	match key:
		"tick":
			value = tick
		"stick_x":
			value = input.stick_x()
		"stick_y":
			value = input.stick_y()
		_:
			value = _probe_input(key)
	return value


## The names a String-valued probe key can take (for fixture validation); empty for keys whose
## values are integers.
func probe_words(_key: String) -> PackedStringArray:
	return PackedStringArray()


func _probe_input(key: String) -> Variant:
	var dot: int = key.find(".")
	if dot < 0:
		return null
	var bit: int = _button_bit(key.substr(dot + 1))
	if bit == 0:
		return null
	match key.substr(0, dot):
		"held":
			return 1 if input.is_held(bit) else 0
		"press_age":
			return input.press_age(bit)
	return null


static func _button_bit(button_name: String) -> int:
	var i: int = InputFrame.BUTTON_NAMES.find(button_name.to_upper())
	return InputFrame.BUTTONS[i] if i >= 0 else 0
