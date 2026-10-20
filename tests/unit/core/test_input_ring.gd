extends GdUnitTestSuite
## InputRing (BUILD.md section 5 feel rules; ADR-0004).


func _frame(held: int, pressed: int) -> InputFrame:
	return InputFrame.make(held, pressed, 0, 0)


func test_press_age_counts_player_frames() -> void:
	var ring := InputRing.new()
	ring.push(_frame(InputFrame.JUMP, InputFrame.JUMP))
	assert_int(ring.press_age(InputFrame.JUMP)).is_equal(0)
	for i: int in range(InputRing.HISTORY):
		ring.push(_frame(0, 0))
		assert_int(ring.press_age(InputFrame.JUMP)).is_equal(i + 1)
	# A press 8 frames old is still served (checklist: jump pressed 8 frames before landing).
	assert_int(ring.press_age(InputFrame.JUMP)).is_equal(8)
	ring.push(_frame(0, 0))
	assert_int(ring.press_age(InputFrame.JUMP)).is_equal(-1)


func test_serves_latest_press_and_using_it_spends_older_ones() -> void:
	var ring := InputRing.new()
	ring.push(_frame(InputFrame.ATTACK, InputFrame.ATTACK))
	ring.push(_frame(0, 0))
	ring.push(_frame(InputFrame.ATTACK, InputFrame.ATTACK))
	ring.push(_frame(0, 0))
	assert_int(ring.press_age(InputFrame.ATTACK)).is_equal(1)
	ring.consume(InputFrame.ATTACK)
	# The older tap must not fire a second action later (BUILD.md s5: the latest input wins).
	assert_int(ring.press_age(InputFrame.ATTACK)).is_equal(-1)


func test_jump_twice_in_the_air_fires_once() -> void:
	# Pressed at L-6 and L-3, used by the landing jump at L: nothing is left for L+1.
	var ring := InputRing.new()
	for i: int in range(7):
		var p: int = InputFrame.JUMP if i == 0 or i == 3 else 0
		ring.push(_frame(p, p))
	ring.consume(InputFrame.JUMP)
	ring.push(_frame(0, 0))
	assert_int(ring.press_age(InputFrame.JUMP)).is_equal(-1)


func test_max_age_window() -> void:
	var ring := InputRing.new()
	ring.push(_frame(InputFrame.DASH, InputFrame.DASH))
	for _i: int in range(5):
		ring.push(_frame(0, 0))
	assert_int(ring.press_age(InputFrame.DASH, 5)).is_equal(5)
	assert_int(ring.press_age(InputFrame.DASH, 4)).is_equal(-1)
	assert_bool(ring.has_press(InputFrame.DASH, 4)).is_false()


func test_merge_keeps_hitstop_presses_at_age_zero() -> void:
	var ring := InputRing.new()
	ring.push(_frame(0, 0))
	# Twelve frozen frames (a parry's hitstop) with a press in the middle.
	for i: int in range(12):
		var pressed: int = InputFrame.ATTACK if i == 3 else 0
		ring.merge(_frame(pressed, pressed))
	assert_int(ring.press_age(InputFrame.ATTACK)).is_equal(0)
	ring.push(_frame(0, 0))
	assert_int(ring.press_age(InputFrame.ATTACK)).is_equal(1)
	assert_int(ring.depth()).is_equal(2)


func test_press_during_hitstop_survives_a_press_used_on_the_hit_frame() -> void:
	# The attack press is used by a parry on the hit frame, then a new press arrives during the
	# 12 f parry hitstop: it must fire on the first free frame.
	var ring := InputRing.new()
	ring.push(_frame(InputFrame.ATTACK, InputFrame.ATTACK))
	ring.consume(InputFrame.ATTACK)
	ring.merge(_frame(0, 0))
	ring.merge(_frame(InputFrame.ATTACK, InputFrame.ATTACK))
	assert_int(ring.press_age(InputFrame.ATTACK)).is_equal(0)
	ring.push(_frame(0, 0))
	assert_int(ring.press_age(InputFrame.ATTACK)).is_equal(1)


func test_merge_takes_latest_held_and_stick() -> void:
	var ring := InputRing.new()
	ring.push(InputFrame.make(InputFrame.JUMP, InputFrame.JUMP, 10, 0))
	ring.merge(InputFrame.make(0, 0, -20, 5))
	assert_bool(ring.is_held(InputFrame.JUMP)).is_false()
	assert_int(ring.stick_x()).is_equal(-20)
	assert_int(ring.stick_y()).is_equal(5)
	assert_int(ring.press_age(InputFrame.JUMP)).is_equal(0)


func test_held_frames_counts_long_holds() -> void:
	var ring := InputRing.new()
	for _i: int in range(30):
		ring.push(_frame(InputFrame.ATTACK, 0))
	# Longer than the ring: the 24 f charged strike can read it.
	assert_int(ring.held_frames(InputFrame.ATTACK)).is_equal(30)
	ring.merge(_frame(InputFrame.ATTACK, 0))
	assert_int(ring.held_frames(InputFrame.ATTACK)).is_equal(30)
	ring.push(_frame(0, 0))
	assert_int(ring.held_frames(InputFrame.ATTACK)).is_equal(0)
	assert_int(ring.held_frames(InputFrame.JUMP)).is_equal(0)


func test_releasing_during_hitstop_restarts_the_hold() -> void:
	var ring := InputRing.new()
	for _i: int in range(22):
		ring.push(_frame(InputFrame.ATTACK, 0))
	ring.merge(_frame(0, 0))
	ring.merge(_frame(InputFrame.ATTACK, InputFrame.ATTACK))
	ring.push(_frame(InputFrame.ATTACK, 0))
	ring.push(_frame(InputFrame.ATTACK, 0))
	assert_int(ring.held_frames(InputFrame.ATTACK)).is_equal(2)


func test_frame_at_and_copy() -> void:
	var ring := InputRing.new()
	ring.push(InputFrame.make(InputFrame.JUMP, InputFrame.JUMP, 1, 2))
	ring.push(InputFrame.make(0, 0, 3, 4))
	assert_int(ring.frame_at(1).stick_x).is_equal(1)
	assert_int(ring.latest().stick_y).is_equal(4)
	assert_int(ring.frame_at(5).held).is_equal(0)
	var other := InputRing.new()
	other.copy_from(ring)
	var h1 := StateHasher.new()
	var h2 := StateHasher.new()
	ring.hash_into(h1)
	other.hash_into(h2)
	assert_int(h1.value()).is_equal(h2.value())
	# The copy answers queries as the original does: its press mask came with it (movement
	# review 6, L2).
	assert_int(other.press_age(InputFrame.JUMP)).is_equal(1)
	assert_int(other.any_press_ticks(InputFrame.JUMP, 7)).is_equal(1)
	other.push(_frame(0, 0))
	assert_int(ring.depth()).is_equal(2)


func test_a_parry_press_is_aged_in_ticks_through_hitstop() -> void:
	# The player is frozen for two ticks after a press: the ring folds them into one slot, so the
	# press is 0 frames old but 3 ticks old (ADR-0013, the parry window counts ticks).
	var ring := InputRing.new()
	ring.push(_frame(InputFrame.ATTACK, InputFrame.ATTACK))
	ring.merge(_frame(0, 0))
	ring.merge(_frame(0, 0))
	ring.merge(_frame(0, 0))
	assert_int(ring.press_age(InputFrame.ATTACK)).is_equal(0)
	assert_int(ring.any_press_ticks(InputFrame.ATTACK, 7)).is_equal(3)
	assert_int(ring.any_press_ticks(InputFrame.ATTACK, 2)).is_equal(-1)
	# A press made during the freeze is as young as its own tick, and the older one is not
	# resurrected by the slot it shares.
	ring.merge(_frame(InputFrame.ATTACK, InputFrame.ATTACK))
	assert_int(ring.any_press_ticks(InputFrame.ATTACK, 0)).is_equal(0)
	ring.spend_presses(InputFrame.ATTACK)
	assert_int(ring.any_press_ticks(InputFrame.ATTACK, 7)).is_equal(-1)


func test_the_tick_clock_survives_a_copy_and_reaches_the_hash() -> void:
	var ring := InputRing.new()
	ring.push(_frame(InputFrame.ATTACK, InputFrame.ATTACK))
	ring.merge(_frame(0, 0))
	var other := InputRing.new()
	other.copy_from(ring)
	assert_int(other.any_press_ticks(InputFrame.ATTACK, 7)).is_equal(1)
	# Same frames, one more folded tick: the press is a tick older, and the hash says so.
	var h1 := StateHasher.new()
	var h2 := StateHasher.new()
	ring.hash_into(h1)
	other.merge(_frame(0, 0))
	other.hash_into(h2)
	assert_int(h1.value()).is_not_equal(h2.value())
