class_name ProcTuning
extends Resource
## The proc rules every Votive shares (BUILD.md section 6, Item procs and Kindling; section 8,
## Stacking math; docs/adr/0015): each proc event's coefficient, how deep a chain of procs may go,
## and the Kindling Flame tier's bonus to proc chances. Coefficients are per-mille (1000 is 1.0).
## Each Votive's own numbers are in its resource under content/votives/.

const PATH: String = "res://content/combat/procs.tres"

@export_group("Coefficients")
## "Every Taper hit, pogo, spell tick and Dust scale is a proc event with a proc coefficient (Taper
## 1.0, pogo 0.8, Kindle 0.5 per tick, Dust 0.3 per scale, Radiance 0.2)."
@export var taper_permille: int = 1000
@export var pogo_permille: int = 800
@export var kindle_permille: int = 500
## Kept for Moth's Dust (BUILD.md section 4): no Wick throws a wing-scale yet.
@export var dust_permille: int = 300
@export var radiance_permille: int = 200

@export_group("Chains")
## "Proc chains are allowed (a proc can trigger another) to a depth of 3, then stop": the deepest
## proc in a chain fires at this level; a hit it lands raises no further proc.
@export var chain_depth: int = 3

@export_group("Kindling")
## The Flame tier (and the tiers above it): "Votive procs +10% chance", relative to the chance
## (10% becomes 11%), as the same row's "+10% damage" is relative (docs/adr/0015).
@export var flame_tier_chance_permille: int = 100


## The coefficient, per-mille, of a proc event raised by [param source] ([ProcSource]); a Votive's
## hit carries its own ([member Votive.hit_coefficient_permille]), so VOTIVE has none here.
func coefficient(source: int) -> int:
	match source:
		ProcSource.TAPER:
			return taper_permille
		ProcSource.POGO:
			return pogo_permille
		ProcSource.KINDLE:
			return kindle_permille
		ProcSource.DUST:
			return dust_permille
		ProcSource.RADIANCE:
			return radiance_permille
	return 0


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	for v: int in [
		taper_permille, pogo_permille, kindle_permille, dust_permille, radiance_permille
	]:
		if v < 0 or v > StackingCurve.PERMILLE:
			e.append("proc coefficients must be 0 to 1000 per-mille (0 to 1.0)")
			break
	if chain_depth < 1:
		e.append("chain_depth must be at least 1 (a proc fires at level 1)")
	if flame_tier_chance_permille < 0:
		e.append("flame_tier_chance_permille must not be negative")
	return e
