class_name ProcApi
extends VotiveApi
## What a Votive's proc may read and do when it fires ("hit" trigger; docs/adr/0015). Enemies are
## handles (their place in the room's list); positions and radii are world units for the listener,
## sub-pixels inside. Every effect goes through combat's rules for proc damage and stuns.

var _level: int = 0
var _source: int = 0
var _coefficient: int = 0
var _target: int = -1
var _damage: int = 0


## The chain level this proc fires at: 1 for a proc of a Taper hit, pogo, Kindle tick or
## Radiance, one more for a proc of a Votive's hit, up to [member ProcTuning.chain_depth].
func level() -> int:
	return _level


## What raised the event ([ProcSource]).
func source() -> int:
	return _source


## The event's coefficient, per-mille.
func coefficient() -> int:
	return _coefficient


## The enemy the event's hit landed on (a handle), or -1.
func target() -> int:
	return _target


## The damage the event's hit dealt (0 for Radiance's push).
func damage() -> int:
	return _damage


## A proc hit of [param amount] damage on enemy [param handle]: proc damage (health and poise,
## Kindling's bonus, a kill's ember; no hitstop, knockback, Kindling hit or Flame), which raises a
## proc event one level deeper. False if there is no such living enemy.
func hit(handle: int, amount: int) -> bool:
	return _bus._proc_hit(handle, amount)


## Stuns every living enemy whose centre is within [param radius_u] units of the event's point for
## [param frames] ticks; returns how many.
func stun_within(radius_u: int, frames: int) -> int:
	return _bus._stun_within(radius_u, frames)


## The living enemy nearest the event's point within [param radius_u] units (the event's own
## target skipped with [param skip_target]), ties to the lower handle; -1 if none.
func nearest_enemy(radius_u: int, skip_target: bool) -> int:
	return _bus._nearest_enemy(radius_u, skip_target)


## True with [param per_mille] / 1000 chance, drawn from the PROCS stream.
func roll_permille(per_mille: int) -> bool:
	return _bus._roll_permille(per_mille)
