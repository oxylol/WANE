class_name EnemyProbe
extends RefCounted
## Named read-only views of the room's enemies for replay fixtures and tools (the key list is in
## tests/replay/README.md): "enemy.<key>" reads the room's first enemy, "enemy<n>.<key>" its n-th
## (from 0). Keys: hp, poise, state (a word), x, y, vx (its knockback), vy, facing, freeze, burn.
## Positions and speeds are sub-pixels.


## The value of [param key], or null if there is no such enemy or key.
static func read(combat: Combat, key: String) -> Variant:
	var e: Enemy = _enemy(combat, key)
	if e == null:
		return null
	var field: String = key.substr(key.find(".") + 1)
	if field == "state":
		return e.state_name()
	var table: Dictionary[String, int] = {
		"hp": e.hp,
		"poise": e.poise,
		"x": e.body.x,
		"y": e.body.y,
		"vx": e.knock_vx,
		"vy": e.body.vy,
		"facing": e.facing,
		"freeze": e.freeze,
		"burn": e.burn_left,
	}
	if table.has(field):
		return table[field]
	return null


## The names a word key can take, or empty for an integer key.
static func words(key: String) -> PackedStringArray:
	if key.begins_with("enemy") and key.ends_with(".state"):
		return PackedStringArray(Enemy.STATE_NAMES)
	return PackedStringArray()


static func _enemy(combat: Combat, key: String) -> Enemy:
	var dot: int = key.find(".")
	if dot < 0:
		return null
	var which: String = key.substr(5, dot - 5)
	var i: int = 0
	if which != "":
		i = which.to_int() if which.is_valid_int() else -1
	if i < 0 or i >= combat.enemies.size():
		return null
	return combat.enemies[i]
