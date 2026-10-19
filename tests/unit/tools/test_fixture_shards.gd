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
	var there: Array[FixtureRunner.Result] = FixtureRunner.new().run_sharded(paths, 2)
	assert_int(there.size()).is_equal(here.size())
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
