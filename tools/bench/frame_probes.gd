class_name FrameProbes
extends RefCounted
## Reads the presentation's script time directly (BUILD.md s13 Frame budget; docs/adr/0020
## Decision 18). Two probe nodes bracket every other node's _process in a frame: [constant
## OPEN_PRIORITY] runs before and [constant CLOSE_PRIORITY] after any priority the game uses
## (input -1000, the driver -900). The close probe also queues a call for the end of the frame:
## the engine flushes its message queue in order after the nodes' _process, so every _draw
## callback a node's _process asked for (queue_redraw) and every deferred call made before the
## close probe has run when that call does. (The renderer's own frame_pre_draw signal would say
## the same in a window, but a headless run never draws, so it never fires.)
##
##   process_us = close probe - open probe            (every node's _process)
##   draw_us    = end of the queue - close probe      (every _draw callback and deferred call)
##
## Neither span holds the simulation step, the engine's housekeeping or the renderer, so a cheaper
## step cannot move them. (The figure this replaces was the
## frame's wall time less the step: it rose by a millisecond when the step fell by three and a
## half, because wall time has a floor of its own.)

const OPEN_PRIORITY: int = -1000000
const CLOSE_PRIORITY: int = 1000000

## Microseconds of the last frame [method take] read.
var process_us: int = 0
var draw_us: int = 0

var _open: Stamp
var _close: Stamp
var _flushed_at: int = 0
var _attached: bool = false


## A node that records when its _process ran and, if [member queue_end] is set, when the frame's
## message queue reached a call it queued then.
class Stamp:
	extends Node
	signal flushed
	var at: int = 0
	var queue_end: bool = false

	func _process(_delta: float) -> void:
		at = Time.get_ticks_usec()
		if queue_end:
			flushed.emit.call_deferred()


## Adds the probes to [param parent] and listens for the draw. Detach before freeing [param parent].
func attach(parent: Node) -> void:
	if _attached:
		return
	_open = Stamp.new()
	_open.process_priority = OPEN_PRIORITY
	_close = Stamp.new()
	_close.process_priority = CLOSE_PRIORITY
	_close.queue_end = true
	_close.flushed.connect(_on_flushed)
	parent.add_child(_open)
	parent.add_child(_close)
	_attached = true


func detach() -> void:
	if not _attached:
		return
	_open.queue_free()
	_close.queue_free()
	_attached = false


## Reads the last frame's two spans and clears the probes. False when a probe did not run since the
## last read (the figures are then not set: a frame must not read as zero cost).
func take() -> bool:
	var ok: bool = _attached and _open.at > 0 and _close.at >= _open.at and _flushed_at >= _close.at
	if ok:
		process_us = _close.at - _open.at
		draw_us = _flushed_at - _close.at
	if _attached:
		_open.at = 0
		_close.at = 0
	_flushed_at = 0
	return ok


func _on_flushed() -> void:
	_flushed_at = Time.get_ticks_usec()
