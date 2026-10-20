extends GdUnitTestSuite
## Camera review 8 (docs/adr/0011-camera.md, Decision 11): a player who turns during a teleport's
## glide (a pogo bounce, a cling) does not jolt the view. The follow turns with the player at once;
## the glide gives back what that adds, so the view's speed (follow plus glide) changes by at most
## the glide's 5 u/f a tick (PROGRESS.md used to list this as Blocked 3).

const VIEWS: Array[Vector2] = [
	Vector2(1920, 1080), Vector2(1920, 1200), Vector2(1920, 1440), Vector2(2520, 1080)
]
const FIXTURE: String = "res://tests/replay/zone1/04_bypass_toss_wait.fixture"
## The glide's acceleration limit (content/camera.tres: glide_accel_milli_u).
const GLIDE_ACCEL_U: float = 5.0


func _rig(view: Vector2) -> CameraRig:
	var rig := CameraRig.new(load(CameraRig.TUNING_PATH) as CameraTuning)
	rig.view_size = view
	return rig


## A player standing, falling or bouncing at [param feet] with vertical speed [param vy].
func _subject(feet: Vector2, vy: float, supported: bool) -> CameraSubject:
	var s := CameraSubject.new()
	s.box = Rect2(feet.x - 14.0, feet.y - 56.0, 28.0, 56.0)
	s.stand_height = 56.0
	s.facing = 1
	s.vy = vy
	s.supported = supported
	return s


## Whether the view's vertical speed went from [param was] to [param v] within the glide's
## acceleration, or by the one exception ADR-0011 allows: a view outrunning the player may slow at
## once to the player's own speed ([param player_vy]).
func _within_limits(was: float, v: float, player_vy: float) -> bool:
	var lo: float = was - GLIDE_ACCEL_U
	var hi: float = was + GLIDE_ACCEL_U
	if was > 0.0 and player_vy < was:
		lo = minf(lo, player_vy)
	elif was < 0.0 and player_vy > was:
		hi = maxf(hi, player_vy)
	return v >= lo - 0.001 and v <= hi + 0.001


func test_the_bypass_fixture_never_jolts_the_view_at_any_screen_shape() -> void:
	for view: Vector2 in VIEWS:
		var run: CameraRun = CameraRun.play(FIXTURE, _rig(view))
		assert_array(Array(run.errors)).is_empty()
		var teleports: int = 0
		for f: int in range(2, run.centers.size()):
			if run.subjects[f].teleported:
				teleports += 1
			if not run.gliding[f] or run.subjects[f].teleported or run.subjects[f - 1].teleported:
				continue
			var was: float = run.velocity(f - 1).y
			var v: float = run.velocity(f).y
			(
				assert_bool(_within_limits(was, v, run.subjects[f].vy))
				. override_failure_message(
					"%s frame %d: the view's speed changes from %.2f to %.2f u" % [view, f, was, v]
				)
				. is_true()
			)
		# Four tosses, so four glides, each with a bounce somewhere in it.
		assert_int(teleports).is_equal(4)


func test_a_bounce_in_the_middle_of_a_glide_never_jolts_the_view() -> void:
	var rig: CameraRig = _rig(VIEWS[2])
	var room := Rect2(0, 0, 4000, 4000)
	rig.reset(_subject(Vector2(500, 3000), 0.0, true), room)
	# Teleported 400 u up, then fallen for 13 ticks (the follow chases the fall), then a bounce.
	var s: CameraSubject = _subject(Vector2(500, 2600), 0.0, false)
	s.teleported = true
	rig.step(s, room)
	var was: float = rig.center.y - rig.previous.y
	var vy: float = 0.0
	var feet: float = 2600.0
	for tick: int in range(40):
		vy = vy + 0.83 if tick < 14 else -13.2 + 0.67 * float(tick - 14)
		feet += vy
		var t: CameraSubject = _subject(Vector2(500, feet), vy, tick >= 14 and tick < 16)
		rig.step(t, room)
		var v: float = rig.center.y - rig.previous.y
		(
			assert_bool(_within_limits(was, v, vy))
			. override_failure_message(
				"tick %d: the view's speed changes from %.2f to %.2f u" % [tick, was, v]
			)
			. is_true()
		)
		was = v
