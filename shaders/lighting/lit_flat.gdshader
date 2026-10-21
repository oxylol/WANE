// A grey-box surface lit by the pass (docs/adr/0023 Decision 3.2): the Phase 1 stand-ins for
// tiles, the player, enemies and props, until their art and normal maps arrive (the ink shaders
// are the real surface shaders). Unshaded: Light2D is gone, so light reaches the surface only
// through light_common.gdshaderinc. A tile gets a bevel normal from the room's distance field, so
// the ember rakes across its edges; anything else is flat.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/lighting/light_common.gdshaderinc"

// Whether the normal comes from the room's distance field (tiles) or is flat (everything else).
uniform bool sdf_normals = false;
// How far into a wall the bevel reaches, in world units: LightingTuning.wall_bevel_u, which
// LightSurfaces sets on the bevel material.
uniform float bevel_u = 6.0;
// Light the surface gives off itself, added after the lighting.
uniform float emissive = 0.0;
// A grey box that stands for a function (the player's, an enemy's, by colour) keeps its hue in
// every light: it takes the light's brightness and not its colour, so that the 2400 K of the ember
// at Pitch does not turn cyan into green. Phase 1 only: the art's own palettes replace the boxes.
uniform bool keep_hue = false;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec3 n = vec3(0.0, 0.0, 1.0);
	if (sdf_normals) {
		n = wane_sdf_normal(world, bevel_u);
	}
	vec3 rad = wane_radiance(world, n, SCREEN_UV);
	if (keep_hue) {
		rad = vec3(wane_luma(rad));
	}
	COLOR.rgb = COLOR.rgb * rad + COLOR.rgb * emissive;
}
