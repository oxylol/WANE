extends GdUnitTestSuite
## StateHasher: order-sensitive, 32-bit, stable.


func test_same_input_same_hash() -> void:
	var a := StateHasher.new()
	var b := StateHasher.new()
	for v: int in [1, -1, 1 << 40, 0]:
		a.add_int(v)
		b.add_int(v)
	assert_int(a.value()).is_equal(b.value())


func test_order_matters() -> void:
	var a := StateHasher.new()
	a.add_int(1)
	a.add_int(2)
	var b := StateHasher.new()
	b.add_int(2)
	b.add_int(1)
	assert_int(a.value()).is_not_equal(b.value())


func test_high_word_matters() -> void:
	var a := StateHasher.new()
	a.add_int(1)
	var b := StateHasher.new()
	b.add_int(1 + (1 << 32))
	assert_int(a.value()).is_not_equal(b.value())


func test_value_is_unsigned_32_bit() -> void:
	var h := StateHasher.new()
	h.add_string("wane")
	h.add_bool(true)
	h.add_int(-5)
	assert_bool(h.value() >= 0 and h.value() <= 0xFFFFFFFF).is_true()


func test_matches_reference_values() -> void:
	# Reference values from an independent Python implementation of the same scheme.
	assert_int(StateHasher.new().value()).is_equal(0)
	var h := StateHasher.new()
	h.add_int(0)
	assert_int(h.value()).is_equal(0x407E4BA3)
	var g := StateHasher.new()
	for v: int in [1, -1, 1 << 40, 0]:
		g.add_int(v)
	assert_int(g.value()).is_equal(0x752331DE)
