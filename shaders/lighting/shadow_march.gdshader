// The shadow march (docs/adr/0023 Decision 4.3; BUILD.md section 10: "2D ray-marched soft shadows
// from the ember against the collision layer"). It runs once per pixel of the shadow buffer, a
// screen-space RGBA8 image of the view at `shadow_scale`, one visibility channel per
// shadow-casting light (R is the ember). Sprites and tiles read it at SCREEN_UV, so the cost does
// not multiply with overdraw. game/lighting/shadow_twin.gd is the CPU twin: change one, change
// the other.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://shaders/lighting/light_common.gdshaderinc"

// The view in world units: x, y of the top left, then width and height.
uniform vec4 view_rect = vec4(0.0, 0.0, 1920.0, 1080.0);
// Up to four casters: x, y, radius (a radius of 0 or less is not casting), penumbra light radius.
uniform vec4 casters[4];
// Dynamic occluders: a box is (centre x, centre y, half width, half height), a circle is
// (centre x, centre y, radius, -1).
uniform vec4 occluders[16];
uniform int occluder_count = 0;
uniform float skin_u = 14.0;
uniform int max_steps = 48;
uniform float min_step_u = 1.5;
uniform int wall_walk_steps = 12;

float scene(vec2 p) {
	float d = wane_room_distance(p);
	for (int i = 0; i < 16; i++) {
		if (i >= occluder_count) {
			break;
		}
		vec4 o = occluders[i];
		float od;
		if (o.w < 0.0) {
			od = length(p - o.xy) - o.z;
		} else {
			vec2 q = abs(p - o.xy) - o.zw;
			od = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		}
		d = min(d, od);
	}
	return d;
}

float visibility_from(vec2 p, vec4 caster) {
	vec2 to_light = caster.xy - p;
	float dist = length(to_light);
	if (caster.z <= 0.0 || dist >= caster.z || dist < 0.001) {
		return 1.0;
	}
	vec2 dir = to_light / dist;
	float skin = 1.0;
	vec2 q = p;
	float d = scene(q);
	if (d < 0.0) {
		float walked = 0.0;
		for (int i = 0; i < 32; i++) {
			if (i >= wall_walk_steps || d >= 0.0) {
				break;
			}
			float step_u = max(-d, min_step_u);
			q += dir * step_u;
			walked += step_u;
			d = scene(q);
		}
		if (d < 0.0 || walked > skin_u) {
			return 0.0;
		}
		skin = 1.0 - walked / skin_u;
	}
	float total = length(caster.xy - q);
	float res = 1.0;
	float t = min_step_u;
	for (int i = 0; i < 128; i++) {
		if (i >= max_steps || t >= total) {
			break;
		}
		float h = scene(q + dir * t);
		res = min(res, h * total / (caster.w * t));
		if (res < 0.001) {
			return 0.0;
		}
		t += max(h, min_step_u);
	}
	res = clamp(res, 0.0, 1.0);
	return res * res * (3.0 - 2.0 * res) * skin;
}

void fragment() {
	vec2 p = view_rect.xy + UV * view_rect.zw;
	vec4 v = vec4(1.0);
	v.r = visibility_from(p, casters[0]);
	v.g = visibility_from(p, casters[1]);
	v.b = visibility_from(p, casters[2]);
	v.a = visibility_from(p, casters[3]);
	COLOR = v;
}
