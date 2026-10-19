class_name DebugControls
extends Node
## The debug keys, on every build (BUILD.md section 13, tooling: "the F3 debug overlay, a
## frame-stepper"). F3 shows or hides the overlay. With the overlay shown, F4 pauses and resumes
## the simulation, and while paused F5 steps exactly one tick and F6 ten, polling the controller
## for each tick as play would, so a press made while paused lands on the next step. The stepper is
## part of the overlay: with it hidden F4 to F6 do nothing, and hiding it resumes play, so a stray
## F4 never freezes the game with nothing on screen (task 5 review 2, M2). Keyboard only, and no
## modifier: no game binding uses these keys (a test checks the bindings), the controller never
## reaches them, and stepping never holds a game key down (Shift, the keyboard's dash, once
## stepped ten ticks with a dash held: task 5 review, H1).

const OVERLAY_KEY: Key = KEY_F3
const PAUSE_KEY: Key = KEY_F4
const STEP_KEY: Key = KEY_F5
const STEP_MANY_KEY: Key = KEY_F6
## Ticks one F6 steps.
const STEP_MANY: int = 10
## Every debug key.
const KEYS: Array[Key] = [OVERLAY_KEY, PAUSE_KEY, STEP_KEY, STEP_MANY_KEY]

var driver: SimDriver
var overlay: DebugOverlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if handle_key(key.keycode):
		get_viewport().set_input_as_handled()


## Acts on [param keycode]; true if it was a debug key.
func handle_key(keycode: Key) -> bool:
	match keycode:
		OVERLAY_KEY:
			if overlay != null:
				overlay.toggle()
				if not overlay.shown and driver != null and driver.paused:
					driver.set_paused(false)
		PAUSE_KEY:
			if not _stepper_on():
				return false
			driver.set_paused(not driver.paused)
			_refresh()
		STEP_KEY, STEP_MANY_KEY:
			if not _stepper_on():
				return false
			if driver.paused:
				for _i: int in range(STEP_MANY if keycode == STEP_MANY_KEY else 1):
					driver.step_once()
				_refresh()
		_:
			return false
	return true


## The stepper's keys act only with a driver and the overlay shown.
func _stepper_on() -> bool:
	return driver != null and overlay != null and overlay.shown


func _refresh() -> void:
	if overlay != null:
		overlay.refresh()
