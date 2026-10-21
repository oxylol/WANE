extends GdUnitTestSuite
## The unit stage in several processes (tools/ci/unit_runner.gd, docs/adr/0006, "Unit shards"),
## run on small suites written for the purpose into tests/unit_scratch/ (outside the folder the
## stage scans): what passes merges, and every way a process can go wrong fails the stage and says
## so. Each case starts real gdUnit4 processes, so there are few and each covers several things.

const SCRATCH: String = "res://tests/unit_scratch"
const SAMPLES: String = "res://tests/unit/tools/samples/"
## Not reports/unit, which belongs to the run that is running this suite.
const REPORTS: String = "res://reports/unit_runner_test"

var _log: String = ""


func before_test() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH))
	_log = ProjectSettings.globalize_path("user://test_unit_runner_none.jsonl")


func after_test() -> void:
	_clean()


func _clean() -> void:
	var dir: String = ProjectSettings.globalize_path(SCRATCH)
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)
	_remove_tree(ProjectSettings.globalize_path(REPORTS))


func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


## Writes a suite called [param file_name] whose tests are [param tests] (name to body lines).
func _suite(file_name: String, tests: Dictionary[String, String]) -> String:
	var lines: PackedStringArray = ["extends GdUnitTestSuite", ""]
	for test_name: String in tests:
		lines.append("func %s() -> void:" % test_name)
		lines.append("\t" + tests[test_name])
		lines.append("")
	return _write(file_name, "\n".join(lines))


func _write(file_name: String, text: String) -> String:
	var path: String = SCRATCH.path_join(file_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func _runner(processes: int) -> UnitRunner:
	var runner := UnitRunner.new()
	runner.quiet = true
	runner.processes = processes
	runner.log_path = _log
	runner.report_dir = REPORTS
	runner.time_limit_seconds = 120
	return runner


func _failure_text(runner: UnitRunner) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for block: PackedStringArray in runner.failures:
		lines.append_array(block)
	lines.append_array(runner.complaints)
	return "\n".join(lines)


func _paths(runner: UnitRunner) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for suite: UnitReport.Suite in runner.reported:
		out.append(suite.path)
	out.sort()
	return out


func test_passing_suites_in_two_processes_merge_into_one_answer_with_a_report_each() -> void:
	var a: String = _suite(
		"test_a.gd", {"test_one": "assert_int(1).is_equal(1)", "test_two": "pass"}
	)
	var b: String = _suite("test_b.gd", {"test_three": "assert_int(3).is_equal(3)"})
	var runner: UnitRunner = _runner(2)
	assert_bool(runner.run([SCRATCH])).override_failure_message(_failure_text(runner)).is_true()
	assert_str(runner.summary).is_equal("3 cases")
	assert_int(runner.shares.size()).is_equal(2)
	assert_array(runner.failures).is_empty()
	assert_array(runner.complaints).is_empty()
	assert_array(_paths(runner)).is_equal(
		PackedStringArray([a.trim_prefix("res://"), b.trim_prefix("res://")])
	)
	assert_int(runner.process_seconds.size()).is_equal(2)
	# Each process has a report folder of its own.
	for k: int in range(2):
		var dir: String = ProjectSettings.globalize_path(REPORTS.path_join(str(k)))
		assert_str(UnitReport.newest_results(dir)).is_not_empty()


func test_one_process_runs_the_same_suites_with_the_same_answer() -> void:
	_suite("test_a.gd", {"test_one": "pass", "test_two": "pass"})
	_suite("test_b.gd", {"test_three": "pass"})
	var runner: UnitRunner = _runner(1)
	assert_bool(runner.run([SCRATCH])).override_failure_message(_failure_text(runner)).is_true()
	assert_str(runner.summary).is_equal("3 cases")
	assert_int(runner.shares.size()).is_equal(1)
	assert_int(runner.shares[0].size()).is_equal(2)


func test_a_failing_case_a_killed_process_and_a_quiet_exit_each_fail_the_stage() -> void:
	_suite("test_good.gd", {"test_fine": "pass"})
	_suite("test_bad.gd", {"test_wrong_on_purpose": "assert_int(1).is_equal(2)"})
	_suite("test_dies.gd", {"test_is_killed": "OS.kill(OS.get_process_id())"})
	_suite("test_quits.gd", {"test_ends_the_run": "Engine.get_main_loop().call(&'quit', 0)"})
	var runner: UnitRunner = _runner(4)
	assert_bool(runner.run([SCRATCH])).is_false()
	var text: String = _failure_text(runner)
	# The failing case, by suite and name.
	assert_str(text).contains("test_bad > test_wrong_on_purpose")
	# The process that was killed: it exited non-zero with no failing case, and says which.
	assert_str(text).contains("with no failing case")
	assert_str(text).contains("unit process")
	assert_str(runner.summary).contains("failed")
	# Whatever the others did, nothing here is reported as a pass of the whole.
	assert_str(runner.summary).is_not_equal("4 cases")


func test_a_suite_a_process_never_reports_fails_even_when_the_process_exits_clean() -> void:
	_suite("test_real.gd", {"test_runs": "pass"})
	# A line that starts like a test inside a string: found by name, but gdUnit4 sees no test.
	_write(
		"test_fake.gd",
		'extends GdUnitTestSuite\n\nconst TEXT: String = """\nfunc test_not_a_test() -> void:\n"""\n'
	)
	var runner: UnitRunner = _runner(1)
	assert_bool(runner.run([SCRATCH])).is_false()
	assert_str(_failure_text(runner)).contains(
		"suite did not report: res://tests/unit_scratch/test_fake.gd"
	)
	assert_str(_failure_text(runner)).contains("exited 0")


func test_a_run_that_never_ends_is_stopped_and_fails_at_the_time_limit() -> void:
	_suite("test_fast.gd", {"test_quick": "pass"})
	_suite("test_hangs.gd", {"test_never_ends": "while true:\n\t\tOS.delay_msec(50)"})
	var runner: UnitRunner = _runner(2)
	runner.time_limit_seconds = 4
	var began: int = Time.get_ticks_msec()
	assert_bool(runner.run([SCRATCH])).is_false()
	assert_int(Time.get_ticks_msec() - began).is_less(30000)
	assert_str(_failure_text(runner)).contains("unit run stopped after the 4 s time limit")
	assert_str(runner.summary).is_equal("run stopped")


func test_a_path_with_no_suite_fails_instead_of_passing_empty() -> void:
	_write("helper.gd", "extends RefCounted\n")
	var runner: UnitRunner = _runner(2)
	assert_bool(runner.run([SCRATCH])).is_false()
	assert_str(_failure_text(runner)).contains("no test cases found")


func test_a_process_count_is_at_most_four_and_at_most_the_suites() -> void:
	var runner := UnitRunner.new()
	assert_int(runner.process_count(100)).is_between(1, UnitRunner.MAX_PROCESSES)
	assert_int(runner.process_count(1)).is_equal(1)
	assert_int(runner.process_count(0)).is_equal(1)
	runner.processes = 3
	assert_int(runner.process_count(100)).is_equal(3)
	assert_int(runner.process_count(2)).is_equal(2)


## A process that printed the recorded gdUnit4 output [param sample] (or, with none, a few lines
## that end before any summary) and exited with [param code].
func _proc(index: int, sample: String, code: int) -> UnitRunner.Proc:
	var proc := UnitRunner.Proc.new()
	proc.index = index
	proc.exit_code = code
	proc.watch = UnitRunner.UnitWatch.new()
	if sample == "":
		proc.watch.out = PackedStringArray(
			["Run Test Suite: res://tests/unit/x.gd", "x > test_a STARTED"]
		)
	else:
		proc.watch.out = FileAccess.get_file_as_string(SAMPLES + sample).split("\n")
	return proc


func _cases_of(sample: String) -> int:
	var lines: PackedStringArray = FileAccess.get_file_as_string(SAMPLES + sample).split("\n")
	return QuietReport.parse_unit(lines).cases


func test_the_cases_of_processes_that_passed_are_added_up() -> void:
	var runner: UnitRunner = _runner(2)
	var procs: Array[UnitRunner.Proc] = [
		_proc(0, "unit_passed.out", 0), _proc(1, "unit_passed.out", 0)
	]
	assert_bool(runner.merge(procs, [])).is_true()
	assert_str(runner.summary).is_equal("%d cases" % (2 * _cases_of("unit_passed.out")))
	assert_array(runner.failures).is_empty()


func test_a_failing_process_adds_its_failures_and_fails_the_stage() -> void:
	var runner: UnitRunner = _runner(2)
	var procs: Array[UnitRunner.Proc] = [
		_proc(0, "unit_passed.out", 0), _proc(1, "unit_failed.out", 100)
	]
	assert_bool(runner.merge(procs, ["a"])).is_false()
	var all: int = _cases_of("unit_passed.out") + _cases_of("unit_failed.out")
	assert_str(runner.summary).starts_with("%d cases, " % all)
	assert_str(runner.summary).contains("failed")
	assert_array(runner.failures).is_not_empty()


func test_a_process_that_exits_clean_without_a_summary_fails() -> void:
	var runner: UnitRunner = _runner(2)
	var procs: Array[UnitRunner.Proc] = [_proc(0, "unit_passed.out", 0), _proc(1, "", 0)]
	assert_bool(runner.merge(procs, [])).is_false()
	assert_str(_failure_text(runner)).contains("unit process 1 exited 0 but printed no summary")
	assert_str(runner.summary).contains("1 of 2 processes without a result")


func test_processes_that_all_died_leave_no_result() -> void:
	var runner: UnitRunner = _runner(2)
	var procs: Array[UnitRunner.Proc] = [_proc(0, "", 9), _proc(1, "", 139)]
	assert_bool(runner.merge(procs, [])).is_false()
	assert_str(runner.summary).is_equal("no result")
	assert_str(_failure_text(runner)).contains("unit process 0 exited 9")
	assert_str(_failure_text(runner)).contains("unit process 1 exited 139")


func test_a_lone_process_is_called_the_unit_run_as_before() -> void:
	var runner: UnitRunner = _runner(1)
	var procs: Array[UnitRunner.Proc] = [_proc(0, "", 1)]
	assert_bool(runner.merge(procs, [])).is_false()
	assert_str(_failure_text(runner)).contains("unit run exited 1")
