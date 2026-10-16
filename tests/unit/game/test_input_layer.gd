extends GdUnitTestSuite
## Input layer: dead zones (BUILD.md section 12) and bindings.


func test_inner_dead_zone_reads_zero() -> void:
	assert_bool(InputLayer.shape_stick(Vector2(0.11, 0.0), 12, 95) == Vector2.ZERO).is_true()
	assert_bool(InputLayer.shape_stick(Vector2(0.08, 0.08), 12, 95) == Vector2.ZERO).is_true()


func test_outer_dead_zone_reads_full() -> void:
	var v: Vector2 = InputLayer.shape_stick(Vector2(0.0, -0.96), 12, 95)
	assert_float(v.y).is_equal_approx(-1.0, 0.0001)
	assert_float(v.x).is_equal_approx(0.0, 0.0001)


func test_radial_rescale_keeps_direction_and_is_continuous() -> void:
	var raw := Vector2(0.3, 0.4)  # magnitude 0.5
	var v: Vector2 = InputLayer.shape_stick(raw, 12, 95)
	assert_float(v.angle()).is_equal_approx(raw.angle(), 0.0001)
	assert_float(v.length()).is_equal_approx((0.5 - 0.12) / (0.95 - 0.12), 0.0001)
	var just_outside: Vector2 = InputLayer.shape_stick(Vector2(0.1201, 0.0), 12, 95)
	assert_float(just_outside.length()).is_less(0.001)


func test_default_settings_validate_and_bind_every_action() -> void:
	var settings: InputSettings = load(InputLayer.SETTINGS_PATH) as InputSettings
	assert_array(Array(settings.validate())).is_empty()
	assert_int(settings.dead_zone_inner_percent).is_equal(12)
	assert_int(settings.dead_zone_outer_percent).is_equal(95)
	InputLayer.install_actions(settings)
	for action: String in InputSettings.ACTIONS:
		assert_bool(InputMap.has_action(InputLayer.ACTION_PREFIX + action)).is_true()
		assert_int(InputMap.action_get_events(InputLayer.ACTION_PREFIX + action).size()).is_greater(
			0
		)


func test_bad_bindings_are_reported() -> void:
	var s := InputSettings.new()
	s.bindings = PackedStringArray(["jump=key:NotAKey", "fly=key:Z", "attack"])
	var errors: PackedStringArray = s.validate()
	var text: String = "\n".join(errors)
	assert_str(text).contains("bad event 'key:NotAKey'")
	assert_str(text).contains("unknown action 'fly'")
	assert_str(text).contains("has no '='")
	assert_str(text).contains("no binding for 'dash'")


func test_poll_latches_a_press_released_before_the_tick() -> void:
	var layer: InputLayer = auto_free(InputLayer.new())
	add_child(layer)
	layer.poll()
	_send_action("attack", true)
	_send_action("attack", false)
	var frame: InputFrame = layer.poll()
	assert_int(frame.pressed & InputFrame.ATTACK).is_equal(InputFrame.ATTACK)
	assert_int(frame.held & InputFrame.ATTACK).is_equal(0)
	assert_int(layer.poll().pressed).is_equal(0)


## Feeds an event through Input the way the engine does, so the layer sees it in _input with
## Input's action state already updated.
func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _send_action(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = InputLayer.ACTION_PREFIX + action
	e.pressed = pressed
	_send(e)


func test_a_held_trigger_presses_once() -> void:
	# Godot reports every trigger event above the threshold as "pressed"; only the crossing may
	# latch a press, or a held trigger would re-dash whenever the cooldown ends.
	var layer: InputLayer = auto_free(InputLayer.new())
	add_child(layer)
	layer.poll()
	var presses: int = 0
	for value: float in [0.0, 0.6, 0.72, 0.71, 0.73, 0.72, 0.74, 0.0]:
		var motion := InputEventJoypadMotion.new()
		motion.axis = JOY_AXIS_TRIGGER_RIGHT
		motion.axis_value = value
		_send(motion)
		if layer.poll().pressed & InputFrame.DASH != 0:
			presses += 1
	assert_int(presses).is_equal(1)


func test_stick_quantisation_ignores_noise_and_snaps_full_deflection() -> void:
	var out := Vector2i.ZERO
	out = InputLayer.quantize_stick(Vector2(0.5, 0.0), out, 8)
	var settled: Vector2i = out
	for noise: float in [0.004, -0.006, 0.008, -0.003, 0.007]:
		out = InputLayer.quantize_stick(Vector2(0.5 + noise, 0.0), out, 8)
		assert_bool(out == settled).is_true()
	assert_int(InputLayer.quantize_stick(Vector2(1.0, -1.0), out, 8).x).is_equal(127)
	assert_int(InputLayer.quantize_stick(Vector2(1.0, -1.0), out, 8).y).is_equal(-127)
	# Just short of full is the top level below it, not full.
	assert_int(InputLayer.quantize_stick(Vector2(0.98, 0.0), out, 8).x).is_equal(120)
	assert_int(InputLayer.quantize_stick(Vector2(0.0, 0.0), Vector2i(64, 0), 8).x).is_equal(0)


func test_trigger_near_the_threshold_does_not_flicker() -> void:
	var layer: InputLayer = auto_free(InputLayer.new())
	add_child(layer)
	layer.poll()
	var presses: int = 0
	var releases: int = 0
	var was_held: bool = false
	for value: float in [0.51, 0.49, 0.51, 0.49, 0.52, 0.48, 0.51, 0.45, 0.39, 0.51]:
		var motion := InputEventJoypadMotion.new()
		motion.axis = JOY_AXIS_TRIGGER_LEFT
		motion.axis_value = value
		_send(motion)
		var frame: InputFrame = layer.poll()
		presses += 1 if frame.pressed & InputFrame.MEND != 0 else 0
		var held: bool = frame.held & InputFrame.MEND != 0
		releases += 1 if was_held and not held else 0
		was_held = held
	# Down at 0.51, held through the wobble, up at 0.39 (below 0.40), down again at 0.51.
	assert_int(presses).is_equal(2)
	assert_int(releases).is_equal(1)
	var rest := InputEventJoypadMotion.new()
	rest.axis = JOY_AXIS_TRIGGER_LEFT
	rest.axis_value = 0.0
	_send(rest)
	layer.poll()


func test_quantisation_noise_near_a_step_midpoint() -> void:
	# A target of 60 (between levels 56 and 64) with +-3 units of noise must hold one level.
	var out: Vector2i = InputLayer.quantize_stick(Vector2(60.0 / 127.0, 0.0), Vector2i.ZERO, 8)
	var settled: int = out.x
	for noise: float in [3.0, -3.0, 2.5, -2.8, 3.0, -3.0]:
		out = InputLayer.quantize_stick(Vector2((60.0 + noise) / 127.0, 0.0), out, 8)
		assert_int(out.x).is_equal(settled)
	# Full deflection is reported the moment the shaped stick reaches it, even from the level
	# just below; anything short of it stays on that level.
	var near_full: Vector2i = InputLayer.quantize_stick(
		Vector2(125.0 / 127.0, 0.0), Vector2i(120, 0), 8
	)
	assert_int(near_full.x).is_equal(120)
	assert_int(InputLayer.quantize_stick(Vector2(1.0, 0.0), near_full, 8).x).is_equal(127)


func test_dead_zones_survive_quantisation() -> void:
	# BUILD.md section 12: inner 12%, outer 95%. The quantiser must not move either edge.
	var cases: Array[Vector2] = [
		Vector2(0.119, 0.0),
		Vector2(0.125, 8.0),
		Vector2(0.5, 56.0),
		Vector2(0.949, 120.0),
		Vector2(0.95, 127.0),
	]
	for c: Vector2 in cases:
		var shaped: Vector2 = InputLayer.shape_stick(Vector2(c.x, 0.0), 12, 95)
		var q: Vector2i = InputLayer.quantize_stick(shaped, Vector2i.ZERO, 8)
		assert_int(q.x).override_failure_message("raw %f" % c.x).is_equal(int(c.y))
		var neg: Vector2i = InputLayer.quantize_stick(-shaped, Vector2i.ZERO, 8)
		assert_int(neg.x).is_equal(-int(c.y))


func test_release_while_the_tree_is_paused_does_not_stick() -> void:
	var layer: InputLayer = auto_free(InputLayer.new())
	add_child(layer)
	_send_action("jump", true)
	assert_int(layer.poll().pressed & InputFrame.JUMP).is_equal(InputFrame.JUMP)
	get_tree().paused = true
	_send_action("jump", false)
	get_tree().paused = false
	assert_int(layer.poll().held & InputFrame.JUMP).is_equal(0)
	_send_action("jump", true)
	assert_int(layer.poll().pressed & InputFrame.JUMP).is_equal(InputFrame.JUMP)
	_send_action("jump", false)
	layer.poll()


func test_a_release_another_node_consumed_does_not_stick() -> void:
	var layer: InputLayer = auto_free(InputLayer.new())
	add_child(layer)
	_send_action("attack", true)
	layer.poll()
	# Added after the layer, so it sees events first; it swallows the release.
	var swallower: Swallower = auto_free(Swallower.new())
	add_child(swallower)
	_send_action("attack", false)
	swallower.queue_free()
	assert_int(swallower.swallowed).is_equal(1)
	assert_int(layer.poll().held & InputFrame.ATTACK).is_equal(0)
	_send_action("attack", true)
	assert_int(layer.poll().pressed & InputFrame.ATTACK).is_equal(InputFrame.ATTACK)
	_send_action("attack", false)
	layer.poll()


func test_a_press_made_in_a_pause_menu_is_not_a_gameplay_press() -> void:
	var layer: InputLayer = auto_free(InputLayer.new())
	add_child(layer)
	layer.poll()
	get_tree().paused = true
	_send_action("jump", true)
	get_tree().paused = false
	# Still held when play resumes, but it was pressed in the menu: no jump.
	var frame: InputFrame = layer.poll()
	assert_int(frame.held & InputFrame.JUMP).is_equal(InputFrame.JUMP)
	assert_int(frame.pressed & InputFrame.JUMP).is_equal(0)
	_send_action("jump", false)
	layer.poll()
	_send_action("jump", true)
	assert_int(layer.poll().pressed & InputFrame.JUMP).is_equal(InputFrame.JUMP)
	_send_action("jump", false)
	layer.poll()


## Consumes attack releases before the input layer sees them.
class Swallower:
	extends Node
	var swallowed: int = 0

	func _input(event: InputEvent) -> void:
		if event.is_action_released(InputLayer.ACTION_PREFIX + "attack"):
			swallowed += 1
			get_viewport().set_input_as_handled()


func test_settings_ranges_are_validated() -> void:
	var s: InputSettings = (load(InputLayer.SETTINGS_PATH) as InputSettings).duplicate()
	s.stick_step = 0
	s.trigger_press_percent = 0
	var text: String = "\n".join(s.validate())
	assert_str(text).contains("stick_step")
	assert_str(text).contains("trigger_press_percent")


func test_noise_on_the_idle_axis_of_a_sideways_stick_never_flips() -> void:
	# Held fully right, then half right, with +-1% raw noise on the vertical axis for a minute:
	# the vertical value never leaves 0, so every frame is identical.
	var rng: Rng = Rng.seeded(11, 0)
	for x: float in [1.0, 0.6]:
		var out := Vector2i.ZERO
		var changes: int = 0
		var last := Vector2i(999, 999)
		for _i: int in range(3600):
			var noise: float = float(rng.between(-100, 100)) / 10000.0
			var shaped: Vector2 = InputLayer.shape_stick(Vector2(x, noise), 12, 95)
			out = InputLayer.quantize_stick(shaped, out, 8)
			if out != last:
				changes += 1
				last = out
		assert_int(changes).override_failure_message("x %f" % x).is_equal(1)
		assert_int(out.y).is_equal(0)


func test_a_deliberate_vertical_push_still_registers_and_reverses_at_once() -> void:
	var out: Vector2i = InputLayer.quantize_stick(Vector2(0.0, -1.0), Vector2i.ZERO, 8)
	assert_int(out.y).is_equal(-127)
	# A flick to the other side reads the new side on the same frame, not via a frame of 0.
	out = InputLayer.quantize_stick(Vector2(0.0, 1.0), out, 8)
	assert_int(out.y).is_equal(127)
	out = InputLayer.quantize_stick(Vector2(0.0, 0.3), out, 8)
	assert_int(out.y).is_equal(40)
	out = InputLayer.quantize_stick(Vector2(0.0, -0.3), out, 8)
	assert_int(out.y).is_equal(-40)


func test_a_stick_resting_on_the_dead_zone_edge_does_not_flicker() -> void:
	# Resting at 12% with +-1% noise, straight and diagonal: it registers once and stays.
	var rng: Rng = Rng.seeded(13, 0)
	for dir: Vector2 in [Vector2(1.0, 0.0), Vector2(0.7071, 0.7071)]:
		var out := Vector2i.ZERO
		var changes: int = 0
		for _i: int in range(3600):
			var m: float = 0.12 + float(rng.between(-100, 100)) / 10000.0
			var release: int = 10 if out != Vector2i.ZERO else -1
			var next: Vector2i = InputLayer.quantize_stick(
				InputLayer.shape_stick(dir * m, 12, 95, release), out, 8
			)
			if next != out:
				changes += 1
			out = next
		assert_int(changes).override_failure_message("direction %s" % dir).is_less_equal(2)
	# Out of the dead zone at 12%, back in only at 10%.
	assert_bool(InputLayer.shape_stick(Vector2(0.115, 0.0), 12, 95) == Vector2.ZERO).is_true()
	assert_bool(InputLayer.shape_stick(Vector2(0.105, 0.0), 12, 95, 10) == Vector2.ZERO).is_false()
	assert_bool(InputLayer.shape_stick(Vector2(0.099, 0.0), 12, 95, 10) == Vector2.ZERO).is_true()
