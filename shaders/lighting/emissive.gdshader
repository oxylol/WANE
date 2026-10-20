// Light the world gives off (docs/adr/0023 Decision 3.4): fire, sparks, procs, telegraphs, the
// blade's heat. It is unaffected by the ambient and exceeds 1.0 in the HDR 2D pass, so the post
// pass blooms it. `boost` is LightingTuning.emissive_boost.
shader_type canvas_item;
render_mode unshaded;

uniform float boost = 1.5;

void fragment() {
	COLOR.rgb *= boost;
}
