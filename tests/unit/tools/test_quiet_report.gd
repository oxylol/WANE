extends GdUnitTestSuite
## The failure extraction behind `ci/test.sh --quiet` and `ci/unit.sh --quiet`
## (tools/ci/quiet_report.gd), run on recorded gdUnit4 output (tests/unit/tools/samples/, ANSI
## colour codes included) and on the messages the compile stage and the fixture runner produce.

const SAMPLES: String = "res://tests/unit/tools/samples/"
const SUITE: String = "res://tests/unit/scratch/test_scratch_fail.gd"


func _sample(file_name: String) -> PackedStringArray:
	return FileAccess.get_file_as_string(SAMPLES + file_name).split("\n")


func _numbered(count: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(count):
		out.append("line %d" % i)
	return out


func test_ansi_colours_and_clear_screen_are_stripped() -> void:
	var coloured: String = "\u001b[38;2;178;34;34m\u001b[1m FAILED\u001b[0m\u001b[2J\u001b[H ok"
	assert_str(QuietReport.strip_ansi(coloured)).is_equal(" FAILED ok")


func test_the_samples_really_carry_colour_codes() -> void:
	for file_name: String in ["unit_failed.out", "unit_passed.out", "unit_runtime_error.out"]:
		(
			assert_bool(FileAccess.get_file_as_string(SAMPLES + file_name).contains("\u001b["))
			. is_true()
		)


func test_a_failing_run_gives_each_failing_case_with_its_message() -> void:
	var result: QuietReport.UnitResult = QuietReport.parse_unit(_sample("unit_failed.out"))
	assert_bool(result.has_summary).is_true()
	assert_int(result.cases).is_equal(3)
	assert_int(result.failures).is_equal(2)
	assert_int(result.failed()).is_equal(2)
	assert_int(result.blocks.size()).is_equal(2)
	(
		assert_array(result.blocks[0])
		. is_equal(
			[
				"test_scratch_fail > test_fails_equal",
				"    Expecting:",
				"     5",
				"     but was",
				"     4",
				"    at 'test_fails_equal' in %s:10" % SUITE,
			]
		)
	)
	assert_str(result.blocks[1][0]).is_equal("test_scratch_fail > test_fails_array")
	assert_str(result.blocks[1][1]).is_equal("    Expecting contains exactly elements:")
	assert_str(result.blocks[1][result.blocks[1].size() - 1]).is_equal(
		"    at 'test_fails_array' in %s:15" % SUITE
	)


func test_the_bbcode_difference_table_is_left_out() -> void:
	var result: QuietReport.UnitResult = QuietReport.parse_unit(
		_sample("unit_failed_with_diff.out")
	)
	assert_int(result.cases).is_equal(4)
	assert_int(result.blocks.size()).is_equal(3)
	(
		assert_array(result.blocks[2])
		. is_equal(
			[
				"test_scratch_fail > test_fails_array_is_equal",
				"    Expecting:",
				"     '[1, 2, 4]'",
				"     but was",
				"     '[1, 2, 3]'",
				"    at 'test_fails_array_is_equal' in %s:20" % SUITE,
			]
		)
	)


func test_the_failure_text_has_no_escape_codes_and_the_passing_case_is_absent() -> void:
	var result: QuietReport.UnitResult = QuietReport.parse_unit(_sample("unit_failed.out"))
	for block: PackedStringArray in result.blocks:
		for line: String in block:
			assert_bool(line.contains("\u001b")).is_false()
			assert_bool(line.contains("test_passes")).is_false()


func test_a_runtime_error_in_a_case_is_a_failure_with_the_engines_message() -> void:
	var result: QuietReport.UnitResult = QuietReport.parse_unit(_sample("unit_runtime_error.out"))
	assert_int(result.cases).is_equal(2)
	assert_int(result.errors).is_equal(1)
	assert_int(result.blocks.size()).is_equal(1)
	(
		assert_array(result.blocks[0])
		. is_equal(
			[
				"test_scratch_error > test_runtime_error",
				"    Godot Runtime Error !",
				"    'Cannot call method 'queue_free' on a null value.'",
				"    at 'test_runtime_error' in res://tests/unit/scratch/test_scratch_error.gd:6",
			]
		)
	)


func test_engine_error_lines_among_the_output_do_not_leak_into_a_failure() -> void:
	# Recorded with stdout and stderr merged: a SCRIPT ERROR and its backtrace come first.
	var merged: QuietReport.UnitResult = QuietReport.parse_unit(
		_sample("unit_runtime_error_with_stderr.out")
	)
	var plain: QuietReport.UnitResult = QuietReport.parse_unit(_sample("unit_runtime_error.out"))
	assert_int(merged.blocks.size()).is_equal(1)
	assert_array(merged.blocks[0]).is_equal(plain.blocks[0])


func test_a_suite_that_does_not_compile_gives_its_parse_errors() -> void:
	var result: QuietReport.UnitResult = QuietReport.parse_unit(_sample("unit_compile_error.out"))
	assert_bool(result.has_summary).is_false()
	assert_int(result.blocks.size()).is_equal(0)
	(
		assert_array(result.discovery)
		. is_equal(
			[
				'Parse Error: Cannot assign a value of type "String" as "int".',
				"at res://tests/unit/scratch/test_scratch_compile.gd:5",
				'Parse Error: Cannot assign a value of type String to variable "x" with specified type int.',
				"at res://tests/unit/scratch/test_scratch_compile.gd:5",
			]
		)
	)
	var blocks: Array[PackedStringArray] = result.failure_blocks(105)
	assert_int(blocks.size()).is_equal(1)
	assert_str(blocks[0][0]).is_equal("a suite does not compile")
	assert_int(blocks[0].size()).is_equal(5)


func test_a_green_run_has_its_case_count_and_nothing_to_report() -> void:
	var result: QuietReport.UnitResult = QuietReport.parse_unit(_sample("unit_passed.out"))
	assert_bool(result.has_summary).is_true()
	assert_int(result.cases).is_equal(6)
	assert_int(result.failed()).is_equal(0)
	assert_int(result.blocks.size()).is_equal(0)


func test_a_run_cut_off_before_its_summary_still_reports_what_it_saw() -> void:
	var lines: PackedStringArray = _sample("unit_failed.out")
	var cut: int = 0
	while not QuietReport.strip_ansi(lines[cut]).begins_with("Statistics:"):
		cut += 1
	var result: QuietReport.UnitResult = QuietReport.parse_unit(lines.slice(0, cut))
	assert_bool(result.has_summary).is_false()
	assert_int(result.cases).is_equal(0)
	assert_int(result.failed()).is_equal(2)


func test_a_failed_exit_with_no_failing_case_shows_the_last_lines() -> void:
	var lines: PackedStringArray = _numbered(30)
	var result: QuietReport.UnitResult = QuietReport.parse_unit(lines)
	var blocks: Array[PackedStringArray] = result.failure_blocks(7)
	assert_int(blocks.size()).is_equal(1)
	assert_str(blocks[0][0]).is_equal("unit run exited 7 with no failing case; its last lines:")
	assert_int(blocks[0].size()).is_equal(1 + QuietReport.TAIL_LINES)
	assert_str(blocks[0][blocks[0].size() - 1]).is_equal("    line 29")


func test_a_long_message_is_cut_but_keeps_its_location() -> void:
	var lines: PackedStringArray = PackedStringArray(
		["  res://tests/unit/x/test_big.gd > test_dump FAILED 5ms", "  Report:"]
	)
	for i: int in range(40):
		lines.append(" row %d" % i)
	lines[lines.size() - 1] += "\tat 'test_dump' in res://tests/unit/x/test_big.gd:77"
	lines.append("")
	lines.append(
		"Overall Summary: 1 test cases | 0 errors | 1 failures | 0 flaky | 0 skipped | 0 orphans |"
	)
	var result: QuietReport.UnitResult = QuietReport.parse_unit(lines)
	var block: PackedStringArray = result.blocks[0]
	assert_int(block.size()).is_equal(1 + QuietReport.MAX_DETAIL_LINES + 1)
	assert_str(block[0]).is_equal("test_big > test_dump")
	assert_str(block[block.size() - 2]).contains("more line")
	assert_str(block[block.size() - 1]).is_equal(
		"    at 'test_dump' in res://tests/unit/x/test_big.gd:77"
	)


func test_a_parameterized_case_keeps_its_name_and_an_orphan_warning_is_reported() -> void:
	var lines: PackedStringArray = [
		"  res://t/test_p.gd > test_sum:1 (2, 3) FAILED (retry 2) 3ms",
		"  Report:",
		"  Expecting: 5",
		"  res://t/test_p.gd > test_leak WARNING 2ms",
		"  Report:",
		"  Detected orphan nodes: 1",
	]
	var result: QuietReport.UnitResult = QuietReport.parse_unit(lines)
	assert_int(result.blocks.size()).is_equal(2)
	assert_str(result.blocks[0][0]).is_equal("test_p > test_sum:1 (2, 3)")
	assert_array(result.blocks[0].slice(1)).is_equal(["    Expecting: 5"])
	assert_str(result.blocks[1][0]).is_equal("test_p > test_leak")


func test_a_suite_level_failure_is_reported_as_the_suite_finalize() -> void:
	var lines: PackedStringArray = [
		"  test_suite > finalize()",
		"  Report:",
		"  Found orphan nodes",
		"Statistics: 1 test cases | 0 errors | 1 failures | 0 flaky | 0 skipped | 0 orphans | FAILED 5ms",
	]
	var result: QuietReport.UnitResult = QuietReport.parse_unit(lines)
	assert_int(result.blocks.size()).is_equal(1)
	assert_str(result.blocks[0][0]).is_equal("test_suite > finalize()")


func test_clip_keeps_the_head_a_marker_and_the_tail() -> void:
	assert_int(QuietReport.clip(_numbered(15)).size()).is_equal(15)
	var cut: PackedStringArray = QuietReport.clip(_numbered(20))
	assert_int(cut.size()).is_equal(16)
	assert_str(cut[14]).is_equal("line 14")
	assert_str(cut[15]).is_equal("... 5 more lines")
	var tailed: PackedStringArray = QuietReport.clip(_numbered(20), 15, 1)
	assert_str(tailed[13]).is_equal("line 13")
	assert_str(tailed[14]).is_equal("... 5 more lines")
	assert_str(tailed[15]).is_equal("line 19")
	assert_str(QuietReport.clip(_numbered(16))[15]).is_equal("... 1 more line")


func test_a_stage_is_one_line() -> void:
	assert_str(QuietReport.stage_line("compile", true, "152 scripts", 4.1)).is_equal(
		"compile PASS 152 scripts 4.1 s"
	)
	assert_str(QuietReport.stage_line("unit", false, "1203 cases, 2 failed", 61.04)).is_equal(
		"unit FAIL 1203 cases, 2 failed 61.0 s"
	)
	# A tie rounds up, on every platform: printf rounds 0.25 to "0.2" on Linux and macOS and CI's
	# Windows printed "0.23" (the old assertion here).
	assert_str(QuietReport.stage_line("unit", true, "", 0.25)).is_equal("unit PASS 0.3 s")


func test_seconds_are_one_decimal_rounded_half_up_in_integers() -> void:
	assert_str(QuietReport.seconds_text(0.0)).is_equal("0.0")
	assert_str(QuietReport.seconds_text(0.04)).is_equal("0.0")
	assert_str(QuietReport.seconds_text(0.05)).is_equal("0.1")
	assert_str(QuietReport.seconds_text(0.75)).is_equal("0.8")
	assert_str(QuietReport.seconds_text(9.96)).is_equal("10.0")
	assert_str(QuietReport.seconds_text(384.8)).is_equal("384.8")
	assert_str(QuietReport.seconds_text(-1.0)).is_equal("0.0")


func test_a_failing_fixture_shows_its_name_path_and_failing_expectations() -> void:
	# The messages the fixture runner gave for an air_control copy expecting vx=2000 at frame 8.
	var messages: PackedStringArray = [
		"line 14: at 8 vx=2000: frame 8: vx=2000 (actual vx=2304, expected = 2000)",
		"line 15: at 9 vx=1: frame 9: vx=1 (actual vx=2304, expected = 1)",
	]
	var block: PackedStringArray = QuietReport.fixture_failure(
		"scratch_broken", "res://tests/replay/scratch/scratch_broken.fixture", messages
	)
	(
		assert_array(block)
		. is_equal(
			[
				"FAIL scratch_broken (res://tests/replay/scratch/scratch_broken.fixture)",
				"    " + messages[0],
				"    " + messages[1],
			]
		)
	)
	var many: PackedStringArray = QuietReport.fixture_failure(
		"big", "res://a.fixture", _numbered(40)
	)
	assert_int(many.size()).is_equal(1 + QuietReport.MAX_DETAIL_LINES + 1)


func test_a_script_that_does_not_compile_shows_each_distinct_engine_error_once() -> void:
	var errors: PackedStringArray = [
		'line 5: Parse Error: Cannot assign a value of type "String" as "int".',
		'line 5: Parse Error: Cannot assign a value of type String to variable "x".',
		'line 5: Parse Error: Cannot assign a value of type "String" as "int".',
	]
	var block: PackedStringArray = QuietReport.compile_failure("res://tests/unit/x.gd", errors)
	(
		assert_array(block)
		. is_equal(
			[
				"does not compile: res://tests/unit/x.gd",
				"    " + errors[0],
				"    " + errors[1],
			]
		)
	)


func test_the_error_counter_keeps_what_the_engine_said_about_each_script() -> void:
	var counter: ErrorCounter = ErrorCounter.new()
	var none: Array[ScriptBacktrace] = []
	counter._log_error(
		"reload",
		"res://tests/unit/x.gd",
		5,
		"",
		"Parse Error: bad",
		false,
		Logger.ERROR_TYPE_SCRIPT,
		none
	)
	counter._log_error("f", "core/io/file.cpp", 9, "cond", "", false, Logger.ERROR_TYPE_ERROR, none)
	counter._log_error(
		"w", "res://x.gd", 1, "", "just a warning", false, Logger.ERROR_TYPE_WARNING, none
	)
	assert_int(counter.errors).is_equal(2)
	assert_array(counter.by_file["res://tests/unit/x.gd"]).is_equal(["line 5: Parse Error: bad"])
	assert_bool(counter.by_file.has("core/io/file.cpp")).is_false()
	assert_bool(counter.by_file.has("res://x.gd")).is_false()
