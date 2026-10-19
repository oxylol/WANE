class_name PlayerSpells
extends RefCounted
## Ash's spells and Mend (BUILD.md section 6, Spells and Flame; docs/adr/0013). A spell runs in
## its own layer beside locomotion, as a strike does: the player keeps moving, and no strike or
## other spell starts while one runs. Static helpers on a [Player], kept apart from the state
## machine so it stays readable; the state they change is the player's.
##
## - Kindle: a spell press with the Flame. A cone in the stick's direction (up, down in the air, or
##   forward), live on its active frames; from [member KitParams.kindle_cancel_from] any action
##   ends it.
## - Radiance: a spell press with the stick down, on the ground, at Kindling Blaze or above. Its
##   burst comes on the frame after its startup; from the burst any action ends it.
## - Mend: a Mend press on the ground with a heart missing. The Flame is paid at once and the
##   player stands still for [member KitParams.mend_frames], then heals. Letting go, any action
##   (a spell too) or a hit ends it, and the Flame is lost. Still held at the end, it starts again
##   if it can.

enum { NONE, KINDLE, RADIANCE, MEND }

const NAMES: Array[String] = ["none", "kindle", "radiance", "mend"]
## The events that mean the player took an action this tick: they end a spell that allows them
## (and the knockback after a hit: [PlayerCombat]).
const ACTION_EVENTS: Array[String] = [
	SimEvents.DASH,
	SimEvents.JUMP,
	SimEvents.AIR_JUMP,
	SimEvents.WALL_JUMP,
	SimEvents.WALL_KICK,
	SimEvents.ATTACK,
	SimEvents.TOSS,
	SimEvents.TELEPORT,
	SimEvents.DROP_THROUGH,
]


## True while a spell runs that other actions must wait for: Kindle before its cancel frame,
## Radiance before its burst. Mend never holds an action back: the action ends it. An action on
## Radiance's burst frame ends the spell, and the burst still comes ([member Player.radiance_burst]:
## task 6 review, H3, where it was lost and the Flame spent for nothing).
static func holds(pl: Player) -> bool:
	var k: KitParams = pl.kit
	match pl.spell:
		KINDLE:
			return pl.spell_frame < k.kindle_cancel_from
		RADIANCE:
			return pl.spell_frame <= k.radiance_startup
	return false


## Counts the spell under way by a tick: it ends after its last frame; Mend heals on its last
## channel frame and, still held, starts again on the next.
static func advance(pl: Player, ring: InputRing) -> void:
	if pl.spell == NONE:
		return
	pl.spell_frame += 1
	var k: KitParams = pl.kit
	match pl.spell:
		KINDLE:
			if pl.spell_frame > k.kindle_startup + k.kindle_active + k.kindle_recovery:
				stop(pl)
		RADIANCE:
			if pl.spell_frame == k.radiance_startup + 1:
				pl.radiance_burst = true
			elif pl.spell_frame > k.radiance_startup + 1 + k.radiance_recovery:
				stop(pl)
		MEND:
			_channel(pl, ring)


static func _channel(pl: Player, ring: InputRing) -> void:
	var k: KitParams = pl.kit
	if not ring.is_held(InputFrame.MEND) or pl.loco != Player.GROUND:
		stop(pl)
		return
	if pl.spell_frame == k.mend_frames:
		pl.vitals.hearts.heal(k.mend_hearts)
		pl.events.add(SimEvents.HEAL, pl.body.x, pl.body.y, pl.vitals.hearts.current)
	elif pl.spell_frame > k.mend_frames:
		if _can_mend(pl):
			_start_mend(pl)
		else:
			stop(pl)


## Ends the spell under way (a Mend's Flame is not given back).
static func stop(pl: Player) -> void:
	pl.spell = NONE
	pl.spell_frame = 0
	pl.spell_dir = Vector2i.ZERO


## Ends a spell that allows the action the player took this tick (see [constant ACTION_EVENTS]).
static func yield_to_actions(pl: Player) -> void:
	if pl.spell == NONE or holds(pl):
		return
	for kind: String in ACTION_EVENTS:
		if pl.events.has(kind):
			stop(pl)
			return


## Starts a buffered spell press, or a Mend press, if the state allows it. A spell waits (in its
## 8 f buffer) for a strike or another spell to end; it ends Mend (the Flame paid for Mend is lost:
## task 6 review, M2) and cancels a dash from the frame a strike may (dash frame 6), unless it
## fizzles: a spell with too little Flame leaves the dash alone (M6).
static func try_start(pl: Player, ring: InputRing) -> void:
	var p: MovementParams = pl.p
	if ring.has_press(InputFrame.SPELL, p.attack_buffer_frames) and not _layer_busy(pl):
		var f: InputFrame = ring.frame_at(ring.press_age(InputFrame.SPELL, p.attack_buffer_frames))
		ring.consume(InputFrame.SPELL)
		var stick: Vector2i = PlayerInput.dir4(f.stick_x, f.stick_y, p.stick_threshold)
		if not _affordable(pl, stick):
			pl.events.add(SimEvents.FIZZLE, pl.body.x, pl.body.y)
			return
		if pl.spell == MEND:
			stop(pl)
		if pl.loco == Player.DASH:
			pl.end_dash(true)
		_cast(pl, stick)
		return
	if pl.spell != NONE or pl.current_attack() != null:
		return
	if ring.has_press(InputFrame.MEND, p.attack_buffer_frames) and ring.is_held(InputFrame.MEND):
		if _can_mend(pl):
			ring.consume(InputFrame.MEND)
			_start_mend(pl)


## True while a spell press must wait in its buffer: a strike or a spell other than Mend runs, or
## a dash that a strike could not cancel yet.
static func _layer_busy(pl: Player) -> bool:
	if pl.current_attack() != null or (pl.spell != NONE and pl.spell != MEND):
		return true
	return pl.loco == Player.DASH and pl.dash_frame < pl.p.dash_attack_cancel_from


## True if a spell pressed with [param stick] can be paid for: Radiance's or Kindle's Flame.
static func _affordable(pl: Player, stick: Vector2i) -> bool:
	var k: KitParams = pl.kit
	var flame: int = pl.vitals.flame.value
	if _radiance_asked(pl, stick) and flame >= k.radiance_cost:
		return true
	return flame >= k.kindle_cost


## A spell with the stick down on the ground (a dash along it included) at Kindling Blaze or above
## asks for Radiance.
static func _radiance_asked(pl: Player, stick: Vector2i) -> bool:
	var grounded: bool = pl.loco == Player.GROUND or (pl.loco == Player.DASH and pl.body.on_ground)
	return stick.y > 0 and grounded and pl.vitals.kindling.tier() >= Kindling.BLAZE


static func _cast(pl: Player, stick: Vector2i) -> void:
	var k: KitParams = pl.kit
	var v: Vitals = pl.vitals
	var grounded: bool = pl.loco == Player.GROUND
	if _radiance_asked(pl, stick):
		if v.flame.spend(k.radiance_cost):
			_begin(pl, RADIANCE, Vector2i.ZERO)
			return
	if not v.flame.spend(k.kindle_cost):
		pl.events.add(SimEvents.FIZZLE, pl.body.x, pl.body.y)
		return
	var dir := Vector2i(0, stick.y)
	if stick.y == 0 or (stick.y > 0 and grounded):
		# Forward: the stick's side if it leans one way, else the way the player faces. Down on
		# the ground is the floor.
		if stick.x != 0 and pl.loco != Player.WALL:
			pl.facing = stick.x
		dir = Vector2i(pl.facing, 0)
	_begin(pl, KINDLE, dir)


## Starts [param kind]. Like any action it ends the knockback after a hit, Mend included (task 6
## review, M1: Mend channelled while the knockback slid Ash 64 u).
static func _begin(pl: Player, kind: int, dir: Vector2i) -> void:
	pl.spell = kind
	pl.spell_frame = 1
	pl.spell_dir = dir
	pl.knock_left = 0
	pl.strike_serial += 1
	pl.events.add(SimEvents.CAST, pl.body.x, pl.body.y, kind)


static func _can_mend(pl: Player) -> bool:
	var h: Hearts = pl.vitals.hearts
	return (
		pl.loco == Player.GROUND
		and h.current < h.max_hearts
		and pl.vitals.flame.value >= pl.kit.mend_cost
	)


## Mend is channelled standing still: it stops the player where it starts (task 6 review, M1: a
## knockback's last speed slid Ash on into the channel).
static func _start_mend(pl: Player) -> void:
	pl.vitals.flame.spend(pl.kit.mend_cost)
	pl.body.vx = 0
	_begin(pl, MEND, Vector2i.ZERO)


## Kindle's cone on its active frames: [member KitParams.kindle_sections] rectangles end to end
## from the player's centre along [member Player.spell_dir], each wider than the last (CLAUDE.md
## rule 8: hitboxes are rectangles). Empty otherwise.
static func kindle_boxes(pl: Player) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var k: KitParams = pl.kit
	if pl.spell != KINDLE:
		return out
	if pl.spell_frame <= k.kindle_startup or pl.spell_frame > k.kindle_startup + k.kindle_active:
		return out
	var b: Body = pl.body
	var c := Vector2i(b.x, b.y - b.height / 2)
	var n: int = k.kindle_sections
	var d: Vector2i = pl.spell_dir
	for i: int in range(n):
		var near: int = k.kindle_length * i / n
		var far: int = k.kindle_length * (i + 1) / n
		var w: int = k.kindle_width_near
		if n > 1:
			w += (k.kindle_width_far - k.kindle_width_near) * i / (n - 1)
		var along_lo: int = mini(d.x * near + d.y * near, d.x * far + d.y * far)
		var along_hi: int = maxi(d.x * near + d.y * near, d.x * far + d.y * far)
		if d.x != 0:
			out.append(Rect2i(c.x + along_lo, c.y - w / 2, along_hi - along_lo, w))
		else:
			out.append(Rect2i(c.x - w / 2, c.y + along_lo, w, along_hi - along_lo))
	return out


## True on the tick Radiance bursts (the frame after its startup), whatever ended the spell since
## on that tick; combat clears it as it bursts.
static func radiance_bursts(pl: Player) -> bool:
	return pl.radiance_burst
