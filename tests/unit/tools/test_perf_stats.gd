extends GdUnitTestSuite
## The perf bench's statistics and gate numbers (tools/bench/perf_stats.gd, perf_budget.gd,
## content/perf/budget.tres; docs/adr/0020).


func test_a_tick_keeps_the_least_time_any_run_gave_it() -> void:
	var best := PackedInt32Array()
	PerfStats.fold_min(best, PackedInt32Array([5, 9, 3, 7]))
	PerfStats.fold_min(best, PackedInt32Array([6, 2, 8, 7]))
	PerfStats.fold_min(best, PackedInt32Array([4, 9, 3, 1]))
	assert_array(Array(best)).is_equal([4, 2, 3, 1])


func test_percentiles_are_nearest_rank() -> void:
	var hundred := PackedInt32Array()
	for i: int in range(1, 101):
		hundred.append(i)
	assert_int(PerfStats.percentile(hundred, 500)).is_equal(50)
	assert_int(PerfStats.percentile(hundred, 990)).is_equal(99)
	assert_int(PerfStats.percentile(hundred, 1000)).is_equal(100)
	assert_int(PerfStats.percentile(hundred, 10)).is_equal(1)
	# 101 samples: the 99th percentile is the 100th value, so one tick in a hundred may be over.
	hundred.append(101)
	assert_int(PerfStats.percentile(hundred, 990)).is_equal(100)
	assert_int(PerfStats.percentile(PackedInt32Array(), 990)).is_equal(0)
	assert_int(PerfStats.percentile(PackedInt32Array([7]), 990)).is_equal(7)


func test_warm_up_ticks_are_left_out() -> void:
	var run := PackedInt32Array([90, 80, 3, 1, 2])
	assert_array(Array(PerfStats.sorted_from(run, 2))).is_equal([1, 2, 3])
	assert_array(Array(PerfStats.sorted_from(run, 99))).is_empty()
	assert_array(Array(PerfStats.sorted_from(run, -4))).is_equal([1, 2, 3, 80, 90])


func test_the_worst_ticks_come_slowest_first_and_earliest_among_equals() -> void:
	var run := PackedInt32Array([9, 5, 7, 7, 1, 8])
	assert_array(Array(PerfStats.worst(run, 0, 3))).is_equal([0, 5, 2])
	assert_array(Array(PerfStats.worst(run, 1, 2))).is_equal([5, 2])
	assert_array(Array(PerfStats.worst(run, 0, 99))).has_size(6)


func test_times_print_as_milliseconds() -> void:
	assert_str(PerfStats.ms(3000)).is_equal("3.00")
	assert_str(PerfStats.ms(16600)).is_equal("16.60")
	assert_str(PerfStats.ms(1234)).is_equal("1.23")


func test_the_budget_is_section_13s() -> void:
	var b: PerfBudget = load(PerfBudget.PATH) as PerfBudget
	assert_array(Array(b.validate())).is_empty()
	# "Input + simulation step 3.0 ms; Sprite and animation submit 2.0; Lighting pass 3.0; VFX 2.0;
	# Post 1.0; Audio and UI 1.0; Headroom 4.6", 16.6 ms in all; "99th-percentile frame time <= 16.0
	# ms on reference PC settings, <= 15.0 ms on the Deck profile".
	assert_int(b.sim_p99_us).is_equal(3000)
	assert_int(b.sprite_us).is_equal(2000)
	assert_int(b.lighting_us).is_equal(3000)
	assert_int(b.vfx_us).is_equal(2000)
	assert_int(b.post_us).is_equal(1000)
	assert_int(b.audio_ui_us).is_equal(1000)
	assert_int(b.headroom_us).is_equal(4600)
	assert_int(b.frame_total_us()).is_equal(16600)
	assert_int(b.reference_p99_us).is_equal(16000)
	assert_int(b.deck_p99_us).is_equal(15000)
	# "No frame-time spike above 20 ms".
	assert_int(b.sim_max_us).is_equal(20000)
	assert_int(b.zone_max_us).is_equal(20000)
	# The presentation's script time is "Sprite and animation submit 2.0 + VFX 2.0 + Audio and UI
	# 1.0": 5.0 ms (the lighting pass and post are the GPU's).
	assert_int(b.presentation_us()).is_equal(5000)
	assert_int(b.min_peak_procs).is_equal(39)


func test_a_budget_that_breaks_a_rule_is_refused() -> void:
	for change: String in [
		"sim_p99_us",
		"sim_max_us",
		"repeats",
		"zone_passes",
		"headroom_us",
		"deck_p99_us",
		"burst_procs_max",
		"min_frames",
	]:
		var b: PerfBudget = (load(PerfBudget.PATH) as PerfBudget).duplicate() as PerfBudget
		match change:
			"sim_p99_us":
				b.sim_p99_us = b.sim_max_us + 1
			"sim_max_us":
				b.sim_max_us = 0
			"repeats":
				b.repeats = 0
			"zone_passes":
				b.zone_passes = 0
			"headroom_us":
				b.headroom_us += 1
			"deck_p99_us":
				b.deck_p99_us = b.reference_p99_us + 1
			"burst_procs_max":
				b.burst_procs_max = b.min_peak_procs - 1
			"min_frames":
				b.min_frames = 0
		assert_array(Array(b.validate())).is_not_empty()
