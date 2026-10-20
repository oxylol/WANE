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
## Owed time within this of a tick boundary counts as on it when a slow motion ends (the frames
## of a slow sum to whole ticks only up to rounding).
const SLOW_END_SECONDS: float = 0.0000001

@export var input_layer: InputLayer

var sim: Simulation
var recorder: ReplayRecorder
## 0..1: where real time lies between the previous tick's state (0) and the newest (1); views
## draw lerp(previous, newest, alpha).
var alpha: float = 1.0
## Frame-stepper: while paused, ticks only advance through [method step_once].
var paused: bool = false
## Slow motion (BUILD.md section 6, hit feedback): below 1 while [method slow] is running, the
## share of real time each tick gets. The simulation and its replay are unchanged; only how fast
## the ticks come is.
var time_scale: float = 1.0
## Microseconds the last [method Simulation.step] took (the frame bench reads it: docs/adr/0020).
var last_step_us: int = 0

## Real time owed to the simulation, in seconds; at most zero after stepping (a tick runs at the
## start of its period).
var _accumulator: float = 0.0
## Real time rounded away while locked, to be paid back in whole ticks.
var _drift: float = 0.0
## Slow ticks still to be stepped (see [method slow]).
var _slow_left: int = 0
## A slow asked for during the player's hitstop, waiting for the hitstop to end (see
## [method slow]).
var _held_scale: float = 1.0
var _held_ticks: int = 0
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
	time_scale = 1.0
	_slow_left = 0
	_held_ticks = 0
	if input_layer != null:
		input_layer.reset()


## Runs the next [param ticks] ticks at [param scale] of real speed ("slow-motion 0.8x for 8 f on
## kill", "time to 0.5x for 6 f" on a parry). A slow that starts while another runs keeps the
## slower scale and the longer remainder. The slow ends when the last slow tick's period does,
## so on a 60 Hz display a whole number of slowed frames (8 / 0.8 = 10, 6 / 0.5 = 12) ends
## exactly on a tick and the frames after it draw the newest state again.
##
## Slow motion starts after the hitstop: a slow asked for while the player is frozen is held
## until the freeze ends and then runs its ticks, so the 0.5x of a parry and the 0.8x of a Charged
## kill are seen as slow motion and not spent inside the freeze, where nothing moves (task 6
## review, M2; docs/adr/0013).
func slow(scale: float, ticks: int) -> void:
	if ticks <= 0 or scale <= 0.0 or scale >= 1.0:
		return
	if sim != null and sim.player != null and sim.player.freeze > 0:
		_held_scale = minf(_held_scale, scale) if _held_ticks > 0 else scale
		_held_ticks = maxi(_held_ticks, ticks)
		return
	_start_slow(scale, ticks)


func _start_slow(scale: float, ticks: int) -> void:
	time_scale = minf(time_scale, scale) if slowing() else scale
	_slow_left = maxi(_slow_left, ticks)


## True from [method slow] until the last slow tick's period has ended.
func slowing() -> bool:
	return time_scale < 1.0


func _process(delta: float) -> void:
	if sim == null or paused:
		return
	var ticks: int = _whole_ticks(delta)
	_update_lock(ticks > 0)
	if slowing():
		_run_slow(delta, ticks)
		return
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


## One frame of slow motion: owed time grows by the frame's time times [member time_scale] and
## views draw interpolated, so a slowed tick is drawn over several frames. Locked, the frame counts
## as its whole number of ticks, as in [method _process], and what that rounds away is drift.
func _run_slow(delta: float, ticks: int) -> void:
	var frame_time: float = delta
	if _locked:
		if ticks == 0:
			ticks = roundi(delta / TICK_SECONDS)
		_drift += delta - ticks * TICK_SECONDS
		frame_time = ticks * TICK_SECONDS
	_accumulator += frame_time * time_scale
	_run_owed_ticks()
	if _slow_left == 0 and _accumulator > -SLOW_END_SECONDS:
		# The last slow tick's period has ended: real speed again.
		time_scale = 1.0
	if not slowing() and _locked:
		# A slow whose frames were not a whole number of ticks leaves a phase; it is repaid as
		# drift, in whole ticks.
		_drift += _accumulator
		_accumulator = 0.0
		alpha = 1.0
		return
	alpha = clampf(1.0 + _accumulator / TICK_SECONDS, 0.0, 1.0)


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


## Pauses or resumes the frame-stepper. Paused, the views draw the newest tick, the one the F3
## overlay shows, not a frame between ticks (task 5 review 2, L1: at 144 Hz a pause mid-dash drew
## the player 9 u behind its boxes until the first step).
##
## Resuming owes nothing: the phase left when it paused (up to a tick of negative owed time) is
## dropped, so the first frame after it steps a tick at once and draws forward from the newest
## state, never a fraction of a tick back toward the one before (presentation review r3, L2: at
## 144 Hz the player was drawn up to 0.6 of a tick's motion backward on the resume frame).
func set_paused(on: bool) -> void:
	var was: bool = paused
	paused = on
	if on:
		alpha = 1.0
	elif was:
		_accumulator = 0.0


## Polls input and advances the simulation by exactly one tick.
func step_once() -> void:
	if _slow_left > 0:
		_slow_left -= 1
	elif slowing():
		# A tick after the last slow one: its period runs at real speed.
		time_scale = 1.0
	var frame: InputFrame = input_layer.poll() if input_layer != null else InputFrame.new()
	var began: int = Time.get_ticks_usec()
	sim.step(frame)
	last_step_us = Time.get_ticks_usec() - began
	recorder.record(frame)
	if _held_ticks > 0 and (sim.player == null or sim.player.freeze == 0):
		_start_slow(_held_scale, _held_ticks)
		_held_ticks = 0
	if _slow_left > 0 and sim.player != null and sim.player.freeze > 0:
		# A slow already running when a hitstop starts (a second parry inside the first one's slow
		# motion) waits for it, like one asked for inside the hitstop: its remaining ticks are
		# not spent where nothing moves (presentation review r2, M1).
		_held_scale = minf(_held_scale, time_scale) if _held_ticks > 0 else time_scale
		_held_ticks = maxi(_held_ticks, _slow_left)
		_slow_left = 0
		time_scale = 1.0
	if paused:
		alpha = 1.0
	ticked.emit()


## Writes the session so far to [param path] (a .wrp replay).
func save_replay(path: String) -> Error:
	if sim == null:
		return ERR_UNCONFIGURED
	return ReplayFiles.save(recorder.finish(sim), path)
