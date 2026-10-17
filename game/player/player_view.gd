class_name PlayerView
extends Node2D
## Grey-box Ash: the collider coloured by state with a mark on the facing side, and the ember
## when it is out. Drawn between the last two simulation ticks (BUILD.md section 13: "Rendering
## interpolates between the last two simulation states"). A placeholder until the rig (Phase 2);
## it reads the core and never writes it.

const STATE_COLOURS: Dictionary[String, Color] = {
	"ground": Color(0.35, 0.70, 1.00),
	"air": Color(1.00, 0.85, 0.35),
	"dash": Color(1.00, 0.35, 0.85),
	"wall": Color(0.40, 1.00, 0.50),
}
const EMBER := Color(1.00, 0.55, 0.15)
const INVULNERABLE := Color(1.0, 1.0, 1.0, 0.5)

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


## Starts from [param sim]'s state with nothing to interpolate from.
func begin(sim: Simulation) -> void:
	capture(sim)
	_before = _after
	_ember_before = _ember_after


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
	# A teleport or a respawn moves the player in one tick: draw it there, not sliding there.
	if sim.events.has(SimEvents.TELEPORT) or sim.events.has(SimEvents.HAZARD):
		_before = _after


## Draws at [param alpha] (0..1) between the last two ticks.
func show_at(alpha: float) -> void:
	_alpha = alpha
	queue_redraw()


## The collider as drawn at [param alpha] between the last two ticks.
func box_at(alpha: float) -> Rect2:
	return Rect2(_before.position.lerp(_after.position, alpha), _after.size)


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
