extends GdUnitTestSuite
## Fixed-point helpers (ADR-0003): rounding must be exact and symmetric for negative values.


func test_div_floor_rounds_toward_negative_infinity() -> void:
	assert_int(Fx.div_floor(7, 2)).is_equal(3)
	assert_int(Fx.div_floor(-7, 2)).is_equal(-4)
	assert_int(Fx.div_floor(7, -2)).is_equal(-4)
	assert_int(Fx.div_floor(-7, -2)).is_equal(3)
	assert_int(Fx.div_floor(-8, 2)).is_equal(-4)
	assert_int(Fx.div_floor(0, 5)).is_equal(0)


func test_div_round_is_half_away_from_zero() -> void:
	assert_int(Fx.div_round(5, 2)).is_equal(3)
	assert_int(Fx.div_round(-5, 2)).is_equal(-3)
	assert_int(Fx.div_round(4, 3)).is_equal(1)
	assert_int(Fx.div_round(-4, 3)).is_equal(-1)
	assert_int(Fx.div_round(5, -2)).is_equal(-3)
	assert_int(Fx.div_round(-5, -2)).is_equal(3)


func test_to_units_floor() -> void:
	assert_int(Fx.to_units_floor(255)).is_equal(0)
	assert_int(Fx.to_units_floor(256)).is_equal(1)
	assert_int(Fx.to_units_floor(-1)).is_equal(-1)


func test_design_unit_conversions_match_build_doc() -> void:
	# BUILD.md section 5: 540 u/s run speed is 9 u per tick; 1020 u/s jump is 17 u per tick.
	assert_int(Fx.speed(540)).is_equal(9 * Fx.SUB)
	assert_int(Fx.speed(1020)).is_equal(17 * Fx.SUB)
	assert_int(Fx.speed(-540)).is_equal(-9 * Fx.SUB)
	# 2400 u/s^2 is 170.67 sub-pixels per tick^2, rounded to 171.
	assert_int(Fx.accel(2400)).is_equal(171)
	assert_int(Fx.accel(3000)).is_equal(213)


func test_per_tick_and_scaling() -> void:
	assert_int(Fx.per_tick(9 * Fx.SUB, 6)).is_equal(384)
	assert_int(Fx.per_tick(9 * Fx.SUB, 4)).is_equal(576)
	assert_int(Fx.per_tick(100, 0)).is_equal(100)
	assert_int(Fx.permille(1000, 600)).is_equal(600)
	assert_int(Fx.permille(-171, 600)).is_equal(-103)
	assert_int(Fx.percent(4352, 85)).is_equal(3699)


func test_approach() -> void:
	assert_int(Fx.approach(0, 10, 3)).is_equal(3)
	assert_int(Fx.approach(9, 10, 3)).is_equal(10)
	assert_int(Fx.approach(0, -10, 3)).is_equal(-3)
	assert_int(Fx.approach(5, 5, 3)).is_equal(5)


func test_mul32_matches_modular_multiplication() -> void:
	assert_int(Fx.mul32(0xFFFFFFFF, 0xFFFFFFFF)).is_equal(1)
	assert_int(Fx.mul32(0x85EBCA6B, 2)).is_equal(0x0BD794D6)
	assert_int(Fx.mul32(123456789, 987654321)).is_equal((123456789 * 987654321) & 0xFFFFFFFF)


func test_rotl32_and_fmix32() -> void:
	assert_int(Fx.rotl32(0x80000001, 1)).is_equal(0x00000003)
	assert_int(Fx.rotl32(0x12345678, 8)).is_equal(0x34567812)
	# Reference value of MurmurHash3 fmix32(1).
	assert_int(Fx.fmix32(1)).is_equal(0x514E28B7)
	assert_int(Fx.fmix32(0)).is_equal(0)
