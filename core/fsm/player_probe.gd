class_name PlayerProbe
extends RefCounted
## Named read-only views of the player for replay fixtures and the F3 overlay (the key list is in
## tests/replay/README.md). Positions and velocities are sub-pixels unless the key ends in "u".

const WORD_KEYS: Array[String] = ["state", "action", "chain"]


## The value of [param key], or null if the key is unknown.
static func read(pl: Player, events: SimEvents, key: String) -> Variant:
	if key.begins_with("event."):
		return 1 if events.has(key.substr(6)) else 0
	if WORD_KEYS.has(key):
		return _word(pl, key)
	return _number(pl, key)


static func words(pl: Player, key: String) -> PackedStringArray:
	match key:
		"state":
			return PackedStringArray(Player.LOCO_NAMES)
		"action", "chain":
			var out: PackedStringArray = ["none"]
			for a: AttackDef in pl.attacks.attacks:
				out.append(a.id)
			return out
	return PackedStringArray()


static func _word(pl: Player, key: String) -> String:
	match key:
		"state":
			return Player.LOCO_NAMES[pl.loco]
		"action":
			return pl.current_attack().id if pl.action != Player.NO_ACTION else "none"
	return pl.chain_next


static func _number(pl: Player, key: String) -> Variant:
	var b: Body = pl.body
	var table: Dictionary[String, int] = {
		"x": b.x,
		"y": b.y,
		"xu": Fx.div_floor(b.x, Fx.SUB),
		"yu": Fx.div_floor(b.y, Fx.SUB),
		"vx": b.vx,
		"vy": b.vy,
		"height": Fx.div_floor(b.height, Fx.SUB),
		"ground": 1 if b.on_ground else 0,
		"slope": 1 if b.on_slope else 0,
		"hit_wall": b.hit_wall,
		"hit_ceiling": 1 if b.hit_ceiling else 0,
		"nudge_x": b.nudge_x,
		"nudge_y": b.nudge_y,
		"facing": pl.facing,
		"crouch": 1 if pl.crouching else 0,
		"air_frames": pl.air_frames,
		"air_jumps": pl.air_jumps_left,
		"air_dashes": pl.air_dashes_left,
		"dash_frame": pl.dash_frame,
		"dash_cooldown": pl.ground_dash_cooldown,
		"carry": pl.carry_frames,
		"jump_frame": pl.jump_frame,
		"jump_cut": 1 if pl.jump_cut else 0,
		"wall": pl.wall_side,
		"wall_frames": pl.wall_frames,
		"wall_lock": pl.wall_lock,
		"action_frame": pl.action_frame,
		"strike": 1 if pl.strike_box().size != Vector2i.ZERO else 0,
		"pogo_live": 1 if pl.pogo_box().size != Vector2i.ZERO else 0,
		"since_bounce": pl.since_bounce,
		"invuln": 1 if pl.is_invulnerable() else 0,
		"ember": 1 if pl.toss.active else 0,
		"ember_x": pl.toss.x,
		"ember_y": pl.toss.y,
		"toss_cooldown": pl.toss.cooldown,
	}
	if table.has(key):
		return table[key]
	return null
