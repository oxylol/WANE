class_name Scenario
extends RefCounted
## Everything needed to construct a [Simulation] before the first input: the run seed and the
## starting conditions. A run is a scenario plus an input stream (CLAUDE.md rule 4); the replay
## header stores exactly this.

## Run seed. Every random stream derives from it.
var seed_value: int = 0
## Wick id (content/wicks/<id>/); empty for a simulation with no player (core tests).
var wick: String = "ash"
## Starting room id (content/rooms/...), or "" for no room.
var room: String = ""
## Spawn point in world units, bottom-centre of the player's collider; (-1, -1) means the room's
## own spawn marker.
var spawn_x: int = -1
var spawn_y: int = -1
## Free-form integer options for tests and modes (difficulty, flags), sorted by key when stored.
var options: Dictionary[String, int] = {}


static func make(p_seed: int, p_room: String = "", p_wick: String = "ash") -> Scenario:
	var s := Scenario.new()
	s.seed_value = p_seed
	s.room = p_room
	s.wick = p_wick
	return s


func option(key: String, default_value: int = 0) -> int:
	return options.get(key, default_value)


func copy() -> Scenario:
	var s := Scenario.new()
	s.seed_value = seed_value
	s.wick = wick
	s.room = room
	s.spawn_x = spawn_x
	s.spawn_y = spawn_y
	s.options = options.duplicate()
	return s


func equals(other: Scenario) -> bool:
	if seed_value != other.seed_value or wick != other.wick or room != other.room:
		return false
	if spawn_x != other.spawn_x or spawn_y != other.spawn_y:
		return false
	return sorted_option_keys() == other.sorted_option_keys() and _options_match(other)


func sorted_option_keys() -> Array[String]:
	var keys: Array[String] = []
	for key: String in options.keys():
		keys.append(key)
	keys.sort()
	return keys


func hash_into(h: StateHasher) -> void:
	h.add_int(seed_value)
	h.add_string(wick)
	h.add_string(room)
	h.add_int(spawn_x)
	h.add_int(spawn_y)
	for key: String in sorted_option_keys():
		h.add_string(key)
		h.add_int(options[key])


func _options_match(other: Scenario) -> bool:
	for key: String in options.keys():
		if not other.options.has(key) or options[key] != other.options[key]:
			return false
	return true
