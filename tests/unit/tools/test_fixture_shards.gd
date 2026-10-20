extends GdUnitTestSuite
## The fixture suite runs in several processes at once (docs/adr/0006): a shard's results come
## back exactly as the same fixtures run in this process, and a shard that dies fails its
## fixtures instead of passing them by omission.

const SOME: Array[String] = [
	"res://tests/replay/movement/jump_full.fixture",
	"res://tests/replay/combat/side1_hits_dummy_once.fixture",
	"res://tests/replay/tech/tech02_dash_jump_frame5.fixture",
	"res://tests/replay/core/input_buffer_latest_press.fixture",
	"res://tests/replay/camera/cam_teleport.fixture",
]


func _paths() -> Array[String]:
	var paths: Array[String] = []
	for path: String in SOME:
		if FileAccess.file_exists(path):
			paths.append(path)
	return paths


func test_the_fixtures_named_here_exist() -> void:
	assert_int(_paths().size()).is_equal(SOME.size())


func test_sharded_results_are_the_same_as_in_one_process() -> void:
	var paths: Array[String] = _paths()
	var here: Array[FixtureRunner.Result] = FixtureRunner.new().run_paths(paths)
	var runner := FixtureRunner.new()
	var there: Array[FixtureRunner.Result] = runner.run_sharded(paths, 2)
	assert_int(there.size()).is_equal(here.size())
	# Each shard also reports the CPU time it used, for the suite's budget (Linux only).
	assert_int(runner.shard_cpu_msec.size()).is_equal(2)
	for ms: int in runner.shard_cpu_msec:
		if FileAccess.file_exists("/proc/self/stat"):
			assert_int(ms).is_greater(0)
		else:
			assert_int(ms).is_equal(-1)
	assert_int(runner.sharded_msec).is_greater(0)
	for i: int in range(here.size()):
		assert_str(there[i].path).is_equal(here[i].path)
		assert_str(there[i].name).is_equal(here[i].name)
		assert_bool(there[i].passed).is_equal(here[i].passed)
		assert_array(Array(there[i].messages)).is_equal(Array(here[i].messages))
		assert_int(there[i].frames).is_equal(here[i].frames)
		assert_str(there[i].hash_line).is_equal(here[i].hash_line)
		assert_bool(there[i].passed).is_true()


func test_a_result_survives_its_line() -> void:
	var r := FixtureRunner.Result.new()
	r.name = "a_fixture"
	r.path = "res://tests/replay/x/a_fixture.fixture"
	r.frames = 120
	r.msec = 12.5
	r.hash_line = "in:0000abcd content:12345678 120:deadbeef 60:0badf00d"
	r.fail("line 4: at 3 x=1: frame 3: x=2\n    golden a\tb")
	r.fail('ünïcode, a backslash \\ and a quote "')
	var back: FixtureRunner.Result = FixtureRunner.Result.from_line(r.to_line())
	assert_str(back.name).is_equal(r.name)
	assert_str(back.path).is_equal(r.path)
	assert_bool(back.passed).is_false()
	assert_int(back.frames).is_equal(120)
	assert_float(back.msec).is_equal(12.5)
	assert_str(back.hash_line).is_equal(r.hash_line)
	assert_array(Array(back.messages)).is_equal(Array(r.messages))


func test_a_shard_that_dies_fails_its_fixtures() -> void:
	var runner := FixtureRunner.new()
	runner.shard_script = "res://tests/unit/tools/no_such_shard.gd"
	var results: Array[FixtureRunner.Result] = runner.run_sharded(_paths(), 2)
	assert_int(results.size()).is_equal(SOME.size())
	for r: FixtureRunner.Result in results:
		assert_bool(r.passed).is_false()
		assert_str(r.messages[0]).contains("returned no result")


func _run_in_mode(mode_value: NativeBackend.Mode) -> FixtureRunner:
	var saved_mode: NativeBackend.Mode = NativeBackend.mode()
	NativeBackend.configure(mode_value)
	var runner := FixtureRunner.new()
	var results: Array[FixtureRunner.Result] = runner.run_sharded(_paths(), 2)
	NativeBackend.configure(saved_mode)
	for r: FixtureRunner.Result in results:
		assert_bool(r.passed).is_true()
	return runner


func test_a_shard_runs_in_the_mode_this_process_asked_for() -> void:
	# The A/B of CI (WANE_NATIVE=off, then on) is only an A/B if the shards follow the switch.
	var off: FixtureRunner = _run_in_mode(NativeBackend.Mode.OFF)
	assert_array(off.shard_modes).is_equal(["off native=false", "off native=false"])
	if NativeBackend.available():
		var on: FixtureRunner = _run_in_mode(NativeBackend.Mode.ON)
		assert_array(on.shard_modes).is_equal(["on native=true", "on native=true"])


func test_a_shard_on_another_path_fails_its_fixtures() -> void:
	var runner := FixtureRunner.new()
	var saved_mode: NativeBackend.Mode = NativeBackend.mode()
	runner.shard_script = "res://tests/unit/tools/shard_off_path.gd"
	NativeBackend.configure(NativeBackend.Mode.AUTO)
	var results: Array[FixtureRunner.Result] = runner.run_sharded(_paths(), 2)
	NativeBackend.configure(saved_mode)
	assert_int(results.size()).is_equal(SOME.size())
	for r: FixtureRunner.Result in results:
		assert_bool(r.passed).is_false()
		assert_str(r.messages[r.messages.size() - 1]).contains("ran native")


func test_cpu_time_is_read_from_a_proc_stat_line() -> void:
	# utime 250 and stime 30 clock ticks (field 14 and 15) at 100 a second: 2800 ms. The command
	# name may hold spaces and brackets, so the fields count from the last one.
	var line: String = (
		"4242 (Godot (headless) x) S 1 4242 4242 0 -1 4194560 100 0 0 0 250 30 0 0 20 0 5 0 "
		+ "9999 123456 789 18446744073709551615"
	)
	assert_int(FixtureRunner.cpu_msec_from_stat(line)).is_equal(2800)
	assert_int(FixtureRunner.cpu_msec_from_stat("")).is_equal(-1)
	assert_int(FixtureRunner.cpu_msec_from_stat("4242 (short) S 1 2")).is_equal(-1)


func test_a_busy_machine_does_not_fail_a_suite_whose_cpu_time_is_within_the_budget() -> void:
	# Fixed work costs the same CPU time on a loaded machine and more wall time (F3 of the
	# stress-room review: 11 to 15 s of wall time at load 4 on 4 cores, every fixture passing).
	assert_bool(FixtureRunner.over_budget(9000, 8000, 10000)).is_false()
	assert_bool(FixtureRunner.over_budget(15000, 8000, 10000)).is_false()
	# Both over: the suite itself got slower.
	assert_bool(FixtureRunner.over_budget(15000, 12000, 10000)).is_true()
	# Nothing known about CPU time (not Linux): wall time is the measure, as it always was.
	assert_bool(FixtureRunner.over_budget(15000, -1, 10000)).is_true()
	assert_bool(FixtureRunner.over_budget(9000, -1, 10000)).is_false()
	# No budget (an instrumented coverage run).
	assert_bool(FixtureRunner.over_budget(99999, 99999, 0)).is_false()
