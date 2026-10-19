extends GdUnitTestSuite
## The boxes the F3 overlay draws (BUILD.md section 5: "shows hitboxes"; section 6 hitbox sizes;
## CLAUDE.md rule 8: "player hurtboxes are smaller than the sprite").

const WIDE_VIEW := Rect2(-10000, -10000, 20000, 20000)


## The simulation after input frames 0..[param frame] of [param path].
func _sim_at(path: String, frame: int) -> Simulation:
	var fx: Fixture = Fixture.parse_file(path)
	var sim := Simulation.new(fx.scenario)
	for f: int in range(frame + 1):
		sim.step(fx.input_frame(f))
	return sim


func _of(boxes: Array[DebugBoxes.Box], kind: int) -> Array[DebugBoxes.Box]:
	var out: Array[DebugBoxes.Box] = []
	for b: DebugBoxes.Box in boxes:
		if b.kind == kind:
			out.append(b)
	return out


func test_the_hurtbox_sits_inside_the_collider_by_the_kit_insets() -> void:
	var sim: Simulation = _sim_at("res://tests/replay/movement/ground_run_speed.fixture", 10)
	var boxes: Array[DebugBoxes.Box] = DebugBoxes.collect(sim, WIDE_VIEW)
	var collider: Rect2 = _of(boxes, DebugBoxes.COLLIDER)[0].rect
	var hurt: Rect2 = _of(boxes, DebugBoxes.HURTBOX)[0].rect
	assert_vector(collider.size).is_equal(Vector2(20, 44))
	assert_float(hurt.position.x - collider.position.x).is_equal(3.0)
	assert_float(collider.end.x - hurt.end.x).is_equal(3.0)
	assert_float(hurt.position.y - collider.position.y).is_equal(8.0)
	assert_float(collider.end.y - hurt.end.y).is_equal(2.0)


func test_a_side_strike_shows_its_box_only_on_its_active_frames() -> void:
	# tech01: side 1 starts on frame 5 (dash frame 6); startup 2, active 4: frames 3 to 6 of
	# the strike are frames 7 to 10.
	var path: String = "res://tests/replay/tech/tech01_dash_slash.fixture"
	for f: int in range(4, 13):
		var sim: Simulation = _sim_at(path, f)
		var strikes: Array[DebugBoxes.Box] = _of(
			DebugBoxes.collect(sim, WIDE_VIEW), DebugBoxes.STRIKE
		)
		var live: bool = f >= 7 and f <= 10
		assert_int(strikes.size()).is_equal(1 if live else 0)
		if live:
			assert_str(strikes[0].label).is_equal("side1")
			assert_vector(strikes[0].rect.size).is_equal(Vector2(68, 44))
			assert_object(strikes[0].rect).is_equal(DebugBoxes.units(sim.player.strike_box()))


func test_the_pogo_box_shows_on_frames_three_to_nine() -> void:
	var path: String = "res://tests/replay/movement/pogo_hitbox_frames.fixture"
	for f: int in range(0, 13):
		var sim: Simulation = _sim_at(path, f)
		var pogo: Array[DebugBoxes.Box] = _of(DebugBoxes.collect(sim, WIDE_VIEW), DebugBoxes.POGO)
		assert_int(pogo.size()).is_equal(1 if f >= 2 and f <= 8 else 0)
		if not pogo.is_empty():
			assert_vector(pogo[0].rect.size).is_equal(Vector2(36, 24))


func test_spikes_in_view_show_the_part_that_hurts() -> void:
	var sim: Simulation = _sim_at("res://tests/replay/camera/cam_hazard.fixture", 0)
	var view := Rect2(2900, 2100, 200, 200)
	var hazards: Array[DebugBoxes.Box] = _of(DebugBoxes.collect(sim, view), DebugBoxes.HAZARD)
	# Spike tiles from x 2912 in row 69 (y 2208 to 2240); the view reaches x 3100: six tiles.
	assert_int(hazards.size()).is_equal(6)
	var inset: float = float(sim.world.spike_inset_sp) / Fx.SUB
	assert_float(hazards[0].rect.position.y).is_equal(2208.0 + inset)
	assert_float(hazards[0].rect.end.y).is_equal(2240.0)
	# Out of view, nothing.
	(
		assert_int(_of(DebugBoxes.collect(sim, Rect2(0, 0, 100, 100)), DebugBoxes.HAZARD).size())
		. is_zero()
	)


func test_solid_boxes_carry_their_tags_and_the_ember_shows_while_out() -> void:
	var sim: Simulation = _sim_at("res://tests/replay/tech/tech09_reverse_pogo.fixture", 0)
	var solids: Array[DebugBoxes.Box] = _of(DebugBoxes.collect(sim, WIDE_VIEW), DebugBoxes.SOLID)
	var labels: PackedStringArray = []
	for b: DebugBoxes.Box in solids:
		labels.append(b.label)
	assert_bool(labels.has("pogo")).is_true()
	var tossed: Simulation = _sim_at("res://tests/replay/camera/cam_teleport.fixture", 20)
	var ember: Array[DebugBoxes.Box] = _of(DebugBoxes.collect(tossed, WIDE_VIEW), DebugBoxes.EMBER)
	assert_int(ember.size()).is_equal(1)
	var at := Vector2(tossed.player.toss.x, tossed.player.toss.y) / Fx.SUB
	assert_vector(ember[0].rect.get_center()).is_equal(at)


func test_collecting_never_changes_the_simulation() -> void:
	var sim: Simulation = _sim_at("res://tests/replay/tech/tech01_dash_slash.fixture", 8)
	var hash_before: int = sim.state_hash()
	DebugBoxes.collect(sim, WIDE_VIEW)
	assert_int(sim.state_hash()).is_equal(hash_before)


func test_a_bounce_is_marked_on_its_tick() -> void:
	# Task 5 review, M10: on the bounce tick the down-strike hands control back, so its pogo box is
	# gone; the overlay marks where it hit instead.
	var sim: Simulation = _sim_at("res://tests/replay/tech/tech03_pogo_chain.fixture", 57)
	assert_bool(sim.events.has(SimEvents.POGO)).is_true()
	var boxes: Array[DebugBoxes.Box] = DebugBoxes.collect(sim, WIDE_VIEW)
	assert_array(_of(boxes, DebugBoxes.POGO)).is_empty()
	var marks: Array[DebugBoxes.Box] = _of(boxes, DebugBoxes.CONTACT)
	assert_int(marks.size()).is_equal(1)
	assert_str(marks[0].label).is_equal("bounce")


func test_a_hazard_hit_marks_the_hurtbox_that_touched() -> void:
	# Task 5 review 2, M1: the send-back moves the player to safe ground on the tick it touches the
	# spikes, so the hurtbox drawn that tick never touched anything. The overlay marks the hurtbox
	# where it touched, over the spikes' hazard box.
	var sim: Simulation = _sim_at("res://tests/replay/camera/cam_hazard.fixture", 14)
	assert_bool(sim.events.has(SimEvents.HAZARD)).is_true()
	var boxes: Array[DebugBoxes.Box] = DebugBoxes.collect(sim, WIDE_VIEW)
	var marks: Array[DebugBoxes.Box] = _of(boxes, DebugBoxes.CONTACT)
	assert_int(marks.size()).is_equal(1)
	assert_str(marks[0].label).is_equal("hazard hit")
	var hurt: Rect2 = _of(boxes, DebugBoxes.HURTBOX)[0].rect
	assert_vector(marks[0].rect.size).is_equal(hurt.size)
	var touches: bool = false
	for h: DebugBoxes.Box in _of(boxes, DebugBoxes.HAZARD):
		touches = touches or h.rect.intersects(marks[0].rect)
		assert_bool(h.rect.intersects(hurt)).is_false()
	assert_bool(touches).is_true()


func test_the_down_strike_names_its_one_box_once() -> void:
	# Task 5 review, L14: its strike box is its pogo box; the labels printed over each other.
	var sim: Simulation = _sim_at("res://tests/replay/tech/tech03_pogo_chain.fixture", 54)
	var boxes: Array[DebugBoxes.Box] = DebugBoxes.collect(sim, WIDE_VIEW)
	assert_str(_of(boxes, DebugBoxes.STRIKE)[0].label).is_equal("down + pogo")


func test_every_fixture_plays_the_same_with_the_overlay_reading() -> void:
	# Task 5 review, M12, and presentation review r3, L4: the overlay's reads (boxes, text,
	# history, and task 6's live reads of the enemies, the swings, Kindle's cone and the tier) never
	# change the simulation. Every fixture directory is played. Reading is the cost (the overlay
	# reads on every tick of all 390 fixtures took over three minutes), so the directories that
	# exercise the combat reads, and the tech and physics ones, are read on every tick and the
	# state hashed on every tick in the combat ones; the rest are read every tenth tick and at the
	# end, where there is no enemy to read.
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	var played: int = 0
	var root: String = "res://tests/replay/"
	var combat_dirs: Array[String] = ["combat", "doors", "presentation"]
	var read_every_tick: Array[String] = ["combat", "doors", "presentation", "tech", "physics"]
	for dir_name: String in DirAccess.get_directories_at(root):
		if dir_name == "rooms":
			continue
		var step: int = 1 if read_every_tick.has(dir_name) else 10
		for file: String in DirAccess.get_files_at(root + dir_name):
			if not file.ends_with(".fixture"):
				continue
			var fx: Fixture = Fixture.parse_file(root + dir_name + "/" + file)
			var watched := Simulation.new(fx.scenario)
			var plain := Simulation.new(fx.scenario)
			overlay.attach_sim(watched, null)
			for f: int in range(fx.frame_total):
				watched.step(fx.input_frame(f))
				plain.step(fx.input_frame(f))
				overlay.capture()
				if f % step == 0 or f == fx.frame_total - 1:
					DebugBoxes.collect(watched, WIDE_VIEW, overlay._memory)
					overlay.hud_lines()
				if (
					combat_dirs.has(dir_name)
					and (
						watched.state_hash() != plain.state_hash()
						or watched.events.count() != plain.events.count()
					)
				):
					fail(
						(
							"%s/%s: the overlay changed the simulation on frame %d"
							% [dir_name, file, f]
						)
					)
					return
			assert_int(watched.state_hash()).override_failure_message(file).is_equal(
				plain.state_hash()
			)
			played += 1
	assert_int(played).is_greater(300)
