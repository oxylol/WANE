class_name Player
extends RefCounted
## A Wick's state machine (BUILD.md section 5 for movement, section 6 for the strike frames;
## docs/adr/0010 for the rules BUILD.md leaves open). Stepped once per tick by the simulation
## with the player's input ring.
##
## Two layers run side by side: locomotion (ground, air, dash, wall) and an action (a strike).
## Strikes never stop movement; a dash cancels a strike from the strike's dash frame, and a strike
## cancels a dash from dash frame 6 into the dash's carry-over. Every timer counts frames, and a
## state's frame 1 is the tick it began, so "frame 3" is the third tick of that state.
##
## Order within a tick: count timers and advance the strike, then turn, crouch, take buffered
## toss, dash, jump and strike requests in that order, then move, then react to where the move
## left the body (landing with a buffered jump, wall-cling, ledge-grab, pogo, hazards). A buffered
## strike, dash or toss goes the way the stick pointed when it was pressed ([method press_dir]).

const GROUND: int = 0
const AIR: int = 1
const DASH: int = 2
const WALL: int = 3
const LOCO_NAMES: Array[String] = ["ground", "air", "dash", "wall"]
const NO_ACTION: int = -1
## A frame count that has stopped counting (far longer ago than any window it is compared with).
const LONG_AGO: int = 1000

var p: MovementParams
var kit: KitParams
var attacks: AttackSet
var world: CollisionWorld
var body: Body
var events: SimEvents

var facing: int = 1
var loco: int = AIR
var crouching: bool = false
## Ticks since the body last stood on ground (coyote time counts these).
var air_frames: int = 0
## The body left the ground by jumping (no coyote jump) rather than walking off.
var left_by_jump: bool = false
var air_jumps_left: int = 0
var air_dashes_left: int = 0

## Dash: frame (1-based while dashing), velocity, and whether it counts as a ground dash.
var dash_frame: int = 0
var dash_vx: int = 0
var dash_vy: int = 0
var dash_grounded: bool = false
var dash_crouched: bool = false
## This air dash has touched the ground (its landing has been counted).
var dash_landed: bool = false
## Frames left before another ground dash may start.
var ground_dash_cooldown: int = 0
## Carry-over after a dash: frames left and the velocity it holds.
var carry_frames: int = 0

## Variable jump: frames since the jump began (0 when no jump is rising), whether the button has
## been released, and whether the early-release gravity is in force.
var jump_frame: int = 0
var jump_released: bool = false
var jump_cut: bool = false
## The jump began this tick or last: its first airborne move skips gravity, so a jump fired on
## the landing frame rises exactly like one pressed on the ground.
var jump_fresh: bool = false
## Apex hang: frames of reduced gravity left, and whether this jump has used its hang.
var apex_hang_left: int = 0
var apex_hang_used: bool = false

## Wall: the side being clung to (-1 left, 1 right, 0 none), frames on it, and the lock after a
## wall-jump during which horizontal input is ignored.
var wall_side: int = 0
var wall_frames: int = 0
var wall_spent: bool = false
var wall_lock: int = 0
var no_cling_until_down_released: bool = false
## The next cling is the first since a landing, wall-jump or pogo: it restores the air jump and
## air dash and starts a fresh slide. Later clings (re-gripping, or the cling at the top of each
## kick of a climb) continue the slide and restore nothing (docs/adr/0010).
var wall_fresh: bool = true
## Wall coyote time: frames left in which a jump still pushes off the wall just let go of, and
## that wall's side.
var wall_coyote: int = 0
var wall_coyote_side: int = 0

## Strike: index into [member attacks] (or [constant NO_ACTION]), its frame, its direction, and
## the frames since the last strike ended (for the chain).
var action: int = NO_ACTION
var action_frame: int = 0
var action_dir: int = 1
var chain_next: String = "side1"
var chain_timer: int = 0
var action_pogoed: bool = false
## Frames since the last pogo bounce (the next down-strike may start on frame 6), held at
## [constant LONG_AGO] once it no longer matters.
var since_bounce: int = LONG_AGO

var invuln: int = 0
## Frames left in a ground turnaround's catch-up (speed returns from 60% to full over
## turn_frames).
var turn_left: int = 0
## Hitstop: frames the player is frozen for (the ring merges input meanwhile).
var freeze: int = 0

## Kit: the Kindle Votive lets the dash ignite wax and Snuffed (tech 12).
var kindle_dash: bool = false

## Ember toss (Ash's spell, tech 11).
var toss: EmberToss

## Last position where the body stood safely on solid ground (hazard respawn).
var safe_x: int = 0
var safe_y: int = 0


func _init(
	params: MovementParams,
	kit_params: KitParams,
	strikes: AttackSet,
	p_world: CollisionWorld,
	p_events: SimEvents
) -> void:
	p = params
	kit = kit_params
	attacks = strikes
	world = p_world
	events = p_events
	body = Body.make(0, 0, p.half_w, p.height)
	air_jumps_left = p.air_jumps
	air_dashes_left = p.air_dashes
	toss = EmberToss.new()


## Places the player at bottom-centre ([param x], [param y]) in sub-pixels, at rest.
func spawn(x: int, y: int) -> void:
	body.x = x
	body.y = y
	body.vx = 0
	body.vy = 0
	world.refresh_ground(body)
	loco = GROUND if body.on_ground else AIR
	# A mid-air spawn has no coyote time: there was no ledge to walk off.
	left_by_jump = not body.on_ground
	air_frames = 0
	# Until the player first stands on safe ground, a hazard returns them to the spawn point.
	safe_x = x
	safe_y = y


func is_dashing() -> bool:
	return loco == DASH


func is_invulnerable() -> bool:
	if invuln > 0:
		return true
	return loco == DASH and dash_frame >= p.dash_invuln_first and dash_frame <= p.dash_invuln_last


func current_attack() -> AttackDef:
	return attacks.attacks[action] if action != NO_ACTION else null


## One tick. [param ring] already holds this tick's input frame.
func step(ring: InputRing) -> void:
	body.clear_contacts()
	if freeze > 0:
		freeze -= 1
		return
	var dx: int = _dir_x(ring)
	var dy: int = _dir_y(ring)
	_tick_timers()
	_advance_action()
	_turn(dx)
	_crouch(dx, dy)
	# The toss goes first: a teleport pressed with a jump or a dash moves the player, and the
	# jump or dash goes from where it lands rather than being cut off by it.
	toss.try_start(self, ring)
	_try_dash(ring)
	_try_jump(ring, dx, dy)
	PlayerStrikes.try_attack(self, ring)
	_move(ring, dx, dy)
	_after_move(ring, dx, dy)
	toss.step(self)


# --- timers ----------------------------------------------------------------------------------


func _tick_timers() -> void:
	if loco != GROUND:
		air_frames += 1
	ground_dash_cooldown = maxi(ground_dash_cooldown - 1, 0)
	wall_lock = maxi(wall_lock - 1, 0)
	invuln = maxi(invuln - 1, 0)
	if wall_coyote > 0:
		wall_coyote -= 1
		if wall_coyote == 0:
			wall_coyote_side = 0
	since_bounce = mini(since_bounce + 1, LONG_AGO)
	if action == NO_ACTION and chain_timer > 0:
		chain_timer -= 1
		if chain_timer == 0:
			chain_next = "side1"
	if loco == DASH:
		dash_frame += 1
		if dash_frame > p.dash_frames:
			end_dash(true)
	elif carry_frames > 0:
		carry_frames -= 1
	# A jump started after last tick's move (on a landing or a cling) has not risen yet: its count
	# starts with its first airborne move, as a jump pressed on the ground does.
	if jump_frame > 0 and not jump_fresh:
		jump_frame += 1


func _advance_action() -> void:
	if action == NO_ACTION:
		return
	action_frame += 1
	if action_frame > current_attack().total_frames():
		_end_action()


func _end_action() -> void:
	action = NO_ACTION
	action_frame = 0
	chain_timer = attacks.chain_reset_frames
	if chain_timer == 0:
		chain_next = "side1"


# --- facing and crouch -----------------------------------------------------------------------


func _turn(dx: int) -> void:
	# The sprite turns on the input frame (BUILD.md s15), except while the dash or a wall-jump
	# owns the direction.
	if dx != 0 and loco != DASH and wall_lock == 0 and loco != WALL:
		facing = dx


func _crouch(dx: int, dy: int) -> void:
	var want: bool = loco == GROUND and dy > 0 and dx == 0
	if dash_crouched and loco == DASH:
		return
	if want and not crouching:
		crouching = true
		body.height = p.crouch_height
	elif not want and crouching and world.headroom(body, p.height):
		crouching = false
		body.height = p.height
	elif crouching and loco != GROUND and world.headroom(body, p.height):
		crouching = false
		body.height = p.height


# --- dash ------------------------------------------------------------------------------------


func _try_dash(ring: InputRing, pre_start: bool = false) -> void:
	if not ring.has_press(InputFrame.DASH, p.dash_buffer_frames) or loco == DASH:
		return
	var pressed: Vector2i = press_dir(ring, InputFrame.DASH, p.dash_buffer_frames)
	var dx: int = pressed.x
	var dy: int = pressed.y
	var atk: AttackDef = current_attack()
	if atk != null and (atk.dash_from == 0 or action_frame < atk.dash_from):
		return
	var coyote: bool = loco != GROUND and _in_coyote()
	var grounded: bool = loco == GROUND or coyote
	if grounded and ground_dash_cooldown > 0:
		if not coyote:
			# Standing: the press waits in the buffer for the cooldown to end.
			return
		# Off a ledge in coyote time with the ground dash still cooling: the air dash, at once,
		# rather than a ground dash fired late (docs/adr/0010).
		grounded = false
	if not grounded and air_dashes_left <= 0:
		if coyote:
			# Refused, not held to fire late once coyote time is over.
			ring.consume(InputFrame.DASH)
		return
	ring.consume(InputFrame.DASH)
	if atk != null:
		# A cancelled strike ends like a finished one: the chain carries on for
		# chain_reset_frames, so slash, dash, slash keeps the 3-hit rhythm (docs/adr/0010).
		_end_action()
	var dir := Vector2i(dx if dx != 0 else facing, 0)
	if not grounded:
		dir = Vector2i(dx, dy)
		if dir == Vector2i.ZERO:
			dir = Vector2i(facing, 0)
		if loco == WALL and dir.x == wall_side:
			dir.x = -wall_side
	if dir.x != 0:
		facing = dir.x
	var speed: int = p.dash_speed
	if dir.x != 0 and dir.y != 0:
		speed = Fx.permille(p.dash_speed, Fx.DIAGONAL_PERMILLE)
	dash_vx = dir.x * speed
	dash_vy = dir.y * speed
	dash_grounded = grounded
	# A ground dash with the stick anywhere down is a crouch-dash (tech 10), straight down or
	# down-forward: the crouch (28 u) holds for the whole dash.
	dash_crouched = loco == GROUND and (crouching or dy > 0)
	if dash_crouched and not crouching:
		crouching = true
		body.height = p.crouch_height
	if grounded:
		ground_dash_cooldown = p.dash_ground_cooldown
	else:
		air_dashes_left -= 1
	loco = DASH
	# A dash taken on the landing frame (pre_start) counts that frame as frame 0: its nine
	# moving frames and its invulnerability start on the next tick, as a jump fired on the landing
	# frame first rises on the next tick.
	dash_frame = 0 if pre_start else 1
	dash_landed = false
	carry_frames = 0
	jump_frame = 0
	jump_cut = false
	wall_side = 0
	body.vx = dash_vx
	body.vy = dash_vy
	events.add(SimEvents.DASH, body.x, body.y, dir.x + 3 * dir.y)


## Ends the dash. With [param carry] the 3-frame, 50% carry-over follows.
func end_dash(carry: bool) -> void:
	loco = GROUND if body.on_ground else AIR
	dash_frame = 0
	if carry:
		carry_frames = p.dash_carry_frames
		body.vx = Fx.percent(dash_vx, p.dash_carry_percent)
		body.vy = Fx.percent(dash_vy, p.dash_carry_percent)
	if dash_crouched:
		dash_crouched = false
		crouching = not world.headroom(body, p.height)
		body.height = p.crouch_height if crouching else p.height


# --- jump ------------------------------------------------------------------------------------


func _try_jump(ring: InputRing, dx: int, dy: int) -> void:
	if not ring.has_press(InputFrame.JUMP, p.jump_buffer_frames):
		return
	if not _strike_allows_jump() or not _room_to_rise(dy, dx):
		return
	var keep_vx: int = 0
	var from_dash: bool = loco == DASH
	if from_dash:
		if dash_frame < p.dash_jump_first or dash_frame > p.dash_jump_last:
			return
		keep_vx = Fx.percent(dash_vx, p.dash_jump_keep_percent)
	# Drop-through needs the stick straight down, like crouch: a stick a little low while running
	# still jumps.
	if loco == GROUND and dy > 0 and dx == 0 and world.can_drop_through(body):
		ring.consume(InputFrame.JUMP)
		_drop_through()
		return
	var grounded: bool = loco == GROUND or (from_dash and body.on_ground)
	if grounded or _in_coyote():
		ring.consume(InputFrame.JUMP)
		if from_dash:
			end_dash(false)
		_start_jump(p.jump_speed, SimEvents.JUMP)
		if from_dash:
			body.vx = keep_vx
		return
	var side: int = _wall_side_near()
	if side != 0:
		ring.consume(InputFrame.JUMP)
		if from_dash:
			end_dash(false)
		_wall_jump(side, dx)
		return
	if air_jumps_left > 0:
		ring.consume(InputFrame.JUMP)
		if from_dash:
			end_dash(false)
		air_jumps_left -= 1
		_start_jump(p.air_jump_speed, SimEvents.AIR_JUMP)
		if from_dash:
			body.vx = keep_vx


## Every jump rises: with a ceiling flush on the head there is no room, and the press waits in the
## buffer (a step out from under it fires it) rather than firing a jump that goes nowhere.
## Dropping through a one-way (down and jump) needs no room above.
func _room_to_rise(dy: int, dx: int) -> bool:
	if loco == GROUND and dy > 0 and dx == 0 and world.can_drop_through(body):
		return true
	return world.headroom(body, body.height + 1)


## A strike blocks the jump unless its row lists a jump cancel ("jump any frame"), or it is an
## air-only strike (the down-strike) that has reached the ground: a missed pogo never locks the
## jump (docs/adr/0010).
func _strike_allows_jump() -> bool:
	var atk: AttackDef = current_attack()
	if atk == null or atk.jump_any:
		return true
	return atk.air_only and loco == GROUND


func _start_jump(speed: int, kind: String) -> void:
	loco = AIR
	left_by_jump = true
	wall_coyote = 0
	wall_coyote_side = 0
	body.vy = -speed
	body.on_ground = false
	jump_frame = 1
	jump_released = false
	jump_cut = false
	jump_fresh = true
	apex_hang_left = 0
	apex_hang_used = false
	carry_frames = 0
	wall_side = 0
	if crouching and world.headroom(body, p.height):
		crouching = false
		body.height = p.height
	events.add(kind, body.x, body.y, speed)


## Holding away is a wall-jump, which restores the air jump and air dash (BUILD.md: "Resets double
## jump and air dash") and makes the next cling fresh. Anything else is a kick: a fixed kick, like
## the pogo's bounce (no early-release cut, no apex hang), that restores nothing (its row lists no
## reset). So a climb is one full kick per apex however the button is pressed: timed kicks and
## mashing climb at the same rate (docs/adr/0010).
func _wall_jump(side: int, dx: int) -> void:
	var away: int = -side
	if dx == away:
		_start_jump(p.wall_jump_up, SimEvents.WALL_JUMP)
		body.vx = away * p.wall_jump_away
		wall_lock = p.wall_jump_lock
		air_jumps_left = p.air_jumps
		air_dashes_left = p.air_dashes
		refresh_wall()
	else:
		_start_jump(p.wall_kick_up, SimEvents.WALL_KICK)
		jump_frame = 0
		body.vx = away * p.wall_kick_away
		wall_lock = p.wall_kick_lock
	facing = away


## A landing, a wall-jump or a pogo: the next cling is fresh.
func refresh_wall() -> void:
	wall_fresh = true
	wall_spent = false
	wall_frames = 0


func _drop_through() -> void:
	world.drop_through(body)
	loco = AIR
	left_by_jump = true
	air_frames = 0
	events.add(SimEvents.DROP_THROUGH, body.x, body.y)


func _in_coyote() -> bool:
	return (loco == AIR or loco == DASH) and not left_by_jump and air_frames <= p.coyote_frames


## The side (-1, 1) of a clingable wall a wall-jump may push off, preferring the one clung to:
## while clinging, within wall coyote time of letting go of one, or while falling within reach of
## a wall. Not while rising, or mashing jump beside a wall would climb it at jump speed
## (docs/adr/0010).
func _wall_side_near() -> int:
	if wall_side != 0 and world.wall_near(body, wall_side, p.wall_jump_reach):
		return wall_side
	if wall_coyote > 0:
		return wall_coyote_side
	if body.vy < 0:
		return 0
	for side: int in [facing, -facing]:
		if world.wall_near(body, side, p.wall_jump_reach):
			return side
	return 0


# --- strikes ---------------------------------------------------------------------------------


## The strike's hitbox in world sub-pixels as (left, top, right, bottom), or an empty rect.
func strike_box() -> Rect2i:
	return PlayerStrikes.strike_box(self)


## The down-strike's pogo box, live on its pogo frames.
func pogo_box() -> Rect2i:
	return PlayerStrikes.pogo_box(self)


# --- movement --------------------------------------------------------------------------------


func _move(ring: InputRing, dx: int, dy: int) -> void:
	# Reversing the stick ends the dash's carry-over: turning around never has a dead frame.
	if carry_frames > 0 and dx != 0 and body.vx != 0 and dx != signi(body.vx):
		carry_frames = 0
	match loco:
		GROUND:
			_move_ground(ring, dx, dy)
		AIR:
			_move_air(ring, dx, dy)
		DASH:
			_move_dash(ring, dx, dy)
		WALL:
			_move_wall(ring, dx, dy)


func _move_ground(_ring: InputRing, dx: int, _dy: int) -> void:
	var input_x: int = 0 if crouching else dx
	if carry_frames <= 0:
		body.vx = _ground_speed(body.vx, input_x)
	body.vy = 0
	world.walk(body, body.vx, p.corner_lift)
	if not body.on_ground:
		loco = AIR
		left_by_jump = false
		air_frames = 0
	else:
		PlayerContacts.note_safe_ground(self)


func _ground_speed(vx: int, input_x: int) -> int:
	return _horizontal(vx, input_x, p.run_accel, p.run_decel, true)


func _air_speed(vx: int, input_x: int) -> int:
	return _horizontal(vx, input_x, p.air_accel, p.air_decel, false)


## Horizontal speed for one tick. On the ground a reversal flips to 60% of the speed in the new
## direction on the input frame (never a dead frame) and recovers the rest over the next
## turn_frames frames (BUILD.md Ground: "Turnaround"). In the air a reversal is ordinary air
## control (BUILD.md Jump: "0 to max in 8 f"). Above run speed the ground slows back to it; the air
## keeps the extra speed (dash-jump and pogo momentum) while the stick holds that way.
func _horizontal(vx: int, input_x: int, accel: int, decel: int, on_ground: bool) -> int:
	if input_x == 0 or not on_ground:
		turn_left = 0
	if input_x == 0:
		return Fx.approach(vx, 0, decel)
	if vx != 0 and signi(vx) != input_x:
		if not on_ground:
			return Fx.approach(vx, input_x * p.run_speed, accel)
		turn_left = p.turn_frames
		return input_x * Fx.percent(mini(absi(vx), p.run_speed), p.turn_keep_percent)
	if absi(vx) < p.run_speed:
		var a: int = accel
		if turn_left > 0:
			turn_left -= 1
			a = maxi(
				accel,
				Fx.per_tick(
					p.run_speed - Fx.percent(p.run_speed, p.turn_keep_percent), p.turn_frames
				)
			)
		return Fx.approach(vx, input_x * p.run_speed, a)
	turn_left = 0
	if on_ground:
		return Fx.approach(vx, input_x * p.run_speed, decel)
	return vx


func _move_air(ring: InputRing, dx: int, dy: int) -> void:
	# The crouched box cannot move, in the air as on the ground ("Crouch: cannot move"): a body
	# stays crouched in the air only under a ceiling too low to stand (it stands up wherever there
	# is headroom), so hopping there never crawls (docs/adr/0010).
	var input_x: int = 0 if crouching else dx
	if carry_frames <= 0 and wall_lock == 0:
		body.vx = _air_speed(body.vx, input_x)
	_update_jump_release(ring)
	if jump_fresh:
		jump_fresh = false
	else:
		body.vy = mini(body.vy + _gravity(ring), p.terminal)
	var contact: int = world.landing_contact(body, body.vx, body.vy)
	if contact != CollisionQueries.NONE:
		_land_in_stride(ring, dx, dy, contact)
		return
	var lift: int = p.ledge_grab if dx != 0 and dx == signi(body.vx) else p.corner_lift
	world.move_x(body, body.vx, lift, p.corner_slide)
	if body.hit_wall != 0 and dx != body.hit_wall:
		body.vx = 0
	if body.nudge_y < -p.corner_lift:
		events.add(SimEvents.LEDGE_GRAB, body.x, body.y)
	world.move_y(body, body.vy, p.corner_slide)
	if body.hit_ceiling:
		body.vy = 0
		jump_frame = 0
	if body.on_ground and body.vy >= 0:
		_land(ring, dx, dy)


## A fall meeting a ledge it leaves by the far edge (see [method CollisionWorld.landing_contact])
## lands there, with all a landing brings, and walks the rest of the step (off the edge is coyote
## time); a jump, dash or strike pressed before the landing then starts from where the step ends,
## as on any landing tick.
func _land_in_stride(ring: InputRing, dx: int, dy: int, contact: int) -> void:
	var rest: int = body.vx - contact
	world.move_x(body, contact)
	world.move_y(body, body.vy)
	_arrive()
	_walk_rest(rest)
	_landing_actions(ring, dx, dy)


## Walks the part of a landing tick's step left after touching down; walking off the edge leaves
## the ground, in coyote time.
func _walk_rest(rest: int) -> void:
	if rest == 0:
		return
	world.walk(body, rest, p.corner_lift)
	if not body.on_ground:
		loco = AIR if loco == GROUND else loco
		left_by_jump = false
		air_frames = 0


## Gravity for this tick: rise or fall; the early-release multiplier until the apex; and the
## apex hang, exactly [member MovementParams.apex_hang_frames] frames of reduced gravity centred
## on the apex while the jump is held (BUILD.md: "Gravity x 0.6 for the 4 f around apex").
func _gravity(ring: InputRing) -> int:
	var g: int = p.gravity_rise if body.vy < 0 else p.gravity_fall
	if body.vy < 0 and jump_cut:
		return p.release_gravity
	if jump_frame > 0 and not jump_released and ring.is_held(InputFrame.JUMP):
		if not apex_hang_used and _apex_near():
			apex_hang_used = true
			apex_hang_left = p.apex_hang_frames
		if apex_hang_left > 0:
			apex_hang_left -= 1
			return Fx.permille(g, p.apex_hang_permille)
	return g


## The hang starts on the rising frame that centres the apex in it: the first whose speed is
## within the hang's band plus half a frame of full gravity (MovementParams.apex_hang_start), or,
## should the rise skip that, the first frame at or past the apex within the band.
func _apex_near() -> bool:
	if body.vy < 0:
		return -body.vy <= p.apex_hang_start
	return body.vy <= p.apex_hang_speed


## Tracks the release of a rising jump: once released, gravity multiplies from the frame after
## the minimum hold until the apex (BUILD.md: "Released after 4 f applies a ... gravity
## multiplier until apex"). The jump is over once it is falling and its hang is spent.
func _update_jump_release(ring: InputRing) -> void:
	if jump_frame == 0:
		return
	if not ring.is_held(InputFrame.JUMP):
		jump_released = true
		apex_hang_left = 0
	if jump_released and jump_frame > p.jump_min_frames and body.vy < 0:
		jump_cut = true
	if body.vy >= 0:
		jump_cut = false
		if apex_hang_left == 0 and (apex_hang_used or jump_released):
			jump_frame = 0


func _move_dash(ring: InputRing, dx: int, dy: int) -> void:
	PlayerContacts.kindle_ahead(self)
	# A level dash on the ground walks it, following slopes up and down; that includes a level air
	# dash once it has touched down.
	if (dash_grounded or dash_landed) and dash_vy == 0 and body.on_ground:
		body.vx = dash_vx
		body.vy = 0
		world.walk(body, dash_vx, p.corner_lift)
		if body.on_ground:
			air_frames = 0
		return
	body.vx = dash_vx
	body.vy = dash_vy
	# A diagonal dash down past a ledge's far edge touches down there, as a fall does, and runs on
	# along it for the rest of the tick's step.
	var contact: int = CollisionQueries.NONE
	if dash_vx != 0 and dash_vy > 0 and not body.on_ground:
		contact = world.landing_contact(body, dash_vx, dash_vy)
	if contact != CollisionQueries.NONE:
		world.move_x(body, contact)
		world.move_y(body, dash_vy)
	else:
		world.move_x(body, dash_vx, p.corner_lift, p.corner_slide)
		world.move_y(body, dash_vy, p.corner_slide)
	if body.on_ground:
		body.vy = 0
		air_frames = 0
		if dash_vx == 0:
			# A straight-down dash that reaches the floor cannot go on: it ends there, a landing
			# with no lag (BUILD.md: "Landing: 0 f of lag").
			end_dash(false)
			_land(ring, dx, dy)
		elif not dash_grounded and not dash_landed:
			# A diagonal air dash runs on along the floor, but the airtime ends here: the air jump
			# and air dash come back on the frame it touches down, and a buffered jump fires on
			# that frame, from where the step ends, if the dash has reached its jump frames (a
			# dash-jump, as from any dash).
			dash_landed = true
			_touch_down()
			if contact != CollisionQueries.NONE:
				_walk_rest(dash_vx - contact)
			_try_jump(ring, dx, dy)
	elif _dash_meets_cling_wall(dx):
		# An air dash that meets a wall the stick holds toward clings at once, rather than
		# grinding out its remaining frames against it (tech 6; docs/adr/0010).
		end_dash(false)
		_start_cling(dx, ring)


## The air dash was stopped this tick by a clingable wall on the side the stick holds, and is
## not rising (a cling, like any cling, starts only on the way down or level).
func _dash_meets_cling_wall(dx: int) -> bool:
	if dx == 0 or body.hit_wall != dx or dash_vy < 0:
		return false
	if wall_spent or no_cling_until_down_released:
		return false
	return world.wall_near(body, dx, 1)


func _move_wall(ring: InputRing, dx: int, dy: int) -> void:
	wall_frames += 1
	var leave: bool = dx != wall_side or dy > 0 or wall_frames > p.wall_slide_frames
	if leave:
		if dy > 0:
			no_cling_until_down_released = true
		elif wall_frames > p.wall_slide_frames:
			wall_spent = true
		else:
			_start_wall_coyote()
		loco = AIR
		wall_side = 0
		_move_air(ring, dx, dy)
		return
	body.vx = 0
	body.vy = p.wall_slide_speed
	world.move_x(body, wall_side * Fx.SUB, p.ledge_grab, 0)
	if body.nudge_y < 0:
		events.add(SimEvents.LEDGE_GRAB, body.x, body.y)
	world.move_y(body, body.vy, 0)
	if body.on_ground:
		_land(ring, dx, dy)
	elif not world.wall_near(body, wall_side, 1):
		# Slid off the wall's end.
		_start_wall_coyote()
		loco = AIR
		wall_side = 0


## Let go of a cling without jumping: a jump within the wall coyote time still pushes off it.
func _start_wall_coyote() -> void:
	# Counted down at the start of each tick, so a jump up to wall_coyote_frames ticks after
	# letting go still pushes off, as a jump up to coyote_frames ticks after walking off a ledge
	# still jumps.
	wall_coyote = p.wall_coyote_frames + 1
	wall_coyote_side = wall_side


## Arriving on the ground by any route (a fall, a wall slide, a straight-down dash, a teleport):
## the airtime's resources come back, horizontal speed above run speed is lost (the ground slows
## back to run speed, so a landing jump does not carry a dash-jump's speed on), and a jump, dash or
## attack pressed up to their buffers before landing starts on the landing frame (BUILD.md s15).
## [param after_move] is false when the landing happens before this tick's move (a teleport), so
## a dash taken then moves this very tick.
func _land(ring: InputRing, dx: int, dy: int, after_move: bool = true) -> void:
	_arrive()
	_landing_actions(ring, dx, dy, after_move)


## The landing itself (see [method _land]), before any buffered press starts.
func _arrive() -> void:
	loco = GROUND
	if absi(body.vx) > p.run_speed:
		body.vx = signi(body.vx) * p.run_speed
	carry_frames = 0
	_touch_down()
	body.vy = 0
	jump_frame = 0
	jump_cut = false
	wall_side = 0


## A jump, dash or strike pressed within its buffer before the landing starts on its frame.
func _landing_actions(ring: InputRing, dx: int, dy: int, after_move: bool = true) -> void:
	if ring.has_press(InputFrame.JUMP, p.jump_buffer_frames) and _strike_allows_jump():
		ring.consume(InputFrame.JUMP)
		# Down and jump onto a one-way platform drops through it, as on the ground.
		if dy > 0 and dx == 0 and world.can_drop_through(body):
			_drop_through()
			return
		_start_jump(p.jump_speed, SimEvents.JUMP)
		return
	_try_dash(ring, after_move)
	if loco == GROUND:
		PlayerStrikes.try_attack(self, ring)


## The airtime is over: resources, the landing event and safe ground. Also run by a diagonal air
## dash when it touches the floor and runs on along it.
func _touch_down() -> void:
	var impact: int = body.vy
	restore_airtime()
	events.add(SimEvents.LAND, body.x, body.y, impact)
	PlayerContacts.note_safe_ground(self)


## Standing on the ground again: the air jump and air dash, the ground dash cooldown (BUILD.md
## Dash: "Cooldown 24 f on ground, resets on landing or wall-cling") and the walls.
func restore_airtime() -> void:
	air_frames = 0
	left_by_jump = false
	air_jumps_left = p.air_jumps
	air_dashes_left = p.air_dashes
	ground_dash_cooldown = 0
	wall_coyote = 0
	wall_coyote_side = 0
	refresh_wall()


# --- after the move --------------------------------------------------------------------------


func _after_move(ring: InputRing, dx: int, dy: int) -> void:
	if dy <= 0:
		no_cling_until_down_released = false
	if loco == AIR and body.vy >= 0 and dx != 0 and not wall_spent:
		if not no_cling_until_down_released and world.wall_near(body, dx, 1):
			_start_cling(dx, ring)
	# A pogo box and the hurtbox reaching the spikes on the same frame is a bounce: the benefit of
	# the doubt goes to the player.
	if not PlayerContacts.check_pogo(self, ring):
		PlayerContacts.check_hazards(self)


## Starts a cling on [param side]. The first cling since a landing, wall-jump or pogo restores the
## air jump and air dash (BUILD.md: "resets on wall-cling") and starts a fresh 90 f slide; a
## re-grip continues the slide it interrupted. Every cling clears the ground dash cooldown
## ("resets on landing or wall-cling"). A jump pressed before the cling fires on the cling frame,
## as one pressed before landing does.
func _start_cling(side: int, ring: InputRing) -> void:
	loco = WALL
	wall_side = side
	wall_coyote = 0
	wall_coyote_side = 0
	if wall_fresh:
		wall_fresh = false
		wall_frames = 0
		air_jumps_left = p.air_jumps
		air_dashes_left = p.air_dashes
	ground_dash_cooldown = 0
	body.vx = 0
	body.vy = mini(body.vy, p.wall_slide_speed)
	jump_frame = 0
	jump_cut = false
	carry_frames = 0
	facing = -side
	events.add(SimEvents.WALL_CLING, body.x, body.y, side)
	if ring.has_press(InputFrame.JUMP, p.jump_buffer_frames) and _strike_allows_jump():
		ring.consume(InputFrame.JUMP)
		_wall_jump(side, _dir_x(ring))


## The hurtbox: the collider inset on every side (smaller than the sprite; CLAUDE.md rule 8).
func hurtbox() -> Rect2i:
	return PlayerContacts.hurtbox(self)


## After an ember-toss teleport: any dash or rising jump ends, the spell's invulnerability starts,
## and the player is airborne (with no coyote time) or, on ground, has landed.
func teleported(invuln_frames: int, ring: InputRing) -> void:
	if loco == DASH:
		end_dash(false)
	world.refresh_ground(body)
	left_by_jump = true
	air_frames = 0
	jump_frame = 0
	jump_cut = false
	carry_frames = 0
	wall_side = 0
	wall_coyote = 0
	wall_coyote_side = 0
	invuln = maxi(invuln, invuln_frames)
	if body.on_ground:
		_land(ring, _dir_x(ring), _dir_y(ring), false)
	else:
		loco = AIR


# --- input -----------------------------------------------------------------------------------


func _dir_x(ring: InputRing) -> int:
	return PlayerInput.axis(ring.stick_x(), p.stick_threshold)


func _dir_y(ring: InputRing) -> int:
	return PlayerInput.axis(ring.stick_y(), p.stick_threshold)


## The stick's 8-way direction when the buffered press of [param bit] was made
## ([method PlayerInput.press_dir]).
func press_dir(ring: InputRing, bit: int, max_age: int) -> Vector2i:
	return PlayerInput.press_dir(ring, bit, max_age, p.stick_threshold)


# --- state -----------------------------------------------------------------------------------


func hash_into(h: StateHasher) -> void:
	body.hash_into(h)
	for v: int in [
		facing,
		loco,
		air_frames,
		air_jumps_left,
		air_dashes_left,
		dash_frame,
		dash_vx,
		dash_vy,
		ground_dash_cooldown,
		carry_frames,
		jump_frame,
		wall_side,
		wall_frames,
		wall_lock,
		action,
		action_frame,
		action_dir,
		chain_timer,
		since_bounce,
		invuln,
		freeze,
		safe_x,
		safe_y,
		turn_left,
		apex_hang_left,
		wall_coyote,
		wall_coyote_side,
	]:
		h.add_int(v)
	for b: bool in [
		crouching,
		left_by_jump,
		dash_grounded,
		dash_crouched,
		jump_released,
		jump_cut,
		jump_fresh,
		wall_spent,
		no_cling_until_down_released,
		action_pogoed,
		kindle_dash,
		apex_hang_used,
		dash_landed,
		wall_fresh,
	]:
		h.add_bool(b)
	h.add_string(chain_next)
	toss.hash_into(h)
