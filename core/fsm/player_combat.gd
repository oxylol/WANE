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


## After the player's actions: an action taken ends the knockback after a hit (the stick's
## sideways push comes back with any action), and ends a spell that allows it. Run twice a tick:
## after the presses taken before the move, and after the move for those a landing or a cling
## fired (a buffered jump, dash or strike), which count from event [param from] on (task 6 core
## review 2, H1 and M1; movement review 6, M1: those never ended the knockback).
static func after_actions(pl: Player, from: int = 0) -> void:
	PlayerSpells.yield_to_actions(pl, from)
	if pl.knock_left <= 0:
		return
	for kind: String in PlayerSpells.ACTION_EVENTS:
		if pl.events.has_since(kind, from):
			pl.knock_left = 0
			return


## Holding attack unbroken for the Charged strike's [member AttackDef.charge_frames] arms it;
## letting go then asks for it, and the request waits as long as an attack press would (the
## attack buffer). Held frames are the player's own, so hitstop never counts toward a charge
## ([InputRing]). A broken hold ([member Player.charge_broken]) counts nothing until the button is
## let go or pressed afresh.
static func _track_charge(pl: Player, ring: InputRing) -> void:
	if pl.charge_request > 0:
		pl.charge_request -= 1
	var charged: AttackDef = pl.charged_attack
	var held: int = ring.held_frames(InputFrame.ATTACK)
	if held <= 1:
		# Up, or pressed this frame: whatever broke the last hold is over.
		pl.charge_broken = false
	var counted: int = 0 if pl.charge_broken else held
	if charged != null and held == 0 and pl.charge_held >= charged.charge_frames:
		pl.charge_request = pl.p.attack_buffer_frames + 1
		pl.charge_stick = Vector2i(ring.stick_x(), ring.stick_y())
		pl.events.add(SimEvents.CHARGE_RELEASE, pl.body.x, pl.body.y)
	elif charged != null and counted == charged.charge_frames:
		pl.events.add(SimEvents.CHARGE_READY, pl.body.x, pl.body.y)
	pl.charge_held = counted


## The attack hold under way can no longer arm the Charged strike (its press started an up- or
## down-strike, or a death or a send-back broke it): the strike needs a fresh press, held anew.
static func break_charge(pl: Player) -> void:
	pl.charge_broken = true
	pl.charge_held = 0
	pl.charge_request = 0


## An enemy's attack lands on the player (docs/adr/0013, The player hit): hearts and a Kindling
## tier lost, whatever was under way ended, hitstop on the player, a knockback [param away] from
## the attacker and invulnerability. [param at] is where the hit landed, for the event. A strike in
## its armored frames ([method armored]: side 3's and the Charged strike's startup) is not
## ended and the player is not knocked back: the hit costs its hearts, Kindling and hitstop, and
## the strike carries on after the hitstop (movement review 6, H2).
static func hurt(pl: Player, ring: InputRing, away: int, damage: int, at: Vector2i) -> void:
	var c: CombatParams = pl.combat
	pl.events.add(SimEvents.PLAYER_HIT, at.x, at.y, HitKind.encode(HitKind.PLAYER, away, 0))
	pl.vitals.hearts.lose(damage)
	pl.vitals.kindling.drop_tier()
	if pl.vitals.hearts.is_dead():
		die(pl, ring)
		return
	pl.freeze = maxi(pl.freeze, c.hitstop_player_hit)
	# Counted in the player's own frames from the first free frame after the hitstop. This tick's
	# hits are already resolved, and the count drops at the start of each free tick, so the frame
	# the hit landed on adds one: 20 covers frames 1 to 20 after the hitstop, not 1 to 19 (task 6
	# core review 2, H3).
	pl.invuln = maxi(pl.invuln, c.player_hit_invuln_frames + 1)
	if armored(pl):
		return
	pl.interrupt()
	pl.knock_left = c.player_hit_knock_frames
	pl.knock_vx = away * c.player_hit_knockback
	pl.body.vx = pl.knock_vx


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
	PlayerContacts.send_back(pl, ring, pl.home_x, pl.home_y)


## True while the strike under way has armor: a hit on its first [member AttackDef.armor_frames]
## frames does not interrupt it (BUILD.md section 5, "No move has more than 2 frames of startup
## unless it has armor"; docs/adr/0010, Side 3's startup).
static func armored(pl: Player) -> bool:
	var atk: AttackDef = pl.current_attack()
	return atk != null and pl.action_frame <= atk.armor_frames


## A strike's recoil ([member Player.recoil_vx] a tick for [member CombatParams.recoil_frames]
## ticks after the hit's hitstop) moves the body on top of whatever the move did, so the run's
## acceleration never erases it (task 6 core review 2, H2: as a speed it was gone on the first free
## tick). A dash, or a cling, ends it.
static func recoil_move(pl: Player) -> void:
	if pl.recoil_left <= 0:
		return
	if pl.loco == Player.DASH or pl.loco == Player.WALL:
		pl.recoil_left = 0
		return
	pl.recoil_left -= 1
	if pl.loco == Player.GROUND:
		pl.world.walk(pl.body, pl.recoil_vx, pl.p.corner_lift)
		if not pl.body.on_ground:
			pl.loco = Player.AIR
			pl.left_by_jump = false
			pl.air_frames = 0
		return
	pl.world.move_x(pl.body, pl.recoil_vx, pl.p.corner_lift, pl.p.corner_slide)
