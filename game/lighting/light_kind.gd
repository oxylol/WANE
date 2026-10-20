class_name LightKind
extends Resource
## One kind of light in the lighting pass (BUILD.md section 10, Lighting: "the player's ember
## ..., Beacons (cool white, huge), enemy eyes (point lights, tiny), fire (orange, animated), the
## Ember in the Gutter (red, the only light that casts up)"; docs/adr/0023 Decision 3.1). A kind is
## data: a Beacon, a fire or an eye is a [WaneLight] made from one, so a new kind never touches
## code. The ember's own numbers are in [LightingTuning]. Presentation only: the core never reads
## it.

## The shadow channel of a light that casts no shadow.
const NO_SHADOW: int = -1
## Flicker shapes: steady, a slow sine (the ember, the Gutter Ember), or noise on the tick (fire).
const STEADY: int = 0
const SINE: int = 1
const NOISE: int = 2

@export var id: StringName = &""
## Radius of the light in world units.
@export var radius_u: float = 160.0
## Colour temperature in kelvin (the colour is the black body at it).
@export var kelvin: float = 6500.0
## Colour tint multiplied after the black body, for lights that are not white-balanced (the red of
## the Gutter Ember).
@export var tint: Color = Color(1, 1, 1, 1)
## Brightness at the centre.
@export var energy: float = 1.0
## Flicker: shape, rate in hertz and share of the energy either way.
@export_enum("steady", "sine", "noise") var flicker: int = STEADY
@export var flicker_hz: float = 0.0
@export var flicker_amplitude: float = 0.0
## Shadow-buffer channel 0 to 3 (the ember is 0), or -1 for a light that casts no shadow.
@export var shadow_channel: int = NO_SHADOW
## Whether it lights only points above it ("the only light that casts up").
@export var up_only: bool = false
## Falloff: brightness (1 - d / radius) to this power.
@export var falloff_power: float = 1.6
## Where it ranks when more lights than the table holds are in view: lower is kept first.
@export var priority: int = 4
## Height above the surface in world units; 0 uses the pass's [member
## LightingTuning.light_height_u].
@export var height_u: float = 0.0


## The black-body colour at [param k] kelvin (Tanner Helland's fit, 1000 to 40000 K): 2400 K gives
## (1.00, 0.61, 0.24).
static func kelvin_colour(k: float) -> Color:
	var t: float = clampf(k, 1000.0, 40000.0) / 100.0
	var r: float = 255.0
	var g: float = 0.0
	var b: float = 255.0
	if t > 66.0:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
	else:
		g = 99.4708025861 * log(t) - 161.1195681661
		b = 0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307
	return Color(
		clampf(r / 255.0, 0.0, 1.0), clampf(g / 255.0, 0.0, 1.0), clampf(b / 255.0, 0.0, 1.0), 1.0
	)


## The light's colour: the black body times the tint.
func colour() -> Color:
	var c: Color = kelvin_colour(kelvin)
	return Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, 1.0)


## The energy at [param seconds] of play for a light whose phase is [param phase]: steady, a sine,
## or two incommensurate sines standing in for fire's noise (deterministic from the tick: the pass
## has no clock of its own).
func energy_at(seconds: float, phase: float = 0.0) -> float:
	match flicker:
		SINE:
			return energy * (1.0 + flicker_amplitude * sin(TAU * flicker_hz * seconds + phase))
		NOISE:
			var w: float = (
				0.6 * sin(TAU * flicker_hz * seconds + phase)
				+ 0.4 * sin(TAU * flicker_hz * 2.37 * seconds + phase * 1.7 + 1.3)
			)
			return energy * (1.0 + flicker_amplitude * w)
	return energy


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if radius_u <= 0.0 or energy < 0.0:
		e.append("%s: the radius must be positive and the energy not negative" % id)
	if kelvin < 1000.0 or kelvin > 40000.0:
		e.append("%s: kelvin must be 1000 to 40000" % id)
	if flicker_hz < 0.0 or flicker_amplitude < 0.0 or flicker_amplitude >= 1.0:
		e.append("%s: the flicker rate must not be negative and its amplitude must be 0 to 1" % id)
	if shadow_channel < NO_SHADOW or shadow_channel > 3:
		e.append("%s: shadow_channel must be -1 to 3" % id)
	if falloff_power < 0.5 or falloff_power > 6.0:
		e.append("%s: falloff_power must be 0.5 to 6" % id)
	if height_u < 0.0:
		e.append("%s: height_u must not be negative" % id)
	return e
