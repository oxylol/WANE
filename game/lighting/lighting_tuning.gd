class_name LightingTuning
extends Resource
## The numbers of the lighting pass (BUILD.md section 10, Lighting: "the player's ember (radius 420 u
## at base, warm 2400 K, flicker at 0.5 Hz with ±4% amplitude)", "2D ray-marched soft shadows from
## the ember against the collision layer", "a per-zone ambient color multiplied by the Wane Clock's
## darkness factor ... At Pitch, ambient is 0.15 and the world is the ember"; docs/adr/0023
## Decisions 3 and 4). Presentation only: the core never reads it. The other light kinds are
## [LightKind] sub-resources here; every number is in content/lighting.tres.

const PATH: String = "res://content/lighting.tres"
## The shadow profiles (BUILD.md section 12: "lighting pass at 0.75x / 0.5x"): the buffer's scale and
## how many lights cast.
const PROFILE_PC: int = 0
const PROFILE_DECK: int = 1
const PROFILE_MIN: int = 2

@export_group("Ember")
## Radius of the ember's light in world units (section 10: 420 u at base).
@export var ember_radius_u: float = 420.0
## Brightness of the ember at its centre.
@export var ember_energy: float = 1.6
## Colour temperature of the ember (section 10: warm 2400 K).
@export var ember_kelvin: float = 2400.0
## The ember's flicker: a sine at this rate and this share of the energy, either way.
@export var flicker_hz: float = 0.5
@export var flicker_amplitude: float = 0.04
## How the light falls off with distance: brightness (1 - d / radius) to this power.
@export var falloff_power: float = 1.6

@export_group("Lights")
## The height of a light above the surfaces it lights, in world units: low enough that the ember
## rakes across bevels.
@export var light_height_u: float = 40.0
## The lights the table holds (the shader's WANE_MAX_LIGHTS is 16).
@export var max_lights: int = 16
@export var beacon: LightKind
@export var fire: LightKind
@export var gutter_ember: LightKind
@export var eye: LightKind

@export_group("Ambient and the Dark")
## The zone's ambient colour when a zone gives none (a cold bruise violet, in sRGB). The zone's
## own, from its resource, replaces it.
@export var ambient_colour: Color = Color(0.62, 0.56, 0.72, 1)
## The Dark factor, 1 - slope * (D - 1), never below the floor (docs/adr/0023 Decision 3.5): 1.0 at
## D = 1, about 0.68 at Gloam, the floor from D = 2.6 (Pitch). The floor is "At Pitch, ambient is
## 0.15".
@export var dark_slope: float = 0.53
@export var dark_floor: float = 0.15
## The key light of a room that gives none: x and y toward the key (upper left), z its strength.
@export var key_dir: Vector2 = Vector2(-0.6, -0.8)
@export var key_strength: float = 0.5

@export_group("Shadows")
## The march (section 10: 2D ray-marched soft shadows).
@export var max_steps: int = 48
@export var min_step_u: float = 1.5
## The ember's radius as an area light, for the penumbra.
@export var light_r_u: float = 8.0
## A wall's lit skin: a pixel inside a wall is lit, fading out, within this depth of a face turned
## to the light, and black beyond.
@export var skin_u: float = 14.0
## How many steps a pixel inside a wall walks toward the light looking for its face.
@export var wall_walk_steps: int = 12
## The room's distance field is baked at this many world units a texel.
@export var sdf_texel_u: float = 4.0
## How far past a room's edge its solid border reaches, in world units.
@export var border_u: float = 64.0
## The shadow buffer's scale by profile, and the lights that cast on the minimum profile.
@export var shadow_scale_pc: float = 1.0
@export var shadow_scale_deck: float = 0.75
@export var shadow_scale_min: float = 0.5
@export var casters_min: int = 3
## A Clinger is revealed when the ember's light reaches it (visibility times attenuation) by at
## least this, for 30 ticks before it drops (BUILD.md section 15). A starting value: the Clinger's
## own task sets its drop distance.
@export var reveal_threshold: float = 0.1

@export_group("Time")
## The boil: the ink's wobble reseeds this many times a second (docs/adr/0023 Decision 2.2).
@export var boil_hz: float = 12.0

@export_group("Post")
## Bloom above this brightness (emissives exceed 1.0 in the HDR 2D pass), its strength and reach.
@export var bloom_threshold: float = 1.0
@export var bloom_strength: float = 0.55
@export var bloom_radius_px: float = 14.0
@export var grain: float = 0.012
@export var vignette: float = 0.22
## What the stand-in emissives (VFX, telegraphs, fire) are multiplied by to read as light.
@export var emissive_boost: float = 1.5


## The Dark factor at Wane Clock level [param d] (docs/adr/0023 Decision 3.5).
func dark_factor(d: float) -> float:
	return maxf(dark_floor, 1.0 - dark_slope * (d - 1.0))


## The ember's energy at [param seconds] of play, with the flicker.
func energy_at(seconds: float) -> float:
	return ember_energy * (1.0 + flicker_amplitude * sin(TAU * flicker_hz * seconds))


## The ember's colour: the black body at [member ember_kelvin].
func ember_colour() -> Color:
	var c: Color = LightKind.kelvin_colour(ember_kelvin)
	c.a = 1.0
	return c


## The scale of the shadow buffer on [param profile].
func shadow_scale(profile: int) -> float:
	match profile:
		PROFILE_DECK:
			return shadow_scale_deck
		PROFILE_MIN:
			return shadow_scale_min
	return shadow_scale_pc


## How many lights cast shadows on [param profile] (the buffer has four channels).
func casters(profile: int) -> int:
	return casters_min if profile == PROFILE_MIN else 4


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if ember_radius_u <= 0.0 or ember_energy <= 0.0:
		e.append("the ember's radius and energy must be positive")
	if ember_kelvin < 1000.0 or ember_kelvin > 40000.0:
		e.append("ember_kelvin must be 1000 to 40000")
	if dark_floor < 0.0 or dark_floor > 1.0 or dark_slope <= 0.0:
		e.append("dark_floor must be 0 to 1 and dark_slope must be positive")
	if flicker_hz < 0.0 or flicker_amplitude < 0.0 or flicker_amplitude >= 1.0:
		e.append("the flicker rate must not be negative and its amplitude must be 0 to 1")
	if falloff_power < 0.5 or falloff_power > 6.0:
		e.append("falloff_power must be 0.5 to 6")
	if light_height_u <= 0.0 or max_lights < 1 or max_lights > 16:
		e.append("light_height_u must be positive and max_lights 1 to 16")
	if max_steps < 4 or max_steps > 128 or min_step_u <= 0.0 or light_r_u <= 0.0:
		e.append("max_steps must be 4 to 128, min_step_u and light_r_u positive")
	if skin_u <= 0.0 or wall_walk_steps < 1 or wall_walk_steps > 32:
		e.append("skin_u must be positive and wall_walk_steps 1 to 32")
	if sdf_texel_u < 1.0 or sdf_texel_u > 16.0:
		e.append("sdf_texel_u must be 1 to 16")
	if border_u < 1.0:
		e.append("border_u must be at least 1")
	for s: float in [shadow_scale_pc, shadow_scale_deck, shadow_scale_min]:
		if s < 0.25 or s > 1.0:
			e.append("shadow scales must be 0.25 to 1")
	if casters_min < 1 or casters_min > 4:
		e.append("casters_min must be 1 to 4")
	if reveal_threshold <= 0.0 or reveal_threshold > 1.0:
		e.append("reveal_threshold must be above 0 and at most 1")
	if boil_hz <= 0.0:
		e.append("boil_hz must be positive")
	if bloom_strength < 0.0 or bloom_radius_px <= 0.0 or grain < 0.0 or vignette < 0.0:
		e.append("the post numbers must not be negative and the bloom radius must be positive")
	if emissive_boost < 1.0:
		e.append("emissive_boost must be at least 1")
	for k: LightKind in [beacon, fire, gutter_ember, eye]:
		if k == null:
			e.append("a light kind is missing")
		else:
			e.append_array(k.validate())
	return e
