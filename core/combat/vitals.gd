class_name Vitals
extends RefCounted
## What a Wick carries through a fight (BUILD.md section 6): hearts, the Flame bar and the
## Kindling combo meter.

var hearts: Hearts
var flame: Flame
var kindling: Kindling


func _init(p: CombatParams) -> void:
	hearts = Hearts.new(p.hearts)
	flame = Flame.new(p.flame_cap)
	kindling = Kindling.new(p)


func hash_into(h: StateHasher) -> void:
	hearts.hash_into(h)
	flame.hash_into(h)
	kindling.hash_into(h)
