// The post pass (docs/adr/0023 Decision 3.4; BUILD.md section 13, Frame budget: Post 1.0 ms):
// bloom of everything above 1.0 (emissives exceed it in the HDR 2D pass), a soft shoulder so that
// they roll off instead of clipping, film grain and the vignette. The grain is reseeded by the
// boil step (tick-driven), so a frame is reproducible from its tick.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/lighting/light_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float bloom_threshold = 1.0;
uniform float bloom_strength = 0.55;
// The bloom's reach in screen pixels.
uniform float bloom_radius_px = 14.0;
uniform float grain = 0.012;
uniform float vignette = 0.22;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec3 bright(vec2 uv, float lod) {
	vec3 c = textureLod(screen_tex, uv, lod).rgb;
	return max(c - vec3(bloom_threshold), vec3(0.0));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 glow = bright(uv, 2.0) * 0.25;
	// Two rings of eight taps, at the bloom's reach and half of it.
	for (int i = 0; i < 8; i++) {
		float a = 0.785398 * float(i);
		vec2 dir = vec2(cos(a), sin(a));
		glow += bright(uv + dir * px * bloom_radius_px * 0.5, 2.0) * 0.0625;
		glow += bright(uv + dir * px * bloom_radius_px, 3.0) * 0.0625;
	}
	c += glow * bloom_strength;
	// A soft shoulder above 0.8: the top of the range rolls off instead of clipping.
	vec3 over = max(c - vec3(0.8), vec3(0.0));
	c = min(c, vec3(0.8)) + 0.2 * (over / (over + 0.2));
	float v = length((uv - vec2(0.5)) * vec2(1.0, 0.8)) * 1.35;
	c *= 1.0 - vignette * smoothstep(0.35, 1.0, v);
	float g = hash(FRAGCOORD.xy + vec2(wane_boil * 17.0, wane_boil * 5.0)) - 0.5;
	c += g * grain;
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
