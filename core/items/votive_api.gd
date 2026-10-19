class_name VotiveApi
extends RefCounted
## What every Votive listener may read and keep (docs/adr/0015): its stacks, its curve's value at
## them, the numbers in its resource, and one counter the bus keeps for it in the state hash. The
## trigger's own API ([ProcApi], [BladeHitApi], [BounceApi], [RunApi]) adds what that trigger may
## do. The bus fills these fields before each call, and holds itself here only for the call (so
## the two never keep each other alive); a listener reads them only through the methods.

var _bus: ProcBus
var _slot: int = 0
var _stacks: int = 0
var _value: int = 0


## The Votive's stacks.
func stacks() -> int:
	return _stacks


## The Votive's curve at its stacks ([method StackingCurve.value]: the Votive's unit for a linear
## curve, parts per million for the others).
func value() -> int:
	return _value


## A number from the Votive's resource ([member Votive.params]).
func param(param_name: String) -> int:
	return _bus._param_of(_slot, param_name)


## The Votive's counter: the one integer it may keep from call to call (state, hashed).
func counter() -> int:
	return _bus._counter_of(_slot)


func set_counter(v: int) -> void:
	_bus._set_counter_of(_slot, v)


func _set_slot(slot: int, p_stacks: int, p_value: int) -> void:
	_slot = slot
	_stacks = p_stacks
	_value = p_value
