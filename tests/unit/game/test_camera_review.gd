extends GdUnitTestSuite
## The camera review's second round (docs/adr/0011), one test or more per finding: look-down only
## as a request (M3, M6), the fall's look-ahead along its path (M1) and dropped when the fall
## stops (H2), a long teleport's cut (H1), the rest after a double jump (L1) and dithering (M4).

## A tile: the most the view may move against the player's vertical motion in one stretch.
const TILE_U: float = 32.0


func _play(path: String) -> CameraRun:
	var run: CameraRun = CameraRun.play(
		path, CameraRig.new(load(CameraRig.TUNING_PATH) as CameraTuning)
	)
	assert_array(Array(run.errors)).is_empty()
	return run


func test_a_crouched_strike_never_looks_down() -> void:
	# Camera review round 2, M3 (CLAUDE.md rule 9: the camera never takes control during combat):
	# crouching and striking low every 10 frames for 100 frames is a fight, not a request to look.
	var run: CameraRun = _play("res://tests/replay/camera/cam_crouch_attacks.fixture")
	for f: int in range(run.looks.size()):
		assert_float(run.looks[f]).is_equal(0.0)


func test_the_stick_held_down_in_the_air_never_looks_down() -> void:
	# Camera review round 2, M6: look-down needs the player standing crouched on the ground.
	for path: String in ["cam_down_held_in_air", "cam_crouch_dash_open", "cam_tunnel"]:
		var run: CameraRun = _play("res://tests/replay/camera/%s.fixture" % path)
		for f: int in range(run.looks.size()):
			if not run.subjects[f].on_ground:
				assert_float(run.looks[f]).is_equal(0.0)


func test_the_fall_look_never_reaches_past_the_ground_it_lands_on() -> void:
	# Camera review round 2, M1: running off a shelf onto a one-tile platform far below, which the
	# old three-sample probe kept missing. On every tick of the fall the look stays above the
	# platform's top, and it is gone the tick the player lands.
	var run: CameraRun = _play("res://tests/replay/camera/cam_pole_land.fixture")
	var land: int = run.first(SimEvents.LAND, 1)
	assert_int(land).is_greater(60)
	var ground_y: float = run.subjects[land].box.end.y
	var looked: bool = false
	for f: int in range(land):
		var feet: float = run.subjects[f].box.end.y
		assert_float(feet + run.fall_looks[f]).is_less_equal(ground_y + 0.01)
		looked = looked or run.fall_looks[f] > 100.0
	assert_bool(looked).is_true()
	assert_float(run.fall_looks[land]).is_equal(0.0)


func test_a_fall_that_stops_never_carries_the_view_on() -> void:
	# Camera review round 2, H2: falling at speed, then an up-dash, an air jump, a cling or a side
	# dash. The view turns with the player at once: it moves against the player's vertical
	# motion for less than a tile while the player moves faster than a wall slide.
	for fixture: String in [
		"cam_fall_updash", "cam_fall_airjump", "cam_fall_cling", "cam_fall_sidedash"
	]:
		var run: CameraRun = _play("res://tests/replay/camera/%s.fixture" % fixture)
		assert_float(run.longest_run_against()).is_less(TILE_U)
		assert_int(run.rig.follow_misses).is_equal(0)


func test_a_long_teleport_cuts_the_axis_it_must_and_leaves_room_to_carry_on() -> void:
	# Camera review round 2, H1: a teleport too long for the margin cuts that axis all the way to
	# where the follow puts it (not interpolated across), so carrying on the way the teleport went
	# never needs the backstop.
	var run: CameraRun = _play("res://tests/replay/camera/cam_teleport_side_long_run.fixture")
	var at: int = run.first(SimEvents.TELEPORT)
	assert_int(at).is_greater(0)
	assert_float(run.previous[at].x).is_equal(run.centers[at].x)
	assert_int(run.rig.follow_misses).is_equal(0)


func test_a_double_jump_in_place_brings_the_view_back_to_rest() -> void:
	# Camera review round 2, L1: a full jump and air jump rises past the rest window; back on the
	# floor the view returns to where it started instead of resting the dead zone's half-height
	# higher.
	for fixture: String in ["cam_double_jump_in_place", "cam_double_jump_ledge"]:
		var run: CameraRun = _play("res://tests/replay/camera/%s.fixture" % fixture)
		var last: int = run.centers.size() - 1
		assert_float(absf(run.centers[last].y - run.centers[0].y)).is_less(0.5)


func test_turning_back_and_forth_in_place_does_not_swing_the_view() -> void:
	# Camera review round 2, M4: a dither and alternating strikes never move the view more than
	# the player moves.
	for fixture: String in ["cam_dither", "cam_dither10", "cam_dither15", "cam_strike_turns"]:
		var run: CameraRun = _play("res://tests/replay/camera/%s.fixture" % fixture)
		var px := Vector2(INF, -INF)
		var cx := Vector2(INF, -INF)
		for f: int in range(30, run.centers.size()):
			var x: float = run.subjects[f].box.get_center().x
			px = Vector2(minf(px.x, x), maxf(px.y, x))
			cx = Vector2(minf(cx.x, run.centers[f].x), maxf(cx.y, run.centers[f].x))
		assert_float(cx.y - cx.x).is_less_equal(px.y - px.x + 0.01)
