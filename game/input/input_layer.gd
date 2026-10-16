class_name InputLayer
extends Node
## The input layer (BUILD.md section 13, layer 1; ADR-0004). Owns remapping and dead zones and
## hands the core exactly one [InputFrame] per tick through [method poll].
##
## Each tick, [method poll] reads every button's state from the devices, so a release the layer
## never saw as an event (the tree was paused, or another node consumed it) cannot leave a button
## stuck down. Events only add presses: one pressed and released between two ticks is latched and
## still reaches the core as a press. Polling happens at the start of each tick, before the
## simulation steps, so no input waits for anything.

## How [method _update_action] treats a button going down.
enum { LATCH, SYNC, MENU }

const SETTINGS_PATH: String = "res://content/input/input_settings.tres"
const ACTION_PREFIX: String = "wane_"
## Core button bit for each button action (the move actions feed the stick instead).
const BUTTON_ACTIONS: Dictionary[String, int] = {
	"jump": InputFrame.JUMP,
	"attack": InputFrame.ATTACK,
	"dash": InputFrame.DASH,
	"spell": InputFrame.SPELL,
	"mend": InputFrame.MEND,
	"vessel": InputFrame.VESSEL,
	"toss": InputFrame.TOSS,
}

## Joypad whose left stick drives movement.
@export var device: int = 0

var settings: InputSettings
var _latched: int = 0
var _prev_held: int = 0
## Buttons down (with hysteresis), from events and from each poll.
var _down: int = 0
## Last reported stick, for hysteresis.
var _stick_out: Vector2i = Vector2i.ZERO


func _ready() -> void:
	process_priority = -1000
	# Events keep arriving while the tree is paused, so the held state stays true to the devices.
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = load(SETTINGS_PATH) as InputSettings
	install_actions(settings)


## Registers every bound action in the InputMap from [param s].
static func install_actions(s: InputSettings) -> void:
	for line: String in s.bindings:
		var eq: int = line.find("=")
		if eq <= 0:
			continue
		var action: String = ACTION_PREFIX + line.substr(0, eq)
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		# Thresholds are applied by the layer itself (with hysteresis); the action's own dead zone
		# only has to keep resting sticks from registering at all.
		InputMap.add_action(action, 0.05)
		for token: String in line.substr(eq + 1).split(",", false):
			var event: InputEvent = s.parse_event(token)
			if event != null:
				InputMap.action_add_event(action, event)


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	# A button pressed while the tree is paused (in a menu) is not a gameplay press, even if it
	# is still held when play resumes: it has to be pressed again.
	var mode: int = MENU if is_inside_tree() and get_tree().paused else LATCH
	for action: String in BUTTON_ACTIONS:
		if event.is_action(ACTION_PREFIX + action):
			_update_action(action, mode)


## Each button action is down or up with hysteresis on its combined strength (all devices bound
## to it): it goes down at the press threshold and up only once below the release threshold, so
## an analog trigger resting near the threshold neither flickers nor re-presses (a flickering
## Mend would be interrupted and lose its Flame, BUILD.md s6). [param mode] says what an
## up-to-down change means: [constant LATCH] latches a press, so a tap shorter than a tick still
## reaches the core; [constant SYNC] leaves the press to [method poll]'s edge check;
## [constant MENU] marks the button as already held, so it never becomes a press.
func _update_action(action: String, mode: int) -> void:
	var bit: int = BUTTON_ACTIONS[action]
	var strength: float = Input.get_action_raw_strength(ACTION_PREFIX + action)
	var press: float = float(settings.trigger_press_percent) / 100.0
	var release: float = (
		float(settings.trigger_press_percent - settings.trigger_release_gap_percent) / 100.0
	)
	var down: bool = (_down & bit) != 0
	if not down and strength >= press:
		_down |= bit
		if mode == LATCH:
			_latched |= bit
		elif mode == MENU:
			_prev_held |= bit
	elif down and strength < release:
		_down &= ~bit


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset()


## Samples the devices for this tick. Call exactly once per simulation step, before stepping.
func poll() -> InputFrame:
	for action: String in BUTTON_ACTIONS:
		_update_action(action, SYNC)
	var held: int = _down
	var pressed: int = (held & ~_prev_held) | _latched
	_latched = 0
	_prev_held = held
	var stick: Vector2i = _stick()
	return InputFrame.make(held, pressed, stick.x, stick.y)


## Forgets latched presses and held state (on focus loss and when a session restarts).
func reset() -> void:
	_latched = 0
	_prev_held = 0
	_down = 0
	_stick_out = Vector2i.ZERO


func _stick() -> Vector2i:
	var digital := Vector2(
		_axis_strength("move_right") - _axis_strength("move_left"),
		_axis_strength("move_down") - _axis_strength("move_up")
	)
	var raw := Vector2(
		Input.get_joy_axis(device, settings.stick_axis_x as JoyAxis),
		Input.get_joy_axis(device, settings.stick_axis_y as JoyAxis)
	)
	var analog: Vector2 = shape_stick(
		raw,
		settings.dead_zone_inner_percent,
		settings.dead_zone_outer_percent,
		settings.dead_zone_release_percent if _stick_out != Vector2i.ZERO else -1
	)
	var v: Vector2 = digital if digital != Vector2.ZERO else analog
	_stick_out = quantize_stick(v, _stick_out, settings.stick_step)
	return _stick_out


func _axis_strength(action: String) -> float:
	return 1.0 if Input.is_action_pressed(ACTION_PREFIX + action) else 0.0


## Quantises a shaped stick vector to multiples of [param step] (of 127) with one step of
## hysteresis against [param previous]: sensor noise around a level never flips the reported
## value, so a held stick produces identical input frames (and replays stay near 2 KB a
## minute, BUILD.md section 13). Each axis also has a band around zero: it leaves 0 only at half
## a step, and moving to the other side of zero with less than that reads 0, so noise on the
## axis a sideways stick is not pushing never flips between +step and -step. The dead zones stay
## where [method shape_stick] put them: the stronger axis reports its first step as soon as the
## stick leaves the inner dead zone, and exactly 127 (full) is reported only beyond the outer one.
static func quantize_stick(v: Vector2, previous: Vector2i, step: int) -> Vector2i:
	# Beyond the outer dead zone the shaped vector has length 1.
	var rim: bool = v.length_squared() >= 0.9999
	return Vector2i(
		_quantize_axis(v.x, previous.x, step, absf(v.x) >= absf(v.y), rim),
		_quantize_axis(v.y, previous.y, step, absf(v.y) >= absf(v.x), rim)
	)


static func _quantize_axis(a: float, previous: int, step: int, stronger: bool, rim: bool) -> int:
	var full: int = InputFrame.STICK_MAX
	var target: float = clampf(a, -1.0, 1.0) * float(full)
	if target == 0.0:
		return 0
	var dir: int = 1 if target > 0.0 else -1
	var half: float = float(step) * 0.5
	# Full only beyond the outer dead zone, where noise on the other axis may still shave the
	# value a little below 127.
	if rim and absf(target) >= float(full) - half:
		return full * dir
	if previous != 0 and signi(previous) == dir and absf(target - float(previous)) < float(step):
		return previous
	if absf(target) < half and not (previous == 0 and stronger):
		return 0
	# The largest level below full: 120 for a step of 8.
	var top: int = ((full - 1) / step) * step
	return clampi(roundi(absf(target) / float(step)) * step, step, top) * dir


## Radial dead zone with rescaling: below [param inner] percent reads 0, at or above
## [param outer] percent reads full, and the range between is stretched linearly so the stick
## loses no resolution (BUILD.md section 12: "default inner 12%, outer 95%, with radial scaling").
## A stick already out of the dead zone stays out until it falls to [param release] percent
## (pass -1 for a stick at rest), so one resting right on the edge does not flicker; between the
## two it reads the smallest non-zero value.
static func shape_stick(raw: Vector2, inner: int, outer: int, release: int = -1) -> Vector2:
	var magnitude: float = raw.length()
	var lo: float = float(inner) / 100.0
	var hi: float = float(outer) / 100.0
	var edge: float = lo if release < 0 else float(release) / 100.0
	if magnitude <= edge:
		return Vector2.ZERO
	var scaled: float = clampf((magnitude - lo) / (hi - lo), 0.000001, 1.0)
	return raw / magnitude * scaled
