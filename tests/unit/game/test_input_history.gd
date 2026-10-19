extends GdUnitTestSuite
## The F3 overlay's input history (BUILD.md section 5: "input history").


func _frame(held: int, pressed: int, x: int = 0, y: int = 0) -> InputFrame:
	return InputFrame.make(held, pressed, x, y)


func test_numpad_notation() -> void:
	assert_int(InputHistory.numpad(0, 0)).is_equal(5)
	assert_int(InputHistory.numpad(1, 0)).is_equal(6)
	assert_int(InputHistory.numpad(-1, 0)).is_equal(4)
	assert_int(InputHistory.numpad(0, -1)).is_equal(8)
	assert_int(InputHistory.numpad(0, 1)).is_equal(2)
	assert_int(InputHistory.numpad(1, -1)).is_equal(9)
	assert_int(InputHistory.numpad(-1, 1)).is_equal(1)


func test_identical_ticks_merge_into_one_run_newest_first() -> void:
	var h := InputHistory.new(64)
	for t: int in range(5):
		h.push(_frame(0, 0, 127, 0), t)
	h.push(_frame(InputFrame.JUMP, InputFrame.JUMP, 127, 0), 5)
	for t: int in range(6, 9):
		h.push(_frame(InputFrame.JUMP, 0, 127, 0), t)
	assert_int(h.runs.size()).is_equal(2)
	assert_int(h.runs[0].ticks).is_equal(4)
	assert_int(h.runs[0].first_tick).is_equal(5)
	assert_str(InputHistory.describe(h.runs[0])).is_equal("6 Jmp* 4")
	assert_str(InputHistory.describe(h.runs[1])).is_equal("6 5")


func test_a_new_press_always_starts_a_run_even_while_held() -> void:
	var h := InputHistory.new(64)
	h.push(_frame(InputFrame.ATTACK, InputFrame.ATTACK), 0)
	h.push(_frame(InputFrame.ATTACK, 0), 1)
	# Released and pressed again between two ticks: held throughout, pressed again.
	h.push(_frame(InputFrame.ATTACK, InputFrame.ATTACK), 2)
	assert_int(h.runs.size()).is_equal(2)
	assert_str(InputHistory.describe(h.runs[0])).is_equal("5 Atk* 1")
	assert_str(InputHistory.describe(h.runs[1])).is_equal("5 Atk* 2")


func test_a_tap_shorter_than_a_tick_shows_as_a_press() -> void:
	var h := InputHistory.new(64)
	h.push(_frame(0, InputFrame.DASH, 0, 127), 0)
	assert_str(InputHistory.describe(h.runs[0])).is_equal("2 Dsh* 1")


func test_a_tap_is_a_run_of_its_own_never_merged_with_the_ticks_after_it() -> void:
	# Task 5 review, M7: a tap then 40 neutral ticks read "5 Dsh* 41", like a 41-tick hold.
	var h := InputHistory.new(64)
	h.push(_frame(0, InputFrame.DASH), 0)
	for t: int in range(1, 41):
		h.push(_frame(0, 0), t)
	assert_str(InputHistory.describe(h.runs[1])).is_equal("5 Dsh* 1")
	assert_str(InputHistory.describe(h.runs[0])).is_equal("5 40")


func test_the_stick_reads_in_the_dashs_eight_sectors() -> void:
	# Task 5 review, M9: an air dash with the stick at (127, 56) goes down-right; the history read
	# each axis on its own and showed right.
	var h := InputHistory.new(64)
	h.push(_frame(0, 0, 127, 56), 0)
	h.push(_frame(0, 0, 127, 40), 1)
	assert_int(h.runs[1].dir).is_equal(3)
	assert_int(h.runs[0].dir).is_equal(6)


func test_the_stick_counts_from_the_players_threshold() -> void:
	var h := InputHistory.new(64)
	h.push(_frame(0, 0, 63, 0), 0)
	h.push(_frame(0, 0, 64, -64), 1)
	assert_int(h.runs[1].dir).is_equal(5)
	assert_int(h.runs[0].dir).is_equal(9)


func test_only_the_newest_runs_are_kept() -> void:
	var h := InputHistory.new(64)
	for t: int in range(InputHistory.KEEP + 10):
		h.push(_frame(InputFrame.JUMP, InputFrame.JUMP), t)
	assert_int(h.runs.size()).is_equal(InputHistory.KEEP)
	assert_int(h.runs[0].first_tick).is_equal(InputHistory.KEEP + 9)


func test_a_fixture_reads_back_as_its_script() -> void:
	# tests/replay/tech/tech01_dash_slash.fixture, as the simulation consumed it: frame 1 is not
	# in the script, so it is neutral; "17..19 R dash" is one press held for three ticks.
	var fx: Fixture = Fixture.parse_file("res://tests/replay/tech/tech01_dash_slash.fixture")
	var sim := Simulation.new(fx.scenario)
	var h := InputHistory.new(sim.player.p.stick_threshold)
	for f: int in range(fx.frame_total):
		sim.step(fx.input_frame(f))
		h.push(sim.last_input, f)
	var read: PackedStringArray = []
	for run: InputHistory.Run in h.runs:
		read.append(InputHistory.describe(run))
	assert_array(read).is_equal(
		PackedStringArray(
			["6 40", "6 Dsh* 3", "6 5", "6 Atk* 1", "6 8", "6 Atk* 1", "5 1", "6 Dsh* 1"]
		)
	)
