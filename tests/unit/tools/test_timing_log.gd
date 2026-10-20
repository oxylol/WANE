extends GdUnitTestSuite
## The Godot side of the timing log (tools/ci/timing_log.gd, tools/ci/unit_report.gd,
## docs/adr/0023): the line it writes (the fields tools/ci/timing_report.py reads), the floors under
## which a case or fixture is not logged, the switches in the environment, and the reading of
## gdUnit4's report.

const SAMPLE_REPORT: String = "res://tests/unit/tools/samples/unit_results.xml"
const SCRATCH: String = "user://test_timing_log"

var _log_path: String = ""


func before_test() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH))
	_log_path = ProjectSettings.globalize_path(SCRATCH).path_join("timings.jsonl")
	OS.set_environment(TimingLog.ENV_PATH, _log_path)
	OS.unset_environment(TimingLog.ENV_TOOL)
	OS.unset_environment(TimingLog.ENV_RUN)


func after_test() -> void:
	OS.unset_environment(TimingLog.ENV_PATH)
	OS.unset_environment(TimingLog.ENV_TOOL)
	OS.unset_environment(TimingLog.ENV_RUN)
	_clean()


func _clean() -> void:
	var dir: String = ProjectSettings.globalize_path(SCRATCH)
	if DirAccess.dir_exists_absolute(dir):
		_remove_tree(dir)


func _remove_tree(dir: String) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


## Line [param index] of the log, as a typed dictionary.
func _line(index: int) -> Dictionary[String, Variant]:
	var typed: Dictionary[String, Variant] = {}
	typed.assign(_lines()[index])
	return typed


func _lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(_log_path):
		return out
	for text: String in FileAccess.get_file_as_string(_log_path).split("\n", false):
		var parsed: Variant = JSON.parse_string(text)
		assert_bool(parsed is Dictionary).override_failure_message(text).is_true()
		out.append(parsed)
	return out


func test_a_line_is_json_with_the_documented_fields_in_order() -> void:
	var timing := TimingLog.new("run_tests.gd", "native=on")
	timing.add("unit", "suite", "tests/unit/core/test_rng.gd", 1.23456)
	assert_int(timing.pending()).is_equal(1)
	assert_bool(timing.flush()).is_true()
	assert_int(timing.pending()).is_equal(0)
	var text: String = FileAccess.get_file_as_string(_log_path)
	var keys: Array[String] = []
	var line: Dictionary[String, Variant] = _line(0)
	for key: String in line.keys():
		keys.append(key)
	assert_array(keys).is_equal(
		[
			"ts",
			"run",
			"commit",
			"tool",
			"stage",
			"kind",
			"item",
			"variant",
			"seconds",
			"processors",
			"load"
		]
	)
	assert_str(text).contains('"seconds":1.235,')
	assert_str(text).is_equal(text.strip_edges() + "\n")
	assert_str(line["tool"]).is_equal("run_tests.gd")
	assert_str(line["stage"]).is_equal("unit")
	assert_str(line["kind"]).is_equal("suite")
	assert_str(line["item"]).is_equal("tests/unit/core/test_rng.gd")
	assert_str(line["variant"]).is_equal("native=on")
	assert_float(line["seconds"]).is_equal_approx(1.235, 0.0001)
	var processors: int = line["processors"]
	assert_int(processors).is_greater(0)
	var stamp: RegEx = RegEx.create_from_string("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ$")
	var stamp_text: String = line["ts"]
	assert_bool(stamp.search(stamp_text) != null).override_failure_message(stamp_text).is_true()
	assert_str(line["commit"]).is_not_empty()


func test_an_item_with_quotes_and_backslashes_survives_the_round_trip() -> void:
	var timing := TimingLog.new("run_tests.gd")
	var item: String = 'tests/x.gd::test_"quoted"_and_\\_slash'
	timing.add("unit", "case", item, 0.5)
	timing.flush()
	assert_str(_lines()[0]["item"]).is_equal(item)


func test_every_line_of_a_run_shares_its_stamp_and_run_id() -> void:
	var timing := TimingLog.new("run_tests.gd")
	timing.add("compile", "stage", "compile", 4.0)
	timing.add("unit", "stage", "unit", 200.0)
	timing.flush()
	var lines: Array[Dictionary] = _lines()
	assert_int(lines.size()).is_equal(2)
	assert_str(lines[0]["run"]).is_equal(lines[1]["run"])
	assert_str(lines[0]["ts"]).is_equal(lines[1]["ts"])
	assert_that(lines[0]["load"]).is_equal(lines[1]["load"])


func test_a_case_or_fixture_under_its_floor_is_not_logged_but_a_stage_always_is() -> void:
	var timing := TimingLog.new("run_tests.gd")
	timing.add("unit", "case", "quick", TimingLog.FLOORS["case"] - 0.001)
	timing.add("unit", "case", "slow", TimingLog.FLOORS["case"])
	timing.add("fixtures", "fixture", "quick", TimingLog.FLOORS["fixture"] - 0.001)
	timing.add("fixtures", "fixture", "slow", TimingLog.FLOORS["fixture"])
	timing.add("content", "stage", "content", 0.0)
	timing.add("unit", "suite", "tiny.gd", 0.001)
	timing.flush()
	var items: Array[String] = []
	for i: int in range(_lines().size()):
		var line: Dictionary[String, Variant] = _line(i)
		items.append("%s %s" % [line["kind"], line["item"]])
	assert_array(items).is_equal(["case slow", "fixture slow", "stage content", "suite tiny.gd"])


func test_flushing_twice_appends_and_an_empty_flush_writes_nothing() -> void:
	var first := TimingLog.new("run_tests.gd")
	first.add("unit", "stage", "unit", 1.0)
	first.flush()
	var second := TimingLog.new("run_tests.gd")
	assert_bool(second.flush()).is_true()
	second.add("compile", "stage", "compile", 2.0)
	second.flush()
	var lines: Array[Dictionary] = _lines()
	assert_int(lines.size()).is_equal(2)
	assert_str(lines[0]["stage"]).is_equal("unit")
	assert_str(lines[1]["stage"]).is_equal("compile")


func test_off_writes_nothing() -> void:
	OS.set_environment(TimingLog.ENV_PATH, TimingLog.OFF)
	var timing := TimingLog.new("run_tests.gd")
	assert_bool(timing.enabled()).is_false()
	timing.add("unit", "stage", "unit", 1.0)
	assert_int(timing.pending()).is_equal(0)
	assert_bool(timing.flush()).is_true()
	assert_bool(FileAccess.file_exists(_log_path)).is_false()


func test_the_environment_names_the_tool_and_the_run() -> void:
	OS.set_environment(TimingLog.ENV_TOOL, "ci/unit.sh")
	OS.set_environment(TimingLog.ENV_RUN, "shared-run-7")
	var timing := TimingLog.new("run_tests.gd")
	timing.add("unit", "stage", "unit", 1.0)
	timing.flush()
	var line: Dictionary[String, Variant] = _line(0)
	assert_str(line["tool"]).is_equal("ci/unit.sh")
	assert_str(line["run"]).is_equal("shared-run-7")


func test_an_item_can_carry_a_variant_of_its_own() -> void:
	var timing := TimingLog.new("tools/replay/film.gd", "native=on")
	timing.add("film", "film", "jump_tap", 3.0, "every=10 zoom=1.0")
	timing.add("film", "film", "jump_tap", 3.0)
	timing.flush()
	var lines: Array[Dictionary] = _lines()
	assert_str(lines[0]["variant"]).is_equal("every=10 zoom=1.0")
	assert_str(lines[1]["variant"]).is_equal("native=on")


func test_an_unknown_load_is_null_and_a_known_one_has_two_decimals() -> void:
	var entry: Dictionary[String, Variant] = {"seconds": 0.5, "load": -1.0, "processors": 4}
	assert_str(TimingLog.format(entry)).is_equal('{"seconds":0.500,"load":null,"processors":4}')
	entry["load"] = 2.3456
	assert_str(TimingLog.format(entry)).is_equal('{"seconds":0.500,"load":2.35,"processors":4}')


func test_a_log_over_the_size_limit_is_moved_aside_before_the_append() -> void:
	var big: FileAccess = FileAccess.open(_log_path, FileAccess.WRITE)
	var pad: PackedByteArray = PackedByteArray()
	pad.resize(TimingLog.MAX_BYTES + 1)
	pad.fill(32)
	big.store_buffer(pad)
	big.close()
	var timing := TimingLog.new("run_tests.gd")
	timing.add("unit", "stage", "unit", 1.0)
	timing.flush()
	assert_bool(FileAccess.file_exists(_log_path + ".1")).is_true()
	assert_int(_lines().size()).is_equal(1)


func test_the_fixture_runner_reports_each_fixtures_time_in_seconds() -> void:
	var runner := FixtureRunner.new()
	var fast := FixtureRunner.Result.new()
	fast.name = "fast"
	fast.msec = 12.5
	var slow := FixtureRunner.Result.new()
	slow.name = "slow"
	slow.msec = 2500.0
	runner.results = [fast, slow]
	var times: Dictionary[String, float] = runner.timings()
	assert_array(times.keys()).is_equal(["fast", "slow"])
	assert_float(times["fast"]).is_equal_approx(0.0125, 0.000001)
	assert_float(times["slow"]).is_equal_approx(2.5, 0.000001)


func test_the_unit_report_gives_each_suite_its_path_time_and_cases() -> void:
	var suites: Array[UnitReport.Suite] = UnitReport.read(SAMPLE_REPORT)
	assert_int(suites.size()).is_equal(2)
	assert_str(suites[0].path).is_equal("tests/unit/tools/test_quiet_report.gd")
	assert_float(suites[0].seconds).is_equal_approx(0.251, 0.00001)
	assert_int(suites[0].case_names.size()).is_equal(3)
	assert_str(suites[0].case_names[0]).is_equal("test_ansi_colours_and_clear_screen_are_stripped")
	assert_float(suites[0].case_seconds[0]).is_equal_approx(0.011, 0.00001)
	assert_str(suites[1].path).is_equal("tests/unit/core/test_rng.gd")
	assert_float(suites[1].seconds).is_equal_approx(0.371, 0.00001)


func test_an_unreadable_unit_report_has_no_suites() -> void:
	assert_int(UnitReport.read(SCRATCH.path_join("nope.xml")).size()).is_equal(0)
	var garbage: FileAccess = FileAccess.open(_log_path, FileAccess.WRITE)
	garbage.store_string("not xml at all")
	garbage.close()
	assert_int(UnitReport.read(_log_path).size()).is_equal(0)


func test_the_newest_report_folder_is_the_highest_numbered_one_with_results() -> void:
	var root: String = ProjectSettings.globalize_path(SCRATCH).path_join("reports")
	assert_str(UnitReport.newest_results(root)).is_empty()
	for number: int in [1, 2, 10]:
		DirAccess.make_dir_recursive_absolute(root.path_join("report_%d" % number))
		var results: FileAccess = FileAccess.open(
			root.path_join("report_%d" % number).path_join("results.xml"), FileAccess.WRITE
		)
		results.store_string("<testsuites/>")
		results.close()
	DirAccess.make_dir_recursive_absolute(root.path_join("report_11"))
	DirAccess.make_dir_recursive_absolute(root.path_join("css"))
	assert_str(UnitReport.newest_results(root)).is_equal(
		root.path_join("report_10").path_join("results.xml")
	)


func test_the_load_average_is_read_where_the_system_has_one() -> void:
	var load_avg: float = TimingLog.load_average()
	if OS.get_name() == "Linux":
		assert_float(load_avg).is_greater_equal(0.0)
	else:
		assert_float(load_avg).is_greater_equal(-1.0)
