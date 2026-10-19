extends GdUnitTestSuite
## The grey-box views and the camera node: they draw the simulation between ticks and never
## change it (BUILD.md section 13, layer 4).


## The boot scene, instanced and added to the tree.
func _main() -> Node:
	var main: Node = auto_free((load("res://game/main.tscn") as PackedScene).instantiate())
	add_child(main)
	return main


func _fixture(path: String) -> Fixture:
	var fx: Fixture = Fixture.parse_file(path)
	assert_array(fx.errors).is_empty()
	return fx


func test_the_main_scene_runs_the_sandbox_and_the_camera_follows_the_player() -> void:
	var main: Node = _main()
	for _i: int in range(20):
		await get_tree().process_frame
	var driver: SimDriver = main.get_node("SimDriver")
	var camera: GameCamera = main.get_node("World/GameCamera")
	assert_array(driver.sim.load_errors).is_empty()
	assert_int(driver.sim.tick).is_greater(0)
	assert_object(driver.sim.player).is_not_null()
	var view: Rect2 = camera.rig.view_rect(driver.alpha)
	assert_vector(camera.position).is_equal(view.get_center())
	var b: Body = driver.sim.player.body
	assert_bool(view.has_point(Vector2(b.x, b.y) / Fx.SUB)).is_true()


func test_the_main_scene_has_the_f3_overlay_and_the_frame_stepper() -> void:
	# BUILD.md section 15: "The F3 overlay shows hitboxes, state, frame counter and input history
	# in the build"; section 13: "a frame-stepper" (docs/adr/0012).
	var main: Node = _main()
	for _i: int in range(5):
		await get_tree().process_frame
	var driver: SimDriver = main.get_node("SimDriver")
	var overlay: DebugOverlay = main.get_node("World/DebugOverlay")
	var controls: DebugControls = main.get_node("DebugControls")
	assert_bool(overlay.shown).is_false()
	assert_bool(controls.handle_key(KEY_F3)).is_true()
	assert_bool(overlay.shown).is_true()
	assert_bool(controls.handle_key(KEY_F4)).is_true()
	assert_bool(driver.paused).is_true()
	var tick: int = driver.sim.tick
	for _i: int in range(5):
		await get_tree().process_frame
	assert_int(driver.sim.tick).is_equal(tick)
	controls.handle_key(KEY_F5)
	assert_int(driver.sim.tick).is_equal(tick + 1)
	controls.handle_key(KEY_F6)
	assert_int(driver.sim.tick).is_equal(tick + 11)
	# The overlay has the ticks the stepper took in its input history, and its text the tick.
	assert_int(overlay.history.runs.size()).is_greater(0)
	assert_str(overlay.hud_lines()[0]).contains("frame %d" % (tick + 10))
	controls.handle_key(KEY_F4)
	assert_bool(driver.paused).is_false()


func test_the_player_view_draws_between_ticks() -> void:
	var fx: Fixture = _fixture("res://tests/replay/camera/cam_run_turn.fixture")
	var sim := Simulation.new(fx.scenario)
	var view: PlayerView = auto_free(PlayerView.new())
	view.begin(sim)
	for f: int in range(20):
		sim.step(fx.input_frame(f))
		view.capture(sim)
	var x_before: float = view.box_at(0.0).position.x
	var x_after: float = view.box_at(1.0).position.x
	assert_float(x_after).is_greater(x_before)
	assert_float(view.box_at(0.5).position.x).is_equal_approx((x_before + x_after) * 0.5, 0.001)


func test_the_player_view_never_slides_across_a_teleport() -> void:
	var fx: Fixture = _fixture("res://tests/replay/camera/cam_teleport.fixture")
	var sim := Simulation.new(fx.scenario)
	var view: PlayerView = auto_free(PlayerView.new())
	view.begin(sim)
	for f: int in range(46):
		sim.step(fx.input_frame(f))
		view.capture(sim)
	assert_bool(sim.events.has(SimEvents.TELEPORT)).is_true()
	assert_vector(view.box_at(0.0).position).is_equal(view.box_at(1.0).position)


func test_a_corner_correction_nudge_never_snaps_the_drawn_player() -> void:
	# BUILD.md section 15: "the corner-correction nudge is invisible". A step up or down a lip, a
	# lift onto a ledge's corner, a step on a ramp (up to 18 u in a tick) and a slide round a
	# ceiling corner move the collider at once. Both axes, each on its own:
	# - a nudge from rest moves the drawn player on its tick only as it was moving anyway;
	# - the drawn player never lags the collider by more than the largest nudge of the run (the
	#   nudges since it last met the collider), so up a staircase of lips it follows a lip behind
	#   at most (task 5 review, H3);
	# - catching up never moves it more than that nudge a tick beyond the collider's own motion,
	#   and after a single nudge no more than 0.625 of it (a smoothstep's peak over three frames is
	#   0.5): up a staircase it rises steadily where the collider rises a lip at a time;
	# - it meets the collider nudge_ease_frames ticks after the last nudge.
	var tuning: PlayerViewTuning = load(PlayerViewTuning.PATH) as PlayerViewTuning
	var frames: int = tuning.nudge_ease_frames
	var nudged: Vector2i = Vector2i.ZERO
	var largest_run: float = 0.0
	for fixture_name: String in [
		"physics/walk_up_ramp45_onto_door_at_crest",
		"physics/dash_up_ramp_onto_door_at_crest",
		"physics/walk_steps_up_small_lips",
		"physics/walk_steps_down_small_lips",
		"physics/walk_down_ramp45_off_door_stays_grounded",
		"physics/air_dash_lifts_onto_two_lips",
		"physics/walk_up_lip_stairs",
		"physics/dash_up_lip_stairs",
		"movement/jump_ceiling_nudge",
		"movement/ground_corner_lift",
	]:
		var fx: Fixture = _fixture("res://tests/replay/%s.fixture" % fixture_name)
		var sim := Simulation.new(fx.scenario)
		var view: PlayerView = auto_free(PlayerView.new())
		view.begin(sim)
		var since: Array[int] = [1000, 1000]
		var run: Vector2 = Vector2.ZERO
		var count: Vector2i = Vector2i.ZERO
		for f: int in range(fx.frame_total):
			var col_before: Vector2 = view.collider_at(1.0).position
			var drawn_before: Vector2 = view.box_at(1.0).position
			sim.step(fx.input_frame(f))
			view.capture(sim)
			var b: Body = sim.player.body
			var nudge := Vector2(float(b.nudge_x), float(b.nudge_y)) / Fx.SUB
			var natural: Vector2 = view.collider_at(1.0).position - col_before - nudge
			var drawn: Vector2 = view.box_at(1.0).position - drawn_before
			var gap: Vector2 = view.box_at(1.0).position - view.collider_at(1.0).position
			for axis: int in [0, 1]:
				var where: String = "%s tick %d axis %d" % [fixture_name, f, axis]
				var from_rest: bool = since[axis] >= frames
				if from_rest:
					run[axis] = 0.0
					count[axis] = 0
				if nudge[axis] != 0.0:
					nudged[axis] += 1
					since[axis] = 0
					count[axis] += 1
					run[axis] = maxf(run[axis], absf(nudge[axis]))
					largest_run = maxf(largest_run, run[axis])
				else:
					since[axis] += 1
				if since[axis] == 0 and from_rest:
					assert_float(drawn[axis]).override_failure_message(where).is_equal_approx(
						natural[axis], 0.001
					)
				assert_float(absf(gap[axis])).override_failure_message(where).is_less_equal(
					run[axis] + 0.001
				)
				(
					assert_float(absf(drawn[axis] - natural[axis]))
					. override_failure_message(where)
					. is_less_equal(run[axis] * (0.625 if count[axis] == 1 else 1.0) + 0.001)
				)
				if since[axis] >= frames:
					assert_float(gap[axis]).override_failure_message(where).is_equal_approx(
						0.0, 0.001
					)
	assert_int(nudged.y).is_greater(5)
	assert_int(nudged.x).is_greater(0)
	# The staircases put several lips into one tick's nudge.
	assert_float(largest_run).is_greater_equal(16.0)


func test_the_camera_zoom_fits_the_planned_view_and_a_wider_screen_sees_more() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	var camera := GameCamera.new()
	port.add_child(camera)
	add_child(port)
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(3840, 2160), Vector2i(1920, 1200)]:
		port.size = size
		camera.show_at(1.0)
		var shown: Vector2 = Vector2(size) / camera.zoom
		assert_float(shown.x).is_greater_equal(1920.0 - 0.01)
		assert_float(shown.y).is_greater_equal(1080.0 - 0.01)
		assert_bool(is_equal_approx(shown.x, 1920.0) or is_equal_approx(shown.y, 1080.0)).is_true()
		# The rig keeps the player clear of the edges of what is really shown (camera review
		# round 2, M6).
		assert_vector(camera.rig.view_size).is_equal_approx(shown, Vector2(0.01, 0.01))


func test_a_teleport_cut_is_never_drawn_between_ticks() -> void:
	# A long teleport cuts the view on the axis the margin needs (docs/adr/0011): drawn at any
	# alpha on that tick, the view is the new one, never a slide across the cut.
	var fx: Fixture = _fixture("res://tests/replay/camera/cam_teleport_side_long_run.fixture")
	var sim := Simulation.new(fx.scenario)
	var camera: GameCamera = auto_free(GameCamera.new())
	add_child(camera)
	camera.begin(sim)
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		camera.step(sim)
		if sim.events.has(SimEvents.TELEPORT):
			var cut_x: float = camera.rig.center.x
			for alpha: float in [0.0, 0.5, 1.0]:
				camera.show_at(alpha)
				assert_float(camera.position.x).is_equal_approx(cut_x, 0.001)
			return
	fail("the fixture never teleported")


func test_the_room_view_never_changes_the_world() -> void:
	var sim := Simulation.new(_fixture("res://tests/replay/camera/cam_run_turn.fixture").scenario)
	var hash_before: int = sim.state_hash()
	var view: RoomView = auto_free(RoomView.new())
	add_child(view)
	view.show_world(sim.world)
	view.refresh()
	await await_idle_frame()
	assert_int(sim.state_hash()).is_equal(hash_before)
