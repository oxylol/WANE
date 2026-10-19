class_name PlayerStrikes
extends RefCounted
## The player's strikes (BUILD.md section 6, the Taper; docs/adr/0010): which strike a press
## starts, the chain, the cancels out of a dash and into another strike, and the strike and pogo
## boxes. Static helpers on a [Player], kept apart from the state machine so it stays readable; the
## state they change is the player's.


## Starts the strike a buffered attack press asks for, if the current state lets it: up with the
## stick up, the down-strike with it down in the air, else the next side strike of the chain. The
## stick is read 4-way ([method PlayerInput.dir4]) on the frame the press was made. A press a dash
## took over when it cancelled a strike ([member Player.queued_attack]) counts as buffered for as
## long as the dash and its carry-over last.
static func try_attack(pl: Player, ring: InputRing) -> void:
	var p: MovementParams = pl.p
	if pl.queued_attack and pl.loco != Player.DASH and pl.carry_frames <= 0:
		# The dash that took the press over ended without allowing it (a jump out of it).
		pl.queued_attack = false
	var queued: bool = pl.queued_attack
	if not queued and not ring.has_press(InputFrame.ATTACK, p.attack_buffer_frames):
		return
	var stick: Vector2i = pl.queued_attack_stick
	if not queued:
		var f: InputFrame = ring.frame_at(ring.press_age(InputFrame.ATTACK, p.attack_buffer_frames))
		stick = Vector2i(f.stick_x, f.stick_y)
	var dy: int = PlayerInput.dir4(stick.x, stick.y, p.stick_threshold).y
	# A side strike turns to the stick's side wherever it leans, even down on the ground (a d-pad
	# diagonal reads as down there, and there is no down-strike on the ground).
	var dx: int = PlayerInput.dir8(stick.x, stick.y, p.stick_threshold).x
	var airborne: bool = pl.loco != Player.GROUND
	var want: String = pl.chain_next
	if dy < 0:
		want = "up"
	elif dy > 0 and airborne:
		want = "down"
	var atk: AttackDef = pl.current_attack()
	if atk != null:
		var chained: bool = (
			atk.chain_to != "" and want == atk.chain_to and pl.action_frame >= atk.chain_from
		)
		# "Air attack any frame": into another air strike, never into itself (movement review 4,
		# M6: up-strikes back to back were a new box every 3 frames).
		var air_swap: bool = atk.air_attack_any and airborne and want != atk.id
		# A down-strike that missed and reached the ground gives way to a ground strike, as it
		# gives way to the jump (docs/adr/0010).
		var landed_swap: bool = atk.air_only and pl.loco == Player.GROUND
		if not chained and not air_swap and not landed_swap:
			return
	if want == "down" and pl.since_bounce < p.pogo_chain_frame:
		return
	if pl.loco == Player.DASH:
		if pl.dash_frame < p.dash_attack_cancel_from:
			return
		pl.end_dash(true)
	if queued:
		pl.queued_attack = false
	else:
		ring.consume(InputFrame.ATTACK)
	# A side strike turns the player to the stick, except on a wall: the stick holds toward the
	# wall to keep the cling, and the strike goes away from it (the way the player faces). On the
	# tick the player reaches a wall the strike goes away from it too ([method PlayerWall.met]).
	var thr: int = p.stick_threshold
	var wall: int = PlayerWall.met(
		pl, PlayerInput.axis(ring.stick_x(), thr), PlayerInput.axis(ring.stick_y(), thr)
	)
	if want.begins_with("side"):
		if wall != 0:
			pl.facing = -wall
		elif dx != 0 and pl.loco != Player.WALL:
			pl.facing = dx
	start(pl, want)


## Starts the strike [param attack_id] on this frame.
static func start(pl: Player, attack_id: String) -> void:
	pl.action = pl.attacks.index_of(attack_id)
	pl.action_frame = 1
	pl.action_dir = pl.facing
	pl.action_pogoed = false
	pl.chain_timer = 0
	var atk: AttackDef = pl.current_attack()
	pl.chain_next = atk.chain_to if atk.chain_to != "" else "side1"
	if attack_id == "up" or attack_id == "down":
		pl.chain_next = "side1"
	pl.events.add(SimEvents.ATTACK, pl.body.x, pl.body.y, pl.action)


## The strike's hitbox in world sub-pixels as (left, top, right, bottom), or an empty rect.
static func strike_box(pl: Player) -> Rect2i:
	var atk: AttackDef = pl.current_attack()
	if atk == null or not atk.is_active(pl.action_frame):
		return Rect2i()
	return _box_for(pl, atk)


## The down-strike's pogo box, live on its pogo frames.
static func pogo_box(pl: Player) -> Rect2i:
	var atk: AttackDef = pl.current_attack()
	if atk == null or not atk.pogo_live(pl.action_frame) or pl.action_pogoed:
		return Rect2i()
	return _box_for(pl, atk)


static func _box_for(pl: Player, atk: AttackDef) -> Rect2i:
	var b: Body = pl.body
	var w: int = Fx.units(atk.box_w_u)
	var h: int = Fx.units(atk.box_h_u)
	var top: int = b.y + Fx.units(atk.box_y_u)
	var left: int = b.x + Fx.units(atk.box_x_u)
	if pl.action_dir < 0:
		left = b.x - Fx.units(atk.box_x_u) - w
	return Rect2i(left, top, w, h)
