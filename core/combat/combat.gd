class_name Combat
extends RefCounted
## Combat resolution (BUILD.md section 6; docs/adr/0013), once per tick after the player and every
## enemy have moved, so boxes are compared where both ended the tick:
##
## 1. Effects age: kill embers fly (and grant Flame on arrival), Blaze trails burn out, burning
##    enemies take their burn damage.
## 2. The player's hits: the strike box, Kindle's cone and Radiance's burst, the pogo box, then
##    the Blaze trails. A strike or cast hits each enemy once.
## 3. The procs: every proc event raised by 1 and 2 (a Taper hit, a pogo, a Kindle tick, Radiance
##    reaching an enemy) is rolled and its procs fired, chains included ([ProcBus];
##    docs/adr/0015).
## 4. The enemies' hits: an attack's live box touching the hurtbox of a player who is not
##    invulnerable lands once; it is parried if the player pressed attack in the 8 frames up to it.
##
## The player's hits and their procs come first, so a strike or proc that kills, staggers or stuns
## an enemy on the tick its attack would land takes that attack away. Hitstop is set on whoever a
## hit froze and counts from the next tick; the player's input keeps being read meanwhile
## ([InputRing]).

## From this many enemies a Blaze trail asks the query cells which enemies could be in it, rather
## than testing every enemy (building the cells costs more than a few enemies' tests).
const CELL_QUERY_MIN: int = 24

var params: CombatParams
var events: SimEvents
## The run's Votives and the proc event bus (docs/adr/0015).
var procs: ProcBus
var enemies: Array[Enemy] = []
var embers: Array[KillEmber] = []
var trails: Array[FireTrail] = []
## Ticks left of Radiance's full light (presentation lights the room; later systems read it).
var light_left: int = 0

## Where the enemies stand, for the procs' radius and nearest-enemy questions ([EnemyCells]): built
## at the first question of a tick's resolve and kept until the resolve ends; outside a resolve
## every question builds it afresh.
var _cells: EnemyCells = EnemyCells.new()
var _indexed: bool = false


func _init(p_params: CombatParams, p_events: SimEvents, p_procs: ProcBus) -> void:
	params = p_params
	events = p_events
	procs = p_procs


## One tick of combat, after everything has moved. [param pl] may be null (no player).
## The player leaves the room through a door (docs/adr/0014): its enemies, trails and light stay
## behind; a kill ember still in flight reaches the player as they go, with its Flame.
func leave_room(pl: Player) -> void:
	var at: Vector2i = _centre(pl.body)
	for _i: int in range(embers.size()):
		pl.vitals.flame.gain(params.flame_per_kill)
		events.add(SimEvents.EMBER_HOME, at.x, at.y)
	embers.clear()
	trails.clear()
	enemies.clear()
	light_left = 0


func resolve(pl: Player, ring: InputRing) -> void:
	_indexed = false
	_age_effects(pl)
	if pl == null:
		return
	var stop: int = 0
	stop = maxi(stop, _strike(pl))
	stop = maxi(stop, _kindle(pl))
	_radiance(pl)
	stop = maxi(stop, _pogo(pl, ring))
	_trails(pl)
	procs.resolve(self, pl)
	_indexed = false
	if stop > 0:
		pl.freeze = maxi(pl.freeze, stop)
	_enemy_attacks(pl, ring)


# --- effects ---------------------------------------------------------------------------------


func _age_effects(pl: Player) -> void:
	light_left = maxi(light_left - 1, 0)
	var i: int = 0
	while i < embers.size():
		var ember: KillEmber = embers[i]
		var target: Vector2i = ember.at if pl == null else _centre(pl.body)
		if ember.fly(target):
			if pl != null:
				pl.vitals.flame.gain(params.flame_per_kill)
			events.add(SimEvents.EMBER_HOME, target.x, target.y)
			embers.remove_at(i)
		else:
			i += 1
	i = 0
	while i < trails.size():
		trails[i].left -= 1
		if trails[i].left <= 0:
			trails.remove_at(i)
		else:
			i += 1
	if pl == null:
		return
	for k: int in range(enemies.size()):
		var e: Enemy = enemies[k]
		if e.burn_tick(pl.kit.burn_period):
			# A burn tick is one of Kindle's ticks: a proc event (BUILD.md section 6, "Kindle 0.5
			# per tick"; docs/adr/0015).
			var tier: int = pl.vitals.kindling.tier()
			var dealt: int = _damage(pl, k, pl.kit.burn_damage, HitKind.BURN, Vector2i.ZERO)
			var c: Vector2i = e.centre()
			procs.raise(ProcSource.KINDLE, k, c.x, c.y, dealt, tier)


# --- the player's hits -----------------------------------------------------------------------


## The strike box against every enemy; returns the player's hitstop from it.
func _strike(pl: Player) -> int:
	# With no enemy in the room the box matters only for a Blaze strike's trail.
	if enemies.is_empty() and pl.vitals.kindling.tier() < Kindling.BLAZE:
		return 0
	var box: Rect2i = pl.strike_box()
	if box.size == Vector2i.ZERO:
		return 0
	var atk: AttackDef = pl.current_attack()
	if pl.vitals.kindling.tier() >= Kindling.BLAZE:
		trails.append(FireTrail.new(box, params.blaze_trail_frames, pl.strike_serial))
	var stop: int = 0
	for i: int in range(enemies.size()):
		var e: Enemy = enemies[i]
		if not e.is_alive() or e.last_strike == pl.strike_serial:
			continue
		if not box.intersects(e.hurtbox()):
			continue
		if e.def.pogoable and pl.pogo_box().size != Vector2i.ZERO:
			# The down-strike's box is its pogo box on these frames: a pogo-able enemy is
			# bounced off and hit by the pogo ([method _pogo]), not struck as well.
			continue
		e.last_strike = pl.strike_serial
		stop = maxi(stop, _strike_hit(pl, i, atk))
	return stop


## A strike landing on enemy [param i]: its damage, knockback and Flame; the finisher's launch
## and Blaze AoE; the side 1 recoil; White's automatic Charged strike.
func _strike_hit(pl: Player, i: int, atk: AttackDef) -> int:
	var e: Enemy = enemies[i]
	var kind: int = HitKind.LIGHT
	if atk.id == "charged":
		kind = HitKind.CHARGED
	elif atk.launches:
		kind = HitKind.FINISHER
	var dir := Vector2i(pl.action_dir, 0)
	if atk.id == "up":
		dir = Vector2i(0, -1)
	var damage: int = atk.damage
	var knock: int = Fx.speed(atk.knockback_ups)
	if _white_charges(pl):
		var charged: AttackDef = pl.charged_attack
		kind = HitKind.CHARGED
		damage = charged.damage
		knock = Fx.speed(charged.knockback_ups)
	var vx: int = dir.x * knock
	var vy: int = 0
	if atk.id == "up":
		vy = -knock
	elif kind == HitKind.FINISHER:
		vy = -params.finisher_launch
	var bonus: int = procs.blade_bonus(ProcSource.TAPER, i)
	var stop: int = _land(pl, i, damage, kind, dir, vx, vy, bonus)
	pl.vitals.flame.gain(params.flame_per_hit)
	if atk.recoil_ups > 0 and dir.x != 0:
		# A displacement over recoil_frames ticks after the hitstop, on top of the run
		# ([code]Player._recoil_move[/code]; task 6 core review 2, H2).
		pl.recoil_vx = -dir.x * Fx.speed(atk.recoil_ups)
		pl.recoil_left = params.recoil_frames
	if kind == HitKind.FINISHER and pl.vitals.kindling.tier() >= Kindling.BLAZE:
		_blaze_burst(pl, i, e.centre())
	return stop


## White: every [member CombatParams.white_charged_every]-th hit is a Charged strike.
func _white_charges(pl: Player) -> bool:
	if pl.vitals.kindling.tier() < Kindling.WHITE:
		pl.white_hits = 0
		return false
	pl.white_hits += 1
	return pl.white_hits % params.white_charged_every == 0


## Kindle's cone on its active frames; returns the player's hitstop.
func _kindle(pl: Player) -> int:
	if enemies.is_empty():
		return 0
	var boxes: Array[Rect2i] = PlayerSpells.kindle_boxes(pl)
	if boxes.is_empty():
		return 0
	var stop: int = 0
	for i: int in range(enemies.size()):
		var e: Enemy = enemies[i]
		# A dead enemy has no hurtbox, and an empty rect at the origin "intersects" any box over it
		# (task 6 review, M7): the dead are skipped in every hit loop.
		if not e.is_alive() or e.last_strike == pl.strike_serial:
			continue
		var hurt: Rect2i = e.hurtbox()
		for box: Rect2i in boxes:
			if box.intersects(hurt):
				e.last_strike = pl.strike_serial
				stop = maxi(
					stop, _land(pl, i, pl.kit.kindle_damage, HitKind.SPELL, pl.spell_dir, 0, 0)
				)
				if enemies[i].is_alive():
					enemies[i].ignite(pl.kit.burn_frames, pl.kit.burn_period)
				break
	return stop


## Radiance's burst, on the tick after its startup: every enemy pushed away, the room lit.
func _radiance(pl: Player) -> void:
	if not PlayerSpells.radiance_bursts(pl):
		return
	pl.radiance_burst = false
	light_left = pl.kit.radiance_light
	var c: Vector2i = _centre(pl.body)
	events.add(SimEvents.RADIANCE, c.x, c.y)
	var tier: int = pl.vitals.kindling.tier()
	for k: int in range(enemies.size()):
		var e: Enemy = enemies[k]
		if not e.is_alive():
			continue
		var away: int = signi(e.body.x - pl.body.x)
		if away == 0:
			away = pl.facing
		e.knock_vx = away * pl.kit.radiance_push
		# Radiance reaching an enemy is a proc event (docs/adr/0015), though it deals no damage.
		var at: Vector2i = e.centre()
		procs.raise(ProcSource.RADIANCE, k, at.x, at.y, 0, tier)


## The pogo box against pogo-able enemies: a bounce off the first one touched, and a hit on it.
func _pogo(pl: Player, ring: InputRing) -> int:
	if enemies.is_empty():
		return 0
	var box: Rect2i = pl.pogo_box()
	if box.size == Vector2i.ZERO:
		return 0
	for i: int in range(enemies.size()):
		var e: Enemy = enemies[i]
		if not e.is_alive() or not e.def.pogoable or e.last_strike == pl.strike_serial:
			continue
		if not box.intersects(e.hurtbox()):
			continue
		e.last_strike = pl.strike_serial
		PlayerContacts.bounce(pl, ring, box)
		var bonus: int = procs.blade_bonus(ProcSource.POGO, i)
		var stop: int = _land(
			pl, i, pl.down_attack.damage, HitKind.POGO, Vector2i.DOWN, 0, 0, bonus
		)
		pl.vitals.flame.gain(params.flame_per_pogo)
		return stop
	return 0


## The Blaze trails: each strike's trails burn each enemy once, however the trails of a chain
## overlap (task 6 review, H2: two strikes' trails took turns and burned every tick). An enemy
## remembers the strikes that burned it until their trails have all gone out.
func _trails(pl: Player) -> void:
	# With many enemies each trail asks the query cells which could be in it, in the room's order
	# (the cells stay good for the procs after: nothing moves an enemy before they resolve).
	var by_cells: bool = not trails.is_empty() and enemies.size() >= CELL_QUERY_MIN
	if by_cells and not _indexed:
		_cells.build(enemies)
		_indexed = true
	for t: FireTrail in trails:
		if by_cells:
			var near: PackedInt32Array = _cells.touching(t.box)
			near.sort()
			for i: int in near:
				_burn(pl, t, i)
		else:
			for i: int in range(enemies.size()):
				_burn(pl, t, i)
	for e: Enemy in enemies:
		var k: int = 0
		while k < e.trail_burned.size():
			if _trail_lives(e.trail_burned[k]):
				k += 1
			else:
				e.trail_burned.remove_at(k)


## Trail [param t] burns enemy [param i] if it is alive, not burned by that strike's trails yet,
## and in the fire.
func _burn(pl: Player, t: FireTrail, i: int) -> void:
	var e: Enemy = enemies[i]
	if not e.is_alive() or e.trail_burned.has(t.serial):
		return
	if not t.box.intersects(e.hurtbox()):
		return
	e.trail_burned.append(t.serial)
	_damage(pl, i, params.blaze_trail_damage, HitKind.BURN, Vector2i.ZERO)


func _trail_lives(serial: int) -> bool:
	for t: FireTrail in trails:
		if t.serial == serial:
			return true
	return false


## A finisher at Blaze: every other enemy near the one hit takes the AoE's damage.
func _blaze_burst(pl: Player, hit: int, at: Vector2i) -> void:
	var r: int = params.blaze_aoe_radius
	for i: int in range(enemies.size()):
		if i == hit or not enemies[i].is_alive():
			continue
		var d: Vector2i = enemies[i].centre() - at
		if d.x * d.x + d.y * d.y <= r * r:
			_damage(pl, i, params.blaze_aoe_damage, HitKind.BURN, Vector2i.ZERO)


## A hit that counts: damage with Kindling's bonus, knockback, a Kindling hit, hitstop on the
## enemy, the kill, and its proc event. [param bonus] is the damage Votives add to a Taper or pogo
## hit: it is dealt, but the hit's hitstop is weighed without it, so items change what a hit does,
## never how it feels (BUILD.md section 1, pillar 2; docs/adr/0015). Returns the hitstop the player
## takes from it.
func _land(
	pl: Player,
	i: int,
	damage: int,
	kind: int,
	dir: Vector2i,
	vx: int = 0,
	vy: int = 0,
	bonus: int = 0
) -> int:
	var e: Enemy = enemies[i]
	var tier: int = pl.vitals.kindling.tier()
	var dealt: int = pl.vitals.kindling.boost(damage + bonus)
	var weight: int = pl.vitals.kindling.boost(damage)
	var killed: bool = e.take_hit(dealt, vx, vy)
	pl.vitals.kindling.add()
	var stop: int = params.hitstop_for(_base_hitstop(kind), weight)
	var c: Vector2i = e.centre()
	var value: int = HitKind.encode(kind, dir.x, dir.y, tier)
	events.add(SimEvents.HIT, c.x, c.y, value)
	procs.raise(_proc_source(kind), i, c.x, c.y, dealt, tier)
	if killed:
		stop = maxi(stop, params.hitstop_kill)
		_kill(i, value)
	elif e.state == Enemy.STAGGER and e.state_frame == 0:
		events.add(SimEvents.STAGGER, c.x, c.y, i)
	e.freeze = stop
	return stop


## Damage that is not a hit (burns, trails, the AoE, a Votive's proc): no knockback (a strike's
## knockback is kept: task 6 review, H1), no hitstop, no Kindling, no Flame. A kill by it still has
## the Kill row's hitstop on both (BUILD.md section 6, "Kill | 3 f": task 6 review, presentation
## M1). Returns the damage dealt, or -1 if the enemy was already dead.
func _damage(pl: Player, i: int, damage: int, kind: int, dir: Vector2i) -> int:
	var e: Enemy = enemies[i]
	if not e.is_alive():
		return -1
	var c: Vector2i = e.centre()
	var value: int = HitKind.encode(kind, dir.x, dir.y, pl.vitals.kindling.tier())
	var dealt: int = pl.vitals.kindling.boost(damage)
	var killed: bool = e.take_damage(dealt)
	events.add(SimEvents.HIT, c.x, c.y, value)
	if killed:
		e.freeze = maxi(e.freeze, params.hitstop_kill)
		pl.freeze = maxi(pl.freeze, params.hitstop_kill)
		_kill(i, value)
	return dealt


## The proc event a hit of [param kind] raises ([ProcSource]): Kindle's cone is its first tick, a
## pogo is a pogo, every other hit a Taper hit.
static func _proc_source(kind: int) -> int:
	match kind:
		HitKind.SPELL:
			return ProcSource.KINDLE
		HitKind.POGO:
			return ProcSource.POGO
	return ProcSource.TAPER


# --- what procs do (docs/adr/0015) -----------------------------------------------------------


## A Votive's proc hit on enemy [param i] for [param damage]: proc damage, which is not a Taper hit
## ([method _damage]: health and poise with Kindling's bonus, a kill's ember and the Kill row's
## hitstop; no knockback, no hitstop of its own, no Kindling hit, no Flame), shown as a hit of kind
## [constant HitKind.PROC]. Returns the damage dealt, or -1 if there is no such living enemy.
func proc_hit(pl: Player, i: int, damage: int) -> int:
	if pl == null or i < 0 or i >= enemies.size():
		return -1
	return _damage(pl, i, damage, HitKind.PROC, Vector2i.ZERO)


## Stuns every living enemy whose centre is within [param radius] sub-pixels of [param at] for
## [param frames] ticks ([method Enemy.stun]), in the room's order; returns how many.
func stun_within(at: Vector2i, radius: int, frames: int) -> int:
	var found: PackedInt32Array = _query(at, radius, -1)
	found.sort()
	var centres: PackedInt32Array = _cells.centres
	for k: int in found:
		enemies[k].stun(frames)
		events.add(SimEvents.STUN, centres[2 * k], centres[2 * k + 1], k)
	return found.size()


## The living enemy whose centre is nearest [param at], within [param radius] sub-pixels, other
## than [param skip]; ties go to the lower index. -1 if none.
func nearest_enemy(at: Vector2i, radius: int, skip: int) -> int:
	var best: int = -1
	var best_d: int = 0
	var centres: PackedInt32Array = _cells.centres
	for k: int in _query(at, radius, skip):
		var dx: int = centres[2 * k] - at.x
		var dy: int = centres[2 * k + 1] - at.y
		var dd: int = dx * dx + dy * dy
		if best < 0 or dd < best_d or (dd == best_d and k < best):
			best = k
			best_d = dd
	return best


## The living enemies other than [param skip] within [param radius] of [param at] ([EnemyCells]).
func _query(at: Vector2i, radius: int, skip: int) -> PackedInt32Array:
	if not _indexed:
		_cells.build(enemies)
		_indexed = procs.resolving()
	return _cells.within(enemies, at, radius, skip)


## Enemy [param i] died to a hit whose event value is [param value]: the kill event carries it, so
## presentation can tell a Charged kill (its slow motion) and shake along it.
func _kill(i: int, value: int) -> void:
	var c: Vector2i = enemies[i].centre()
	events.add(SimEvents.KILL, c.x, c.y, value)
	embers.append(KillEmber.new(c, params.kill_ember_frames))


func _base_hitstop(kind: int) -> int:
	match kind:
		HitKind.FINISHER:
			return params.hitstop_finisher
		HitKind.CHARGED:
			return params.hitstop_charged
	return params.hitstop_light


# --- the enemies' hits -----------------------------------------------------------------------


## Every swing landing this tick is parried by an attack press in the window, then the press is
## spent: one press parries every swing that lands on its tick, and nothing after (task 6 review,
## H4).
func _enemy_attacks(pl: Player, ring: InputRing) -> void:
	var parried: bool = false
	var press: bool = false
	var press_read: bool = false
	for i: int in range(enemies.size()):
		var e: Enemy = enemies[i]
		if e.attack_spent or pl.is_invulnerable():
			continue
		var box: Rect2i = e.attack_box()
		if box.size == Vector2i.ZERO or not box.intersects(pl.hurtbox()):
			continue
		e.attack_spent = true
		var away: int = signi(pl.body.x - e.body.x)
		if away == 0:
			away = -e.facing
		var at: Vector2i = box.intersection(pl.hurtbox()).get_center()
		# The press is read before any parry this tick spends it: every swing landing on this
		# tick sees the same answer.
		if not press_read:
			press = ring.any_press_age(InputFrame.ATTACK, _parry_age()) >= 0
			press_read = true
		if e.attack.parryable and press:
			_parry(pl, e, away, at)
			parried = true
		else:
			PlayerCombat.hurt(pl, ring, away, e.attack.damage, at)
	if parried:
		ring.spend_presses(InputFrame.ATTACK)


## The oldest press, in player frames, that still parries: the window's frames end on the tick
## the hit lands (age 0).
func _parry_age() -> int:
	return params.parry_window_frames - 1


## "0 damage, 12 f of hitstop on both, enemy knocked back 200 u/s and staggered for 40 f, player
## grants 33 Flame and +5 Kindling."
func _parry(pl: Player, e: Enemy, away: int, at: Vector2i) -> void:
	e.parried(-away)
	e.freeze = params.hitstop_parry
	pl.freeze = maxi(pl.freeze, params.hitstop_parry)
	pl.vitals.flame.gain(params.flame_per_parry)
	pl.vitals.kindling.add(params.kindling_per_parry)
	events.add(SimEvents.PARRY, at.x, at.y, HitKind.encode(HitKind.PARRY, -away, 0))


static func _centre(b: Body) -> Vector2i:
	return Vector2i(b.x, b.y - b.height / 2)


func hash_into(h: StateHasher) -> void:
	h.add_int(light_left)
	h.add_int(enemies.size())
	for e: Enemy in enemies:
		e.hash_into(h)
	h.add_int(embers.size())
	for ember: KillEmber in embers:
		ember.hash_into(h)
	h.add_int(trails.size())
	for t: FireTrail in trails:
		t.hash_into(h)
