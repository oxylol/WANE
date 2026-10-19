class_name InputHistory
extends RefCounted
## The F3 overlay's input history (BUILD.md section 5: "A debug overlay (F3) shows hitboxes,
## state, frame counters and input history"): the inputs the simulation consumed, as runs of
## identical ticks, newest first. A run is a stick direction in numpad notation (5 neutral, 6
## right, 8 up, 2 down, 9 up-right), read in the 8 equal sectors the dash and the toss read
## ([method PlayerInput.dir8]; a strike reads 4: docs/adr/0012), the buttons held, the buttons
## newly pressed on its first tick, and its length in ticks. A new press always starts a new run,
## so a re-press while held shows, and a tap (pressed and let go within a tick) is a run of its
## own, never merged with the ticks after it.

## How many runs are kept.
const KEEP: int = 24


class Run:
	var dir: int = 5
	var held: int = 0
	var pressed: int = 0
	var ticks: int = 1
	var first_tick: int = 0


## Newest first.
var runs: Array[Run] = []
## The stick deflection that counts as a direction (the player's own threshold).
var threshold: int = 64


func _init(p_threshold: int = 64) -> void:
	threshold = p_threshold


## Records the input of tick [param tick].
func push(frame: InputFrame, tick: int) -> void:
	var d: Vector2i = PlayerInput.dir8(frame.stick_x, frame.stick_y, threshold)
	var dir: int = numpad(d.x, d.y)
	if not runs.is_empty() and frame.pressed == 0:
		var last: Run = runs[0]
		var tapped: bool = last.pressed & ~last.held != 0
		if last.dir == dir and last.held == frame.held and not tapped:
			last.ticks += 1
			return
	var run := Run.new()
	run.dir = dir
	run.held = frame.held
	run.pressed = frame.pressed
	run.first_tick = tick
	runs.push_front(run)
	if runs.size() > KEEP:
		runs.resize(KEEP)


func clear() -> void:
	runs.clear()


## Numpad notation for a direction: 7 8 9 / 4 5 6 / 1 2 3, with -1 y up.
static func numpad(dx: int, dy: int) -> int:
	return 5 + dx - 3 * dy


## "6 Jmp* Atk 12": direction, buttons held (a star marks the ones pressed on the run's first
## tick), and the length in ticks.
static func describe(run: Run) -> String:
	var parts: PackedStringArray = [str(run.dir)]
	for i: int in range(InputFrame.BUTTONS.size()):
		var bit: int = InputFrame.BUTTONS[i]
		if run.held & bit != 0 or run.pressed & bit != 0:
			parts.append(InputFrame.BUTTON_ABBR[i] + ("*" if run.pressed & bit != 0 else ""))
	parts.append(str(run.ticks))
	return " ".join(parts)
