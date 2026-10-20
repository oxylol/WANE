extends GdUnitTestSuite
## What the fixture suite reads and where it runs (docs/adr/0006, Shards): the probe plan reads
## every value an expectation looks at and no other, a header read gives a fixture's frames, and
## the shards' shares are a balanced partition.

const PLANNED: String = """
fixture planned
doc BUILD.md section 13
wick none
frames 12
input
  0..11 R
end
expect
  at 3 tick=4
  during 5..6 stick_x=127
  mark m 7..8 tick>=8
  at m+1 stick_y=0 tick=tick@(m+1)
  at 10 held.attack=0
  at 11 stick_x=stick_x@(m+1)
end
"""


func _keys_at(plan: Dictionary[int, PackedStringArray], f: int) -> Array[String]:
	var keys: Array[String] = []
	if plan.has(f):
		keys.assign(plan[f])
	keys.sort()
	return keys


func test_the_plan_reads_what_each_expectation_looks_at_and_nothing_else() -> void:
	var fx: Fixture = Fixture.parse_text(PLANNED)
	assert_array(Array(fx.errors)).is_empty()
	var plan: Dictionary[int, PackedStringArray] = fx.probe_plan()
	# Frame 0 reads every key once: the runner learns from it whether a key exists and what it holds.
	assert_array(_keys_at(plan, 0)).is_equal(["held.attack", "stick_x", "stick_y", "tick"])
	assert_array(_keys_at(plan, 1)).is_empty()
	assert_array(_keys_at(plan, 2)).is_empty()
	assert_array(_keys_at(plan, 3)).is_equal(["tick"])
	assert_array(_keys_at(plan, 4)).is_empty()
	assert_array(_keys_at(plan, 5)).is_equal(["stick_x"])
	assert_array(_keys_at(plan, 6)).is_equal(["stick_x"])
	# The mark m is at 7 or 8: tick is read over its search range (7..8) and where m+1 may be
	# (8..9, and tick@m itself at 7..8); stick_y and the stick_x of the last line follow m+1.
	assert_array(_keys_at(plan, 7)).is_equal(["tick"])
	assert_array(_keys_at(plan, 8)).is_equal(["stick_x", "stick_y", "tick"])
	assert_array(_keys_at(plan, 9)).is_equal(["stick_x", "stick_y", "tick"])
	assert_array(_keys_at(plan, 10)).is_equal(["held.attack"])
	assert_array(_keys_at(plan, 11)).is_equal(["stick_x"])


func test_a_fixture_without_expectations_probes_nothing() -> void:
	var fx: Fixture = Fixture.parse_text(
		"fixture a\ndoc x\nframes 5\ninput\n0..4 R\nend\nexpect\nend\n"
	)
	assert_bool(fx.probe_plan().is_empty()).is_true()


func test_a_reference_outside_the_run_reads_nothing_there() -> void:
	var fx: Fixture = (
		Fixture
		. parse_text(
			"fixture a\ndoc x\nframes 5\nexpect\nat 9 tick=1\nduring 3..40 tick>0\nat 2 tick=tick@7\nend\n"
		)
	)
	var plan: Dictionary[int, PackedStringArray] = fx.probe_plan()
	assert_array(_keys_at(plan, 0)).is_equal(["tick"])
	assert_array(_keys_at(plan, 2)).is_equal(["tick"])


func test_an_expectation_that_reads_an_unprobed_value_fails_not_passes() -> void:
	# If the plan ever missed a value, a "never" must not pass for want of it.
	for line: String in ["never 2..4 tick=99", "during 2..4 tick>0", "mark m 2..4 tick=99"]:
		var fx: Fixture = Fixture.parse_text(
			"fixture a\ndoc x\nwick none\nframes 6\nexpect\n%s\nend\n" % line
		)
		var sim := Simulation.new(fx.scenario)
		var snaps: Array[Dictionary] = []
		for i: int in range(6):
			snaps.append(FixtureRunner.NOT_PROBED)
		snaps[0] = {"tick": 1}
		var result := FixtureRunner.Result.new()
		FixtureRunner.new()._evaluate(fx, snaps, sim, result)
		assert_bool(result.passed).override_failure_message(line).is_false()
		assert_str("\n".join(result.messages)).contains(FixtureRunner.PLAN_MISS)


func test_every_fixture_of_the_suite_reads_its_frames_from_the_header() -> void:
	var paths: Array[String] = FileWalk.find(FixtureRunner.FIXTURE_ROOT, [".fixture"])
	assert_int(paths.size()).is_greater(500)
	for path: String in paths:
		var frames: int = Fixture.peek_frames(path)
		assert_int(frames).override_failure_message(path).is_greater(0)
		assert_int(frames).override_failure_message(path).is_equal(
			Fixture.parse_file(path).frame_total
		)
	assert_int(Fixture.peek_frames("res://tests/replay/no_such.fixture")).is_equal(0)


func test_core_fixtures_and_every_fourth_are_played_back() -> void:
	assert_bool(FixtureRunner.plays_back(FixtureRunner.CORE_FIXTURES + "x.fixture", 3)).is_true()
	assert_bool(FixtureRunner.plays_back("res://tests/replay/a/x.fixture", 8)).is_true()
	assert_bool(FixtureRunner.plays_back("res://tests/replay/a/x.fixture", 9)).is_false()
	var path: String = FixtureRunner.CORE_FIXTURES + "input_buffer_latest_press.fixture"
	var frames: int = Fixture.peek_frames(path)
	assert_int(frames).is_greater(0)
	# A fixture that is played back is simulated twice.
	assert_int(FixtureRunner.shard_weight(path, 1)).is_equal(
		(frames + FixtureRunner.FIXTURE_OVERHEAD_TICKS) * 2
	)


func _weights(values: Array[int]) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for v: int in values:
		out.append(v)
	return out


func _places(count: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(count):
		out.append(i)
	return out


func test_the_shards_share_every_fixture_once_in_suite_order() -> void:
	var weights: PackedInt64Array = _weights([5, 1, 9, 3, 3, 8, 2, 7, 4, 6, 1, 1])
	for count: int in range(1, 6):
		var shares: Array[PackedInt32Array] = FixtureRunner.plan_shards(
			_places(weights.size()), weights, count
		)
		assert_int(shares.size()).is_equal(count)
		var seen: Array[int] = []
		for share: PackedInt32Array in shares:
			for i: int in range(share.size()):
				seen.append(share[i])
				if i > 0:
					assert_int(share[i]).is_greater(share[i - 1])
		seen.sort()
		assert_array(seen).is_equal(Array(_places(weights.size())))


func test_the_shards_are_balanced_and_the_plan_is_the_same_every_time() -> void:
	# 40 fixtures whose weights alternate 1 and 5 and whose every fourth is doubled, as the
	# suite's playbacks are: the interleave puts all of the doubled ones on one of four shards.
	var values: Array[int] = []
	for i: int in range(40):
		values.append((1 if i % 2 == 0 else 5) * (2 if i % 4 == 0 else 1))
	var weights: PackedInt64Array = _weights(values)
	var first: Array[PackedInt32Array] = FixtureRunner.plan_shards(_places(40), weights, 4)
	var second: Array[PackedInt32Array] = FixtureRunner.plan_shards(_places(40), weights, 4)
	var total: int = 0
	var heaviest: int = 0
	var interleaved: PackedInt64Array = _weights([0, 0, 0, 0])
	for i: int in range(40):
		interleaved[i % 4] += weights[i]
	var worst_interleaved: int = maxi(
		maxi(interleaved[0], interleaved[1]), maxi(interleaved[2], interleaved[3])
	)
	for k: int in range(4):
		assert_array(Array(first[k])).is_equal(Array(second[k]))
		var share_load: int = 0
		for place: int in first[k]:
			share_load += weights[place]
		total += share_load
		heaviest = maxi(heaviest, share_load)
	assert_int(heaviest).is_less_equal(total / 4 + 5)
	assert_int(heaviest).is_less(worst_interleaved)


func test_planning_nothing_or_fewer_fixtures_than_shards_works() -> void:
	var none: Array[PackedInt32Array] = FixtureRunner.plan_shards(
		PackedInt32Array(), PackedInt64Array(), 3
	)
	assert_int(none.size()).is_equal(3)
	var few: Array[PackedInt32Array] = FixtureRunner.plan_shards(
		PackedInt32Array([7, 9]), _weights([4, 4]), 4
	)
	assert_int(few[0].size() + few[1].size() + few[2].size() + few[3].size()).is_equal(2)
	assert_int(few[0].size()).is_equal(1)
	assert_int(few[1].size()).is_equal(1)


func test_the_shards_that_start_late_take_less() -> void:
	# Shards 1 and on spend 10 of weight starting up, shard 0 none: 6 fixtures of 5 go 4 to shard 0
	# (20), 1 to shard 1 (10 + 5) and 1 to shard 2 (10 + 5) rather than 2 each.
	var weights: PackedInt64Array = _weights([5, 5, 5, 5, 5, 5])
	var shares: Array[PackedInt32Array] = FixtureRunner.plan_shards(_places(6), weights, 3, 10)
	assert_int(shares[0].size()).is_equal(4)
	assert_int(shares[1].size()).is_equal(1)
	assert_int(shares[2].size()).is_equal(1)
	var even: Array[PackedInt32Array] = FixtureRunner.plan_shards(_places(6), weights, 3)
	assert_int(even[0].size()).is_equal(2)
	assert_int(even[1].size()).is_equal(2)
	assert_int(even[2].size()).is_equal(2)


func test_the_shared_input_frames_are_the_frames_of_every_tick() -> void:
	var paths: Array[String] = FileWalk.find(FixtureRunner.FIXTURE_ROOT, [".fixture"])
	var shared: int = 0
	for path: String in paths:
		var fx: Fixture = Fixture.parse_file(path)
		var frames: Array[InputFrame] = fx.input_frames()
		assert_int(frames.size()).override_failure_message(path).is_equal(fx.frame_total)
		for i: int in range(fx.frame_total):
			var want: InputFrame = fx.input_frame(i)
			if frames[i].pack() != want.pack():
				fail("%s frame %d: %s, not %s" % [path, i, frames[i].describe(), want.describe()])
				return
			if i > 0 and frames[i] == frames[i - 1]:
				shared += 1
	assert_int(shared).is_greater(1000)
