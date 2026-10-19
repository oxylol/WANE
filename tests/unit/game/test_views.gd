extends GdUnitTestSuite
## The grey-box views and the camera node: they draw the simulation between ticks and never
## change it (BUILD.md section 13, layer 4).

## Ticks the corner-correction test steps past a fixture's end, the stick let go.
const TAIL_TICKS: int = 30


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
	# ceiling corner move the collider at once. Both axes, each on its own, the run's nudge being
	# the largest since the drawn player last met the collider:
	# - a nudge from rest moves the drawn player on its tick only as it was moving anyway;
	# - its catch-up speed (its motion beyond the collider's own) changes by at most the ease's
	#   share of the run's nudge a tick, so no nudge, and no second nudge during an ease, is drawn
	#   as a hop (task 5 review 2, H1: the whole second lip of a two-step stair in one tick);
	# - it never falls more than nudge_lag_percent of the run's nudge behind, never overshoots the
	#   collider, and meets it;
	# - from rest, a single nudge is met exactly nudge_ease_frames ticks later.
	var tuning: PlayerViewTuning = load(PlayerViewTuning.PATH) as PlayerViewTuning
	var frames: int = tuning.nudge_ease_frames
	var share: float = PlayerView._accel_share(frames)
	var lag_max: float = float(tuning.nudge_lag_percent) / 100.0
	var nudged: Vector2i = Vector2i.ZERO
	var largest_run: float = 0.0
	var largest_lag: float = 0.0
	var singles: int = 0
	for fixture_name: String in [
		"physics/walk_up_ramp45_onto_door_at_crest",
		"physics/dash_up_ramp_onto_door_at_crest",
		"physics/walk_steps_up_small_lips",
		"physics/walk_steps_down_small_lips",
		"physics/walk_down_ramp45_off_door_stays_grounded",
		"physics/air_dash_lifts_onto_two_lips",
		"physics/walk_up_two_lips",
		"physics/walk_up_lip_stairs",
		"physics/dash_up_lip_stairs",
		"presentation/walk_down_lip_stairs",
		"presentation/dash_down_lip_stairs",
		"presentation/walk_up_stairs9",
		"movement/jump_ceiling_nudge",
		"movement/ground_corner_lift",
	]:
		var fx: Fixture = _fixture("res://tests/replay/%s.fixture" % fixture_name)
		var sim := Simulation.new(fx.scenario)
		var view: PlayerView = auto_free(PlayerView.new())
		view.begin(sim)
		var run: Vector2 = Vector2.ZERO
		var count: Vector2i = Vector2i.ZERO
		var since: Vector2i = Vector2i(1000, 1000)
		var catch: Vector2 = Vector2.ZERO
		var gap: Vector2 = Vector2.ZERO
		# Past the fixture's end with the stick let go, so every run is followed until it is met.
		for f: int in range(fx.frame_total + TAIL_TICKS):
			var col_before: Vector2 = view.collider_at(1.0).position
			var drawn_before: Vector2 = view.box_at(1.0).position
			var gap_before: Vector2 = gap
			sim.step(fx.input_frame(f) if f < fx.frame_total else InputFrame.new())
			view.capture(sim)
			var b: Body = sim.player.body
			var nudge := Vector2(float(b.nudge_x), float(b.nudge_y)) / Fx.SUB
			var natural: Vector2 = view.collider_at(1.0).position - col_before - nudge
			var drawn: Vector2 = view.box_at(1.0).position - drawn_before
			gap = view.box_at(1.0).position - view.collider_at(1.0).position
			for axis: int in [0, 1]:
				var where: String = "%s tick %d axis %d" % [fixture_name, f, axis]
				var from_rest: bool = absf(gap_before[axis]) < 0.0005
				if from_rest:
					run[axis] = 0.0
					count[axis] = 0
					catch[axis] = 0.0
				var moved: float = drawn[axis] - natural[axis]
				(
					assert_float(absf(moved - catch[axis]))
					. override_failure_message(
						"%s: catch-up speed jumped from %.2f to %.2f" % [where, catch[axis], moved]
					)
					. is_less_equal(run[axis] * share + 0.001)
				)
				catch[axis] = moved
				if nudge[axis] != 0.0:
					nudged[axis] += 1
					count[axis] += 1
					since[axis] = 0
					run[axis] = maxf(run[axis], absf(nudge[axis]))
					largest_run = maxf(largest_run, run[axis])
				else:
					since[axis] += 1
					# Closing in, never past: the gap keeps its side of the collider.
					(
						assert_bool(gap[axis] * gap_before[axis] >= 0.0)
						. override_failure_message(where + ": overshot the collider")
						. is_true()
					)
				if nudge[axis] != 0.0 and from_rest:
					assert_float(moved).override_failure_message(where).is_equal_approx(0.0, 0.001)
				assert_float(absf(gap[axis])).override_failure_message(where).is_less_equal(
					run[axis] * lag_max + 0.001
				)
				largest_lag = maxf(largest_lag, absf(gap[axis]))
				if count[axis] == 1 and since[axis] == frames:
					singles += 1
					(
						assert_float(gap[axis])
						. override_failure_message(where + ": a single nudge not met on time")
						. is_equal_approx(0.0, 0.001)
					)
		# Every run ends met.
		assert_vector(gap).override_failure_message(fixture_name).is_equal_approx(
			Vector2.ZERO, Vector2(0.001, 0.001)
		)
	assert_int(nudged.y).is_greater(5)
	assert_int(nudged.x).is_greater(0)
	assert_int(singles).is_greater(3)
	# The staircases put several lips into one tick's nudge, and fall behind by more than one.
	assert_float(largest_run).is_greater_equal(16.0)
	assert_float(largest_lag).is_greater(largest_run)


func test_the_ease_from_rest_is_a_triangle_of_speeds_over_its_frames() -> void:
	# An isolated nudge of 4 shares eases 1, 2 and 1 of them over three frames; one frame takes it
	# whole, two in halves, four along 1, 2, 2, 1.
	var shares: Dictionary[int, float] = {3: 0.25, 1: 1.0, 2: 0.5, 4: 1.0 / 6.0}
	for frames: int in shares:
		assert_float(PlayerView._accel_share(frames)).is_equal_approx(shares[frames], 1e-6)
	var tuning: PlayerViewTuning = load(PlayerViewTuning.PATH) as PlayerViewTuning
	var view: PlayerView = auto_free(PlayerView.new())
	view._stop_ease()
	var steps: Array[float] = []
	view._ease_nudge(Vector2(0.0, 8.0))
	var last: float = view._offset_after.y
	for _i: int in range(tuning.nudge_ease_frames + 2):
		view._ease_nudge(Vector2.ZERO)
		steps.append(last - view._offset_after.y)
		last = view._offset_after.y
	assert_array(steps).is_equal([2.0, 4.0, 2.0, 0.0, 0.0])


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
