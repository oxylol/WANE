class_name Kindling
extends RefCounted
## The combo meter (BUILD.md section 6, "Kindling"): consecutive hits without taking damage, in
## four tiers (Ember 0 to 7, Flame 8 to 19, Blaze 20 to 39, White 40+). Taking damage drops it one
## tier, to that tier's first hit count; dying resets it.

enum { EMBER, FLAME, BLAZE, WHITE }

const TIER_NAMES: Array[String] = ["ember", "flame", "blaze", "white"]

var hits: int = 0
var _params: CombatParams


func _init(p_params: CombatParams) -> void:
	_params = p_params


func tier() -> int:
	var t: int = EMBER
	for i: int in range(_params.kindling_tiers.size()):
		if hits >= _params.kindling_tiers[i]:
			t = i
	return t


func add(count: int = 1) -> void:
	hits += count


## Taking damage: down one tier, not to zero ("Taking damage drops Kindling by one tier").
func drop_tier() -> void:
	hits = _params.kindling_tiers[maxi(tier() - 1, EMBER)]


func reset() -> void:
	hits = 0


## [param damage] with this tier's bonus (+10%, +20%, +30%), rounded to the nearest point.
func boost(damage: int) -> int:
	return Fx.div_round(damage * (1000 + _params.kindling_bonus_permille[tier()]), 1000)


func hash_into(h: StateHasher) -> void:
	h.add_int(hits)
