// A character, enemy or prop frame: closed ink line, two-value gouache, rim, emissive.
// BUILD.md section 10 Style; docs/adr/0023 Decision 2. Unshaded: every light is computed in
// shaders/lighting/light_common.gdshaderinc, nothing is lit twice (Decision 3.2).
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/ink/ink_common.gdshaderinc"

void fragment() {
	COLOR = ink_shade(UV, ink_p_u, ink_world, ink_ax, ink_ay, ink_inst, FRAGCOORD.xy, SCREEN_UV, false);
}
