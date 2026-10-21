// The soft halo a light draws over the ink (docs/adr/0025; BUILD.md section 10, The ember: "a soft
// bloom over the ink"). One quad per light, added to the HDR 2D pass: its colour is the light's
// colour times its energy times the glow strength, its radius is in world units, so the halo is the
// same size at every zoom (the post pass's bloom, which averages screen blocks, cannot make a halo
// of a source a few pixels wide). `falloff` is LightingTuning.glow_falloff.
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float falloff = 2.0;

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float g = pow(max(1.0 - d, 0.0), falloff);
	COLOR = vec4(COLOR.rgb * g, 1.0);
}
