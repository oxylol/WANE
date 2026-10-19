class_name PlayerView
extends Node2D
## Grey-box Ash: the collider coloured by state with a mark on the facing side, and the ember
## when it is out. Drawn between the last two simulation ticks (BUILD.md section 13: "Rendering
## interpolates between the last two simulation states"). A corner-correction nudge is eased: on
## its tick the drawn player keeps moving as it was, then catches up with the collider over
## [member PlayerViewTuning.nudge_ease_frames] (BUILD.md section 15: "the corner-correction nudge
## is invisible"). A placeholder until the rig (Phase 2); it reads the core and never writes it.

const STATE_COLOURS: Dictionary[String, Color] = {
	"ground": Color(0.35, 0.70, 1.00),
	"air": Color(1.00, 0.85, 0.35),
	"dash": Color(1.00, 0.35, 0.85),
	"wall": Color(0.40, 1.00, 0.50),
}
const EMBER := Color(1.00, 0.55, 0.15)
const INVULNERABLE := Color(1.0, 1.0, 1.0, 0.5)

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
## tick before the latest and after the latest; the offset the ease started from, its speed then
## (units per tick) and the ticks since.
var _offset_before: Vector2 = Vector2.ZERO
var _offset_after: Vector2 = Vector2.ZERO
var _ease_from: Vector2 = Vector2.ZERO
var _ease_speed: Vector2 = Vector2.ZERO
var _ease_tick: int = 0
## The largest nudge on each axis since the drawn player last met the collider: the offset never
## exceeds it.
var _ease_cap: Vector2 = Vector2.ZERO


## Starts from [param sim]'s state with nothing to interpolate from.
func begin(sim: Simulation) -> void:
	capture(sim)
	_before = _after
	_ember_before = _ember_after
	_stop_ease()


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
	# A teleport or a respawn moves the player in one tick: draw it there, not sliding there.
	if sim.events.has(SimEvents.TELEPORT) or sim.events.has(SimEvents.HAZARD):
		_before = _after
		_stop_ease()


func _stop_ease() -> void:
	_offset_before = Vector2.ZERO
	_offset_after = Vector2.ZERO
	_ease_from = Vector2.ZERO
	_ease_speed = Vector2.ZERO
	_ease_cap = Vector2.ZERO
	_ease_tick = tuning.nudge_ease_frames


## Advances the ease by a tick; [param nudge] is this tick's corner correction, reversed (where
## the collider was, from where it is). The offset eases to nothing along a cubic over
## nudge_ease_frames: from rest it is a smoothstep; a nudge arriving while one eases adds to what
## is left and starts a new cubic from the speed the drawn player already has, so a run of nudges
## (a staircase of lips) is followed smoothly, never stalling at each one. The offset never
## exceeds the largest single nudge of the run on either axis: up a staircase the drawn player
## follows one lip behind at most rather than falling ever further back (task 5 review, H3).
func _ease_nudge(nudge: Vector2) -> void:
	_offset_before = _offset_after
	var frames: int = tuning.nudge_ease_frames
	if _ease_tick >= frames:
		_ease_cap = Vector2.ZERO
	_ease_tick = mini(_ease_tick + 1, frames)
	var now: Vector2 = _eased(_ease_tick)
	if nudge != Vector2.ZERO:
		_ease_cap = _ease_cap.max(nudge.abs())
		_ease_speed = _eased_speed(_ease_tick)
		_ease_from = (now + nudge).clamp(-_ease_cap, _ease_cap)
		_ease_tick = 0
		now = _ease_from
	_offset_after = now


## The offset [param k] ticks into the current ease: the Hermite cubic from the start offset and
## speed to nothing, at rest, at nudge_ease_frames.
func _eased(k: int) -> Vector2:
	var frames: int = tuning.nudge_ease_frames
	if k >= frames:
		return Vector2.ZERO
	var t: float = float(k) / frames
	var from: float = 2.0 * t * t * t - 3.0 * t * t + 1.0
	var speed: float = t * t * t - 2.0 * t * t + t
	return _ease_from * from + _ease_speed * (speed * frames)


## The offset's speed (units per tick) [param k] ticks into the current ease.
func _eased_speed(k: int) -> Vector2:
	var frames: int = tuning.nudge_ease_frames
	if k >= frames:
		return Vector2.ZERO
	var t: float = float(k) / frames
	var from: float = (6.0 * t * t - 6.0 * t) / frames
	var speed: float = 3.0 * t * t - 4.0 * t + 1.0
	return _ease_from * from + _ease_speed * speed


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


func _draw() -> void:
	var box: Rect2 = box_at(_alpha)
	var colour: Color = STATE_COLOURS.get(_state, Color.GRAY)
	draw_rect(box, colour)
	var eye_x: float = box.end.x - 6.0 if _facing > 0 else box.position.x + 2.0
	draw_rect(Rect2(eye_x, box.position.y + 6.0, 4.0, 4.0), Color(0.1, 0.1, 0.12))
	if _invulnerable:
		draw_rect(box, INVULNERABLE, false, 2.0)
	if _ember_out:
		draw_circle(_ember_before.lerp(_ember_after, _alpha), 6.0, EMBER)
