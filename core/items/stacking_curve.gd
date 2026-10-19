class_name StackingCurve
extends Resource
## How a Votive's number grows with its stacks (BUILD.md section 8, Stacking math; docs/adr/0015),
## in integers, exactly:
##
## - LINEAR ("flat damage, run speed, radius. Add per stack, no cap"): [member first_stack] for
##   the first stack, plus [member per_stack] for each one after, in the Votive's own unit (damage,
##   per-mille of run speed, air dashes).
## - CHANCE ("proc chance adds linearly to 100%, then each further stack is an extra roll"): the
##   same sum, per-mille, returned in parts per million and never capped: 1,000,000 or more is a
##   proc on every event, and each further whole million another ([ProcBus] splits it).
## - HYPERBOLIC ("1 - 1 / (1 + 0.1 x stacks), so 10 stacks is 50%, never 100%"): with
##   k = [member per_stack] per-mille (100 for the doc's 0.1), x = k x stacks per-mille,
##   1 - 1 / (1 + x / 1000) = x / (1000 + x), in parts per million, rounded down: below 100%
##   for every stack count.
## - DIMINISHING ("each stack removes 15% of what remains"): what remains starts at 100%; each
##   stack removes [member per_stack] per-mille of it, rounded down to the part per million (so
##   what remains is never less than the exact value); the value is what has been removed, in
##   parts per million.
##
## Parts per million keep a 10% chance on a 0.5-coefficient hit with the Flame tier's bonus exact
## (55,000 ppm, 5.5%) where per-mille would round it.

enum { LINEAR, CHANCE, HYPERBOLIC, DIMINISHING }

const NAMES: Array[String] = ["linear", "chance", "hyperbolic", "diminishing"]
const PERMILLE: int = 1000
const PPM: int = 1000000

@export var kind: int = LINEAR
## The first stack's amount: in the Votive's unit for LINEAR, per-mille for CHANCE. HYPERBOLIC and
## DIMINISHING have one constant, [member per_stack], and this must equal it.
@export var first_stack: int = 0
## Each further stack's amount, in the same unit; for HYPERBOLIC and DIMINISHING the constant k,
## per-mille.
@export var per_stack: int = 0


## The curve's value at [param stacks] (0 for no stacks): see the class description for units.
func value(stacks: int) -> int:
	if stacks <= 0:
		return 0
	match kind:
		LINEAR:
			return linear(first_stack, per_stack, stacks)
		CHANCE:
			return chance_ppm(first_stack, per_stack, stacks)
		HYPERBOLIC:
			return hyperbolic_ppm(per_stack, stacks)
		DIMINISHING:
			return diminishing_ppm(per_stack, stacks)
	return 0


## [param first] for one stack, plus [param per] for each further stack; no cap.
static func linear(first: int, per: int, stacks: int) -> int:
	if stacks <= 0:
		return 0
	return first + per * (stacks - 1)


## The stacked chance in parts per million: [param first_permille] for one stack, plus
## [param per_permille] for each further stack, uncapped.
static func chance_ppm(first_permille: int, per_permille: int, stacks: int) -> int:
	return linear(first_permille, per_permille, stacks) * (PPM / PERMILLE)


## 1 - 1 / (1 + k x stacks) in parts per million, k = [param k_permille] / 1000, rounded down.
static func hyperbolic_ppm(k_permille: int, stacks: int) -> int:
	if stacks <= 0:
		return 0
	var x: int = k_permille * stacks
	return PPM * x / (PERMILLE + x)


## 1 - (1 - k) ^ stacks in parts per million, k = [param k_permille] / 1000: each stack removes
## k of what remains, the removal rounded down to the part per million.
static func diminishing_ppm(k_permille: int, stacks: int) -> int:
	var remains: int = PPM
	for _i: int in range(maxi(stacks, 0)):
		var removed: int = remains * k_permille / PERMILLE
		if removed <= 0:
			break
		remains -= removed
	return PPM - remains


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if kind < LINEAR or kind > DIMINISHING:
		e.append("a stacking curve is linear, chance, hyperbolic or diminishing")
		return e
	if first_stack < 0 or per_stack < 0:
		e.append("a stacking curve's amounts must not be negative")
	match kind:
		CHANCE:
			if first_stack <= 0:
				e.append("a chance curve's first stack must have a chance")
		HYPERBOLIC, DIMINISHING:
			if first_stack != per_stack:
				e.append(
					"a %s curve has one constant: first_stack must equal per_stack" % NAMES[kind]
				)
			if per_stack <= 0 or per_stack > PERMILLE:
				e.append("a %s curve's constant must be 1 to 1000 per-mille" % NAMES[kind])
	return e
