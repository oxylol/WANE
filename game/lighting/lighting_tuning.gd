class_name LightingTuning
extends Resource
## The numbers of the Phase 1 stand-in lighting (BUILD.md section 10, Lighting: "the player's
## ember (radius 420 u at base, warm 2400 K, flicker at 0.5 Hz with ±4% amplitude)", "2D soft
## shadows from the ember against the collision layer", "At Pitch, ambient is 0.15 and the world
## is the ember"). Presentation only: the core never reads it. Phase 2 task 1 replaces the pass
## (normal maps, emissive maps, ambient times the Wane Clock's Dark factor) and keeps these
## numbers where BUILD.md fixes them.

const PATH: String = "res://content/lighting.tres"

@export_group("Ember")
## Radius of the ember's light in world units (section 10: 420 u at base).
@export var ember_radius_u: float = 420.0
## Brightness of the ember at its centre: Light2D energy.
@export var ember_energy: float = 1.6
## Warm 2400 K as a colour (a black-body at 2400 K is a deep amber).
@export var ember_colour: Color = Color(1.0, 0.66, 0.36)
## The ember's flicker: a sine at this rate and this share of the energy, either way.
@export var flicker_hz: float = 0.5
@export var flicker_amplitude: float = 0.04
## How the light falls off with distance: brightness (1 - d / radius) to this power. Above 1 puts
## the weight near the ember and lets the edge fade out softly.
@export var falloff_power: float = 1.6
## Side of the generated light texture in pixels (it is built in code, not imported).
@export var texture_px: int = 256
## The ember's height above the canvas (Light2D.height), for Phase 2's normal maps; 0 lights the
## flat grey boxes.
@export var ember_height_px: float = 0.0

@export_group("Shadows")
## Edge softness of the shadows: Light2D shadow filter, 0 none, 1 PCF5, 2 PCF13.
@export var shadow_filter: int = 1
## Softness of that filter in pixels.
@export var shadow_smooth: float = 2.0
## How far past a room's edge the room-border occluders reach (the solid beyond the room, so
## the ember does not light outside the room through its walls), in world units.
@export var border_u: float = 64.0

@export_group("Ambient")
## Pitch ambient (section 10: "At Pitch, ambient is 0.15"), the share of full light the world
## keeps with no light on it.
@export var pitch_ambient: float = 0.15
## The zone's ambient tint, multiplied by the ambient share. A cold blue-grey.
@export var ambient_tint: Color = Color(0.78, 0.84, 1.0)


## Ambient colour at Pitch: the tint times 0.15.
func pitch_colour() -> Color:
	var c: Color = ambient_tint * pitch_ambient
	c.a = 1.0
	return c


## The ember's energy at [param seconds] of play, with the flicker.
func energy_at(seconds: float) -> float:
	return ember_energy * (1.0 + flicker_amplitude * sin(TAU * flicker_hz * seconds))


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if ember_radius_u <= 0.0 or ember_energy <= 0.0:
		e.append("the ember's radius and energy must be positive")
	if pitch_ambient < 0.0 or pitch_ambient > 1.0:
		e.append("pitch_ambient must be 0 to 1")
	if flicker_hz < 0.0 or flicker_amplitude < 0.0 or flicker_amplitude >= 1.0:
		e.append("the flicker rate must not be negative and its amplitude must be 0 to 1")
	if falloff_power < 0.5 or falloff_power > 6.0:
		e.append("falloff_power must be 0.5 to 6")
	if texture_px < 64 or texture_px > 1024:
		e.append("texture_px must be 64 to 1024")
	if shadow_filter < 0 or shadow_filter > 2 or shadow_smooth < 0.0:
		e.append("shadow_filter must be 0 to 2 and shadow_smooth must not be negative")
	if border_u < 1.0:
		e.append("border_u must be at least 1")
	return e
