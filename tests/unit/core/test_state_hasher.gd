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
	# Reference values from an independent Python implementation of the same scheme (hashlib's
	# SHA-256 over the words packed as little-endian signed 64-bit integers, the seed first; the
	# first four bytes of the digest, little-endian).
	assert_int(StateHasher.new().value()).is_equal(0xF57055AF)
	var h := StateHasher.new()
	h.add_int(0)
	assert_int(h.value()).is_equal(0xFF084737)
	var g := StateHasher.new()
	for v: int in [1, -1, 1 << 40, 0]:
		g.add_int(v)
	assert_int(g.value()).is_equal(0xAC853C5A)
	var s := StateHasher.new()
	s.add_string("wane")
	assert_int(s.value()).is_equal(0x49DA965A)


func test_a_string_is_its_length_then_its_bytes() -> void:
	# A string's bytes are padded to whole words, so "a" and "a\u0000" differ by their length,
	# and two strings side by side never read as one.
	var a := StateHasher.new()
	a.add_string("ab")
	a.add_string("c")
	var b := StateHasher.new()
	b.add_string("a")
	b.add_string("bc")
	assert_int(a.value()).is_not_equal(b.value())
	var c := StateHasher.new()
	c.add_string("a")
	var d := StateHasher.new()
	d.add_string("a\u0000")
	assert_int(c.value()).is_not_equal(d.value())


func test_a_batch_hashes_as_the_same_ints_one_by_one() -> void:
	var one := StateHasher.new()
	var batch := StateHasher.new()
	for v: int in [3, -7, 1 << 40, 0]:
		one.add_int(v)
	batch.add_ints(PackedInt64Array([3, -7, 1 << 40, 0]))
	assert_int(batch.value()).is_equal(one.value())
	batch.add_int(9)
	batch.add_ints(PackedInt64Array())
	one.add_int(9)
	assert_int(batch.value()).is_equal(one.value())
