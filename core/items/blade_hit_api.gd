class_name BladeHitApi
extends VotiveApi
## What a Votive may do to a Taper or pogo hit before it lands ("blade_hit" trigger;
## docs/adr/0015): add damage. Votives change what a hit does, never how it feels: the damage a
## Votive adds is dealt, but the hit's hitstop is weighed without it (BUILD.md section 1, pillar 2).

var _source: int = 0
var _target: int = -1
var _added: int = 0


## [constant ProcSource.TAPER] or [constant ProcSource.POGO].
func source() -> int:
	return _source


## The enemy the hit lands on (a handle).
func target() -> int:
	return _target


## Adds [param amount] to the hit's damage, before Kindling's bonus multiplies it.
func add_damage(amount: int) -> void:
	_added += amount
