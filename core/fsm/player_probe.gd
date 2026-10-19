class_name PlayerProbe
extends RefCounted
## Named read-only views of the player for replay fixtures and the F3 overlay (the key list is in
## tests/replay/README.md). Positions and velocities are sub-pixels unless the key ends in "u".

const WORD_KEYS: Array[String] = ["state", "action", "chain", "spell", "tier"]


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
		"spell":
			return PackedStringArray(PlayerSpells.NAMES)
		"tier":
			return PackedStringArray(Kindling.TIER_NAMES)
	return PackedStringArray()


static func _word(pl: Player, key: String) -> String:
	match key:
		"state":
			return Player.LOCO_NAMES[pl.loco]
		"action":
			return pl.current_attack().id if pl.action != Player.NO_ACTION else "none"
		"spell":
			return PlayerSpells.NAMES[pl.spell]
		"tier":
			return Kindling.TIER_NAMES[pl.vitals.kindling.tier()]
	return pl.chain_next


static func _number(pl: Player, key: String) -> Variant:
	# One branch per key: a fixture probes every key it checks on every tick, so a probe computes
	# only the value asked for.
	var b: Body = pl.body
	match key:
		"x":
			return b.x
		"y":
			return b.y
		"xu":
			return Fx.div_floor(b.x, Fx.SUB)
		"yu":
			return Fx.div_floor(b.y, Fx.SUB)
		"vx":
			return b.vx
		"vy":
			return b.vy
		"height":
			return Fx.div_floor(b.height, Fx.SUB)
		"ground":
			return 1 if b.on_ground else 0
		"slope":
			return 1 if b.on_slope else 0
		"hit_wall":
			return b.hit_wall
		"hit_ceiling":
			return 1 if b.hit_ceiling else 0
		"nudge_x":
			return b.nudge_x
		"nudge_y":
			return b.nudge_y
		"facing":
			return pl.facing
		"crouch":
			return 1 if pl.crouching else 0
		"air_frames":
			return pl.air_frames
		"air_jumps":
			return pl.air_jumps_left
		"air_dashes":
			return pl.air_dashes_left
		"dash_frame":
			return pl.dash_frame
		"dash_cooldown":
			return pl.ground_dash_cooldown
		"carry":
			return pl.carry_frames
		"jump_frame":
			return pl.jump_frame
		"jump_cut":
			return 1 if pl.jump_cut else 0
		"wall":
			return pl.wall_side
		"wall_frames":
			return pl.wall_frames
		"wall_lock":
			return pl.wall_lock
		"action_frame":
			return pl.action_frame
		"action_dir":
			return pl.action_dir
		"strike":
			return 1 if pl.strike_box().size != Vector2i.ZERO else 0
		"pogo_live":
			return 1 if pl.pogo_box().size != Vector2i.ZERO else 0
		"since_bounce":
			return pl.since_bounce
		"invuln":
			return 1 if pl.is_invulnerable() else 0
		"ember":
			return 1 if pl.toss.active else 0
		"ember_x":
			return pl.toss.x
		"ember_y":
			return pl.toss.y
		"toss_cooldown":
			return pl.toss.cooldown
		"freeze":
			return pl.freeze
		"invuln_frames":
			return pl.invuln
		"hearts":
			return pl.vitals.hearts.current
		"max_hearts":
			return pl.vitals.hearts.max_hearts
		"flame":
			return pl.vitals.flame.value
		"kindling":
			return pl.vitals.kindling.hits
		"spell_frame":
			return pl.spell_frame
		"knock":
			return pl.knock_left
		"charge_held":
			return pl.charge_held
		"charge_request":
			return pl.charge_request
	return null
