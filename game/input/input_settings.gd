class_name InputSettings
extends Resource
## Input layer settings: dead zones and default bindings (BUILD.md section 12, "Input"; section
## 13, layer 1: "Remapping and dead zones live here and nowhere else").
##
## A binding line is "<action>=<event>,<event>..." where an event is "key:<Godot key name>",
## "pad:<joy button index>" or "axis:<joy axis index>:<+|->".

const ACTIONS: Array[String] = [
	"move_left",
	"move_right",
	"move_up",
	"move_down",
	"jump",
	"attack",
	"dash",
	"spell",
	"mend",
	"vessel",
	"toss",
]

## Radial inner dead zone of the left stick, percent of full deflection (BUILD.md: 12%).
@export_range(0, 50) var dead_zone_inner_percent: int = 12
## Radial outer dead zone: deflection at or beyond this percent reads as full (BUILD.md: 95%).
@export_range(50, 100) var dead_zone_outer_percent: int = 95
## A stick that has left the inner dead zone counts as moved until it falls back to this percent
## (hysteresis, so a stick resting on the 12% edge does not flicker; not in BUILD.md).
@export_range(0, 50) var dead_zone_release_percent: int = 10
## The engine's own dead zone on every action, percent: it only keeps a resting stick from
## registering at all, since the layer applies the real thresholds itself (with hysteresis).
@export_range(0, 20) var action_dead_zone_percent: int = 5
## Analog travel, percent, at which a trigger (or stick) bound as a button counts as pressed, and
## how far below that it must fall to count as released (hysteresis).
@export_range(5, 95) var trigger_press_percent: int = 50
@export_range(1, 40) var trigger_release_gap_percent: int = 10
## Joypad axes that drive movement (remappable; BUILD.md section 12).
@export var stick_axis_x: int = JOY_AXIS_LEFT_X
@export var stick_axis_y: int = JOY_AXIS_LEFT_Y
## Stick resolution in the core's units (of 127): the reported stick moves in steps this big,
## with hysteresis, so sensor noise does not reach the simulation.
@export_range(1, 32) var stick_step: int = 8
@export var bindings: PackedStringArray = PackedStringArray()


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if dead_zone_inner_percent >= dead_zone_outer_percent:
		errors.append("inner dead zone must be below the outer dead zone")
	if (
		stick_axis_x < 0
		or stick_axis_x >= JOY_AXIS_MAX
		or stick_axis_y < 0
		or stick_axis_y >= JOY_AXIS_MAX
	):
		errors.append("stick axes must be valid joypad axes")
	if action_dead_zone_percent < 0 or action_dead_zone_percent > dead_zone_inner_percent:
		errors.append("the action dead zone must be 0 to the inner dead zone")
	# Range hints are not enforced when a .tres loads, so check every range here.
	if dead_zone_inner_percent < 0 or dead_zone_outer_percent > 100:
		errors.append("dead zones must lie in 0..100 percent")
	if dead_zone_release_percent < 0 or dead_zone_release_percent > dead_zone_inner_percent:
		errors.append("dead_zone_release_percent must be in 0..dead_zone_inner_percent")
	if trigger_press_percent < 5 or trigger_press_percent > 95:
		errors.append("trigger_press_percent must be in 5..95")
	if trigger_release_gap_percent < 1 or trigger_release_gap_percent >= trigger_press_percent:
		errors.append(
			"trigger_release_gap_percent must be at least 1 and below the press threshold"
		)
	if stick_step < 1 or stick_step > 32:
		errors.append("stick_step must be in 1..32")
	var bound: Array[String] = []
	for line: String in bindings:
		var eq: int = line.find("=")
		if eq <= 0:
			errors.append("binding '%s' has no '='" % line)
			continue
		var action: String = line.substr(0, eq)
		if not ACTIONS.has(action):
			errors.append("binding for unknown action '%s'" % action)
		bound.append(action)
		for token: String in line.substr(eq + 1).split(",", false):
			if parse_event(token) == null:
				errors.append("bad event '%s' for '%s'" % [token, action])
	for action: String in ACTIONS:
		if not bound.has(action):
			errors.append("no binding for '%s'" % action)
	return errors


## Builds the InputEvent described by [param token], or null if it is malformed.
func parse_event(token: String) -> InputEvent:
	var parts: PackedStringArray = token.strip_edges().split(":")
	if parts.size() == 2 and parts[0] == "key":
		var code: Key = OS.find_keycode_from_string(parts[1])
		if code == KEY_NONE:
			return null
		var key := InputEventKey.new()
		key.physical_keycode = code
		return key
	if parts.size() == 2 and parts[0] == "pad" and parts[1].is_valid_int():
		var button := InputEventJoypadButton.new()
		button.button_index = parts[1].to_int() as JoyButton
		return button
	if parts.size() == 3 and parts[0] == "axis" and parts[1].is_valid_int():
		if parts[2] != "+" and parts[2] != "-":
			return null
		var motion := InputEventJoypadMotion.new()
		motion.axis = parts[1].to_int() as JoyAxis
		motion.axis_value = 1.0 if parts[2] == "+" else -1.0
		return motion
	return null
