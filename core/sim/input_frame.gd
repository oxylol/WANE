class_name InputFrame
extends RefCounted
## One tick of player input, as the core sees it (BUILD.md section 13, "Input"; ADR-0004).
##
## Buttons are a bitfield. [member held] is the state at the moment the tick was sampled;
## [member pressed] holds every rising edge since the previous tick, including a press and
## release that both happened between two ticks, so a tap shorter than a frame is never lost.
## The stick is fixed-point in [-[constant STICK_MAX], [constant STICK_MAX]] with +y pointing
## down, already dead-zoned and remapped by the input layer.

const JUMP: int = 1
const ATTACK: int = 2
const DASH: int = 4
const SPELL: int = 8
const MEND: int = 16
const VESSEL: int = 32
const TOSS: int = 64
## Every button bit, in the order of [constant BUTTON_NAMES].
const BUTTONS: Array[int] = [JUMP, ATTACK, DASH, SPELL, MEND, VESSEL, TOSS]
const BUTTON_NAMES: Array[String] = ["JUMP", "ATTACK", "DASH", "SPELL", "MEND", "VESSEL", "TOSS"]
const BUTTON_ABBR: Array[String] = ["Jmp", "Atk", "Dsh", "Spl", "Mnd", "Ves", "Tos"]
const BUTTON_MASK: int = 127
const STICK_MAX: int = 127

var held: int = 0
var pressed: int = 0
var stick_x: int = 0
var stick_y: int = 0


static func make(held_bits: int, pressed_bits: int, x: int, y: int) -> InputFrame:
	var f := InputFrame.new()
	f.held = held_bits & BUTTON_MASK
	f.pressed = pressed_bits & BUTTON_MASK
	f.stick_x = clampi(x, -STICK_MAX, STICK_MAX)
	f.stick_y = clampi(y, -STICK_MAX, STICK_MAX)
	return f


## Inverse of [method pack].
static func unpack(packed: int) -> InputFrame:
	return make(
		packed & BUTTON_MASK,
		(packed >> 7) & BUTTON_MASK,
		((packed >> 14) & 0xFF) - STICK_MAX,
		((packed >> 22) & 0xFF) - STICK_MAX
	)


## Name of a single button bit, for logs and the F3 overlay.
static func button_name(bit: int) -> String:
	var i: int = BUTTONS.find(bit)
	return BUTTON_NAMES[i] if i >= 0 else "?"


func is_held(bit: int) -> bool:
	return held & bit != 0


func was_pressed(bit: int) -> bool:
	return pressed & bit != 0


## -1, 0 or 1 for the horizontal stick against [param threshold].
func dir_x(threshold: int) -> int:
	if stick_x >= threshold:
		return 1
	if stick_x <= -threshold:
		return -1
	return 0


## -1 (up), 0 or 1 (down) for the vertical stick against [param threshold].
func dir_y(threshold: int) -> int:
	if stick_y >= threshold:
		return 1
	if stick_y <= -threshold:
		return -1
	return 0


## All of this frame in one non-negative 30-bit integer: held (7), pressed (7), x (8), y (8).
func pack() -> int:
	return held | (pressed << 7) | ((stick_x + STICK_MAX) << 14) | ((stick_y + STICK_MAX) << 22)


func copy() -> InputFrame:
	return make(held, pressed, stick_x, stick_y)


func equals(other: InputFrame) -> bool:
	return pack() == other.pack()


## Compact human-readable form, e.g. "R Jmp+ Atk" (+ marks a press this tick).
func describe() -> String:
	var parts: PackedStringArray = []
	var dx: int = dir_x(STICK_MAX / 2)
	var dy: int = dir_y(STICK_MAX / 2)
	if dy < 0:
		parts.append("U")
	elif dy > 0:
		parts.append("D")
	if dx < 0:
		parts.append("L")
	elif dx > 0:
		parts.append("R")
	for i: int in range(BUTTONS.size()):
		var bit: int = BUTTONS[i]
		if held & bit != 0 or pressed & bit != 0:
			var label: String = BUTTON_ABBR[i]
			if pressed & bit != 0:
				label += "+"
			parts.append(label)
	return " ".join(parts) if not parts.is_empty() else "-"
