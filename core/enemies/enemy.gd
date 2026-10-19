class_name Enemy
extends RefCounted
## A simulated enemy: a body in the collision world with health and poise, and the reactions
## every enemy shares (BUILD.md section 6, "Enemy-side rules"): knockback, a stagger when poise
## runs out ("at 0 the enemy staggers for 30 f and resets"), hitstop, and death. A kind adds its
## behaviour in [method _think] (choosing when to attack) and [method _while_dead].
##
## An attack runs telegraph, active, recovery ([EnemyAttack]); its hitbox is live on the active
## frames and the first of them is the tick the hit lands, which is what a parry is timed against.

enum { IDLE, TELEGRAPH, STRIKE, RECOVER, STAGGER, DEAD }

const STATE_NAMES: Array[String] = ["idle", "telegraph", "strike", "recover", "stagger", "dead"]

var def: EnemyDef
var params: CombatParams
var world: CollisionWorld
var events: SimEvents
var body: Body
var hp: int = 0
var poise: int = 0
## Health and poise when whole (from [member def] unless a room marker overrides them).
var max_hp: int = 0
var max_poise: int = 0
var facing: int = -1
var state: int = IDLE
## Ticks spent in [member state], counting this one.
var state_frame: int = 0
## The attack under way and its frame (1-based, telegraph first), while attacking.
var attack: EnemyAttack
var attack_frame: int = 0
## Hitstop ticks left: the enemy holds still.
var freeze: int = 0
## Ticks since a hit landed on it (presentation flashes and flinches from this).
var since_hit: int = 1000
## The serial of the last player strike or spell that hit it, so one strike hits once.
var last_strike: int = -1
## The serials of the strikes whose Blaze fire trails have burned it, while those trails live:
## each strike's trails burn it once, however the trails of a chain overlap (task 6 review, H2).
var trail_burned: PackedInt32Array = PackedInt32Array()
## The current attack's telegraph cue has been sent ([constant SimEvents.TELEGRAPH_CUE]): the
## attack is committed and lands on time, hitstop or not.
var cue_sent: bool = false
## Where its room marker put it: a respawn puts it back there.
var home_x: int = 0
var home_y: int = 0
## The current attack has touched the player (hit or parried): it lands once.
var attack_spent: bool = false
## Burning (Kindle "ignites"): ticks left, and ticks until the next burn damage.
var burn_left: int = 0
var burn_next: int = 0
var knock_vx: int = 0
## Launched by finishers and juggled by up-strikes (from [member EnemyDef.light]).
var light: bool = false
var _gravity: int = 0
var _terminal: int = 0
var _stagger_left: int = 0


func _init(
	p_def: EnemyDef,
	p_params: CombatParams,
	p_world: CollisionWorld,
	p_events: SimEvents,
	x: int,
	y: int
) -> void:
	def = p_def
	params = p_params
	world = p_world
	events = p_events
	body = Body.make(x, y, Fx.units(def.width_u) / 2, Fx.units(def.height_u))
	home_x = x
	home_y = y
	max_hp = def.hp
	max_poise = def.poise
	hp = max_hp
	poise = max_poise
	light = def.light
	_gravity = Fx.accel(def.gravity_ups2)
	_terminal = Fx.speed(def.terminal_ups)
	world.refresh_ground(body)


func is_alive() -> bool:
	return state != DEAD


func state_name() -> String:
	return STATE_NAMES[state]


## One tick. A corpse keeps moving: it carries its killing hit's momentum and falls (BUILD.md
## section 6, Kill: "Corpse carries momentum"; task 6 review, H5).
func step(player: Player) -> void:
	since_hit += 1
	if freeze > 0:
		freeze -= 1
		if committed():
			_advance_attack()
		return
	state_frame += 1
	match state:
		DEAD:
			_while_dead()
			if state == DEAD:
				_move()
			return
		STAGGER:
			_stagger_left -= 1
			if _stagger_left <= 0:
				_set_state(IDLE)
		TELEGRAPH, STRIKE, RECOVER:
			_advance_attack()
		IDLE:
			_think(player)
	_send_cue()
	_move()


## Starts [param a]: its telegraph begins this tick.
func start_attack(a: EnemyAttack) -> void:
	attack = a
	attack_frame = 1
	attack_spent = false
	cue_sent = false
	_set_state(TELEGRAPH)
	events.add(SimEvents.TELEGRAPH, body.x, body.y, 0 if a.parryable else 1)
	_send_cue()


## True once the current attack's cue has been sent and until its swing has landed: the attack
## runs on through hitstop, so the swing lands exactly as long after the cue as the cue promised.
func committed() -> bool:
	return attack != null and cue_sent and (state == TELEGRAPH or state == STRIKE)


## Ticks until the current attack's swing lands, counting the hitstop that will hold it back; -1
## when no telegraph runs.
func ticks_to_landing() -> int:
	if attack == null or state != TELEGRAPH:
		return -1
	var left: int = attack.landing_frame() - attack_frame
	return left if committed() else left + freeze


## Sends the telegraph's cue on the tick its swing lands in exactly
## [member CombatParams.telegraph_cue_frames] ticks (BUILD.md section 11: "every telegraph has a
## sound 20 f before the hit"; task 6 review, M4).
func _send_cue() -> void:
	if attack == null or cue_sent or state != TELEGRAPH:
		return
	if attack.landing_frame() - attack_frame != params.telegraph_cue_frames:
		return
	cue_sent = true
	events.add(SimEvents.TELEGRAPH_CUE, body.x, body.y, 0 if attack.parryable else 1)


## The live hitbox in world sub-pixels, or an empty rect.
func attack_box() -> Rect2i:
	if attack == null or not attack.is_active(attack_frame) or state == STAGGER:
		return Rect2i()
	var w: int = Fx.units(attack.box_w_u)
	var left: int = body.x + Fx.units(attack.box_x_u)
	if facing < 0:
		left = body.x - Fx.units(attack.box_x_u) - w
	return Rect2i(left, body.y + Fx.units(attack.box_y_u), w, Fx.units(attack.box_h_u))


## True on the tick the current attack's hit lands (its first active frame).
func lands_now() -> bool:
	return attack != null and state == STRIKE and attack_frame == attack.landing_frame()


## The hurtbox: the collider (enemies get no inset; the player's blade gets the benefit).
func hurtbox() -> Rect2i:
	if not is_alive():
		return Rect2i()
	return Rect2i(body.left(), body.top(), body.right() - body.left(), body.height)


## The centre of the collider, in sub-pixels.
func centre() -> Vector2i:
	return Vector2i(body.x, body.y - body.height / 2)


## Sets it burning for [param frames], the first burn damage [param period] ticks from now. A new
## ignite restarts the burn rather than stacking it.
func ignite(frames: int, period: int) -> void:
	burn_left = frames
	burn_next = period


## Counts the burn down by a tick; true on the ticks it deals its damage (every [param period]).
func burn_tick(period: int) -> bool:
	if burn_left <= 0 or not is_alive():
		return false
	burn_left -= 1
	burn_next -= 1
	if burn_next > 0:
		return false
	burn_next = period
	return true


## Takes [param damage] with knockback [param vx] (sub-pixels per tick along the hit); a
## light enemy also takes [param vy]. Poise drops by the damage; at zero it staggers and resets.
## Returns true if this hit killed it.
func take_hit(damage: int, vx: int, vy: int) -> bool:
	since_hit = 0
	knock_vx = vx
	if light and vy != 0:
		body.vy = vy
		body.on_ground = false
	return take_damage(damage)


## Takes [param damage] that is not a hit (a burn, a Blaze trail, a finisher's AoE): health and
## poise only, so a strike's knockback on the same tick is kept (task 6 review, H1). True if it
## killed it; the corpse keeps whatever momentum it had.
func take_damage(damage: int) -> bool:
	hp -= damage
	if hp <= 0:
		hp = 0
		attack = null
		cue_sent = false
		burn_left = 0
		_set_state(DEAD)
		return true
	poise -= damage
	if poise <= 0:
		stagger(params.poise_stagger_frames)
		poise = max_poise
	return false


## Parried: knocked back away from the player at [param dir] and staggered (BUILD.md: "enemy
## knocked back 200 u/s and staggered for 40 f").
func parried(dir: int) -> void:
	knock_vx = dir * params.parry_knockback
	stagger(params.parry_stagger_frames)


func stagger(frames: int) -> void:
	attack = null
	cue_sent = false
	_stagger_left = frames
	_set_state(STAGGER)


## Kind behaviour while idle: face, decide to attack. The base enemy just stands.
func _think(_player: Player) -> void:
	pass


## Kind behaviour while dead. The base enemy stays dead.
func _while_dead() -> void:
	pass


func _set_state(s: int) -> void:
	state = s
	state_frame = 0


func _advance_attack() -> void:
	attack_frame += 1
	if attack_frame > attack.total():
		attack = null
		_set_state(IDLE)
	elif attack_frame > attack.telegraph + attack.active:
		if state != RECOVER:
			_set_state(RECOVER)
	elif attack_frame > attack.telegraph and state != STRIKE:
		_set_state(STRIKE)


## Knockback bleeds off; gravity pulls it down onto the ground.
func _move() -> void:
	if knock_vx != 0:
		world.move_x(body, knock_vx)
		if body.hit_wall != 0:
			knock_vx = 0
		knock_vx = Fx.approach(knock_vx, 0, params.knockback_decel)
	if not body.on_ground or body.vy < 0:
		body.vy = mini(body.vy + _gravity, _terminal)
		world.move_y(body, body.vy)
		if body.on_ground:
			body.vy = 0
	else:
		world.refresh_ground(body)


func hash_into(h: StateHasher) -> void:
	h.add_int(body.x)
	h.add_int(body.y)
	h.add_int(body.vy)
	h.add_int(hp)
	h.add_int(poise)
	h.add_int(max_hp)
	h.add_int(max_poise)
	h.add_int(facing)
	h.add_int(state)
	h.add_int(state_frame)
	h.add_int(attack_frame)
	h.add_int(def.attacks.find(attack) if attack != null else -1)
	h.add_int(freeze)
	h.add_int(since_hit)
	h.add_int(last_strike)
	h.add_int(trail_burned.size())
	for serial: int in trail_burned:
		h.add_int(serial)
	h.add_int(1 if cue_sent else 0)
	h.add_int(home_x)
	h.add_int(home_y)
	h.add_int(1 if attack_spent else 0)
	h.add_int(burn_left)
	h.add_int(burn_next)
	h.add_int(knock_vx)
	h.add_int(_stagger_left)
	h.add_int(1 if light else 0)
