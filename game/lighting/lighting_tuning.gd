class_name LightingTuning
extends Resource
## The numbers of the lighting pass (BUILD.md section 10, Lighting: "the player's ember (radius 420
## u
## at base, warm 2400 K, flicker at 0.5 Hz with ±4% amplitude)", "2D ray-marched soft shadows from
## the ember against the collision layer", "a per-zone ambient color multiplied by the Wane Clock's
## darkness factor ... At Pitch, ambient is 0.15 and the world is the ember"; docs/adr/0023
## Decisions 3 and 4). Presentation only: the core never reads it. The other light kinds are
## [LightKind] sub-resources here; every number is in content/lighting.tres.

const PATH: String = "res://content/lighting.tres"
## The shadow profiles (BUILD.md section 12: "lighting pass at 0.75x / 0.5x"): the buffer's scale
## and
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
## The key light of a room that gives none: x and y toward the key (upper left), z its strength at
## Dusk (it fades with the Dark to nothing at Pitch: [method key_share]).
@export var key_dir: Vector2 = Vector2(-0.6, -0.8)
@export var key_strength: float = 0.5

@export_group("Shape of the light (wane_shape, wane_gate)")
## 0.35 + 0.65 N.L: the share of a light that a surface keeps whatever way it faces.
@export var flat_share: float = 0.35
## How far a wall's edge normals tilt toward the open (0 flat, 1 the full bevel).
@export var bevel_tilt: float = 0.95
## How far into a wall that bevel reaches, in world units (the lit grey boxes' tiles,
## shaders/lighting/lit_flat.gdshader).
@export var wall_bevel_u: float = 6.0
## The lowest elevation, in degrees above the picture plane, that the key and every light's form
## direction stands at: a flat surface faces a light at this angle however far the light is, so
## the two values follow a shape's tilt and not a ring of distance (docs/adr/0026).
@export var form_elevation_deg: float = 40.0
## The width, in u, of the Gutter Ember's edge between lit above it and dark below.
@export var up_only_soft_u: float = 8.0
## The energy of direct light (before N.L) under which a surface is in its shadow value, and over
## which the light has reached it.
@export var gate_lo: float = 0.05
@export var gate_hi: float = 0.15
## A fire's flicker phase per u of x and y, so that two fires do not flicker together.
@export var flicker_phase_per_u: Vector2 = Vector2(0.013, 0.007)

@export_group("Glow")
## Every light draws a soft halo over the ink (the ember is a bloom, not a dot): its radius is this
## share of the light's reach, never under glow_min_u, its strength this share of its energy, and
## the halo falls off as a power of its distance.
@export var glow_radius_share: float = 0.05
@export var glow_min_u: float = 3.0
@export var glow_strength: float = 0.5
@export var glow_falloff: float = 2.0

@export_group("Shadows")
## The march (section 10: 2D ray-marched soft shadows).
@export var max_steps: int = 48
@export var min_step_u: float = 1.5
## The ember's radius as an area light, for the penumbra.
@export var light_r_u: float = 14.0
## The penumbra radius of a light set close to a surface: a light's penumbra radius is held within
## its clearance from the nearest surface (so a light low over a floor does not shadow its own
## pool), but never under this, in world units.
@export var light_r_min_u: float = 2.0
## A wall's lit skin: a pixel inside a wall is lit, fading out, within this depth of its nearest
## face (the field's depth, square to the face) where that face sees the light, and black beyond.
@export var skin_u: float = 14.0
## The room's distance field is baked at this many world units a texel.
@export var sdf_texel_u: float = 4.0
## How far past a room's edge its solid border reaches, in world units.
@export var border_u: float = 64.0
## How many rooms' distance fields are kept (the ones used longest ago are let go beyond this).
@export var fields_kept: int = 16
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
@export var bloom_radius_u: float = 14.0
## The weights of the bloom's centre tap and of each of its ring's eight.
@export var bloom_core: float = 0.2
@export var bloom_ring: float = 0.1
## The brightness above which the shoulder rolls the top of the range off (hue kept).
@export var shoulder_knee: float = 0.8
@export var grain: float = 0.012
## The vignette's darkening, where it starts and where it is whole (as the distance from the
## screen's centre, 0 to about 0.7), and how much the screen's height counts for.
@export var vignette: float = 0.22
@export var vignette_start: float = 0.26
@export var vignette_end: float = 0.74
@export var vignette_squash: float = 0.8
## What the stand-in emissives (VFX, telegraphs, fire) are multiplied by to read as light.
@export var emissive_boost: float = 1.5


## The Dark factor at Wane Clock level [param d] (docs/adr/0023 Decision 3.5).
func dark_factor(d: float) -> float:
	return maxf(dark_floor, 1.0 - dark_slope * (d - 1.0))


## The share of its strength the room's key keeps at Dark factor [param factor]: 1 at Dusk, falling
## to 0 at the Dark's floor. The key is the world's light; at Pitch "only the ember and Beacons cast
## light" (BUILD.md section 8) while the ambient keeps its floor (section 10: "At Pitch, ambient is
## 0.15 and the world is the ember").
func key_share(factor: float) -> float:
	return clampf((factor - dark_floor) / maxf(1.0 - dark_floor, 0.0001), 0.0, 1.0)


## The ember's energy at [param seconds] of play, with the flicker.
func energy_at(seconds: float) -> float:
	return ember_energy * (1.0 + flicker_amplitude * sin(TAU * flicker_hz * seconds))


## The ember's colour: the black body at [member ember_kelvin].
func ember_colour() -> Color:
	var c: Color = LightKind.kelvin_colour(ember_kelvin)
	c.a = 1.0
	return c


## wane_shape: flat_share, bevel_tilt, form elevation in radians, up_only_soft_u.
func shape_vec() -> Vector4:
	return Vector4(flat_share, bevel_tilt, deg_to_rad(form_elevation_deg), up_only_soft_u)


## wane_gate.
func gate_vec() -> Vector2:
	return Vector2(gate_lo, gate_hi)


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
	if skin_u <= 0.0 or light_r_min_u <= 0.0 or light_r_min_u > light_r_u:
		e.append("skin_u must be positive and light_r_min_u above 0 and at most light_r_u")
	if sdf_texel_u < 1.0 or sdf_texel_u > 16.0:
		e.append("sdf_texel_u must be 1 to 16")
	if fields_kept < 3:
		e.append("fields_kept must be at least 3 (the room on show and its neighbours)")
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
	if bloom_strength < 0.0 or bloom_radius_u <= 0.0 or grain < 0.0 or vignette < 0.0:
		e.append("the post numbers must not be negative and the bloom radius must be positive")
	if bloom_core < 0.0 or bloom_ring < 0.0 or shoulder_knee <= 0.0 or shoulder_knee >= 1.0:
		e.append("bloom_core and bloom_ring must not be negative, shoulder_knee must be 0 to 1")
	if vignette_start < 0.0 or vignette_end <= vignette_start or vignette_squash <= 0.0:
		e.append("vignette_start must not be negative and below vignette_end, squash positive")
	if flat_share < 0.0 or flat_share > 1.0 or bevel_tilt < 0.0 or bevel_tilt > 1.0:
		e.append("flat_share and bevel_tilt must be 0 to 1")
	if wall_bevel_u <= 0.0:
		e.append("wall_bevel_u must be positive")
	if form_elevation_deg < 5.0 or form_elevation_deg > 85.0 or up_only_soft_u <= 0.0:
		e.append("form_elevation_deg must be 5 to 85 and up_only_soft_u positive")
	if gate_lo < 0.0 or gate_hi <= gate_lo:
		e.append("gate_lo must not be negative and be below gate_hi")
	if glow_radius_share < 0.0 or glow_min_u < 0.0 or glow_strength < 0.0 or glow_falloff < 0.5:
		e.append("the glow numbers must not be negative and glow_falloff must be at least 0.5")
	if emissive_boost < 1.0:
		e.append("emissive_boost must be at least 1")
	for k: LightKind in [beacon, fire, gutter_ember, eye]:
		if k == null:
			e.append("a light kind is missing")
		else:
			e.append_array(k.validate())
	return e
