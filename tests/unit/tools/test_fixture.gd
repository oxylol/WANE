extends GdUnitTestSuite
## Fixture DSL parser and runner (ADR-0006).

const GOOD: String = """
fixture sample   # comment
doc BUILD.md section 13
seed 7
wick none
frames 20
input
  0..2 R jump
  3 R
  5 !attack D
  6..7 x=-40 y=12 dash
end
expect
  at 0 tick=1
  mark first_attack 0..19 press_age.attack=0
  at first_attack tick=6
  at first_attack+1 press_age.attack=1
  during 6..7 stick_x=-40 stick_y>=12
  never 8..19 held.dash=1
  at 19 tick=14+tick@first_attack
  at first_attack+2 tick=tick@(first_attack+2)
end
"""


func test_parses_header_and_inputs() -> void:
	var fx: Fixture = Fixture.parse_text(GOOD)
	assert_array(Array(fx.errors)).is_empty()
	assert_str(fx.name).is_equal("sample")
	assert_int(fx.scenario.seed_value).is_equal(7)
	assert_int(fx.frame_total).is_equal(20)
	var f0: InputFrame = fx.input_frame(0)
	assert_int(f0.held).is_equal(InputFrame.JUMP)
	assert_int(f0.pressed).is_equal(InputFrame.JUMP)
	assert_int(f0.stick_x).is_equal(127)
	assert_int(fx.input_frame(1).pressed).is_equal(0)
	assert_int(fx.input_frame(3).held).is_equal(0)
	var f5: InputFrame = fx.input_frame(5)
	assert_int(f5.held).is_equal(0)
	assert_int(f5.pressed).is_equal(InputFrame.ATTACK)
	assert_int(f5.stick_y).is_equal(127)
	var f6: InputFrame = fx.input_frame(6)
	assert_int(f6.stick_x).is_equal(-40)
	assert_int(f6.pressed).is_equal(InputFrame.DASH)
	assert_int(fx.input_frame(10).held).is_equal(0)
	assert_int(fx.expectations.size()).is_equal(8)


func test_runner_passes_good_fixture() -> void:
	var runner := FixtureRunner.new()
	var result: FixtureRunner.Result = runner.run_fixture(Fixture.parse_text(GOOD))
	assert_array(Array(result.messages)).is_empty()
	assert_bool(result.passed).is_true()
	assert_str(result.hash_line).starts_with("in:")
	assert_str(result.hash_line).contains(" 20:")


func test_a_run_without_playback_checks_the_same_hashes() -> void:
	# The suite plays back only a sample of fixtures in full (FixtureRunner.PLAYBACK_EVERY); the
	# rest still record, encode and decode their replay exactly and give the same hash line.
	var full: FixtureRunner.Result = FixtureRunner.new().run_fixture(Fixture.parse_text(GOOD))
	var quick: FixtureRunner.Result = FixtureRunner.new().run_fixture(
		Fixture.parse_text(GOOD), false
	)
	assert_bool(quick.passed).is_true()
	assert_str(quick.hash_line).is_equal(full.hash_line)


func test_runner_reports_failures_with_line_and_values() -> void:
	var text: String = GOOD.replace("at first_attack tick=6", "at first_attack tick=7")
	var result: FixtureRunner.Result = FixtureRunner.new().run_fixture(Fixture.parse_text(text))
	assert_bool(result.passed).is_false()
	assert_str(result.messages[0]).contains("line 16")
	assert_str(result.messages[0]).contains("actual tick=6")


func test_unsatisfied_mark_fails() -> void:
	var text: String = GOOD.replace("mark first_attack 0..19", "mark first_attack 0..4")
	var result: FixtureRunner.Result = FixtureRunner.new().run_fixture(Fixture.parse_text(text))
	assert_bool(result.passed).is_false()
	assert_str("\n".join(result.messages)).contains("no frame in 0..4")


func test_never_fails_when_conditions_hold() -> void:
	var text: String = GOOD.replace("never 8..19 held.dash=1", "never 6..19 held.dash=1")
	var result: FixtureRunner.Result = FixtureRunner.new().run_fixture(Fixture.parse_text(text))
	assert_bool(result.passed).is_false()
	assert_str(result.messages[0]).contains("all conditions held at frame 6")


func test_unknown_key_fails() -> void:
	var text: String = GOOD.replace("at 0 tick=1", "at 0 nonsense=1")
	var result: FixtureRunner.Result = FixtureRunner.new().run_fixture(Fixture.parse_text(text))
	assert_bool(result.passed).is_false()
	assert_str(result.messages[0]).contains("unknown probe key 'nonsense'")


func test_parse_errors() -> void:
	var cases: Array[String] = [
		"fixture a\nframes 5\n",  # missing doc
		"doc x\nframes 5\n",  # missing fixture
		"fixture a\ndoc x\n",  # missing frames
		"fixture a\ndoc x\nframes 5\ninput\n0..9 R\nend\n",  # range beyond frames
		"fixture a\ndoc x\nframes 5\ninput\n0 Q\nend\n",  # unknown token
		"fixture a\ndoc x\nframes 5\nexpect\nat m tick=1\nend\n",  # mark before definition
		"fixture a\ndoc x\nframes 5\nexpect\nat 0 tick\nend\n",  # no operator
		"fixture a\ndoc x\nframes 5\ninput\n",  # unterminated block
		"fixture a\ndoc x\nframes 5\nbogus 1\n",  # unknown directive
		"fixture a\ndoc x\nframes 9\ninput\n0..5 R\n5 jump\nend\n",  # overlapping input lines
		"fixture a\ndoc x\nframes 5\ninput 0..4 R\nend\n",  # words after 'input'
		"fixture a\ndoc x\nseed 1 room r\nframes 5\n",  # extra words on a directive
		"fixture a\ndoc x\nframes 5\nframes 6\n",  # directive twice
		"fixture a\ndoc x\nframes 5\ninput\n0 x=500\nend\n",  # stick out of range
		"fixture a\ndoc x\nframes 9\nexpect\nat 3 tick=tick@0+5\nend\n",  # ambiguous offset
		"fixture a\ndoc x\nframes 9\nexpect\nat 3 tick<run\nend\n",  # ordering a word
		"fixture a\ndoc x\nframes 9\nexpect\nat 3 tick=5x\nend\n",  # malformed value
		"fixture a\ndoc x\nframes 9\nend\n",  # end outside a block
	]
	for text: String in cases:
		(
			assert_array(Array(Fixture.parse_text(text).errors))
			. override_failure_message("expected a parse error for:\n" + text)
			. is_not_empty()
		)


func test_doc_keeps_hash_characters() -> void:
	var fx: Fixture = Fixture.parse_text("fixture a\ndoc BUILD.md s5 # row 2\nframes 1\n")
	assert_str(fx.doc).is_equal("BUILD.md s5 # row 2")


func test_nothing_passes_vacuously() -> void:
	var cases: Array[String] = [
		"never 0..9 tick=tick@99",  # value outside the run
		"at 3 tick!=rnu",  # a word for an integer key
		"never 0..9 tick=rnu",
	]
	for line: String in cases:
		var text: String = "fixture a\ndoc x\nframes 10\nexpect\n%s\nend\n" % line
		var result: FixtureRunner.Result = FixtureRunner.new().run_fixture(Fixture.parse_text(text))
		assert_bool(result.passed).override_failure_message("passed vacuously: " + line).is_false()


func test_value_expressions() -> void:
	var fx: Fixture = Fixture.parse_text(
		"fixture v\ndoc d\nframes 3\nexpect\nat 2 tick=-2u+1u+259\nat 1 tick>=1+tick@0\nend\n"
	)
	assert_array(Array(fx.errors)).is_empty()
	var c: Fixture.Condition = fx.expectations[0].conditions[0]
	assert_int(c.terms.size()).is_equal(3)
	assert_int(c.terms[0].polarity * c.terms[0].literal_int).is_equal(-512)
	assert_int(c.terms[1].literal_int).is_equal(256)
	assert_bool(FixtureRunner.new().run_fixture(fx).passed).is_true()


func test_bless_tells_code_changes_from_fixture_and_content_changes() -> void:
	var runner := FixtureRunner.new()
	var same := FixtureRunner.Result.new()
	same.name = "a"
	same.hash_line = "in:00000001 content:00000002 10:aaaaaaaa"
	var moved := FixtureRunner.Result.new()
	moved.name = "b"
	moved.hash_line = "in:00000001 content:00000002 10:bbbbbbbb"
	var new_inputs := FixtureRunner.Result.new()
	new_inputs.name = "c"
	new_inputs.hash_line = "in:00000009 content:00000002 11:cccccccc"
	var new_content := FixtureRunner.Result.new()
	new_content.name = "d"
	new_content.hash_line = "in:00000001 content:00000009 10:dddddddd"
	runner.results.assign([same, moved, new_inputs, new_content])
	var old: Dictionary[String, String] = {
		"a": "in:00000001 content:00000002 10:aaaaaaaa",
		"b": "in:00000001 content:00000002 10:00000000",
		"c": "in:00000001 content:00000002 10:00000000",
		"d": "in:00000001 content:00000002 10:00000000",
	}
	assert_array(runner.code_changed(old)).is_equal(["b"])


func test_grammar_leftovers_are_errors() -> void:
	for text: String in [
		"fixture a\ndoc x\nframes 9\nexpect\nduring 3..5..8 tick>0\nend\n",
		"fixture a\ndoc x\nframes 9\ninput\n0 R L\nend\n",
		"fixture a\ndoc x\nframes 9\ninput\n0 x=5 R\nend\n",
		"fixture a\ndoc x\nframes 9\ninput\n0 jump jump\nend\n",
		"fixture a\ndoc x\nframes 9\ninput\n0 !jump !jump\nend\n",
	]:
		(
			assert_array(Array(Fixture.parse_text(text).errors))
			. override_failure_message("expected a parse error for:\n" + text)
			. is_not_empty()
		)
	var ok: Fixture = (
		Fixture
		. parse_text(
			"fixture a\ndoc x\nframes 9\ninput\n0 U R jump\nend\nexpect\nat 2 tick=tick@(0)+tick@1\nend\n"
		)
	)
	assert_array(Array(ok.errors)).is_empty()


func test_a_re_press_while_held_can_be_scripted() -> void:
	# "jump !jump": held on both ticks but released and pressed again in between.
	var fx: Fixture = Fixture.parse_text(
		"fixture a\ndoc x\nframes 4\ninput\n0..1 jump\n2 jump !jump\n3 jump\nend\n"
	)
	assert_array(Array(fx.errors)).is_empty()
	assert_int(fx.input_frame(1).pressed).is_equal(0)
	assert_int(fx.input_frame(2).pressed).is_equal(InputFrame.JUMP)
	assert_int(fx.input_frame(2).held).is_equal(InputFrame.JUMP)
	assert_int(fx.input_frame(3).pressed).is_equal(0)
