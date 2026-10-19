class_name Hearts
extends RefCounted
## The player's health in hearts (BUILD.md section 6: "the player's 5 base hearts").

var current: int = 0
var max_hearts: int = 0


func _init(p_max: int) -> void:
	max_hearts = p_max
	current = p_max


func lose(count: int = 1) -> void:
	current = maxi(current - count, 0)


func heal(count: int = 1) -> void:
	current = mini(current + count, max_hearts)


## A new maximum (a Votive's, docs/adr/0015), at least one heart; the hearts held never exceed it.
func set_max(p_max: int) -> void:
	max_hearts = maxi(p_max, 1)
	current = mini(current, max_hearts)


func is_dead() -> bool:
	return current <= 0


func hash_into(h: StateHasher) -> void:
	h.add_int(current)
	h.add_int(max_hearts)
