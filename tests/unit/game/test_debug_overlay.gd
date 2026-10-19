extends GdUnitTestSuite
## The F3 overlay and the frame-stepper (BUILD.md section 5: "A debug overlay (F3) shows
## hitboxes, state, frame counters and input history"; section 13: "a frame-stepper"; section 15:
## "The F3 overlay shows hitboxes, state, frame counter and input history in the build").

var _driver: SimDriver
var _overlay: DebugOverlay
var _controls: DebugControls
var _camera: GameCamera


func before_test() -> void:
	var input_layer: InputLayer = auto_free(InputLayer.new())
	add_child(input_layer)
	_driver = auto_free(SimDriver.new())
	_driver.input_layer = input_layer
	add_child(_driver)
	_driver.start(Fixture.parse_file("res://tests/replay/tech/tech01_dash_slash.fixture").scenario)
	_camera = auto_free(GameCamera.new())
	add_child(_camera)
	_camera.begin(_driver.sim)
	_overlay = auto_free(DebugOverlay.new())
	add_child(_overlay)
	_overlay.attach(_driver, _camera)
	_driver.ticked.connect(_overlay.capture)
	_driver.ticked.connect(_camera.step.bind(_driver.sim))
	_controls = auto_free(DebugControls.new())
	add_child(_controls)
	_controls.driver = _driver
	_controls.overlay = _overlay
	# The test drives ticks itself.
	_driver.paused = true


func after_test() -> void:
	for action: String in InputLayer.BUTTON_ACTIONS:
		Input.action_release(InputLayer.ACTION_PREFIX + action)


func test_f3_shows_and_hides_the_overlay() -> void:
	assert_bool(_overlay.shown).is_false()
	assert_bool(_controls.handle_key(KEY_F3)).is_true()
	assert_bool(_overlay.shown).is_true()
	assert_bool(_overlay.visible).is_true()
	_controls.handle_key(KEY_F3)
	assert_bool(_overlay.shown).is_false()


func test_f4_pauses_and_f5_steps_exactly_one_tick() -> void:
	_driver.paused = false
	_controls.handle_key(KEY_F4)
	assert_bool(_driver.paused).is_true()
	var tick: int = _driver.sim.tick
	_controls.handle_key(KEY_F5)
	assert_int(_driver.sim.tick).is_equal(tick + 1)
	_controls.handle_key(KEY_F6)
	assert_int(_driver.sim.tick).is_equal(tick + 11)
	_controls.handle_key(KEY_F4)
	assert_bool(_driver.paused).is_false()


func test_f5_does_nothing_while_the_game_runs() -> void:
	_driver.paused = false
	var tick: int = _driver.sim.tick
	_controls.handle_key(KEY_F5)
	assert_int(_driver.sim.tick).is_equal(tick)


func test_no_game_binding_uses_a_debug_key() -> void:
	# Task 5 review, H1: Shift+F5 stepped ten ticks with Shift, the keyboard's dash, held.
	var settings: InputSettings = load(InputLayer.SETTINGS_PATH) as InputSettings
	var bound: String = ",".join(settings.bindings)
	for key: Key in DebugControls.KEYS:
		assert_str(bound).not_contains("key:%s," % OS.get_keycode_string(key))
		assert_bool(bound.ends_with("key:%s" % OS.get_keycode_string(key))).is_false()


func test_hitstop_shows_one_press_once() -> void:
	# Task 5 review, M8: during hitstop the ring folds presses into its newest slot, so reading it
	# showed one tap on every frozen tick. The history reads the frame each tick consumed.
	_driver.sim.player.freeze = 4
	var tap := InputFrame.make(0, InputFrame.ATTACK, 0, 0)
	_driver.sim.step(tap)
	_overlay.capture()
	for _i: int in range(4):
		_driver.sim.step(InputFrame.new())
		_overlay.capture()
	var presses: int = 0
	for run: InputHistory.Run in _overlay.history.runs:
		if run.pressed & InputFrame.ATTACK != 0:
			presses += 1
	assert_int(presses).is_equal(1)


func test_other_keys_are_left_to_the_game() -> void:
	assert_bool(_controls.handle_key(KEY_SPACE)).is_false()


func test_a_press_made_while_paused_lands_on_the_next_step() -> void:
	Input.action_press(InputLayer.ACTION_PREFIX + "jump")
	_controls.handle_key(KEY_F5)
	assert_bool(_driver.sim.input.latest().was_pressed(InputFrame.JUMP)).is_true()
	_controls.handle_key(KEY_F5)
	assert_bool(_driver.sim.input.latest().was_pressed(InputFrame.JUMP)).is_false()
	assert_bool(_driver.sim.input.latest().is_held(InputFrame.JUMP)).is_true()


func test_the_text_shows_the_tick_state_strike_frame_and_input_history() -> void:
	var fx: Fixture = Fixture.parse_file("res://tests/replay/tech/tech01_dash_slash.fixture")
	# Step the fixture's own inputs through the driver's simulation to frame 8 (the state after
	# input frame 8, as fixtures number it): side 1 started on frame 5, so frame 8 is its frame 4.
	for f: int in range(9):
		_driver.sim.step(fx.input_frame(f))
		_overlay.capture()
	var text: String = "\n".join(_overlay.hud_lines())
	assert_str(text).contains("frame 8")
	assert_str(text).contains("PAUSED")
	assert_str(text).contains("strike side1 frame 4 of 14 (active 3 to 6)")
	assert_str(text).contains("ground")
	var runs: PackedStringArray = []
	for run: InputHistory.Run in _overlay.history.runs:
		runs.append(InputHistory.describe(run))
	assert_array(runs).is_equal(PackedStringArray(["6 6", "6 Atk* 1", "5 1", "6 Dsh* 1"]))


func test_drawing_records_the_boxes_and_never_changes_the_simulation() -> void:
	var fx: Fixture = Fixture.parse_file("res://tests/replay/tech/tech01_dash_slash.fixture")
	for f: int in range(8):
		_driver.sim.step(fx.input_frame(f))
	var hash_before: int = _driver.sim.state_hash()
	_overlay.set_shown(true)
	await await_idle_frame()
	var kinds: Array[int] = []
	for b: DebugBoxes.Box in _overlay.boxes:
		kinds.append(b.kind)
	assert_bool(kinds.has(DebugBoxes.COLLIDER)).is_true()
	assert_bool(kinds.has(DebugBoxes.HURTBOX)).is_true()
	assert_bool(kinds.has(DebugBoxes.STRIKE)).is_true()
	assert_int(_driver.sim.state_hash()).is_equal(hash_before)
