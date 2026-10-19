extends GdUnitTestSuite
## Flame, Kindling, hearts and hitstop weight (BUILD.md section 6).


func _params() -> CombatParams:
	return (load(CombatTuning.PATH) as CombatTuning).compile()


func test_flame_fills_to_its_cap_and_spends_only_what_it_has() -> void:
	var f := Flame.new(100)
	f.gain(11 * 9)
	assert_int(f.value).is_equal(99)
	f.gain(11)
	assert_int(f.value).is_equal(100)
	assert_bool(f.spend(33)).is_true()
	assert_int(f.value).is_equal(67)
	assert_bool(f.spend(68)).is_false()
	assert_int(f.value).is_equal(67)


func test_kindling_tiers_start_at_8_20_and_40_hits() -> void:
	var k := Kindling.new(_params())
	var expected: Dictionary[int, int] = {
		0: Kindling.EMBER,
		7: Kindling.EMBER,
		8: Kindling.FLAME,
		19: Kindling.FLAME,
		20: Kindling.BLAZE,
		39: Kindling.BLAZE,
		40: Kindling.WHITE,
		400: Kindling.WHITE
	}
	for hits: int in expected:
		k.hits = hits
		assert_int(k.tier()).is_equal(expected[hits])


func test_kindling_adds_ten_twenty_and_thirty_percent_damage() -> void:
	var k := Kindling.new(_params())
	var damage: Dictionary[int, int] = {0: 10, 8: 11, 20: 12, 40: 13}
	for hits: int in damage:
		k.hits = hits
		assert_int(k.boost(10)).is_equal(damage[hits])
	k.hits = 40
	assert_int(k.boost(36)).is_equal(47)


func test_taking_damage_drops_kindling_one_tier_not_to_zero() -> void:
	var k := Kindling.new(_params())
	k.hits = 45
	k.drop_tier()
	assert_int(k.tier()).is_equal(Kindling.BLAZE)
	assert_int(k.hits).is_equal(20)
	k.drop_tier()
	assert_int(k.hits).is_equal(8)
	k.drop_tier()
	assert_int(k.hits).is_equal(0)
	k.drop_tier()
	assert_int(k.hits).is_equal(0)


func test_hearts_never_go_below_zero_or_above_the_maximum() -> void:
	var h := Hearts.new(5)
	h.heal()
	assert_int(h.current).is_equal(5)
	h.lose(7)
	assert_int(h.current).is_equal(0)
	assert_bool(h.is_dead()).is_true()


func test_heavy_hits_add_a_frame_of_hitstop_per_ten_damage_over_thirty_capped_at_eight() -> void:
	var p: CombatParams = _params()
	assert_int(p.hitstop_for(p.hitstop_light, 10)).is_equal(2)
	assert_int(p.hitstop_for(p.hitstop_charged, 36)).is_equal(6)
	assert_int(p.hitstop_for(p.hitstop_charged, 47)).is_equal(7)
	assert_int(p.hitstop_for(p.hitstop_light, 60)).is_equal(5)
	assert_int(p.hitstop_for(p.hitstop_charged, 200)).is_equal(8)
	# The parry's 12 f is not a weight: the cap never shortens it.
	assert_int(p.hitstop_for(p.hitstop_parry, 0)).is_equal(12)


func test_content_refuses_a_parry_window_the_input_ring_cannot_hold() -> void:
	# Task 6 review, L2: a window past the ring's depth asserted on every hit check, and in a debug
	# build read as "pressed this frame", so every parryable swing was parried.
	var tuning: CombatTuning = (load(CombatTuning.PATH) as CombatTuning).duplicate()
	assert_array(Array(tuning.validate())).is_empty()
	for bad: int in [0, InputRing.HISTORY + 2, 12]:
		tuning.parry_window_frames = bad
		assert_array(Array(tuning.validate())).override_failure_message(str(bad)).is_not_empty()
	tuning.parry_window_frames = InputRing.HISTORY + 1
	assert_array(Array(tuning.validate())).is_empty()


func test_content_refuses_a_telegraph_cue_no_telegraph_can_give() -> void:
	# The cue is sent 20 f before the hit; every telegraph is at least that long (BUILD.md
	# section 6), so a longer cue would never be sent.
	var tuning: CombatTuning = (load(CombatTuning.PATH) as CombatTuning).duplicate()
	assert_int(tuning.telegraph_cue_frames).is_equal(20)
	for bad: int in [0, EnemyAttack.MIN_TELEGRAPH + 1]:
		tuning.telegraph_cue_frames = bad
		assert_array(Array(tuning.validate())).override_failure_message(str(bad)).is_not_empty()
