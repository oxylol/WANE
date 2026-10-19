class_name PlayerCombat
extends RefCounted
## What combat does to the player (BUILD.md section 6; docs/adr/0013): a hit and its knockback, a
## hazard's cost, death, the Charged strike's hold and White's dash. Static helpers on a [Player],
## kept apart from the state machine so it stays readable; the state they change is the player's.


## Before the player's actions each tick: the Charged strike's hold is read, and at Kindling White
## the ground dash has no cooldown ("dash has no cooldown"), nor with a Votive that takes it away
## ([member Player.dash_free]: Hollow Step, docs/adr/0015).
static func before_actions(pl: Player, ring: InputRing) -> void:
	_track_charge(pl, ring)
	if pl.vitals.kindling.tier() >= Kindling.WHITE or pl.dash_free:
		pl.ground_dash_cooldown = 0


## After the player's actions each tick: an action taken ends the knockback after a hit (the
## stick's sideways push comes back with any action), and ends a spell that allows it.
static func after_actions(pl: Player) -> void:
	PlayerSpells.yield_to_actions(pl)
	if pl.knock_left <= 0:
		return
	for kind: String in PlayerSpells.ACTION_EVENTS:
		if pl.events.has(kind):
			pl.knock_left = 0
			return


## Holding attack unbroken for the Charged strike's [member AttackDef.charge_frames] arms it;
## letting go then asks for it, and the request waits as long as an attack press would (the
## attack buffer). Held frames are the player's own, so hitstop never counts toward a charge
## ([InputRing]).
static func _track_charge(pl: Player, ring: InputRing) -> void:
	if pl.charge_request > 0:
		pl.charge_request -= 1
	var charged: AttackDef = pl.charged_attack
	var held: int = ring.held_frames(InputFrame.ATTACK)
	if charged != null and held == 0 and pl.charge_held >= charged.charge_frames:
		pl.charge_request = pl.p.attack_buffer_frames + 1
		pl.charge_stick = Vector2i(ring.stick_x(), ring.stick_y())
		pl.events.add(SimEvents.CHARGE_RELEASE, pl.body.x, pl.body.y)
	elif charged != null and held == charged.charge_frames:
		pl.events.add(SimEvents.CHARGE_READY, pl.body.x, pl.body.y)
	pl.charge_held = held


## An enemy's attack lands on the player (docs/adr/0013, The player hit): hearts and a Kindling
## tier lost, whatever was under way ended, hitstop on the player, a knockback [param away] from
## the attacker and invulnerability. [param at] is where the hit landed, for the event.
static func hurt(pl: Player, ring: InputRing, away: int, damage: int, at: Vector2i) -> void:
	var c: CombatParams = pl.combat
	pl.events.add(SimEvents.PLAYER_HIT, at.x, at.y, HitKind.encode(HitKind.PLAYER, away, 0))
	pl.vitals.hearts.lose(damage)
	pl.vitals.kindling.drop_tier()
	if pl.vitals.hearts.is_dead():
		die(pl, ring)
		return
	pl.interrupt()
	pl.freeze = maxi(pl.freeze, c.hitstop_player_hit)
	pl.knock_left = c.player_hit_knock_frames
	pl.knock_vx = away * c.player_hit_knockback
	pl.body.vx = pl.knock_vx
	pl.invuln = maxi(pl.invuln, c.player_hit_invuln_frames)


## A hazard touched the hurtbox: it costs [member CombatParams.hazard_damage] hearts and a
## Kindling tier, as a hit does. True if that killed the player (who is then already back at the
## spawn).
static func hazard(pl: Player, ring: InputRing) -> bool:
	pl.vitals.hearts.lose(pl.combat.hazard_damage)
	pl.vitals.kindling.drop_tier()
	if pl.vitals.hearts.is_dead():
		die(pl, ring)
		return true
	return false


## No hearts left (Phase 1, docs/adr/0013): back to the room's spawn with full hearts, no Flame
## and Kindling reset ("Dying resets it").
static func die(pl: Player, ring: InputRing) -> void:
	var v: Vitals = pl.vitals
	pl.events.add(SimEvents.DEATH, pl.body.x, pl.body.y)
	v.hearts.heal(v.hearts.max_hearts)
	v.flame.value = 0
	v.kindling.reset()
	pl.white_hits = 0
	pl.knock_left = 0
	pl.knock_vx = 0
	pl.charge_held = 0
	pl.charge_request = 0
	PlayerContacts.send_back(pl, ring, pl.home_x, pl.home_y)
