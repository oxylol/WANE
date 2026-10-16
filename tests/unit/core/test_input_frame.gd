extends GdUnitTestSuite
## InputFrame (ADR-0004): packing is lossless and directions honour the threshold.


func test_pack_round_trips_every_field() -> void:
	var f := InputFrame.make(InputFrame.JUMP | InputFrame.DASH, InputFrame.DASH, -127, 64)
	var g: InputFrame = InputFrame.unpack(f.pack())
	assert_int(g.held).is_equal(f.held)
	assert_int(g.pressed).is_equal(f.pressed)
	assert_int(g.stick_x).is_equal(-127)
	assert_int(g.stick_y).is_equal(64)
	assert_bool(g.equals(f)).is_true()


func test_pack_is_non_negative_and_fits_31_bits() -> void:
	var f := InputFrame.make(127, 127, 127, 127)
	assert_int(f.pack()).is_greater_equal(0)
	assert_int(f.pack()).is_less(1 << 31)
	assert_int(InputFrame.new().pack()).is_equal((127 << 14) | (127 << 22))


func test_make_clamps_stick_and_masks_buttons() -> void:
	var f := InputFrame.make(0xFFFF, 0xFFFF, 500, -500)
	assert_int(f.held).is_equal(InputFrame.BUTTON_MASK)
	assert_int(f.stick_x).is_equal(127)
	assert_int(f.stick_y).is_equal(-127)


func test_directions_use_threshold() -> void:
	var f := InputFrame.make(0, 0, 40, -41)
	assert_int(f.dir_x(41)).is_equal(0)
	assert_int(f.dir_x(40)).is_equal(1)
	assert_int(f.dir_y(41)).is_equal(-1)


func test_describe() -> void:
	var f := InputFrame.make(InputFrame.JUMP | InputFrame.ATTACK, InputFrame.ATTACK, 127, 0)
	assert_str(f.describe()).is_equal("R Jmp Atk+")
	assert_str(InputFrame.new().describe()).is_equal("-")


func test_button_queries_and_names() -> void:
	var f := InputFrame.make(InputFrame.DASH, InputFrame.JUMP, 0, 0)
	assert_bool(f.is_held(InputFrame.DASH)).is_true()
	assert_bool(f.is_held(InputFrame.JUMP)).is_false()
	assert_bool(f.was_pressed(InputFrame.JUMP)).is_true()
	assert_bool(f.was_pressed(InputFrame.DASH)).is_false()
	assert_str(InputFrame.button_name(InputFrame.TOSS)).is_equal("TOSS")
	assert_str(InputFrame.button_name(1 << 20)).is_equal("?")
	assert_bool(f.copy().equals(f)).is_true()


func test_describe_up_left_and_down() -> void:
	assert_str(InputFrame.make(0, 0, -127, -127).describe()).is_equal("U L")
	assert_str(InputFrame.make(InputFrame.MEND, 0, 0, 127).describe()).is_equal("D Mnd")
	assert_int(InputFrame.make(0, 0, 0, 127).dir_y(64)).is_equal(1)
	assert_int(InputFrame.make(0, 0, 0, 0).dir_y(64)).is_equal(0)
