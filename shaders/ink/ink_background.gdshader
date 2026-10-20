// A background or parallax layer: the same fill, with the open, broken line of BUILD.md section 10
// ("backgrounds get an open, broken line that drops out where light hits"): the line is broken
// where a low-frequency mask is low and fades where the ember reaches. docs/adr/0023 Decision 2.3.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/ink/ink_common.gdshaderinc"

void fragment() {
	COLOR = ink_shade(UV, ink_p_u, ink_world, ink_ax, ink_ay, ink_inst, FRAGCOORD.xy, SCREEN_UV, true);
}
