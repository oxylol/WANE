// The ink line and the gouache fill (BUILD.md section 10, Style; docs/adr/0023 Decision 2).
//
// A sprite is three textures in the channel layout of ADR-0023 Decision 1.3, all sampled at the
// same UV (tools/artbuild/ writes them):
//   shape_tex   R signed silhouette distance S, G unsigned distance to the nearest visible edge U,
//               B front-side flag, A emissive coverage
//   normal_tex  RGB the bevel normal (0.5 + 0.5 n, y down), A gloss
//   parts_tex   R palette column, G brush angle, B pressure taper, A flags
// plus the palette (4 rows a variant: lit, shadow, rim, emissive) and the shared noise.
//
// Everything that depends on a light, the view or the tick is computed here: line weight, wobble,
// taper, two values, rim, brush, grain. Light comes only from shaders/lighting/light_common
// .gdshaderinc and time only from the wane_boil global (the tick's boil step): no shader reads a
// clock built-in (ADR-0023 Decision 6.2), so a frame is reproducible from its tick.
//
// Built-in variables (FRAGCOORD, SCREEN_UV) are not visible inside functions, so the fragment
// stage passes them in.

#include "res://shaders/lighting/light_common.gdshaderinc"

// ---- The numbers (globals; content/art/ink.tres, game/art/ink_globals.gd) ----
global uniform vec4 wane_ink; // line_lit_u, line_shadow_u, line_min_px, wobble_u
global uniform vec4 wane_ink_wave; // wave1_u, wave2_u, edge_dark_u, edge_dark
global uniform vec4 wane_fill; // lit_threshold, terminator_soft, brush_noise, brush_strength
global uniform vec4 wane_fill_more; // brush_stretch, rim_u, grain_strength, back_line_u
global uniform vec4 wane_ink_more; // ink_value, taper_floor, ink_over_fill, emissive_gain
global uniform vec4 wane_ink_light; // line_light_lo, line_light_hi, bg_drop_lo, bg_drop_hi
global uniform vec4 wane_ink_bg; // bg_break_lo, bg_break_hi, bg_thin, bg_mask_wave_u
global uniform vec4 wane_ink_extra; // smear_opacity, smear_tail_pow, gloss_power, gloss_strength

// ---- The channel layout. These constants are the decode half of ADR-0023 Decision 1.3 and must
// ---- equal tools/artbuild/channels.py (tools/ci/test_ink_layout.py checks).
const float INK_S_ZERO = 128.0; // S byte of 0 u
const float INK_S_STEPS_PER_U = 16.0; // S: byte = 128 + 16 d
const float INK_U_STEPS_PER_U = 16.0; // U: byte = 16 d
const float INK_ANGLE_RANGE = 3.14159265; // brush angle: byte 255 is pi
const int INK_PALETTE_ROWS = 4; // lit, shadow, rim, emissive
const int INK_PALETTE_COLUMNS = 16;
const int INK_FLAG_SMEAR = 8; // parts alpha, bit 3: the part is a smear (its taper channel is the arc's age)
// Cells of the shared noise (assets/art/build/noise/noise.png, 256 x 256, Decision 1.7).
const float INK_NOISE_PX = 256.0;
const float INK_WOBBLE1_CELLS = 16.0; // B
const float INK_WOBBLE2_CELLS = 32.0; // A
// Structure, not tuning: how the two wobble octaves share the amplitude, and the span of the
// dissolve noise in u.
const float INK_WOBBLE1_WEIGHT = 0.66;
const float INK_DISSOLVE_TILE_U = 32.0;
const float INK_BRUSH_TILE_U = 16.0; // u across one tile of the brush noise: its coarsest cell is 1 u

uniform sampler2D shape_tex : filter_linear, repeat_disable;
uniform sampler2D normal_tex : filter_linear, repeat_disable;
uniform sampler2D parts_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 frame_u = vec2(64.0, 64.0); // the frame's cell in u
uniform float texel_u = 1.0; // u per texel at the bound scale (1 at 1x, 0.25 at 4x)
uniform bool carries_ember = false;
uniform int palette_row = 0; // palette variant
uniform int mode = 0; // 0 lit, 1 silhouette, 2 visibility, 3 channel debug

varying vec2 ink_p_u; // position in the frame, in u, in the texture's own axes
varying vec2 ink_world; // world position
varying vec2 ink_ax; // the node's x axis in the world (carries flips and rotation)
varying vec2 ink_ay;
varying vec4 ink_inst; // per instance: r flash, g emissive boost, b dissolve, a alpha

void vertex() {
	ink_p_u = VERTEX * texel_u;
	ink_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	ink_ax = MODEL_MATRIX[0].xy;
	ink_ay = MODEL_MATRIX[1].xy;
	ink_inst = COLOR;
}

float ink_decode_s(float r) {
	return (r * 255.0 - INK_S_ZERO) / INK_S_STEPS_PER_U;
}

float ink_decode_u(float g) {
	return g * 255.0 / INK_U_STEPS_PER_U;
}

// A direction in the texture's axes (x right, y down) to the world's.
vec2 ink_to_world(vec2 v, vec2 axn, vec2 ayn) {
	return v.x * axn + v.y * ayn;
}

vec2 ink_safe_normalize(vec2 v, vec2 fallback) {
	float l = length(v);
	return l > 0.0001 ? v / l : fallback;
}

// The boil step's offset into the noise: a low-discrepancy pair from the integer step, so no two
// steps match and a step is reproducible.
vec2 ink_boil_offset() {
	return fract(vec2(0.7548776662, 0.5698402909) * mod(wane_boil, 4096.0));
}

// Two octaves of the noise's B and A at wavelengths wave1_u and wave2_u (in u, so a rescale does
// not make an edge hairy), in -wobble_u .. +wobble_u. Applied to S and U alike.
float ink_wobble(vec2 p_u) {
	vec2 off = ink_boil_offset();
	float a = texture(noise_tex, p_u / (wane_ink_wave.x * INK_WOBBLE1_CELLS) + off).b;
	float b = texture(noise_tex, p_u / (wane_ink_wave.y * INK_WOBBLE2_CELLS) + off.yx).a;
	return wane_ink.w * ((a - 0.5) * 2.0 * INK_WOBBLE1_WEIGHT + (b - 0.5) * 2.0 * (1.0 - INK_WOBBLE1_WEIGHT));
}

// The distance field's gradient by four taps, per u, in the texture's axes. channel 0 is S, 1 is U.
vec2 ink_gradient(vec2 uv, int channel) {
	vec2 px = 1.0 / vec2(textureSize(shape_tex, 0));
	vec4 xp = textureLod(shape_tex, uv + vec2(px.x, 0.0), 0.0);
	vec4 xm = textureLod(shape_tex, uv - vec2(px.x, 0.0), 0.0);
	vec4 yp = textureLod(shape_tex, uv + vec2(0.0, px.y), 0.0);
	vec4 ym = textureLod(shape_tex, uv - vec2(0.0, px.y), 0.0);
	float dx;
	float dy;
	if (channel == 0) {
		dx = ink_decode_s(xp.r) - ink_decode_s(xm.r);
		dy = ink_decode_s(yp.r) - ink_decode_s(ym.r);
	} else {
		dx = ink_decode_u(xp.g) - ink_decode_u(xm.g);
		dy = ink_decode_u(yp.g) - ink_decode_u(ym.g);
	}
	return vec2(dx, dy) / (2.0 * texel_u);
}

// One frame of ink and gouache. uv indexes all three textures; p_u, world and the two axes come
// from the vertex stage; inst is the per-instance colour; frag is FRAGCOORD.xy and screen_uv is
// SCREEN_UV. background true draws the open, broken line of a background layer.
vec4 ink_shade(vec2 uv, vec2 p_u, vec2 world, vec2 ax, vec2 ay, vec4 inst, vec2 frag, vec2 screen_uv, bool background) {
	vec4 sh = texture(shape_tex, uv);
	vec4 nm = texture(normal_tex, uv);
	vec4 pt = texture(parts_tex, uv);
	// A smear's taper channel is its age along the arc, 0 at the tail and 1 at the blade.
	bool smear = (int(pt.a * 255.0 + 0.5) & INK_FLAG_SMEAR) != 0;
	float age = smear ? pt.b : 1.0;
	float s_dist = ink_decode_s(sh.r);
	float u_dist = ink_decode_u(sh.g);
	float side = sh.b;
	float upp = max(length(dFdx(p_u)), 0.0001); // u per screen pixel
	float aa = max(0.75 * fwidth(u_dist), 0.05);
	float wob = ink_wobble(p_u);
	bool carrier = carries_ember && !background;

	// Alpha from the silhouette, dissolved by the instance's b.
	float alpha = (1.0 - smoothstep(-aa, aa, s_dist + wob)) * inst.a;
	float dn = texture(noise_tex, p_u / INK_DISSOLVE_TILE_U).g;
	alpha *= smoothstep(inst.b * 0.9, inst.b * 0.9 + 0.04, dn);
	// A smear is a ribbon of the motion: it fades out toward the tail of its arc.
	if (smear) {
		alpha *= wane_ink_extra.x * pow(age, wane_ink_extra.y);
	}

	if (mode == 1) {
		return vec4(1.0, 1.0, 1.0, alpha);
	}
	if (mode == 2) {
		return vec4(vec3(wane_visibility(screen_uv, 0)), alpha);
	}
	if (mode == 3) {
		return vec4(s_dist / 16.0 + 0.5, u_dist / 16.0, side, 1.0);
	}

	vec2 axn = normalize(ax);
	vec2 ayn = normalize(ay);

	// The line light: the direction toward the light that reaches the sprite, and how fully it does.
	vec3 line_light = wane_line_light(world, screen_uv, carrier);
	vec2 ldir = line_light.xy;
	float lstr = line_light.z;

	// The line, the rim and the edge darkening exist only near a visible edge: within the shadow
	// side's weight (or line_min_px screen pixels when zoomed out) plus the anti-aliasing, the
	// wobble, the darkening and the rim. The gradients and the weight are only worked out there.
	float back_u = max(aa, wane_fill_more.w);
	float reach_u = max(wane_ink.y, wane_ink.z * upp) + back_u + 2.0 * aa + wane_ink.w + wane_ink_wave.z + wane_fill_more.y;
	float cover = 0.0;
	float w = 0.0;
	float em_near = sh.a;
	// The break mask of a background's open line (sampled outside the branch below: a mipmapped
	// fetch needs uniform control flow).
	float bg_mask = 1.0;
	if (background) {
		bg_mask = texture(noise_tex, p_u / (wane_ink_bg.w * INK_WOBBLE1_CELLS)).b;
	}
	if (u_dist < reach_u) {
		// The visible edge's outward normal: minus the gradient of U on the front side, plus it on
		// the back. Where the four taps straddle the edge the gradient collapses; the bevel
		// normal's outward direction stands in.
		vec2 gu = ink_gradient(uv, 1);
		vec2 n_edge_t = side > 0.5 ? -gu : gu;
		if (length(n_edge_t) < 0.2) {
			n_edge_t = nm.xy * 2.0 - 1.0;
		}
		vec2 n_edge = ink_safe_normalize(ink_to_world(n_edge_t, axn, ayn), vec2(0.0, -1.0));

		// Weight: thick on the shadow side, hairline on the lit side, tapered at shape ends, never
		// under line_min_px.
		float lit_side = smoothstep(wane_ink_light.x, wane_ink_light.y, dot(n_edge, ldir)) * lstr;
		w = mix(wane_ink.x, wane_ink.y, 1.0 - lit_side) * mix(wane_ink_more.y, 1.0, pt.b);
		// Never under line_min_px wide on the screen; a line thinner than that is drawn at the
		// pixel's width and as light as it is thin, as a hairline is on paper.
		float floor_u = max(wane_ink.z * upp, 0.0001);
		float line_cover_scale = clamp(w / floor_u, 0.0, 1.0);
		w = max(w, floor_u);
		if (smear) {
			// A motion ribbon: the line is the hairline, and it thins out toward the tail.
			w = max(mix(wane_ink.x, w, age), floor_u);
			line_cover_scale *= pow(age, wane_ink_extra.y);
		}
		if (background) {
			w *= mix(wane_ink_bg.z, 1.0, smoothstep(wane_ink_bg.x, wane_ink_bg.y, bg_mask));
			float reach = wane_light_reaching(world, screen_uv);
			line_cover_scale *= 1.0 - smoothstep(wane_ink_light.z, wane_ink_light.w, reach);
		}
		float band = mix(back_u, w, side);
		cover = (1.0 - smoothstep(band - aa, band + aa, u_dist + wob)) * line_cover_scale;
		// An emissive part (the ember, an eye) is a light, not a drawn shape: it carries no ink, and
		// neither does the part around it, along its edge.
		float em_step = (back_u + 2.0 * aa + wane_ink.w) / texel_u;
		vec2 em_px = em_step / vec2(textureSize(shape_tex, 0));
		em_near = max(em_near, textureLod(shape_tex, uv + vec2(em_px.x, 0.0), 0.0).a);
		em_near = max(em_near, textureLod(shape_tex, uv - vec2(em_px.x, 0.0), 0.0).a);
		em_near = max(em_near, textureLod(shape_tex, uv + vec2(0.0, em_px.y), 0.0).a);
		em_near = max(em_near, textureLod(shape_tex, uv - vec2(0.0, em_px.y), 0.0).a);
		cover *= 1.0 - em_near;
	}
	float band_edge = mix(back_u, w, side);

	// The part: palette column, normal, brush.
	int idx = clamp(int(pt.r * 255.0 + 0.5), 0, INK_PALETTE_COLUMNS - 1);
	int row = palette_row * INK_PALETTE_ROWS;
	vec3 c_lit = texelFetch(palette_tex, ivec2(idx, row), 0).rgb;
	vec3 c_shadow = texelFetch(palette_tex, ivec2(idx, row + 1), 0).rgb;
	vec3 c_rim = texelFetch(palette_tex, ivec2(idx, row + 2), 0).rgb;
	vec4 c_em = texelFetch(palette_tex, ivec2(idx, row + 3), 0);
	vec3 nt = nm.xyz * 2.0 - 1.0;
	vec3 n = normalize(vec3(ink_to_world(nt.xy, axn, ayn), max(nt.z, 0.05)));
	float angle = pt.g * INK_ANGLE_RANGE;
	vec2 bdir = vec2(cos(angle), sin(angle));
	vec2 bperp = vec2(-bdir.y, bdir.x);
	vec2 bc = vec2(dot(p_u, bdir) / (INK_BRUSH_TILE_U * wane_fill_more.x), dot(p_u, bperp) / INK_BRUSH_TILE_U);
	float brush = (texture(noise_tex, bc).g - 0.5) * 2.0;

	// Two values: the surface is lit where a light has reached it and it faces the light (N.L of
	// the form direction above the threshold), the brush noise breaking the terminator like a
	// brush edge. A smear is all one value.
	float lit = wane_key_lit(world, n, screen_uv, carrier, wane_fill.x, wane_fill.y, wane_fill.z * brush);
	if (smear) {
		lit = 1.0;
	}
	vec3 base = mix(c_shadow, c_lit, lit) * (1.0 + wane_fill.w * brush);
	vec3 rad = wane_radiance(world, n, screen_uv);
	vec3 col = base * rad;

	// Fill darkens where it meets the line, measured from the line's band.
	float to_band = max(u_dist + wob - band_edge, 0.0);
	col *= 1.0 - wane_ink_wave.w * (1.0 - em_near) * (1.0 - smoothstep(0.0, wane_ink_wave.z, to_band));

	// Paper grain in screen space.
	col *= 1.0 + wane_fill_more.z * (texture(noise_tex, frag / INK_NOISE_PX).r - 0.5) * 2.0;

	// Rim: inside the silhouette just under the line, facing the light. Its direction is the
	// gradient of S, not the edge normal, which flips at T-junctions.
	vec3 rim = vec3(0.0);
	if (u_dist < reach_u) {
		vec2 gs = ink_gradient(uv, 0);
		vec2 n_sil = ink_safe_normalize(ink_to_world(gs, axn, ayn), vec2(0.0, -1.0));
		float rim_band = 1.0 - smoothstep(0.0, max(wane_fill_more.y, 0.0001), max(-s_dist - w, 0.0));
		rim = c_rim * rad * rim_band * max(dot(n_sil, ldir), 0.0) * lstr;
	}
	// Gloss: a highlight where the surface's tilt turns its normal toward the half vector of the
	// light and the viewer (the ember raking along an edge of steel or wax).
	vec3 l3 = vec3(ldir * cos(wane_shape.z), sin(wane_shape.z));
	vec3 half_v = normalize(l3 + vec3(0.0, 0.0, 1.0));
	float spec = nm.a * wane_ink_extra.w * pow(max(dot(n, half_v), 0.0), wane_ink_extra.z) * lstr;
	vec3 fill = col + rim * (smear ? 0.0 : 1.0) + c_rim * rad * spec;

	// Ink is never lighter than the fill it covers.
	vec3 ink = min(c_shadow * wane_ink_more.x, fill * wane_ink_more.z);
	vec3 outc = mix(fill, ink, cover);

	// Emissive replaces the fill it covers and is untouched by ambient; its halo is the light's
	// (shaders/lighting/glow.gdshader) and the post pass blooms what exceeds 1.
	outc = outc * (1.0 - sh.a * c_em.a) + sh.a * c_em.rgb * c_em.a * wane_ink_more.w * inst.g;
	outc = mix(outc, vec3(1.0), inst.r);
	return vec4(outc, alpha);
}
