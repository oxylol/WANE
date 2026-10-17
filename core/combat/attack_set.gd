class_name AttackSet
extends Resource
## A Wick's weapon: every strike's frame data (BUILD.md section 6, "The Taper").

@export var attacks: Array[AttackDef] = []
## Frames after a strike's recovery ends during which the next press continues the chain (20 f).
@export var chain_reset_frames: int = 20


func find(attack_id: String) -> AttackDef:
	for a: AttackDef in attacks:
		if a.id == attack_id:
			return a
	return null


func index_of(attack_id: String) -> int:
	for i: int in range(attacks.size()):
		if attacks[i].id == attack_id:
			return i
	return -1


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	for required: String in ["side1", "side2", "side3", "up", "down", "charged"]:
		if find(required) == null:
			e.append("missing strike '%s'" % required)
	for a: AttackDef in attacks:
		e.append_array(a.validate())
		if a.chain_to != "" and find(a.chain_to) == null:
			e.append("%s chains to unknown strike '%s'" % [a.id, a.chain_to])
	if chain_reset_frames < 0:
		e.append("chain_reset_frames must not be negative")
	return e
