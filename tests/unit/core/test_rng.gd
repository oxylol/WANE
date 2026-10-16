extends GdUnitTestSuite
## Rng and RngStreams (ADR-0005): deterministic, split, well distributed.

## First four outputs of Rng.seeded(1, 0), computed by an independent Python implementation of
## xoshiro128** with the same seeding (docs/adr/0005). A change invalidates every replay.
const SEED1_STREAM0: Array[int] = [0xE16BD0AC, 0x07D54959, 0xEDCA5E97, 0x2CDA5CD6]


func test_same_seed_same_sequence() -> void:
	var a: Rng = Rng.seeded(42, 0)
	var b: Rng = Rng.seeded(42, 0)
	for _i: int in range(100):
		assert_int(a.next_u32()).is_equal(b.next_u32())


func test_golden_sequence_is_stable_across_platforms() -> void:
	# If this changes, every replay ever recorded desyncs. It must never change.
	var r: Rng = Rng.seeded(1, 0)
	var got: Array[int] = []
	for _i: int in range(4):
		got.append(r.next_u32())
	assert_array(got).is_equal(SEED1_STREAM0)


func test_streams_are_independent() -> void:
	var s1 := RngStreams.new(7)
	var s2 := RngStreams.new(7)
	for _i: int in range(50):
		s1.vfx().next_u32()
	assert_int(s1.loot().next_u32()).is_equal(s2.loot().next_u32())
	assert_int(s1.vfx().next_u32()).is_not_equal(s2.vfx().next_u32())


func test_streams_differ_from_each_other() -> void:
	var s := RngStreams.new(7)
	var firsts: Array[int] = []
	for id: int in range(RngStreams.COUNT):
		firsts.append(s.stream(id).next_u32())
	for i: int in range(firsts.size()):
		for j: int in range(i + 1, firsts.size()):
			assert_int(firsts[i]).is_not_equal(firsts[j])


func test_values_are_32_bit() -> void:
	var r: Rng = Rng.seeded(-123456789, 3)
	for _i: int in range(1000):
		var v: int = r.next_u32()
		assert_bool(v >= 0 and v <= 0xFFFFFFFF).is_true()


func test_below_is_in_range_and_roughly_uniform() -> void:
	var r: Rng = Rng.seeded(99, 1)
	var counts: Array[int] = [0, 0, 0, 0, 0, 0]
	for _i: int in range(6000):
		var v: int = r.below(6)
		assert_bool(v >= 0 and v < 6).is_true()
		counts[v] += 1
	for c: int in counts:
		assert_int(c).is_between(850, 1150)


func test_between_and_chance() -> void:
	var r: Rng = Rng.seeded(5, 2)
	for _i: int in range(200):
		assert_int(r.between(-3, 3)).is_between(-3, 3)
	assert_int(r.between(4, 4)).is_equal(4)
	assert_bool(r.chance_permille(0)).is_false()
	assert_bool(r.chance_permille(1000)).is_true()
	var hits: int = 0
	for _i: int in range(10000):
		if r.chance_permille(100):
			hits += 1
	assert_int(hits).is_between(900, 1100)


func test_state_round_trip() -> void:
	var r: Rng = Rng.seeded(11, 0)
	r.next_u32()
	var saved: PackedInt64Array = r.get_state()
	var a: int = r.next_u32()
	r.set_state(saved)
	assert_int(r.next_u32()).is_equal(a)


func test_named_stream_accessors() -> void:
	var s := RngStreams.new(3)
	var t := RngStreams.new(3)
	assert_int(s.loot().next_u32()).is_equal(t.stream(RngStreams.LOOT).next_u32())
	assert_int(s.spawns().next_u32()).is_equal(t.stream(RngStreams.SPAWNS).next_u32())
	assert_int(s.ai().next_u32()).is_equal(t.stream(RngStreams.AI).next_u32())
	assert_int(s.procs().next_u32()).is_equal(t.stream(RngStreams.PROCS).next_u32())
	assert_int(RngStreams.NAMES.size()).is_equal(RngStreams.COUNT)


func test_below_degenerate_bounds() -> void:
	var r: Rng = Rng.seeded(1, 0)
	assert_int(r.below(1)).is_equal(0)
	assert_int(r.below(0)).is_equal(0)


func test_negative_seed_matches_reference() -> void:
	var r: Rng = Rng.seeded(-7, 3)
	assert_int(r.next_u32()).is_equal(0xFB0EBDAC)
	assert_int(r.next_u32()).is_equal(0x2D0C9F04)


func test_seeds_differing_only_in_high_word_differ() -> void:
	# 0x100000001 and 0 used to collide when the words were XORed together.
	assert_int(Rng.seeded(0x100000001, 0).next_u32()).is_not_equal(Rng.seeded(0, 0).next_u32())
	assert_int(Rng.seeded(1 << 32, 0).next_u32()).is_not_equal(Rng.seeded(0, 0).next_u32())
	assert_int(Rng.seeded(5, 1).next_u32()).is_not_equal(Rng.seeded(5, 0).next_u32())


func test_full_32_bit_span() -> void:
	var r: Rng = Rng.seeded(2, 0)
	for _i: int in range(100):
		var v: int = r.between(-(1 << 31), (1 << 31) - 1)
		assert_bool(v >= -(1 << 31) and v < (1 << 31)).is_true()
