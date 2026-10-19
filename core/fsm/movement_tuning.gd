class_name MovementTuning
extends Resource
## A Wick's movement numbers in BUILD.md section 5's own units (units, units per second, units
## per second squared, frames at 60 Hz, percent and per-mille), so the resource reads beside the
## doc. [method compile] converts them once into the sub-pixel integers the core runs on
## (ADR-0003). Ash's values live in content/wicks/ash/movement.tres; tuned values become the spec
## and are mirrored in BUILD.md.

@export_group("Body")
## Collider width (BUILD.md: 20 u).
@export var width_u: int = 20
## Standing collider height (44 u).
@export var height_u: int = 44
## Crouching collider height (44 to 28).
@export var crouch_height_u: int = 28
## Stick deflection, out of 127, that counts as a direction.
@export var stick_threshold: int = 64

@export_group("Ground")
## Max run speed (540 u/s).
@export var run_speed_ups: int = 540
## Frames from 0 to max run speed (6 f).
@export var run_accel_frames: int = 6
## Frames from max run speed to 0 (4 f).
@export var run_decel_frames: int = 4
## Speed kept, in the new direction, on a turnaround (60%), and the frames after the reversal
## in which the rest of the speed comes back (2 f).
@export var turn_keep_percent: int = 60
@export var turn_frames: int = 2
## Sideways corner correction over ledge corners (8 u).
@export var corner_lift_u: int = 8
## Corner correction around ceiling corners (6 u), vertical and sideways.
@export var corner_slide_u: int = 6

@export_group("Jump")
## Jump velocity (900 u/s: a full hold reaches 176 u).
@export var jump_speed_ups: int = 900
## Frames before a released jump starts to cut (4 f).
@export var jump_min_frames: int = 4
## Gravity multiplier after an early release, until the apex (4.5x), per-mille.
@export var jump_release_gravity_permille: int = 4500
## Gravity while rising (2400 u/s^2).
@export var gravity_rise_ups2: int = 2400
## Gravity while falling (3000 u/s^2).
@export var gravity_fall_ups2: int = 3000
## Gravity multiplier at the apex while jump is held (0.6x), per-mille.
@export var apex_hang_permille: int = 600
## Frames the apex hang lasts (4 f).
@export var apex_hang_frames: int = 4
## Terminal fall speed (1500 u/s).
@export var terminal_ups: int = 1500
## Frames after walking off a ledge that still allow a ground jump (6 f).
@export var coyote_frames: int = 6
## Frames a jump press is remembered before landing (8 f).
@export var jump_buffer_frames: int = 8
## Frames a dash or attack press is remembered while it cannot start yet (BUILD.md feel rules:
## "Buffers are generous (8 f)").
@export var dash_buffer_frames: int = 8
@export var attack_buffer_frames: int = 8
## Air jumps per airtime (Ash: 1).
@export var air_jumps: int = 1
## Air jump velocity as a percent of the ground jump (85%).
@export var air_jump_percent: int = 85
## Frames from 0 to max horizontal speed in the air (8 f).
@export var air_accel_frames: int = 8
## Frames from max horizontal speed to 0 in the air with the stick neutral.
@export var air_decel_frames: int = 8

@export_group("Dash")
## Dash distance (180 u) over [member dash_frames] (9 f).
@export var dash_distance_u: int = 180
@export var dash_frames: int = 9
## Carry-over after the dash (3 f at 50%).
@export var dash_carry_frames: int = 3
@export var dash_carry_percent: int = 50
## Invulnerable dash frames, inclusive (1 to 7 of 9).
@export var dash_invuln_first: int = 1
@export var dash_invuln_last: int = 7
## Frames from one ground dash's start to the next (24 f).
@export var dash_ground_cooldown_frames: int = 24
## Air dashes per airtime (1).
@export var air_dashes: int = 1
## Dash frames, inclusive, during which a jump keeps the dash's horizontal speed (5 to 9).
@export var dash_jump_first: int = 5
@export var dash_jump_last: int = 9
## Horizontal dash speed a dash-jump keeps (100%).
@export var dash_jump_keep_percent: int = 100
## First dash frame an attack may cancel the dash (6).
@export var dash_attack_cancel_from: int = 6

@export_group("Wall")
## Wall-cling slide speed (180 u/s) and how long the slide lasts (90 f).
@export var wall_slide_ups: int = 180
@export var wall_slide_frames: int = 90
## How far from a wall a falling player who never clung can still wall-jump off it (not in
## BUILD.md; feel value: 3 u never reaches across a gap).
@export var wall_jump_reach_u: int = 3
## Wall coyote time: frames after letting go of a cling (stick released or pushed away, or slid
## off the wall's end) in which a jump still pushes off that wall (not in BUILD.md; feel value,
## the ground's 6 f coyote time).
@export var wall_coyote_frames: int = 6
## Wall-jump holding away: velocity up and away (794, 480 u/s) and the direction lock (5 f).
@export var wall_jump_up_ups: int = 794
@export var wall_jump_away_ups: int = 480
@export var wall_jump_lock_frames: int = 5
## Neutral wall-kick: up and away (900, 240 u/s).
@export var wall_kick_up_ups: int = 900
@export var wall_kick_away_ups: int = 240
## Frames the kick's push away is kept before the stick steers again (not in BUILD.md: 1 frame,
## so the kick visibly leaves the wall before the player steers back to it).
@export var wall_kick_lock_frames: int = 1
## Automatic ledge-grab within this distance of a wall's top (10 u).
@export var ledge_grab_u: int = 10

@export_group("Pogo")
## Bounce velocity (794 u/s); horizontal speed is preserved.
@export var pogo_bounce_ups: int = 794
## The frame after a bounce (the bounce is frame 1) from which the next down-strike can start
## (BUILD.md: frame 6).
@export var pogo_chain_frame: int = 6


## Compiled sub-pixel values. See [MovementParams]. [param run_speed_bonus_permille] is the run
## speed the run's Votives add, per-mille of [member run_speed_ups] (docs/adr/0015): the most the
## Wick runs at, on the ground and in the air; the acceleration and deceleration times are kept,
## so they scale with it, and the turnaround and the landing follow it. Nothing else moves.
func compile(run_speed_bonus_permille: int = 0) -> MovementParams:
	var p := MovementParams.new()
	p.half_w = Fx.units(width_u) / 2
	p.height = Fx.units(height_u)
	p.crouch_height = Fx.units(crouch_height_u)
	p.stick_threshold = stick_threshold
	# Fx.speed with the bonus inside the one rounding: with no bonus it is Fx.speed exactly.
	p.run_speed = Fx.div_round(
		run_speed_ups * Fx.SUB * (1000 + run_speed_bonus_permille), Fx.HZ * 1000
	)
	p.run_accel = Fx.per_tick(p.run_speed, run_accel_frames)
	p.run_decel = Fx.per_tick(p.run_speed, run_decel_frames)
	p.turn_keep_percent = turn_keep_percent
	p.turn_frames = turn_frames
	p.corner_lift = Fx.units(corner_lift_u)
	p.corner_slide = Fx.units(corner_slide_u)
	p.jump_speed = Fx.speed(jump_speed_ups)
	p.jump_min_frames = jump_min_frames
	p.gravity_rise = Fx.accel(gravity_rise_ups2)
	p.gravity_fall = Fx.accel(gravity_fall_ups2)
	p.release_gravity = Fx.permille(p.gravity_rise, jump_release_gravity_permille)
	p.apex_hang_permille = apex_hang_permille
	p.apex_hang_frames = apex_hang_frames
	# The hang window is the speed band the hung gravity crosses in apex_hang_frames frames,
	# centred on zero velocity.
	p.apex_hang_speed = Fx.permille(p.gravity_rise, apex_hang_permille) * apex_hang_frames / 2
	# The hang starts on the rising frame that puts the apex nearest its middle: the first frame
	# whose speed is within the band plus half a full-gravity step (docs/adr/0010).
	p.apex_hang_start = p.apex_hang_speed + p.gravity_rise / 2
	p.terminal = Fx.speed(terminal_ups)
	p.coyote_frames = coyote_frames
	p.jump_buffer_frames = jump_buffer_frames
	p.dash_buffer_frames = dash_buffer_frames
	p.attack_buffer_frames = attack_buffer_frames
	p.air_jumps = air_jumps
	p.air_jump_speed = Fx.percent(p.jump_speed, air_jump_percent)
	p.air_accel = Fx.per_tick(p.run_speed, air_accel_frames)
	p.air_decel = Fx.per_tick(p.run_speed, air_decel_frames)
	p.dash_speed = Fx.per_tick(Fx.units(dash_distance_u), dash_frames)
	p.dash_frames = dash_frames
	p.dash_carry_frames = dash_carry_frames
	p.dash_carry_percent = dash_carry_percent
	p.dash_invuln_first = dash_invuln_first
	p.dash_invuln_last = dash_invuln_last
	p.dash_ground_cooldown = dash_ground_cooldown_frames
	p.air_dashes = air_dashes
	p.dash_jump_first = dash_jump_first
	p.dash_jump_last = dash_jump_last
	p.dash_jump_keep_percent = dash_jump_keep_percent
	p.dash_attack_cancel_from = dash_attack_cancel_from
	p.wall_slide_speed = Fx.speed(wall_slide_ups)
	p.wall_slide_frames = wall_slide_frames
	p.wall_jump_reach = Fx.units(wall_jump_reach_u)
	p.wall_coyote_frames = wall_coyote_frames
	p.wall_jump_up = Fx.speed(wall_jump_up_ups)
	p.wall_jump_away = Fx.speed(wall_jump_away_ups)
	p.wall_jump_lock = wall_jump_lock_frames
	p.wall_kick_up = Fx.speed(wall_kick_up_ups)
	p.wall_kick_away = Fx.speed(wall_kick_away_ups)
	p.wall_kick_lock = wall_kick_lock_frames
	p.ledge_grab = Fx.units(ledge_grab_u)
	p.pogo_bounce = Fx.speed(pogo_bounce_ups)
	p.pogo_chain_frame = pogo_chain_frame
	return p


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if width_u <= 0 or width_u % 2 != 0:
		e.append("width_u must be positive and even")
	if crouch_height_u <= 0 or crouch_height_u >= height_u:
		e.append("crouch_height_u must be positive and below height_u")
	if stick_threshold < 1 or stick_threshold > InputFrame.STICK_MAX:
		e.append("stick_threshold must be in 1..%d" % InputFrame.STICK_MAX)
	var frame_counts: Array[int] = [
		run_accel_frames, run_decel_frames, air_accel_frames, air_decel_frames, dash_frames
	]
	if frame_counts.min() < 1 or jump_min_frames < 1:
		e.append("frame counts must be at least 1")
	for buffer: int in [jump_buffer_frames, dash_buffer_frames, attack_buffer_frames]:
		if buffer < 1 or buffer > InputRing.HISTORY:
			e.append("input buffers must be 1 to the input ring's %d frames" % InputRing.HISTORY)
			break
	if wall_coyote_frames < 0 or wall_jump_reach_u < 0:
		e.append("wall coyote and reach must not be negative")
	if pogo_chain_frame < 1:
		e.append("pogo_chain_frame must be at least 1")
	if (
		dash_invuln_first < 1
		or dash_invuln_last > dash_frames
		or dash_invuln_first > dash_invuln_last
	):
		e.append("dash invulnerability must lie inside the dash")
	if dash_jump_first < 1 or dash_jump_last > dash_frames or dash_jump_first > dash_jump_last:
		e.append("dash-jump window must lie inside the dash")
	if gravity_fall_ups2 <= 0 or gravity_rise_ups2 <= 0 or terminal_ups <= 0:
		e.append("gravity and terminal velocity must be positive")
	if corner_lift_u > ledge_grab_u:
		e.append("ledge_grab_u must be at least corner_lift_u")
	return e
