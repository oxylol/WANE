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
// A light's penumbra radius is never more than its clearance from the nearest surface, nor less
// than this (LightingTuning.light_r_min_u): a light set low over a floor is not shadowed by it.
uniform float light_r_min_u = 2.0;

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

// The outward direction of the nearest face: the field's gradient by four taps half a texel of the
// room's field apart (the scene's, so a dynamic occluder has faces too).
vec2 scene_normal(vec2 p) {
	float e = 0.5 * wane_room_rect.z / float(textureSize(wane_room_sdf, 0).x);
	vec2 g = vec2(scene(p + vec2(e, 0.0)) - scene(p - vec2(e, 0.0)),
			scene(p + vec2(0.0, e)) - scene(p - vec2(0.0, e)));
	float len = length(g);
	return len > 0.0001 ? g / len : vec2(0.0, -1.0);
}

float visibility_from(vec2 p, vec4 caster) {
	if (caster.z <= 0.0) {
		return 1.0;
	}
	float dist = length(caster.xy - p);
	if (dist >= caster.z || dist < 0.001) {
		return 1.0;
	}
	// Inside a wall: lit within skin_u of its nearest face, at 1 - depth / skin_u, and only as far as
	// that face sees the light. The depth is the field's own (square to the face), so the skin is as
	// deep wherever the light is along the face; a walk toward the light lengthened with the angle
	// and drew a lens under every light near a floor, and its steps drew terraces.
	float skin = 1.0;
	vec2 q = p;
	float d = scene(p);
	if (d < 0.0) {
		if (-d >= skin_u) {
			return 0.0;
		}
		skin = 1.0 + d / skin_u;
		q = p - scene_normal(p) * d;
	}
	vec2 to_light = caster.xy - q;
	float total = length(to_light);
	if (total < 0.001) {
		return skin;
	}
	vec2 dir = to_light / total;
	// The penumbra radius, held within the light's clearance: a light whose disc would reach into
	// the floor it sits over would otherwise dim, and band, its own pool.
	float r = clamp(scene(caster.xy), light_r_min_u, caster.w);
	float res = 1.0;
	float t = min_step_u;
	for (int i = 0; i < 128; i++) {
		if (i >= max_steps || t >= total) {
			break;
		}
		float h = scene(q + dir * t);
		res = min(res, h * total / (r * t));
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
