extends GdUnitTestSuite
## Camera review 7 (docs/adr/0011-camera.md): a fall away from the last support never lifts the
## view (H1), a death by an enemy's hit cuts the view as a hazard respawn does (H2), a held
## Charged strike starts no look-down (H3), the shake keeps the 80 u margin (M1), and the view
## never changes speed by more than 3 u/f once a glide is over (L1).

const VIEWS: Array[Vector2] = [
	Vector2(1920, 1080), Vector2(1920, 1200), Vector2(1920, 1440), Vector2(2520, 1080)
]
const DIR: String = "res://tests/replay/camera/"
const TILE_U: float = 32.0


func _rig(view: Vector2) -> CameraRig:
	var rig := CameraRig.new(load(CameraRig.TUNING_PATH) as CameraTuning)
	rig.view_size = view
	return rig


func _play(path: String, view: Vector2) -> CameraRun:
	var run: CameraRun = CameraRun.play(path, _rig(view))
	assert_array(Array(run.errors)).is_empty()
	return run


## The longest stretch of view travel against the player's fall in the air, with no hop exemption
## of any kind: the rule itself (ADR-0011: under a tile of view motion against the player).
func _run_against_no_exemption(run: CameraRun) -> float:
	var longest: float = 0.0
	var stretch: float = 0.0
	for f: int in range(1, run.centers.size()):
		var s: CameraSubject = run.subjects[f]
		if s.teleported or s.respawned or run.gliding[f] or run.gliding[f - 1]:
			stretch = 0.0
			continue
		var moved: float = s.box.end.y - run.subjects[f - 1].box.end.y
		if not s.supported and moved * run.velocity(f).y < 0.0:
			stretch += absf(run.velocity(f).y)
			longest = maxf(longest, stretch)
		else:
			stretch = 0.0
	return longest


func test_h1_falling_away_above_the_last_support_never_lifts_the_view() -> void:
	var paths: Array[String] = [
		DIR + "cam7_cling_walljump_fast.fixture",
		DIR + "cam7_climb_letgo.fixture",
		DIR + "cam7_step_up_hop_off.fixture",
		DIR + "cam5_wall_jump_long_drift.fixture",
	]
	var problems: PackedStringArray = []
	for path: String in paths:
		for view: Vector2 in VIEWS:
			var run: CameraRun = _play(path, view)
			var against: float = _run_against_no_exemption(run)
			if against >= TILE_U:
				(
					problems
					. append(
						(
							"%s at %s: the view rises %.1f u while Ash falls (the suite's measure: %.1f)"
							% [path.get_file(), view, against, run.longest_run_against()]
						)
					)
				)
	if not problems.is_empty():
		fail("\n".join(problems))


func test_h2_a_death_sends_the_view_with_the_player_as_a_respawn_does() -> void:
	var problems: PackedStringArray = []
	for path: String in [DIR + "cam7_death_far.fixture", DIR + "cam7_sandbox_death.fixture"]:
		for view: Vector2 in VIEWS:
			var run: CameraRun = _play(path, view)
			var died: int = run.first(SimEvents.DEATH)
			assert_int(died).is_greater(0)
			var drift: float = 0.0
			for f: int in range(died + 1, mini(died + 60, run.centers.size())):
				drift += run.velocity(f).length()
			if not run.previous[died].is_equal_approx(run.centers[died]):
				problems.append(
					(
						"%s %s: frame %d draws the view across %.0f u between ticks"
						% [
							path.get_file(),
							view,
							died,
							run.previous[died].distance_to(run.centers[died])
						]
					)
				)
			if run.rig.follow_misses > 0 or drift > 1.0:
				(
					problems
					. append(
						(
							"%s %s: the backstop moved the view %d times; it drifts %.0f u after, Ash standing"
							% [path.get_file(), view, run.rig.follow_misses, drift]
						)
					)
				)
	if not problems.is_empty():
		fail("\n".join(problems))


func test_h2_the_drawn_player_does_not_slide_across_a_death() -> void:
	var fx: Fixture = Fixture.parse_file(DIR + "cam7_sandbox_death.fixture")
	var sim := Simulation.new(fx.scenario)
	var view: PlayerView = auto_free(PlayerView.new())
	var died: int = -1
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		view.capture(sim)
		if sim.events.has(SimEvents.DEATH):
			died = f
			break
	assert_int(died).is_greater(0)
	assert_vector(view.collider_at(0.0).position).is_equal_approx(
		view.collider_at(1.0).position, Vector2(0.01, 0.01)
	)


func test_h3_a_crouched_charge_never_starts_a_look_down() -> void:
	var problems: PackedStringArray = []
	for view: Vector2 in VIEWS:
		var run: CameraRun = _play(DIR + "cam7_crouch_charge.fixture", view)
		var release: int = run.first(SimEvents.CHARGE_RELEASE)
		assert_int(release).is_equal(90)
		for f: int in range(release + 1):
			if run.looks[f] > 0.0:
				(
					problems
					. append(
						(
							"%s: the look-down starts on frame %d of the charge (look %.0f u at frame 89)"
							% [view, f, run.looks[89]]
						)
					)
				)
				break
	if not problems.is_empty():
		fail("\n".join(problems))


func test_m1_the_drawn_view_keeps_the_margin_through_a_shake() -> void:
	var fx: Fixture = Fixture.parse_file(DIR + "cam7_edge_hit.fixture")
	var margin: float = float(_rig(VIEWS[0]).tuning.edge_margin_u)
	var problems: PackedStringArray = []
	var hit_seen: bool = false
	for scale: float in [0.5, 1.0]:
		var sim := Simulation.new(fx.scenario)
		var rig: CameraRig = _rig(VIEWS[0])
		var feedback := HitFeedback.new()
		feedback.shake.scale = scale
		var room := Rect2(
			0, 0, sim.world.grid.width * TileGrid.TILE, sim.world.grid.height * TileGrid.TILE
		)
		rig.reset(CameraSubject.of(sim, rig.tuning.fall_lead_frames), room)
		var worst: float = 1.0e9
		var at: int = -1
		for f: int in range(fx.frame_total):
			sim.step(fx.input_frame(f))
			var s := CameraSubject.of(sim, rig.tuning.fall_lead_frames)
			rig.step(s, room)
			feedback.on_tick(sim)
			var shake: Vector2 = feedback.shake_offset()
			hit_seen = hit_seen or shake != Vector2.ZERO
			var half: Vector2 = rig.half_view()
			var drawn: Vector2 = (
				rig.center + GameCamera.shake_within_margin(rig.center, shake, s.box, half, margin)
			)
			var v := Rect2(drawn - half, half * 2.0)
			var gap: float = minf(
				minf(s.box.position.x - v.position.x, v.end.x - s.box.end.x),
				minf(s.box.position.y - v.position.y, v.end.y - s.box.end.y)
			)
			if gap < worst:
				worst = gap
				at = f
		feedback.free()
		if worst < margin - 0.001:
			problems.append(
				(
					"shake at %.0f%%: the player drawn %.2f u from the edge on frame %d"
					% [scale * 100.0, worst, at]
				)
			)
	assert_bool(hit_seen).is_true()
	if not problems.is_empty():
		fail("\n".join(problems))


func test_m1_a_shake_is_untouched_where_the_view_has_room() -> void:
	var half := Vector2(960, 540)
	var box := Rect2(940, 700, 40, 100)
	var centre := Vector2(960, 540)
	var out: Vector2 = GameCamera.shake_within_margin(centre, Vector2(3, -2), box, half, 80.0)
	assert_vector(out).is_equal(Vector2(3, -2))


func test_l1_the_view_never_changes_speed_by_more_than_3_after_a_glide() -> void:
	var run: CameraRun = _play(DIR + "cam7_tp_up_updash.fixture", VIEWS[0])
	assert_float(_worst_change(run)).is_less_equal(3.0 + 0.001)


## The worst change of the view's vertical speed in a tick that is not a glide tick (the glide's
## own 5 u/f acceleration is its own rule): the tick after the glide's last is counted.
func _worst_change(run: CameraRun) -> float:
	var worst: float = 0.0
	for f: int in range(2, run.centers.size()):
		if run.gliding[f] or run.subjects[f].teleported:
			continue
		worst = maxf(worst, absf(run.velocity(f).y - run.velocity(f - 1).y))
	return worst
