extends GdUnitTestSuite
## The camera review's sixth round (docs/adr/0011), at all four screen shapes: crouched strikes
## pumping a held look-down (H1), a teleport's glide needing the backstop when Ash dashes on toward
## a ceiling or a borderless edge (M1), the view freezing on every hop's way down while it eases up
## to a ledge (M2). The shaft climb after a slide (L1) is in the camera rig's suite, which also
## plays the committed fixtures (tests/replay/camera/cam6_*) under every rule it checks.

const VIEWS: Array[Vector2] = [
	Vector2(1920, 1080), Vector2(1920, 1200), Vector2(1920, 1440), Vector2(2520, 1080)
]
const DIR: String = "res://tests/replay/camera/"
const EPS: float = 0.001


func _rig(view: Vector2) -> CameraRig:
	var rig := CameraRig.new(load(CameraRig.TUNING_PATH) as CameraTuning)
	rig.view_size = view
	return rig


func _play(text: String, view: Vector2) -> CameraRun:
	var run: CameraRun = CameraRun.play_fixture(Fixture.parse_text(text), _rig(view))
	assert_array(Array(run.errors)).is_empty()
	return run


func _play_file(fixture_name: String, view: Vector2) -> CameraRun:
	var run: CameraRun = CameraRun.play(DIR + fixture_name + ".fixture", _rig(view))
	assert_array(Array(run.errors)).is_empty()
	return run


## A fixture in test/camera: crouched with the stick held down from frame 0, a fresh attack press
## on each of [param strikes], the stick still down between them, to frame [param frames].
func _crouch_strikes(strikes: Array[int], frames: int) -> String:
	var lines: PackedStringArray = [
		"fixture crouch_strikes",
		'doc BUILD.md s5 look-down "never during a strike" (camera review 6, H1)',
		"room test/camera",
		"spawn 1800 1600",
		"frames %d" % frames,
		"input",
	]
	var from: int = 0
	for at: int in strikes:
		if at > from:
			lines.append("  %d..%d D" % [from, at - 1])
		lines.append("  %d D !attack" % at)
		from = at + 1
	lines.append("  %d..%d D" % [from, frames - 1])
	lines.append_array(["end", "expect", "end"])
	return "\n".join(lines)


func test_crouched_strikes_never_pump_a_held_look_down() -> void:
	# H1: the look shrank by 8 u a tick through each 14-tick strike and came back with no delay
	# on the first crouched tick after it: the view swung 32 u down and 35 u up every strike while
	# Ash stood still and fought. Every spacing that leaves free ticks between strikes.
	var problems: PackedStringArray = []
	for spacing: int in range(15, 41):
		var strikes: Array[int] = []
		for at: int in range(60, 240, spacing):
			strikes.append(at)
		var text: String = _crouch_strikes(strikes, 260)
		for view: Vector2 in VIEWS:
			var run: CameraRun = _play(text, view)
			# The look reached its 200 u before the first strike, and from then on neither the
			# look nor the view turns: the view only settles on down into the look.
			assert_float(run.looks[59]).is_equal(200.0)
			for f: int in range(60, run.centers.size()):
				if run.looks[f] < run.looks[f - 1] - EPS or run.velocity(f).y < -EPS:
					problems.append("every %d ticks at %s: frame %d" % [spacing, view, f])
					break
	if not problems.is_empty():
		fail("\n".join(problems))


func test_crouched_strikes_never_start_a_look_down() -> void:
	# The second review's case: crouched strikes in a fight, the stick held down between them,
	# with fewer than 20 free ticks between strikes, never start a look.
	var free: int = (load(CameraRig.TUNING_PATH) as CameraTuning).look_down_delay_frames
	for spacing: int in range(15, 14 + free):
		var strikes: Array[int] = []
		for at: int in range(10, 240, spacing):
			strikes.append(at)
		# Ending 16 free ticks after the last strike (14 ticks long): fewer than the delay.
		var text: String = _crouch_strikes(strikes, strikes[strikes.size() - 1] + 30)
		for view: Vector2 in VIEWS:
			var run: CameraRun = _play(text, view)
			for f: int in range(run.centers.size()):
				(
					assert_float(run.looks[f])
					. override_failure_message(
						"every %d ticks at %s: frame %d" % [spacing, view, f]
					)
					. is_equal(0.0)
				)


func test_a_look_down_interrupted_on_the_ground_waits_its_whole_delay_again() -> void:
	# H1: after a lapse caused by a dash or by letting the stick go, asking again waits the whole
	# 20 ticks (only a drop with the stick held down carries a look on through its landing).
	var delay: int = (load(CameraRig.TUNING_PATH) as CameraTuning).look_down_delay_frames
	var lapses: Array[String] = ["  60 R dash", "  60..61 -", "  60..63 D R"]
	for lapse: String in lapses:
		var text: String = "\n".join(
			[
				"fixture look_lapse",
				'doc BUILD.md s5 look-down "after 20 f of crouching" (camera review 6, H1)',
				"room test/camera",
				"spawn 1800 1600",
				"frames 160",
				"input",
				"  0..59 D",
				lapse,
				"  80..159 D",
				"end",
				"expect",
				"end"
			]
		)
		for view: Vector2 in VIEWS:
			var run: CameraRun = _play(text, view)
			assert_float(run.looks[59]).is_equal(200.0)
			var asked: int = 0
			for f: int in range(60, run.centers.size()):
				asked = asked + 1 if run.subjects[f].looking_down else 0
				if run.looks[f] > run.looks[f - 1] + EPS:
					(
						assert_int(asked)
						. override_failure_message("%s at %s: frame %d" % [lapse, view, f])
						. is_greater_equal(delay)
					)


func test_a_spell_cast_crouched_never_starts_or_moves_a_look_down() -> void:
	# Task 6: Radiance is cast with the stick held down, so a crouched cast is fighting, as a
	# crouched strike is (CLAUDE.md rule 9): its 19 ticks never count toward the look's delay,
	# and a look already showing holds through them.
	var delay: int = (load(CameraRig.TUNING_PATH) as CameraTuning).look_down_delay_frames
	var lines: PackedStringArray = [
		"fixture crouch_spell",
		"doc BUILD.md s5 look-down, s6 Radiance (a spell with the stick held down)",
		"room test/camera",
		"spawn 1800 1600",
		"option flame 66",
		"option kindling 20",
		"frames 120",
		"input",
		"  0..9 D",
		"  10 D spell",
		"  11..119 D",
		"end",
		"expect",
		"  at 10 spell=radiance",
		"  at 29 spell=none",
		"end",
	]
	for view: Vector2 in VIEWS:
		var run: CameraRun = _play("\n".join(lines), view)
		for f: int in range(29 + delay - 1):
			(
				assert_float(run.looks[f])
				. override_failure_message("%s: frame %d" % [view, f])
				. is_equal(0.0)
			)
		assert_float(run.looks[run.looks.size() - 1]).is_equal(200.0)
	lines[8] = "  0..59 D"
	lines[9] = "  60 D spell"
	lines[10] = "  61..119 D"
	lines[13] = "  at 60 spell=radiance"
	lines[14] = "  at 79 spell=none"
	for view: Vector2 in VIEWS:
		var held: CameraRun = _play("\n".join(lines), view)
		assert_float(held.looks[59]).is_equal(200.0)
		for f: int in range(60, held.centers.size()):
			(
				assert_float(held.looks[f])
				. override_failure_message("%s: frame %d" % [view, f])
				. is_equal(200.0)
			)
			assert_float(held.velocity(f).y).is_greater_equal(-EPS)


## The teleports of the sweep: a toss straight at a one-tile ceiling or a borderless top, or down
## off a shelf toward a borderless bottom, held [param wait] ticks, the teleport, then
## [param onward] (a dash on at once, or a jump and then the dash).
func _toss_on(room: String, spawn: Vector2i, down: bool, wait: int, jump_first: bool) -> String:
	var toss: String = "D R toss" if down else "U toss"
	var dash: String = "D dash" if down else "U dash"
	var lines: PackedStringArray = [
		"fixture toss_on",
		'doc BUILD.md s5 "A teleport glides" (camera review 6, M1)',
		"room " + room,
		"spawn %d %d" % [spawn.x, spawn.y],
		"frames %d" % (wait + 90),
		"input",
		"  0 " + toss,
		"  %d toss" % wait
	]
	if jump_first and not down:
		lines.append("  %d..%d jump" % [wait + 1, wait + 4])
		lines.append("  %d %s" % [wait + 5, dash])
	elif jump_first:
		lines.append("  %d..%d R" % [wait + 1, wait + 4])
		lines.append("  %d %s" % [wait + 5, dash])
	else:
		lines.append("  %d %s" % [wait + 1, dash])
	lines.append_array(["end", "expect", "end"])
	return "\n".join(lines)


func test_a_teleport_then_a_dash_on_toward_an_edge_needs_no_backstop() -> void:
	# M1: the glide's offset held the view behind a follow that a ceiling or a borderless top held
	# still, while an up-dash carried Ash 180 u on into the margin: the backstop for up to 7
	# ticks, the view's speed jumping 10 to 19 u a tick. The bottom twin did the same. Ceilings,
	# borderless tops and bottoms 12 to 24 rows away, toss waits 20 to 52, a dash on at once or
	# after a jump, at every screen shape: never the backstop, and the view's speed changes within
	# the glide's limit.
	var tuning: CameraTuning = load(CameraRig.TUNING_PATH) as CameraTuning
	var accel: float = float(tuning.glide_accel_milli_u) / 1000.0
	# A one-tile ceiling, a borderless top or a borderless bottom, and its spawn on the platform.
	var rooms: Dictionary[String, Vector2i] = {
		"test/cam6_ceiling_f12": Vector2i(960, 384),
		"test/cam6_ceiling_f18": Vector2i(960, 576),
		"test/cam6_ceiling_f24": Vector2i(960, 768),
		"test/cam6_otop_f12": Vector2i(960, 384),
		"test/cam5_otop_f16": Vector2i(960, 512),
		"test/cam6_otop_f24": Vector2i(960, 768),
		"test/cam6_obot_f12": Vector2i(620, 1536),
		"test/cam6_obot_f14": Vector2i(620, 1472),
		"test/cam6_obot_f20": Vector2i(620, 1280),
	}
	var problems: PackedStringArray = []
	var teleports: int = 0
	for room: String in rooms:
		var spawn: Vector2i = rooms[room]
		var down: bool = room.contains("obot")
		for wait: int in range(20, 55, 4):
			for jump_first: bool in [false, true]:
				var text: String = _toss_on(room, spawn, down, wait, jump_first)
				for view: Vector2 in VIEWS:
					var run: CameraRun = _play(text, view)
					if run.first(SimEvents.TELEPORT) < 0:
						continue
					teleports += 1
					var problem: String = _speed_problem(run, accel)
					if run.rig.follow_misses > 0:
						problem = "the backstop moved the view %d times" % run.rig.follow_misses
					if problem != "":
						problems.append(
							(
								"%s wait %d%s at %s: %s"
								% [room, wait, " jump" if jump_first else "", view, problem]
							)
						)
	assert_int(teleports).is_greater(500)
	if not problems.is_empty():
		fail("\n".join(problems))


## The first tick on which the view's vertical speed changes by more than [param accel], other than
## to slow at once to the player's own speed (ADR-0011), described, or "".
func _speed_problem(run: CameraRun, accel: float) -> String:
	for f: int in range(2, run.centers.size()):
		if run.subjects[f].teleported or run.subjects[f].respawned:
			continue
		var v: float = run.velocity(f).y
		var was: float = run.velocity(f - 1).y
		var lo: float = was - accel
		var hi: float = was + accel
		var player_vy: float = run.subjects[f].vy
		if was > 0.0 and player_vy < was:
			lo = minf(lo, player_vy)
		elif was < 0.0 and player_vy > was:
			hi = maxf(hi, player_vy)
		if v < lo - EPS or v > hi + EPS:
			return "frame %d: the view's speed goes from %.2f to %.2f u" % [f, was, v]
	return ""


func test_hops_on_a_ledge_never_move_the_view() -> void:
	# M2: hopping in place on the ledge while the view still eased up to it froze the view for
	# each hop's whole way down (10 ticks at a time). The ease pauses only while Ash falls away
	# from the support, so the hops leave the view exactly as it is without them.
	for view: Vector2 in VIEWS:
		var hops: CameraRun = _play_file("cam6_step_up_hops", view)
		var still: CameraRun = _play_file("cam_step_up", view)
		var jumps: int = 0
		for f: int in range(still.centers.size()):
			if f >= 100 and hops.events[f].has(SimEvents.JUMP):
				jumps += 1
			(
				assert_float(hops.centers[f].y)
				. override_failure_message("%s: frame %d" % [view, f])
				. is_equal_approx(still.centers[f].y, EPS)
			)
		assert_int(jumps).is_equal(3)


func test_hopping_up_a_staircase_or_out_of_a_look_never_slows_the_view() -> void:
	# M2: on the staircase the view's rise fell to 0.2 u a tick at every hop (3 Hz); out of the
	# look-down the view froze while Ash fell back to the floor, then drifted 55 u up after the
	# landing while Ash stood. Now the staircase's rise only gathers pace until the top, and after
	# the drift fixture's landing the view has under half a tile left to go.
	for view: Vector2 in VIEWS:
		var stairs: CameraRun = _play_file("cam5_staircase_hops", view)
		var first: int = stairs.first(SimEvents.JUMP)
		var top: int = stairs.first(SimEvents.LAND, 150)
		assert_int(top).is_greater(first)
		for f: int in range(first + 30, top):
			(
				assert_float(stairs.velocity(f).y)
				. override_failure_message("staircase at %s: frame %d" % [view, f])
				. is_less_equal(stairs.velocity(f - 1).y + 0.25)
			)
		var drift: CameraRun = _play_file("cam5_look_then_jump_drift", view)
		var landed: int = drift.first(SimEvents.LAND, drift.first(SimEvents.JUMP))
		assert_int(landed).is_greater(0)
		var last: int = drift.centers.size() - 1
		(
			assert_float(drift.centers[landed].y - drift.centers[last].y)
			. override_failure_message(str(view))
			. is_less(16.0)
		)
