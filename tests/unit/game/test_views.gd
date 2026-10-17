extends GdUnitTestSuite
## The grey-box views and the camera node: they draw the simulation between ticks and never
## change it (BUILD.md section 13, layer 4).


func _fixture(path: String) -> Fixture:
	var fx: Fixture = Fixture.parse_file(path)
	assert_array(fx.errors).is_empty()
	return fx


func test_the_main_scene_runs_the_sandbox_and_the_camera_follows_the_player() -> void:
	var main: Node = auto_free((load("res://game/main.tscn") as PackedScene).instantiate())
	add_child(main)
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
