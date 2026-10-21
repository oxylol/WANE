extends GdUnitTestSuite
## How the unit stage divides its suites over processes (tools/ci/unit_shards.gd, docs/adr/0006,
## "Unit shards"): the plan balances by cost and keeps what must stay together together, every
## suite is in exactly one process, the costs come from the timing log and fall back to file size,
## and the suites found are the ones gdUnit4 itself would run.

const SCRATCH: String = "user://test_unit_shards"
const UNIT_ROOT: String = "res://tests/unit"

var _log: String = ""


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH))
	_log = ProjectSettings.globalize_path(SCRATCH).path_join("timings.jsonl")


func after_test() -> void:
	var dir: String = ProjectSettings.globalize_path(SCRATCH)
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _bundles(
	costs: Dictionary[String, float], groups: Dictionary[String, String] = {}
) -> Array[UnitShards.Bundle]:
	var suites: Array[String] = []
	for path: String in costs:
		suites.append(path)
	suites.sort()
	return UnitShards.bundles(suites, costs, groups)


func _write_log(lines: PackedStringArray) -> void:
	var file: FileAccess = FileAccess.open(_log, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()


func _suite_line(item: String, seconds: float, variant: String = "native=auto") -> String:
	return (
		'{"ts":"t","run":"r","commit":"c","tool":"ci/test.sh","stage":"unit","kind":"suite",'
		+ (
			'"item":"%s","variant":"%s","seconds":%.3f,"processors":4,"load":1.00}'
			% [item, variant, seconds]
		)
	)


func _flat(shares: Array[PackedStringArray]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for share: PackedStringArray in shares:
		out.append_array(share)
	out.sort()
	return out


func test_the_costliest_suite_goes_first_onto_the_process_with_the_least() -> void:
	var costs: Dictionary[String, float] = {"a": 100.0, "b": 60.0, "c": 50.0, "d": 40.0, "e": 30.0}
	var shares: Array[PackedStringArray] = UnitShards.plan(_bundles(costs), 2)
	# a(100) to p0, b(60) to p1, c(50) to p1 (60 < 100: now 110), d(40) to p0 (100 < 110: now 140),
	# e(30) to p1 (110 < 140).
	assert_int(shares.size()).is_equal(2)
	assert_array(shares[0]).is_equal(PackedStringArray(["a", "d"]))
	assert_array(shares[1]).is_equal(PackedStringArray(["b", "c", "e"]))


func test_every_suite_is_in_exactly_one_process_whatever_the_costs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for trial: int in range(30):
		var costs: Dictionary[String, float] = {}
		var count: int = rng.randi_range(1, 40)
		for i: int in range(count):
			costs["tests/unit/s%02d.gd" % i] = rng.randf_range(0.0, 100.0)
		var want: PackedStringArray = PackedStringArray(costs.keys())
		want.sort()
		for processes: int in [1, 2, 3, 4, 7]:
			var shares: Array[PackedStringArray] = UnitShards.plan(_bundles(costs), processes)
			assert_array(_flat(shares)).override_failure_message("trial %d" % trial).is_equal(want)
			assert_int(shares.size()).is_less_equal(processes)
			assert_int(shares.size()).is_greater(0)


func test_the_busiest_process_is_no_more_than_the_largest_suite_over_the_mean() -> void:
	# The longest-first rule leaves the busiest process no more than the largest suite above the
	# mean, which is what makes the plan worth having.
	var costs: Dictionary[String, float] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var total: float = 0.0
	var biggest: float = 0.0
	for i: int in range(60):
		var cost: float = rng.randf_range(0.5, 40.0)
		costs["s%02d" % i] = cost
		total += cost
		biggest = maxf(biggest, cost)
	var shares: Array[PackedStringArray] = UnitShards.plan(_bundles(costs), 4)
	var busiest: float = 0.0
	for share: PackedStringArray in shares:
		var load_of: float = 0.0
		for path: String in share:
			load_of += costs[path]
		busiest = maxf(busiest, load_of)
	assert_float(busiest).is_less_equal(total / 4.0 + biggest)


func test_a_plan_is_the_same_every_time_and_ties_go_to_the_lower_process_and_path() -> void:
	var costs: Dictionary[String, float] = {"c": 5.0, "a": 5.0, "b": 5.0, "d": 5.0}
	var first: Array[PackedStringArray] = UnitShards.plan(_bundles(costs), 2)
	var second: Array[PackedStringArray] = UnitShards.plan(_bundles(costs), 2)
	assert_array(first).is_equal(second)
	assert_array(first[0]).is_equal(PackedStringArray(["a", "c"]))
	assert_array(first[1]).is_equal(PackedStringArray(["b", "d"]))


func test_suites_of_one_group_share_a_process_and_weigh_as_one() -> void:
	var costs: Dictionary[String, float] = {"a": 10.0, "b": 10.0, "c": 10.0, "d": 1.0, "e": 1.0}
	var groups: Dictionary[String, String] = {"a": "files", "b": "files", "c": "files"}
	var bundles: Array[UnitShards.Bundle] = _bundles(costs, groups)
	assert_int(bundles.size()).is_equal(3)
	assert_float(bundles[0].cost).is_equal(30.0)
	var shares: Array[PackedStringArray] = UnitShards.plan(bundles, 4)
	for share: PackedStringArray in shares:
		assert_bool(share.has("a") == share.has("b") and share.has("b") == share.has("c")).is_true()
	# The group is the heaviest bundle and has a process to itself; the small suites get one each.
	assert_array(shares[0]).is_equal(PackedStringArray(["a", "b", "c"]))
	assert_int(shares.size()).is_equal(3)


func test_fewer_suites_than_processes_makes_fewer_processes() -> void:
	var costs: Dictionary[String, float] = {"a": 1.0, "b": 2.0}
	assert_int(UnitShards.plan(_bundles(costs), 4).size()).is_equal(2)
	assert_int(UnitShards.plan(_bundles(costs), 1).size()).is_equal(1)
	assert_int(UnitShards.plan(_bundles(costs), 0).size()).is_equal(1)


func test_a_suite_costs_the_median_of_its_last_three_logged_times() -> void:
	_write_log(
		[
			_suite_line("tests/unit/a.gd", 90.0),
			_suite_line("tests/unit/a.gd", 10.0),
			_suite_line("tests/unit/a.gd", 20.0),
			_suite_line("tests/unit/a.gd", 30.0),
			_suite_line("tests/unit/b.gd", 5.0),
		]
	)
	var seen: Dictionary[String, float] = UnitShards.logged_seconds(_log, "native=auto")
	assert_float(seen["tests/unit/a.gd"]).is_equal(20.0)
	assert_float(seen["tests/unit/b.gd"]).is_equal(5.0)


func test_the_times_of_the_same_variant_win_and_other_variants_stand_in() -> void:
	_write_log(
		[
			_suite_line("tests/unit/a.gd", 1.0, "native=on"),
			_suite_line("tests/unit/a.gd", 50.0, "native=off"),
			_suite_line("tests/unit/b.gd", 50.0, "native=off"),
		]
	)
	var seen: Dictionary[String, float] = UnitShards.logged_seconds(_log, "native=on")
	assert_float(seen["tests/unit/a.gd"]).is_equal(1.0)
	assert_float(seen["tests/unit/b.gd"]).is_equal(50.0)


func test_other_lines_and_a_rotated_half_are_read_correctly() -> void:
	var rotated: FileAccess = FileAccess.open(_log + ".1", FileAccess.WRITE)
	rotated.store_string(_suite_line("tests/unit/a.gd", 8.0) + "\n")
	rotated.close()
	_write_log(
		[
			'{"kind":"case","stage":"unit","item":"tests/unit/a.gd::t","variant":"","seconds":99.000}',
			'{"kind":"suite","stage":"fixtures","item":"tests/unit/a.gd","variant":"","seconds":99.0}',
			"torn line",
			_suite_line("tests/unit/a.gd", 12.0),
		]
	)
	var seen: Dictionary[String, float] = UnitShards.logged_seconds(_log, "native=auto")
	assert_int(seen.size()).is_equal(1)
	assert_float(seen["tests/unit/a.gd"]).is_equal(10.0)


func test_a_suite_the_log_has_not_seen_costs_its_size_at_the_rate_of_those_it_has() -> void:
	var seen_path: String = "res://tests/unit/tools/test_unit_shards.gd"
	var fresh_path: String = "res://tests/unit/tools/test_quiet_report.gd"
	var seen_size: int = UnitShards.file_size(seen_path)
	var fresh_size: int = UnitShards.file_size(fresh_path)
	_write_log([_suite_line("tests/unit/tools/test_unit_shards.gd", 10.0)])
	var suites: Array[String] = [seen_path, fresh_path]
	var cost: Dictionary[String, float] = UnitShards.costs(suites, _log, "native=auto")
	assert_float(cost[seen_path]).is_equal(10.0)
	assert_float(cost[fresh_path]).is_equal_approx(10.0 * fresh_size / seen_size, 0.0001)


func test_with_no_log_a_suite_costs_its_size() -> void:
	var path: String = "res://tests/unit/tools/test_unit_shards.gd"
	var cost: Dictionary[String, float] = UnitShards.costs([path], _log + ".missing", "")
	assert_float(cost[path]).is_equal(float(UnitShards.file_size(path)))


func test_the_median_of_samples() -> void:
	assert_float(UnitShards.median(PackedFloat64Array())).is_equal(0.0)
	assert_float(UnitShards.median(PackedFloat64Array([3.0]))).is_equal(3.0)
	assert_float(UnitShards.median(PackedFloat64Array([9.0, 1.0, 4.0]))).is_equal(4.0)
	assert_float(UnitShards.median(PackedFloat64Array([8.0, 2.0, 4.0, 6.0]))).is_equal(5.0)


func test_a_group_is_named_by_its_line_and_a_file_without_one_has_none() -> void:
	assert_str(UnitShards.group_of("res://tests/unit/tools/test_room_document.gd")).is_equal(
		"room-scratch"
	)
	assert_str(UnitShards.group_of("res://tests/unit/core/test_rng.gd")).is_empty()


func test_the_suites_that_share_the_room_scratch_folder_are_all_in_the_group() -> void:
	# A suite that writes rooms to tests/replay/rooms/ed_scratch/ (or builds the editor panel, which
	# reads every room there) must run in one process with the others that do, or one process would
	# read a room another is half way through writing. This is the net for a suite added later.
	var touching: Array[String] = []
	for path: String in FileWalk.find(UNIT_ROOT, [".gd"]):
		if path.ends_with("/test_unit_shards.gd"):
			continue
		var text: String = FileAccess.get_file_as_string(path)
		var touches: bool = false
		for word: String in ["ed_scratch", "RoomEditorSuite", "RoomEditorPanel", "RoomDocument"]:
			touches = touches or text.contains(word)
		if touches:
			touching.append(path)
	assert_array(touching).is_not_empty()
	for path: String in touching:
		if path.ends_with("/room_editor_suite.gd"):
			continue
		(
			assert_str(UnitShards.group_of(path))
			. override_failure_message(
				"%s uses the room scratch folder: add '# unit-group: room-scratch'" % path
			)
			. is_equal("room-scratch")
		)


func test_the_suites_found_are_the_ones_gdunit4_would_run() -> void:
	# The unit stage hands gdUnit4 each suite by name instead of the folder, so a suite this misses
	# would never run. gdUnit4's own scanner is the authority: every script it finds must be found
	# here unless it has no test method (a base class of helpers), and nothing else may be.
	var found: Array[String] = UnitShards.find_suites([UNIT_ROOT])
	assert_int(found.size()).is_greater(50)
	var scanned: Array[String] = []
	var scanner := GdUnitTestSuiteScanner.new()
	for script: Script in scanner.scan_directory(UNIT_ROOT):
		if _has_test_method(script):
			scanned.append(script.resource_path)
	scanned.sort()
	assert_array(found).is_equal(scanned)


func _has_test_method(script: Script) -> bool:
	var current: Script = script
	while current != null and not current.resource_path.contains("GdUnitTestSuite"):
		var methods: Array[Dictionary] = current.get_script_method_list()
		for i: int in range(methods.size()):
			var method_name: String = methods[i]["name"]
			if method_name.begins_with("test"):
				return true
		current = current.get_base_script()
	return false
