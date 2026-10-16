class_name SimDriver
extends Node
## The fixed-step driver (BUILD.md section 13: "One step(input: InputFrame) per tick"; CLAUDE.md
## rule 1). Runs the core at exactly 60 Hz whatever the display rate, polls input at the start of
## every tick, records every tick for replay, and exposes the interpolation factor views use to
## draw between the last two simulation states.
##
## A tick is stepped at the start of its 1/60 s period, so the newest state is never behind real
## time: at 60 Hz every frame steps once and draws that tick's state ([member alpha] = 1, no added
## latency); at higher refresh rates frames between ticks draw the interpolated state that
## matches real time. This node contains no gameplay: it only decides when to call
## [method Simulation.step].

signal ticked

const TICK_SECONDS: float = 1.0 / 60.0
## A frame time within this many seconds of a whole number of ticks (one, or two to four after a
## hitch) looks like a fixed-refresh vsync frame.
const SNAP_SECONDS: float = 0.0006
## After this many such frames in a row the driver locks to the display: each frame then counts
## as a whole number of ticks, so a 60 Hz display with vsync jitter steps exactly once per frame
## and always draws the newest state. The time this rounds away is carried as drift and repaid a
## whole tick at a time, so a 59.94 or 62 Hz display still runs at real speed. Two seconds is far
## longer than chance allows on a variable-refresh display, whose frame times only sometimes
## land near a tick.
const LOCK_FRAMES: int = 120
## When a lock is lost to a burst of slow frames (a stutter: every miss among the last
## [constant BURST_FRAMES] of an otherwise clean window), half a second of vsync-like frames locks
## it again; misses scattered across the window mean the display really changed, and a relock
## needs the full [constant LOCK_FRAMES].
const RELOCK_FRAMES: int = 30
const BURST_FRAMES: int = 10
## A locked driver unlocks once more than [constant UNLOCK_MISSES] of the last
## [constant UNLOCK_WINDOW] frames did not look like vsync frames (the window moved to a 144 Hz
## display, or variable refresh was switched on); a lone hitch or stray frame does not unlock it,
## and counts as the nearest whole number of ticks. Unlocked, frame times are counted exactly and
## drawn interpolated (120 Hz, 144 Hz, variable refresh).
const UNLOCK_WINDOW: int = 60
const UNLOCK_MISSES: int = 6
## Catch-up limit after a hitch: beyond this the simulation slows down rather than spiralling.
const MAX_STEPS_PER_FRAME: int = 4

@export var input_layer: InputLayer

var sim: Simulation
var recorder: ReplayRecorder
## 0..1: where real time lies between the previous tick's state (0) and the newest (1); views
## draw lerp(previous, newest, alpha).
var alpha: float = 1.0
## Frame-stepper: while paused, ticks only advance through [method step_once].
var paused: bool = false

## Real time owed to the simulation, in seconds; at most zero after stepping (a tick runs at the
## start of its period).
var _accumulator: float = 0.0
## Real time rounded away while locked, to be paid back in whole ticks.
var _drift: float = 0.0
## Locked to a fixed-refresh display (see [constant LOCK_FRAMES]). This describes the display,
## so it survives [method start].
var _locked: bool = false
## Vsync-like frames in a row while unlocked.
var _streak: int = 0
## The last unlock came from a stutter burst (see [constant RELOCK_FRAMES]).
var _fast_relock: bool = false
## While locked: which of the last [constant UNLOCK_WINDOW] frames were not vsync-like (1), and
## how many.
var _misses: PackedByteArray = PackedByteArray()
var _miss_count: int = 0
var _miss_at: int = 0


func _ready() -> void:
	process_priority = -900


## Starts a new session from [param scenario], replacing any running one.
func start(scenario: Scenario) -> void:
	sim = Simulation.new(scenario)
	recorder = ReplayRecorder.new(scenario)
	_accumulator = 0.0
	_drift = 0.0
	alpha = 1.0
	if input_layer != null:
		input_layer.reset()


func _process(delta: float) -> void:
	if sim == null or paused:
		return
	var ticks: int = _whole_ticks(delta)
	_update_lock(ticks > 0)
	if not _locked:
		_accumulator += delta
		_run_owed_ticks()
		alpha = clampf(1.0 + _accumulator / TICK_SECONDS, 0.0, 1.0)
		return
	# Locked: the frame is a whole number of ticks (a stray frame, the nearest), and what that
	# rounds away is repaid only in whole ticks (one frame steps an extra time or one fewer),
	# never as a fraction, so every frame ends exactly on a tick and draws the newest state.
	if ticks == 0:
		ticks = roundi(delta / TICK_SECONDS)
	_drift += delta - ticks * TICK_SECONDS
	var dt: float = ticks * TICK_SECONDS
	if _drift >= TICK_SECONDS:
		_drift -= TICK_SECONDS
		dt += TICK_SECONDS
	elif _drift <= -TICK_SECONDS:
		_drift += TICK_SECONDS
		dt -= TICK_SECONDS
	_accumulator += dt
	_run_owed_ticks()
	_accumulator = 0.0
	alpha = 1.0


func _update_lock(vsync_like: bool) -> void:
	if not _locked:
		_streak = _streak + 1 if vsync_like else 0
		if _streak >= (RELOCK_FRAMES if _fast_relock else LOCK_FRAMES):
			# The phase left by interpolated frames moves into the drift, to be repaid in whole
			# ticks.
			_locked = true
			_streak = 0
			_misses.resize(UNLOCK_WINDOW)
			_misses.fill(0)
			_miss_count = 0
			_miss_at = 0
			_drift += _accumulator
			_accumulator = 0.0
		return
	var miss: int = 0 if vsync_like else 1
	_miss_count += miss - _misses[_miss_at]
	_misses[_miss_at] = miss
	_miss_at = (_miss_at + 1) % UNLOCK_WINDOW
	if _miss_count > UNLOCK_MISSES:
		# The drift owed becomes ordinary owed time again.
		_locked = false
		_fast_relock = _misses_before_burst() == 0
		_accumulator += _drift
		_drift = 0.0


## Misses in the unlock window older than its last [constant BURST_FRAMES] frames.
func _misses_before_burst() -> int:
	var count: int = 0
	for age: int in range(BURST_FRAMES, UNLOCK_WINDOW):
		count += _misses[(_miss_at - 1 - age + UNLOCK_WINDOW * 2) % UNLOCK_WINDOW]
	return count


## True while the driver treats the display as fixed-refresh (for tests and the F3 overlay).
func is_locked() -> bool:
	return _locked


## The number of ticks (1 to [constant MAX_STEPS_PER_FRAME]) [param delta] is within
## [constant SNAP_SECONDS] of, or 0.
func _whole_ticks(delta: float) -> int:
	for n: int in range(1, MAX_STEPS_PER_FRAME + 1):
		if absf(delta - n * TICK_SECONDS) < SNAP_SECONDS:
			return n
	return 0


## Steps every tick whose period has started, up to the catch-up limit; time beyond the limit is
## dropped (the game slows down instead of spiralling).
func _run_owed_ticks() -> void:
	var steps: int = 0
	while _accumulator > 0.0000001 and steps < MAX_STEPS_PER_FRAME:
		step_once()
		_accumulator -= TICK_SECONDS
		steps += 1
	if _accumulator > 0.0:
		_accumulator = 0.0


## Polls input and advances the simulation by exactly one tick.
func step_once() -> void:
	var frame: InputFrame = input_layer.poll() if input_layer != null else InputFrame.new()
	sim.step(frame)
	recorder.record(frame)
	if paused:
		alpha = 1.0
	ticked.emit()


## Writes the session so far to [param path] (a .wrp replay).
func save_replay(path: String) -> Error:
	if sim == null:
		return ERR_UNCONFIGURED
	return ReplayFiles.save(recorder.finish(sim), path)
