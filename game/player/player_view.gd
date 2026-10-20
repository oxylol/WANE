class_name PlayerView
extends Node2D
## Grey-box Ash: the collider coloured by state with a mark on the facing side, and the ember
## when it is out. Drawn between the last two simulation ticks (BUILD.md section 13: "Rendering
## interpolates between the last two simulation states"). A corner-correction nudge is eased: on
## its tick the drawn player keeps moving as it was, then catches up with the collider, from rest
## over [member PlayerViewTuning.nudge_ease_frames] (BUILD.md section 15: "the corner-correction
## nudge is invisible"). It squashes on a landing and stretches at the top of a jump (BUILD.md
## section 10: squash on landing, 3 f, 110% wide; stretch at jump apex, 2 f, 94% wide; scaled by the
## vertical speed), anchored at the feet and drawn only: the collider, the camera and the lighting
## keep the true box ([method box_at]), and nothing waits for it. A placeholder until the rig
## (Phase 2); it reads the core and never writes it.

const STATE_COLOURS: Dictionary[String, Color] = {
	"ground": Color(0.35, 0.70, 1.00),
	"air": Color(1.00, 0.85, 0.35),
	"dash": Color(1.00, 0.35, 0.85),
	"wall": Color(0.40, 1.00, 0.50),
}
const EMBER := Color(1.00, 0.55, 0.15)
const INVULNERABLE := Color(1.0, 1.0, 1.0, 0.5)
const EYE := Color(0.1, 0.1, 0.12)

var tuning: PlayerViewTuning = load(PlayerViewTuning.PATH) as PlayerViewTuning

## The collider after the tick before the latest, and after the latest (units).
var _before: Rect2 = Rect2()
var _after: Rect2 = Rect2()
var _ember_before: Vector2 = Vector2.ZERO
var _ember_after: Vector2 = Vector2.ZERO
var _ember_out: bool = false
var _state: String = "ground"
var _facing: int = 1
var _invulnerable: bool = false
var _alpha: float = 1.0
## Where the drawn player sits relative to the collider while a nudge eases (units), after the
## tick before the latest and after the latest, and how fast it is closing that gap (units a
## tick, on each axis).
var _offset_before: Vector2 = Vector2.ZERO
var _offset_after: Vector2 = Vector2.ZERO
var _catch: Vector2 = Vector2.ZERO
## The largest nudge on each axis since the drawn player last met the collider: the run's nudge,
## which sets how hard it may catch up and how far it may fall behind.
var _run: Vector2 = Vector2.ZERO
## Ticks captured, for the squash's and the stretch's ages.
var _tick: int = 0
## The tick the squash and the stretch began on (or a tick long past), and how strongly, 0..1.
var _squash_tick: int = -1000
var _squash_amount: float = 0.0
var _stretch_tick: int = -1000
var _stretch_amount: float = 0.0
## The vertical speed after the tick before, whether the player was in the air then, and the
## fastest rise (sub-pixels a tick) since it left the ground.
var _vy_before: int = 0
var _was_air: bool = false
var _rise_peak: int = 0


## Starts from [param sim]'s state with nothing to interpolate from.
func begin(sim: Simulation) -> void:
	capture(sim)
	_before = _after
	_ember_before = _ember_after
	_stop_ease()
	_stop_shape()


## Takes the state after a tick.
func capture(sim: Simulation) -> void:
	var pl: Player = sim.player
	if pl == null:
		return
	var b: Body = pl.body
	_before = _after
	_after = Rect2(
		float(b.left()) / Fx.SUB,
		float(b.top()) / Fx.SUB,
		float(b.right() - b.left()) / Fx.SUB,
		float(b.height) / Fx.SUB
	)
	var was_out: bool = _ember_out
	_ember_out = pl.toss.active
	_ember_before = _ember_after
	_ember_after = Vector2(float(pl.toss.x) / Fx.SUB, float(pl.toss.y) / Fx.SUB)
	if not was_out:
		_ember_before = _ember_after
	_state = str(sim.probe("state"))
	_facing = pl.facing
	_invulnerable = pl.invuln > 0
	_ease_nudge(Vector2(-b.nudge_x, -b.nudge_y) / Fx.SUB)
	_note_shape(sim, pl)
	# A teleport, a respawn (a hazard's, or a lethal hit's: the player is sent back to the room's
	# spawn on that tick) or a door moves the player in one tick: draw it there, not sliding
	# there (task 5 review 3, M2).
	if (
		sim.events.has(SimEvents.TELEPORT)
		or sim.events.has(SimEvents.HAZARD)
		or sim.events.has(SimEvents.DEATH)
		or sim.events.has(SimEvents.ROOM)
	):
		_before = _after
		_stop_ease()
		_stop_shape()


## Starts the squash on a land event and the stretch at the end of a rise, from this tick's events
## and the player's vertical speed ([param sim] after the tick).
func _note_shape(sim: Simulation, pl: Player) -> void:
	_tick += 1
	var vy: int = pl.body.vy
	var in_air: bool = _state == "air"
	var landed: int = sim.events.kinds.find(SimEvents.LAND)
	if landed >= 0:
		var impact_ups: float = float(absi(sim.events.values[landed])) * Fx.HZ / Fx.SUB
		var span: float = float(tuning.landing_full_impact_ups - tuning.landing_min_impact_ups)
		var amount: float = clampf((impact_ups - tuning.landing_min_impact_ups) / span, 0.0, 1.0)
		if amount > 0.0:
			_squash_tick = _tick
			_squash_amount = amount
	if in_air and vy < 0:
		_rise_peak = maxi(_rise_peak, -vy)
	if _was_air and in_air and _vy_before < 0 and vy >= 0 and not pl.body.hit_ceiling:
		var rise_ups: float = float(_rise_peak) * Fx.HZ / Fx.SUB
		_stretch_tick = _tick
		_stretch_amount = clampf(rise_ups / float(tuning.apex_full_rise_ups), 0.0, 1.0)
	if not in_air or vy >= 0:
		_rise_peak = 0
	_vy_before = vy
	_was_air = in_air


func _stop_shape() -> void:
	_squash_amount = 0.0
	_stretch_amount = 0.0
	_squash_tick = -1000
	_stretch_tick = -1000
	_rise_peak = 0


func _stop_ease() -> void:
	_offset_before = Vector2.ZERO
	_offset_after = Vector2.ZERO
	_catch = Vector2.ZERO
	_run = Vector2.ZERO


## Advances the ease by a tick; [param nudge] is this tick's corner correction, reversed (where
## the collider was, from where it is). Each axis closes its gap with a speed that changes by at
## most a share of the run's nudge a tick (task 5 review 2, H1: an ease that moved the drawn
## player by a whole lip in one tick showed a staircase as a hop every few frames), braking so it
## meets the collider at rest:
## - from rest a nudge eases along a triangle of speeds over nudge_ease_frames (an 8 u lip over 3
##   frames: 2, 4 and 2 u), and on its own tick the drawn player moves only as it was moving;
## - a nudge arriving during an ease adds to what is left, and the speed carries on from where it
##   was, so up a staircase of lips the drawn player climbs steadily;
## - it never falls more than nudge_lag_percent of the run's nudge behind (the lag the speed's
##   limit alone would allow up a staircase dashed three lips a tick is twice the nudge).
func _ease_nudge(nudge: Vector2) -> void:
	_offset_before = _offset_after
	var share: float = _accel_share(tuning.nudge_ease_frames)
	var lag_max: float = float(tuning.nudge_lag_percent) / 100.0
	for axis: int in [0, 1]:
		var gap: float = _offset_after[axis]
		var speed: float = _catch[axis]
		if gap == 0.0:
			speed = 0.0
			_run[axis] = 0.0
		var accel: float = _run[axis] * share
		var want: float = signf(gap) * EaseMath.braking_speed(absf(gap), accel)
		speed = clampf(want, speed - accel, speed + accel)
		if speed * gap > 0.0 and absf(speed) > absf(gap):
			speed = gap
		gap -= speed
		if nudge[axis] != 0.0:
			_run[axis] = maxf(_run[axis], absf(nudge[axis]))
			gap += nudge[axis]
		var bound: float = _run[axis] * lag_max
		if absf(gap) > bound:
			speed += gap - signf(gap) * bound
			gap = signf(gap) * bound
		_offset_after[axis] = gap
		_catch[axis] = speed


## The share of the run's nudge the catch-up speed may change by in a tick: from rest, a nudge
## then eases in exactly [param frames] ticks along a triangle of speeds (for 3 frames 1, 2 and 1
## quarters of it).
static func _accel_share(frames: int) -> float:
	var half: int = frames / 2
	if frames % 2 == 1:
		return 1.0 / float((half + 1) * (half + 1))
	return 1.0 / float(half * (half + 1))


## Draws at [param alpha] (0..1) between the last two ticks.
func show_at(alpha: float) -> void:
	_alpha = alpha
	queue_redraw()


## The player as drawn at [param alpha] between the last two ticks: the collider, eased off any
## corner-correction nudge.
func box_at(alpha: float) -> Rect2:
	var box: Rect2 = collider_at(alpha)
	box.position += _offset_before.lerp(_offset_after, alpha)
	return box


## The collider at [param alpha] between the last two ticks, with no easing. The feet and the size
## are interpolated, so a crouch or a stand (the height changing in a tick) never floats or sinks
## the feet between ticks (task 5 review, L19).
func collider_at(alpha: float) -> Rect2:
	var size: Vector2 = _before.size.lerp(_after.size, alpha)
	var feet: Vector2 = Vector2(_before.get_center().x, _before.end.y).lerp(
		Vector2(_after.get_center().x, _after.end.y), alpha
	)
	return Rect2(feet - Vector2(size.x * 0.5, size.y), size)


## The drawn width and height factors at [param alpha] between the last two ticks: 1 at rest,
## wide and low through a landing's squash, narrow and tall through the apex's stretch, the area
## kept either way. The core's boxes are never scaled by it.
func scale_at(alpha: float) -> Vector2:
	var wide: float = 1.0
	var squash_t: float = (float(_tick - _squash_tick) - 1.0 + alpha) / tuning.landing_squash_frames
	if squash_t >= 0.0 and squash_t < 1.0:
		var drop: float = 1.0 - squash_t * squash_t * (3.0 - 2.0 * squash_t)
		wide *= (
			1.0 + (float(tuning.landing_squash_width_percent) / 100.0 - 1.0) * _squash_amount * drop
		)
	var stretch_t: float = (float(_tick - _stretch_tick) - 1.0 + alpha) / tuning.apex_stretch_frames
	if stretch_t >= 0.0 and stretch_t < 1.0:
		var swell: float = sin(PI * stretch_t)
		wide *= (
			1.0 - (1.0 - float(tuning.apex_stretch_width_percent) / 100.0) * _stretch_amount * swell
		)
	return Vector2(wide, 1.0 / wide)


## The player as drawn at [param alpha]: [method box_at] scaled by [method scale_at] about the
## middle of its feet.
func drawn_box_at(alpha: float) -> Rect2:
	var box: Rect2 = box_at(alpha)
	var size: Vector2 = box.size * scale_at(alpha)
	return Rect2(Vector2(box.get_center().x - size.x * 0.5, box.end.y - size.y), size)


func _draw() -> void:
	var box: Rect2 = drawn_box_at(_alpha)
	var k: Vector2 = scale_at(_alpha)
	var colour: Color = STATE_COLOURS.get(_state, Color.GRAY)
	draw_rect(box, colour)
	var eye := Vector2(tuning.eye_size_u, tuning.eye_size_u) * k
	var gap: float = tuning.eye_edge_gap_u * k.x
	var eye_x: float = box.end.x - gap - eye.x if _facing > 0 else box.position.x + gap
	draw_rect(Rect2(Vector2(eye_x, box.position.y + tuning.eye_drop_u * k.y), eye), EYE)
	if _invulnerable:
		draw_rect(box, INVULNERABLE, false, tuning.invulnerable_outline_u)
	if _ember_out:
		draw_circle(_ember_before.lerp(_ember_after, _alpha), tuning.ember_radius_u, EMBER)
