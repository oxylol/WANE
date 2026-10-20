extends GdUnitTestSuite
## The frame bench's direct reading of the presentation's script time (tools/bench/frame_probes.gd;
## BUILD.md s13 Frame budget; docs/adr/0020 Decision 17): the time in the nodes' _process and in
## the _draw callbacks, not the frame's wall time less the simulation step.

const FRAMES: int = 6
const SLOW_BEFORE_US: int = 20000
const INSIDE_US: int = 3000
const DRAW_US: int = 4000


## Busy-waits [member us] microseconds in _process at [member process_priority].
class ProcessWait:
	extends Node
	var us: int = 0

	func _process(_delta: float) -> void:
		var until: int = Time.get_ticks_usec() + us
		while Time.get_ticks_usec() < until:
			pass


## Busy-waits [member us] microseconds in _draw, every frame.
class DrawWait:
	extends Node2D
	var us: int = 0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var until: int = Time.get_ticks_usec() + us
		while Time.get_ticks_usec() < until:
			pass


func _wait_node(us: int, priority: int) -> ProcessWait:
	var w: ProcessWait = auto_free(ProcessWait.new())
	w.us = us
	w.process_priority = priority
	add_child(w)
	return w


## Plays [constant FRAMES] frames and returns the least reading of each span: the work is fixed,
## so the least is the code's cost and the rest is the machine.
func _play(probes: FrameProbes) -> Vector2i:
	var least_process: int = 1 << 30
	var least_draw: int = 1 << 30
	await get_tree().process_frame
	for i: int in range(FRAMES):
		await get_tree().process_frame
		assert_bool(probes.take()).is_true()
		least_process = mini(least_process, probes.process_us)
		least_draw = mini(least_draw, probes.draw_us)
	return Vector2i(least_process, least_draw)


func test_the_process_span_holds_the_nodes_between_the_probes_and_nothing_else() -> void:
	var probes := FrameProbes.new()
	probes.attach(self)
	_wait_node(SLOW_BEFORE_US, FrameProbes.OPEN_PRIORITY - 1)
	_wait_node(INSIDE_US, 0)
	var least: Vector2i = await _play(probes)
	probes.detach()
	assert_int(least.x).is_greater_equal(INSIDE_US)
	assert_int(least.x).is_less(SLOW_BEFORE_US)


func test_the_draw_span_holds_the_draw_callbacks() -> void:
	var probes := FrameProbes.new()
	probes.attach(self)
	var d: DrawWait = auto_free(DrawWait.new())
	d.us = DRAW_US
	add_child(d)
	var least: Vector2i = await _play(probes)
	probes.detach()
	assert_int(least.y).is_greater_equal(DRAW_US)


func test_a_span_is_the_same_whatever_the_simulation_step_costs() -> void:
	# What the old reading (wall time less the step) got wrong: a step that falls or rises is
	# outside both spans. A 12 ms wait before the open probe stands for a step of 12 ms.
	var probes := FrameProbes.new()
	probes.attach(self)
	var step: ProcessWait = _wait_node(0, FrameProbes.OPEN_PRIORITY - 1)
	_wait_node(INSIDE_US, 0)
	var cheap: Vector2i = await _play(probes)
	step.us = 12000
	var dear: Vector2i = await _play(probes)
	probes.detach()
	assert_int(absi(dear.x - cheap.x)).is_less(2000)
	assert_int(absi(dear.y - cheap.y)).is_less(2000)


func test_a_probe_that_did_not_run_is_reported_not_read_as_zero() -> void:
	var probes := FrameProbes.new()
	assert_bool(probes.take()).is_false()
	probes.attach(self)
	assert_bool(probes.take()).is_false()
	probes.detach()
