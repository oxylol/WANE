extends GdUnitTestSuite
## BUILD.md section 8, Stacking math, at the points the doc quotes (docs/adr/0015): integers,
## exactly, with the rounding stated in core/items/stacking_curve.gd.

const PPM: int = StackingCurve.PPM


func _curve(kind: int, first: int, per: int) -> StackingCurve:
	var c := StackingCurve.new()
	c.kind = kind
	c.first_stack = first
	c.per_stack = per
	return c


func test_no_stacks_is_nothing_on_every_curve() -> void:
	for kind: int in range(StackingCurve.NAMES.size()):
		assert_int(_curve(kind, 100, 100).value(0)).is_equal(0)
		assert_int(_curve(kind, 100, 100).value(-3)).is_equal(0)


## "Linear: flat damage, run speed, radius. Add per stack, no cap."
func test_linear_adds_per_stack_with_no_cap() -> void:
	var knuckle: StackingCurve = _curve(StackingCurve.LINEAR, 3, 3)
	assert_int(knuckle.value(1)).is_equal(3)
	assert_int(knuckle.value(2)).is_equal(6)
	assert_int(knuckle.value(10)).is_equal(30)
	assert_int(knuckle.value(1000)).is_equal(3000)
	var wick: StackingCurve = _curve(StackingCurve.LINEAR, 80, 80)
	assert_int(wick.value(1)).is_equal(80)
	assert_int(wick.value(2)).is_equal(160)


## A first stack unlike the rest: "parries heal half a heart; stacks add a quarter" in quarters.
func test_linear_first_stack_may_differ() -> void:
	var mercy: StackingCurve = _curve(StackingCurve.LINEAR, 2, 1)
	assert_array([mercy.value(1), mercy.value(2), mercy.value(3)]).is_equal([2, 3, 4])


## "A 10%-chance Lantern at 10 stacks procs every hit; at 15 stacks, every hit plus a 50% chance
## of a second."
func test_chance_adds_to_one_hundred_percent_then_rolls() -> void:
	var bell: StackingCurve = _curve(StackingCurve.CHANCE, 100, 100)
	assert_int(bell.value(1)).is_equal(100000)
	assert_int(bell.value(5)).is_equal(500000)
	assert_int(bell.value(10)).is_equal(PPM)
	assert_int(bell.value(15)).is_equal(PPM + 500000)
	assert_int(bell.value(15) / PPM).is_equal(1)
	assert_int(bell.value(15) % PPM).is_equal(500000)


## "1 - 1 / (1 + 0.1 x stacks), so 10 stacks is 50%, never 100%."
func test_hyperbolic_is_half_at_ten_stacks_and_never_whole() -> void:
	var armour: StackingCurve = _curve(StackingCurve.HYPERBOLIC, 100, 100)
	assert_int(armour.value(10)).is_equal(500000)
	# 1 - 1 / 1.1 = 0.0909090..., rounded down.
	assert_int(armour.value(1)).is_equal(90909)
	# 1 - 1 / 1.2 = 0.1666...
	assert_int(armour.value(2)).is_equal(166666)
	# 1 - 1 / 11 = 0.90909...
	assert_int(armour.value(100)).is_equal(909090)
	for stacks: int in [1000, 100000, 10000000]:
		assert_int(armour.value(stacks)).is_less(PPM)
	var last: int = 0
	for stacks: int in range(1, 200):
		assert_int(armour.value(stacks)).is_greater(last)
		last = armour.value(stacks)


## "Diminishing ... each stack removes 15% of what remains."
func test_diminishing_removes_fifteen_percent_of_what_remains() -> void:
	var cooldown: StackingCurve = _curve(StackingCurve.DIMINISHING, 150, 150)
	assert_int(cooldown.value(1)).is_equal(150000)
	# 1 - 0.85^2 = 0.2775, 1 - 0.85^3 = 0.385875: exact in parts per million.
	assert_int(cooldown.value(2)).is_equal(277500)
	assert_int(cooldown.value(3)).is_equal(385875)
	# 1 - 0.85^4 = 0.47799375: the removal rounds down, so what remains never falls below the
	# exact 522,006.25.
	assert_int(cooldown.value(4)).is_equal(477993)
	var remains: int = PPM
	for stacks: int in range(1, 60):
		var removed: int = remains * 150 / 1000
		remains -= removed
		assert_int(cooldown.value(stacks)).is_equal(PPM - remains)
	assert_int(cooldown.value(1000)).is_less(PPM)


func test_validation() -> void:
	assert_array(Array(_curve(StackingCurve.LINEAR, 3, 3).validate())).is_empty()
	assert_array(Array(_curve(StackingCurve.CHANCE, 100, 100).validate())).is_empty()
	assert_array(Array(_curve(StackingCurve.HYPERBOLIC, 100, 100).validate())).is_empty()
	assert_array(Array(_curve(StackingCurve.DIMINISHING, 150, 150).validate())).is_empty()
	var bad: Array[StackingCurve] = [
		_curve(9, 1, 1),
		_curve(StackingCurve.LINEAR, -1, 1),
		_curve(StackingCurve.CHANCE, 0, 100),
		_curve(StackingCurve.HYPERBOLIC, 100, 50),
		_curve(StackingCurve.DIMINISHING, 1500, 1500),
		_curve(StackingCurve.HYPERBOLIC, 0, 0),
	]
	for c: StackingCurve in bad:
		(
			assert_array(Array(c.validate()))
			. override_failure_message("%d %d %d" % [c.kind, c.first_stack, c.per_stack])
			. is_not_empty()
		)
