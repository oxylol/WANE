class_name InkGlobals
extends RefCounted
## Writes the ink and gouache numbers (content/art/ink.tres, InkTuning) and the boil step into the
## global shader parameters the ink shaders read (ADR-0023 Decisions 2.2, 2.6 and 7.2). The
## globals are declared in project.godot [shader_globals]; a shader that names a global the
## project does not declare fails to compile, so a missing one is a test failure
## (tests/unit/game/test_ink_shaders.gd).

## Global name to the InkTuning method that packs it.
const PACKED: Dictionary[StringName, StringName] = {
	&"wane_ink": &"ink_vec",
	&"wane_ink_wave": &"wave_vec",
	&"wane_fill": &"fill_vec",
	&"wane_fill_more": &"fill_more_vec",
	&"wane_ink_more": &"ink_more_vec",
	&"wane_ink_light": &"ink_light_vec",
	&"wane_ink_bg": &"ink_bg_vec",
}

const BOIL: StringName = &"wane_boil"


## Pushes [param t] to the shaders. Safe to call again after a tuning change.
static func apply(t: InkTuning) -> void:
	for global_name: StringName in PACKED:
		var packed: Variant = t.call(PACKED[global_name])
		RenderingServer.global_shader_parameter_set(global_name, packed)


## The boil step for a tick: the wobble is reseeded every step, so no two steps match and a frame
## is reproducible from its tick (ADR-0023 Decision 2.2).
static func boil_step(tick: int, boil_hz: float) -> float:
	return floorf(float(tick) * boil_hz / 60.0)


## Sets the boil step for [param tick].
static func set_tick(tick: int, boil_hz: float) -> void:
	RenderingServer.global_shader_parameter_set(BOIL, boil_step(tick, boil_hz))
