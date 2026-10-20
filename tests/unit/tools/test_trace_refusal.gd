extends GdUnitTestSuite
## trace.gd refuses the fixtures check.gd rejects, with the same "parse:" lines (the parry and
## dash audit, L3).

const BROKEN: String = """fixture trace_refusal_sample
doc BUILD.md s6 Parry: a sample whose frame 10 is set by two lines.
room test/flat
frames 21
input
  0..20 R
  10 R attack
end
"""

const GOOD: String = """fixture trace_refusal_good
doc BUILD.md s5 Run: a sample that parses.
room test/flat
frames 5
input
  0..4 R
end
"""


func _trace(text: String) -> Dictionary[String, Variant]:
	var path: String = "user://trace_refusal_sample.fixture"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var output: Array[String] = []
	var args: PackedStringArray = [
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"res://tools/replay/trace.gd",
		"--",
		ProjectSettings.globalize_path(path),
		"tick",
		"x",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	return {"code": code, "out": "\n".join(output)}


func test_the_refusal_lines_are_the_ones_check_reports() -> void:
	var fx: Fixture = Fixture.parse_text(BROKEN)
	var runner := FixtureRunner.new()
	var result: FixtureRunner.Result = runner.run_fixture(fx)
	assert_bool(result.passed).is_false()
	assert_array(fx.refusals()).is_not_empty()
	assert_str(fx.refusals()[0]).contains("frame 10 is already set")
	assert_str(result.messages[0]).is_equal(fx.refusals()[0])


func test_a_clean_fixture_has_no_refusals() -> void:
	assert_array(Fixture.parse_text(GOOD).refusals()).is_empty()


func test_trace_prints_no_table_for_a_fixture_check_rejects() -> void:
	var run: Dictionary[String, Variant] = _trace(BROKEN)
	var out: String = run["out"]
	assert_int(run["code"]).is_equal(1)
	assert_str(out).contains("parse: line")
	assert_str(out).contains("frame 10 is already set")
	assert_str(out).not_contains("frame  input")


func test_trace_still_prints_a_table_for_a_good_fixture() -> void:
	var run: Dictionary[String, Variant] = _trace(GOOD)
	var out: String = run["out"]
	assert_int(run["code"]).is_equal(0)
	assert_str(out).contains("frame  input")
