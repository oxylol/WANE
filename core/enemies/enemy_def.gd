class_name EnemyDef
extends Resource
## An enemy kind's numbers (BUILD.md sections 6 and 7): size, health, poise, how it falls, and
## its attacks. Units as BUILD.md gives them.

@export var kind: String = ""
@export var width_u: int = 32
@export var height_u: int = 64
@export var hp: int = 100
## "Every enemy has a poise value; player hits reduce it": a hit takes poise equal to its damage.
@export var poise: int = 30
## Light enemies are launched by finishers ("launches light enemies").
@export var light: bool = false
## Can be pogoed off.
@export var pogoable: bool = true
@export var gravity_ups2: int = 3000
@export var terminal_ups: int = 1500
@export var attacks: Array[EnemyAttack] = []


func find_attack(attack_id: String) -> EnemyAttack:
	for a: EnemyAttack in attacks:
		if a.id == attack_id:
			return a
	return null


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if kind == "":
		e.append("an enemy needs a kind")
	if width_u <= 0 or height_u <= 0 or hp <= 0 or poise <= 0:
		e.append("%s: size, hp and poise must be positive" % kind)
	if gravity_ups2 < 0 or terminal_ups < 0:
		e.append("%s: gravity and terminal velocity must not be negative" % kind)
	for a: EnemyAttack in attacks:
		e.append_array(a.validate())
	return e
