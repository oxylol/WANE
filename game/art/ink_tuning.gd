class_name InkTuning
extends Resource
## The numbers of the ink line and the gouache fill (BUILD.md section 10, Style; ADR-0023
## Decision 2.6). Starting values from the ADR's spike, not tuned: tuning follows CLAUDE.md, one
## number at a time with a feel-log entry. Presentation only: the core never reads it.
##
## The shaders read these as global shader parameters, packed in vec4s (game/art/ink_globals.gd
## writes them): wane_ink, wane_ink_wave, wane_fill, wane_fill_more (ADR-0023 Decision 7.2) and
## more for numbers the ADR's four left no room for: wane_ink_more, wane_ink_light, wane_ink_bg,
## wane_ink_extra (ADR-0026) and wane_ink_core (the emissive core, ADR-0026 addendum of the fix
## round 2b).

const PATH: String = "res://content/art/ink.tres"

@export_group("Line (wane_ink)")
## Line weight on the side of an edge that faces the light, in u (section 10: "hairline on the
## lit side").
@export var line_lit_u: float = 0.3
## Line weight on the side of an edge that faces away from the light, in u ("thick on the shadow
## side").
@export var line_shadow_u: float = 1.3
## The weight never falls below this many screen pixels: a 0.3 u hairline is 0.3 px at 1x.
@export var line_min_px: float = 0.8
## Amplitude of the two-octave wobble along the edge, in u.
@export var wobble_u: float = 0.32

@export_group("Wobble and edge (wane_ink_wave)")
## Wavelength of the wobble's first octave, in u (specified in u so a rescale does not make the
## edge hairy).
@export var wave1_u: float = 10.0
## Wavelength of the second octave, in u.
@export var wave2_u: float = 4.0
## How far from the line the fill darkens where it meets the line, in u.
@export var edge_dark_u: float = 1.0
## How much it darkens there (share of the value).
@export var edge_dark: float = 0.22

@export_group("Two values (wane_fill)")
## N.L (of the form direction, docs/adr/0026) a surface must reach, in a light's reach, to turn from
## its shadow value to its lit one. A surface facing the viewer reads sin(form elevation) there, so
## this sits below it: only a surface tilted away from the light turns to shadow.
@export var lit_threshold: float = 0.5
## Half-width of that turn in N.L: the terminator's softness.
@export var terminator_soft: float = 0.04
## How much the brush noise moves the terminator (a brush-edged terminator).
@export var brush_noise: float = 0.10
## How much the brush streaks move the value (share of it, either way).
@export var brush_strength: float = 0.12

@export_group("Brush, rim, paper (wane_fill_more)")
## Length of a brush streak against its width: the noise is stretched this much along the part's
## major axis.
@export var brush_stretch: float = 14.0
## Width of the rim band inside the silhouette that faces the light, in u.
@export var rim_u: float = 1.2
## Paper grain amplitude (share of the value, either way), in screen space.
@export var grain_strength: float = 0.07
## Width of the line on the back side of an interior edge, in u; 0 leaves only its anti-aliasing.
@export var back_line_u: float = 0.0

@export_group("Ink and emissive (wane_ink_more)")
## The ink's value: the part's shadow colour times this.
@export var ink_value: float = 0.18
## The line's weight at the very end of a shape, as a share of its full weight (the pressure
## taper's floor).
@export var taper_floor: float = 0.2
## Ink is never lighter than the fill it covers: it is held to this share of the fill.
@export var ink_over_fill: float = 0.6
## Brightness of an emissive region at full strength; above 1 so that the post pass can bloom it.
@export var emissive_gain: float = 3.0

@export_group("Line light (wane_ink_light)")
## n.l at which the line starts to thin (the edge faces the light from here).
@export var line_light_lo: float = -0.2
## n.l at which the line is fully on the lit side.
@export var line_light_hi: float = 0.4
## Light reaching a background's open line, as a share of the ember's energy, where it starts to
## drop out.
@export var bg_drop_lo: float = 0.15
## And where it is gone.
@export var bg_drop_hi: float = 0.55

@export_group("Smear and gloss (wane_ink_extra)")
## How opaque a smear is at the blade (1 is solid), and the power its opacity and line fall to
## nothing at along the arc toward the tail (the age channel, 0 tail to 1 blade).
@export var smear_opacity: float = 0.85
@export var smear_tail_pow: float = 1.5
## The sharpness of a glossy part's highlight (the power of N.H) and how strong it is.
@export var gloss_power: float = 24.0
@export var gloss_strength: float = 0.7

@export_group("Emissive core (wane_ink_core)")
## How deep into an emissive part (from its own outline, in u) its heat rises to the full: the ember
## is a hot core grading out to its edge, not a flat disc (BUILD.md section 10, The ember).
@export var emissive_core_u: float = 2.0
## How far the hottest core goes from the palette's emissive colour toward white (0 none, 1 white):
## the ember's "orange-white".
@export var emissive_core_white: float = 0.6

@export_group("Background line (wane_ink_bg)")
## The break mask's value below which the open line is at its thinnest.
@export var bg_break_lo: float = 0.42
## And above which it is whole.
@export var bg_break_hi: float = 0.5
## Weight of the open line inside a break, as a share of its full weight (0: a gap).
@export var bg_thin: float = 0.0
## Wavelength of the break mask, in u.
@export var bg_mask_wave_u: float = 48.0

## The boil rate (how many times a second the line's wobble is reseeded, ADR-0023 Decision 2.2) is
## `LightingTuning.boil_hz`: LightField writes `wane_boil` from it, so there is one number.


## wane_ink
func ink_vec() -> Vector4:
	return Vector4(line_lit_u, line_shadow_u, line_min_px, wobble_u)


## wane_ink_wave
func wave_vec() -> Vector4:
	return Vector4(wave1_u, wave2_u, edge_dark_u, edge_dark)


## wane_fill
func fill_vec() -> Vector4:
	return Vector4(lit_threshold, terminator_soft, brush_noise, brush_strength)


## wane_fill_more
func fill_more_vec() -> Vector4:
	return Vector4(brush_stretch, rim_u, grain_strength, back_line_u)


## wane_ink_more
func ink_more_vec() -> Vector4:
	return Vector4(ink_value, taper_floor, ink_over_fill, emissive_gain)


## wane_ink_light
func ink_light_vec() -> Vector4:
	return Vector4(line_light_lo, line_light_hi, bg_drop_lo, bg_drop_hi)


## wane_ink_extra
func extra_vec() -> Vector4:
	return Vector4(smear_opacity, smear_tail_pow, gloss_power, gloss_strength)


## wane_ink_core
func core_vec() -> Vector4:
	return Vector4(emissive_core_u, emissive_core_white, 0.0, 0.0)


## wane_ink_bg
func ink_bg_vec() -> Vector4:
	return Vector4(bg_break_lo, bg_break_hi, bg_thin, bg_mask_wave_u)


func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if line_lit_u < 0.0 or line_shadow_u < line_lit_u:
		e.append(
			"the shadow side's line must be at least as heavy as the lit side's, and not negative"
		)
	if line_min_px < 0.0 or line_min_px > 4.0:
		e.append("line_min_px must be 0 to 4")
	if wobble_u < 0.0 or wobble_u > 2.0:
		e.append("wobble_u must be 0 to 2")
	if wave1_u < 1.0 or wave2_u < 1.0 or wave2_u > wave1_u:
		e.append("the wobble wavelengths must be at least 1 u, the second no longer than the first")
	if edge_dark_u < 0.0 or edge_dark < 0.0 or edge_dark > 1.0:
		e.append("edge_dark_u must not be negative and edge_dark must be 0 to 1")
	if lit_threshold <= 0.0 or lit_threshold >= 1.0:
		e.append("lit_threshold must be between 0 and 1")
	if terminator_soft <= 0.0 or terminator_soft >= lit_threshold:
		e.append("terminator_soft must be positive and below lit_threshold")
	if brush_noise < 0.0 or brush_noise > 0.5 or brush_strength < 0.0 or brush_strength > 0.5:
		e.append("brush_noise and brush_strength must be 0 to 0.5")
	if brush_stretch < 1.0 or brush_stretch > 64.0:
		e.append("brush_stretch must be 1 to 64")
	if rim_u < 0.0 or grain_strength < 0.0 or grain_strength > 0.3 or back_line_u < 0.0:
		e.append("rim_u and back_line_u must not be negative, grain_strength must be 0 to 0.3")
	if ink_value < 0.0 or ink_value > 1.0:
		e.append("ink_value must be 0 to 1")
	if taper_floor < 0.0 or taper_floor > 1.0:
		e.append("taper_floor must be 0 to 1")
	if ink_over_fill < 0.0 or ink_over_fill > 1.0:
		e.append("ink_over_fill must be 0 to 1")
	if emissive_gain < 0.0 or emissive_gain > 16.0:
		e.append("emissive_gain must be 0 to 16")
	if line_light_hi <= line_light_lo or line_light_lo < -1.0 or line_light_hi > 1.0:
		e.append("line_light_lo must be below line_light_hi, both within -1 to 1")
	if bg_drop_hi <= bg_drop_lo or bg_drop_lo < 0.0:
		e.append("bg_drop_lo must be below bg_drop_hi and not negative")
	if bg_break_hi <= bg_break_lo or bg_break_lo < 0.0 or bg_break_hi > 1.0:
		e.append("bg_break_lo must be below bg_break_hi, both within 0 to 1")
	if smear_opacity <= 0.0 or smear_opacity > 1.0 or smear_tail_pow < 0.1 or smear_tail_pow > 8.0:
		e.append("smear_opacity must be above 0 and at most 1, smear_tail_pow 0.1 to 8")
	if gloss_power < 1.0 or gloss_power > 256.0 or gloss_strength < 0.0 or gloss_strength > 4.0:
		e.append("gloss_power must be 1 to 256 and gloss_strength 0 to 4")
	if emissive_core_u <= 0.0 or emissive_core_u > 16.0:
		e.append("emissive_core_u must be above 0 and at most 16")
	if emissive_core_white < 0.0 or emissive_core_white > 1.0:
		e.append("emissive_core_white must be 0 to 1")
	if bg_thin < 0.0 or bg_thin > 1.0 or bg_mask_wave_u < 4.0:
		e.append("bg_thin must be 0 to 1 and bg_mask_wave_u at least 4")
	return e
