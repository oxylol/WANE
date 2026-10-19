class_name PlayerWall
extends RefCounted
## The wall (BUILD.md section 5 Wall; docs/adr/0010): reaching one, clinging, the kick and the
## wall-jump off it, letting go with wall coyote time, and which wall a press means. Static helpers
## on a [Player], kept apart from the state machine so it stays readable; the state they change is
## the player's. The slide itself is the player's wall movement ([code]Player._move_wall[/code]).


## Starts a cling on [param side]. The first cling since a landing, wall-jump or pogo restores the
## air jump and air dash (BUILD.md: "resets on wall-cling"; never taking away air dashes a Votive
## granted beyond the Wick's own: docs/adr/0015) and starts a fresh 90 f slide; a
## re-grip continues the slide it interrupted. Every cling clears the ground dash cooldown
## ("resets on landing or wall-cling"). A jump pressed before the cling fires on the cling frame,
## as one pressed before landing does.
static func cling(pl: Player, side: int, ring: InputRing) -> void:
	var p: MovementParams = pl.p
	pl.loco = Player.WALL
	pl.wall_side = side
	pl.wall_coyote = 0
	pl.wall_coyote_side = 0
	if pl.wall_fresh:
		pl.wall_fresh = false
		pl.wall_frames = 0
		pl.air_jumps_left = p.air_jumps
		pl.air_dashes_left = maxi(pl.air_dashes_left, p.air_dashes)
	pl.ground_dash_cooldown = 0
	pl.body.vx = 0
	pl.body.vy = mini(pl.body.vy, p.wall_slide_speed)
	pl.jump_frame = 0
	pl.jump_cut = false
	pl.carry_frames = 0
	pl.facing = -side
	pl.events.add(SimEvents.WALL_CLING, pl.body.x, pl.body.y, side)
	if ring.has_press(InputFrame.JUMP, p.jump_buffer_frames) and pl.strike_allows_jump():
		ring.consume(InputFrame.JUMP)
		jump_off(pl, side, PlayerInput.axis(ring.stick_x(), p.stick_threshold))


## Holding away is a wall-jump, which restores the air jump and air dash (BUILD.md: "Resets double
## jump and air dash"; as a cling does, never taking a Votive's extra air dashes away) and makes the
## next cling fresh. Anything else is a kick: a fixed kick, like
## the pogo's bounce (no early-release cut, no apex hang), that restores nothing (its row lists no
## reset). So a climb is one full kick per apex however the button is pressed: timed kicks and
## mashing climb at the same rate (docs/adr/0010).
static func jump_off(pl: Player, side: int, dx: int) -> void:
	var p: MovementParams = pl.p
	var away: int = -side
	if dx == away:
		pl.start_jump(p.wall_jump_up, SimEvents.WALL_JUMP)
		pl.body.vx = away * p.wall_jump_away
		pl.wall_lock = p.wall_jump_lock
		pl.air_jumps_left = p.air_jumps
		pl.air_dashes_left = maxi(pl.air_dashes_left, p.air_dashes)
		refresh(pl)
	else:
		pl.start_jump(p.wall_kick_up, SimEvents.WALL_KICK)
		pl.jump_frame = 0
		pl.body.vx = away * p.wall_kick_away
		pl.wall_lock = p.wall_kick_lock
	pl.facing = away


## A landing, a wall-jump or a pogo: the next cling is fresh.
static func refresh(pl: Player) -> void:
	pl.wall_fresh = true
	pl.wall_spent = false
	pl.wall_frames = 0


## Let go of a cling without jumping: a jump within the wall coyote time still pushes off it.
static func let_go(pl: Player) -> void:
	# Counted down at the start of each tick, so a jump up to wall_coyote_frames ticks after
	# letting go still pushes off, as a jump up to coyote_frames ticks after walking off a ledge
	# still jumps.
	pl.wall_coyote = pl.p.wall_coyote_frames + 1
	pl.wall_coyote_side = pl.wall_side


## The side (-1, 1) of a clingable wall a wall-jump may push off, preferring the one clung to:
## while clinging, within wall coyote time of letting go of one, or while falling within reach of
## a wall. Not while rising, or mashing jump beside a wall would climb it at jump speed
## (docs/adr/0010).
static func side_near(pl: Player) -> int:
	var reach: int = pl.p.wall_jump_reach
	if pl.wall_side != 0 and pl.world.wall_near(pl.body, pl.wall_side, reach):
		return pl.wall_side
	if pl.wall_coyote > 0:
		return pl.wall_coyote_side
	if pl.body.vy < 0:
		return 0
	for side: int in [pl.facing, -pl.facing]:
		if pl.world.wall_near(pl.body, side, reach):
			return side
	return 0


## The side of the clingable wall the stick holds toward ([param dx], [param dy]) that this tick's
## move clings to: a fall, or an air dash, that will end the tick clinging there. A press on the
## tick the player reaches a wall is a press on the wall (docs/adr/0010): a jump waits for the
## cling this tick and kicks off it, and a dash, strike or toss toward it goes away from it, as it
## would one tick later, once clinging. The move is tried on a copy of the body with this tick's
## speeds, so the answer is the cling the move makes, never one a tick early or one that does not
## come (movement review 5, M4, M5 and L6). 0 if there is none.
static func met(pl: Player, ring: InputRing, dx: int, dy: int) -> int:
	# A stick held through a hazard send-back moves nothing ([member Player.stick_hold_x]).
	if dx == 0 or dy > 0 or pl.wall_spent or pl.stick_hold_x != 0:
		return 0
	if pl.loco == Player.AIR:
		return dx if _air_move_clings(pl, ring, dx) else 0
	if pl.loco == Player.DASH:
		return dx if _dash_move_clings(pl, dx) else 0
	return 0


## True if this tick's air move ends with the body in the air, falling or level, within 1 u of a
## clingable wall on [param dx]'s side: the cling [code]Player._after_move[/code] starts.
static func _air_move_clings(pl: Player, ring: InputRing, dx: int) -> bool:
	var p: MovementParams = pl.p
	var v: Vector2i = pl.air_velocity_ahead(ring, dx)
	if v.y < 0:
		return false
	var b: Body = pl.body.copy()
	var lift: int = p.ledge_grab if dx == signi(v.x) else p.corner_lift
	var w: CollisionWorld = pl.world
	if w.landing_contact(b, v.x, v.y, lift, p.corner_slide) != CollisionQueries.NONE:
		return false
	w.move_x(b, v.x, lift, p.corner_slide)
	w.move_y(b, v.y, p.corner_slide)
	return not b.on_ground and w.wall_near(b, dx, 1)


## True if this tick's air dash ends against a clingable wall on [param dx]'s side, in the air:
## the cling [code]Player._move_dash[/code] starts ([method dash_meets]). Wax a kindle-dash
## burns this tick is out of the way, as it will be.
static func _dash_move_clings(pl: Player, dx: int) -> bool:
	if pl.dash_vy < 0 or ((pl.dash_grounded or pl.dash_landed) and pl.body.on_ground):
		return false
	var p: MovementParams = pl.p
	var w: CollisionWorld = pl.world
	var b: Body = pl.body.copy()
	var burnt: Array[SolidBox] = PlayerContacts.wax_ahead(pl, Vector2i(pl.dash_vx, pl.dash_vy))
	for s: SolidBox in burnt:
		s.enabled = false
	var clings: bool = false
	if (
		pl.dash_vx == 0
		or pl.dash_vy <= 0
		or b.on_ground
		or (
			w.landing_contact(b, pl.dash_vx, pl.dash_vy, p.corner_lift, p.corner_slide)
			== CollisionQueries.NONE
		)
	):
		w.move_x(b, pl.dash_vx, p.corner_lift, p.corner_slide)
		w.move_y(b, pl.dash_vy, p.corner_slide)
		clings = not b.on_ground and b.hit_wall == dx and w.wall_near(b, dx, 1)
	for s: SolidBox in burnt:
		s.enabled = true
	return clings


## The air dash was stopped this tick by a clingable wall on the side the stick holds, and is
## not rising (a cling, like any cling, starts only on the way down or level).
static func dash_meets(pl: Player, dx: int, dy: int) -> bool:
	if dx == 0 or pl.body.hit_wall != dx or pl.dash_vy < 0:
		return false
	if pl.wall_spent or dy > 0:
		return false
	return pl.world.wall_near(pl.body, dx, 1)
