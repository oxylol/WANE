class_name PlayerStrikes
extends RefCounted
## The player's strikes (BUILD.md section 6, the Taper; docs/adr/0010): which strike a press
## starts, the chain, the cancels out of a dash and into another strike, and the strike and pogo
## boxes. Static helpers on a [Player], kept apart from the state machine so it stays readable; the
## state they change is the player's.


## Starts the strike a buffered attack press asks for, if the current state lets it: up with the
## stick up, the down-strike with it down in the air, else the next side strike of the chain. The
## stick is read 4-way ([method PlayerInput.dir4]) on the frame the press was made. A press a dash
## took over when it cancelled a strike ([member Player.queued_attack_left]) counts as buffered
## while the dash and its carry-over last, and for the attack buffer after the dash ends; a press
## made since replaces it (the buffer keeps the latest press). [param landed] is a landing this
## tick whose step walked on off the far edge (see [code]Player._land_in_stride[/code]).
static func try_attack(pl: Player, ring: InputRing, landed: bool = false) -> void:
	var p: MovementParams = pl.p
	if PlayerSpells.holds(pl):
		return
	if pl.charge_request > 0 and _try_charged(pl, ring):
		return
	var fresh: bool = ring.has_press(InputFrame.ATTACK, p.attack_buffer_frames)
	if fresh:
		# The latest press wins (BUILD.md s5: the buffer "always stores the latest input"; movement
		# review 5, M3).
		pl.queued_attack_left = 0
	var queued: bool = pl.queued_attack_left > 0
	if not queued and not fresh:
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
		var landed_swap: bool = atk.air_only and (pl.loco == Player.GROUND or landed)
		if not chained and not air_swap and not landed_swap:
			return
	if want == "down" and pl.since_bounce < p.pogo_chain_frame:
		return
	if pl.loco == Player.DASH:
		if pl.dash_frame < p.dash_attack_cancel_from:
			return
		pl.end_dash(true)
	if queued:
		pl.queued_attack_left = 0
	else:
		ring.consume(InputFrame.ATTACK)
	# A side strike turns the player to the stick, except on a wall: the stick holds toward the
	# wall to keep the cling, and the strike goes away from it (the way the player faces). On the
	# tick the player reaches a wall the strike goes away from it too ([method PlayerWall.met]).
	var thr: int = p.stick_threshold
	var wall: int = PlayerWall.met(
		pl, ring, PlayerInput.axis(ring.stick_x(), thr), PlayerInput.axis(ring.stick_y(), thr)
	)
	if want.begins_with("side"):
		if wall != 0:
			pl.facing = -wall
		elif dx != 0 and pl.loco != Player.WALL:
			pl.facing = dx
	start(pl, want)
	# Only a side press's hold arms the Charged strike: a hold whose press started an up- or
	# down-strike never does (docs/adr/0013; movement review 6, H1: holding attack through a pogo
	# and letting go fired a sideways Charged strike in the air that refused the next pogo).
	if (want == "up" or want == "down") and ring.is_held(InputFrame.ATTACK):
		PlayerCombat.break_charge(pl)


## The Charged strike a release asked for ([member Player.charge_request]; docs/adr/0013): as soon
## as no strike runs, and out of a dash from the frame a strike may cancel it. It goes the way the
## stick leans, else the way the player faces; on a wall, or on the tick the player reaches one,
## away from it, as a side strike does (docs/adr/0010, Wall; movement review 6, M3). True if it
## started.
static func _try_charged(pl: Player, ring: InputRing) -> bool:
	if pl.current_attack() != null:
		return false
	if pl.loco == Player.DASH:
		if pl.dash_frame < pl.p.dash_attack_cancel_from:
			return false
		pl.end_dash(true)
	# The way the stick held when the hold was let go, however long the request waited.
	var thr: int = pl.p.stick_threshold
	var dx: int = PlayerInput.axis(pl.charge_stick.x, thr)
	var wall: int = PlayerWall.met(
		pl, ring, PlayerInput.axis(ring.stick_x(), thr), PlayerInput.axis(ring.stick_y(), thr)
	)
	if wall != 0:
		pl.facing = -wall
	elif dx != 0 and pl.loco != Player.WALL:
		pl.facing = dx
	pl.charge_request = 0
	start(pl, "charged")
	return true


## Starts the strike [param attack_id] on this frame.
static func start(pl: Player, attack_id: String) -> void:
	pl.strike_serial += 1
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
