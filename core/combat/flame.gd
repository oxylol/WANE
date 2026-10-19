class_name Flame
extends RefCounted
## The Flame bar (BUILD.md section 6, "Flame"): earned by fighting, spent on spells and Mend.

var value: int = 0
var cap: int = 100


func _init(p_cap: int) -> void:
	cap = p_cap


func gain(amount: int) -> void:
	value = mini(value + amount, cap)


## Spends [param amount] if there is that much; false (and nothing spent) if not.
func spend(amount: int) -> bool:
	if value < amount:
		return false
	value -= amount
	return true


func hash_into(h: StateHasher) -> void:
	h.add_int(value)
	h.add_int(cap)
