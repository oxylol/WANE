// The post pass (docs/adr/0023 Decision 3.4; BUILD.md section 13, Frame budget: Post 1.0 ms):
// bloom of everything above 1.0 (emissives exceed it in the HDR 2D pass), a soft shoulder so that
// they roll off instead of clipping (by brightness, so that a colour keeps its hue), film grain and
// the vignette. The grain is reseeded by the boil step (tick-driven), so a frame is reproducible
// from its tick. The bloom averages screen blocks, so it takes a source of some size; the halo of
// a light a few pixels wide is drawn by shaders/lighting/glow.gdshader. Every number is
// LightingTuning's.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/lighting/light_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float bloom_threshold = 1.0;
uniform float bloom_strength = 0.55;
// The bloom's reach in world units, the weights of its centre tap and of each tap of its ring.
uniform float bloom_radius_u = 14.0;
uniform float bloom_core = 0.2;
uniform float bloom_ring = 0.1;
// Where the shoulder starts; above it the top of the range rolls off.
uniform float shoulder_knee = 0.8;
uniform float grain = 0.012;
uniform float vignette = 0.22;
uniform float vignette_start = 0.26;
uniform float vignette_end = 0.74;
uniform float vignette_squash = 0.8;

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
	// One tap at the pixel and a ring of eight at the bloom's reach, from the screen's mip levels so
	// that each tap already averages a block: nine fetches a pixel.
	// The taps average blocks of the screen that grow with the radius (a block about as wide as the
	// ring's taps are far apart), so the bloom stays smooth when the camera zooms in.
	float radius_px = bloom_radius_u / max(wane_view.z, 0.0001);
	float ring_lod = max(log2(radius_px) - 0.75, 1.0);
	vec3 glow = bright(uv, ring_lod - 1.0) * bloom_core;
	for (int i = 0; i < 8; i++) {
		float a = 0.785398 * float(i);
		vec2 dir = vec2(cos(a), sin(a));
		glow += bright(uv + dir * px * radius_px, ring_lod) * bloom_ring;
	}
	c += glow * bloom_strength;
	// A soft shoulder: above the knee the brightness rolls off instead of clipping, and the colour
	// is scaled as a whole, so an orange that is bright stays orange.
	float luma = wane_luma(c);
	float rolled = luma;
	if (luma > shoulder_knee) {
		float over = luma - shoulder_knee;
		float room = 1.0 - shoulder_knee;
		rolled = shoulder_knee + room * (over / (over + room));
	}
	c *= rolled / max(luma, 0.0001);
	float v = length((uv - vec2(0.5)) * vec2(1.0, vignette_squash));
	c *= 1.0 - vignette * smoothstep(vignette_start, vignette_end, v);
	float g = hash(FRAGCOORD.xy + vec2(wane_boil * 17.0, wane_boil * 5.0)) - 0.5;
	c += g * grain;
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
