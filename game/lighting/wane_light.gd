class_name WaneLight
extends RefCounted
## One light in the world (docs/adr/0023 Decision 3.1): a position, a [LightKind] that says what it
## is, and the few things that differ per light. The [LightField] owns the table these are written
## into. A Beacon, a fire, a Gutter Ember or an enemy's eye is a WaneLight made from its kind; the
## ember is the first. Presentation only: the core never reads it.

var kind: LightKind
## Where it is, in world units.
var position: Vector2 = Vector2.ZERO
## Overrides: a radius or an energy scale other than the kind's, and a phase so that two fires of
## one kind do not flicker together.
var radius_u: float = 0.0
var energy_scale: float = 1.0
var phase: float = 0.0
var enabled: bool = true
## Overrides the kind's colour (an enemy's eye is the colour its sheet says), if its alpha is above
## 0.
var colour_override: Color = Color(0, 0, 0, 0)


func _init(p_kind: LightKind, p_position: Vector2 = Vector2.ZERO) -> void:
	kind = p_kind
	position = p_position
	radius_u = p_kind.radius_u


## The light's colour.
func colour() -> Color:
	return colour_override if colour_override.a > 0.0 else kind.colour()


## The energy at [param seconds] of play: the kind's, with its flicker, times the scale.
func energy_at(seconds: float) -> float:
	return kind.energy_at(seconds, phase) * energy_scale
