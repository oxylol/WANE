// The lighting pass's common code (docs/adr/0023 Decisions 3 and 7.3; BUILD.md section 10, Lighting).
// Every lit shader includes this and stays `render_mode unshaded`: the game has no PointLight2D, no
// LightOccluder2D and no CanvasModulate. Light reaches a surface only through these functions,
// from the `wane_*` global shader parameters that game/lighting/light_field.gd writes each frame.
// No shader reads a clock of its own: everything that moves derives from the simulation tick.
#ifndef WANE_LIGHT_COMMON
#define WANE_LIGHT_COMMON

global uniform vec4 wane_ambient;
global uniform float wane_dark;
global uniform vec4 wane_key;
global uniform vec4 wane_ember;
global uniform sampler2D wane_light_table : filter_nearest, repeat_disable;
global uniform int wane_light_count;
global uniform sampler2D wane_shadow : filter_linear, repeat_disable;
global uniform vec4 wane_view;
global uniform sampler2D wane_room_sdf : filter_linear, repeat_disable;
global uniform vec4 wane_room_rect;
global uniform float wane_boil;
global uniform float wane_time;
// The shape of the lighting, all from content/lighting.tres (LightingTuning): flat_share (the share
// of a light a surface keeps whatever way it faces), bevel_tilt (how far the room's walls tilt
// their edge normals), form_elevation (radians: how high above the picture plane the key and every
// light's form direction stands at least) and up_only_soft_u (the width of the Gutter Ember's
// above-only edge).
global uniform vec4 wane_shape;
// The gate of the two-value choice: the energy of direct light (before N.L) below which a surface
// is in its shadow value, and above which the light has reached it.
global uniform vec2 wane_gate;

// The light table (RGBA32F, 16 x 4). Column i is light i.
//   row 0: x, y (u), radius (u), height (u)
//   row 1: rgb * energy, flags (bit 0 casts a shadow, bits 1-2 its shadow-buffer channel,
//          bit 3 lights only points above it)
//   row 2: falloff power, light radius for the penumbra (u), 0, 0
//   row 3: reserved
const int WANE_MAX_LIGHTS = 16;
const int WANE_FLAG_SHADOW = 1;
const int WANE_FLAG_UP_ONLY = 8;

// The world position of a screen uv: wane_view is (world x, world y of the view's top left, the
// view's width and height in world units). It is in u, not in the screen's pixels, which are not
// the world's when the window is stretched or at 4K.
vec2 wane_world_of(vec2 screen_uv) {
	return wane_view.xy + screen_uv * wane_view.zw;
}

float wane_visibility(vec2 screen_uv, int caster) {
	vec4 v = textureLod(wane_shadow, screen_uv, 0.0);
	if (caster == 0) {
		return v.r;
	} else if (caster == 1) {
		return v.g;
	} else if (caster == 2) {
		return v.b;
	}
	return v.a;
}

// Signed distance to the room's walls in world units: negative inside a wall.
float wane_room_distance(vec2 world) {
	vec2 uv = (world - wane_room_rect.xy) / wane_room_rect.zw;
	return textureLod(wane_room_sdf, uv, 0.0).r;
}

// The wall face's normal under the ember: the gradient of the room's distance field tilts a
// surface within `bevel_u` of a wall's edge outward, so the ember rakes across the edge like a
// bevel. `inside` is how far into the wall this point is (>= 0).
vec3 wane_sdf_normal(vec2 world, float bevel_u) {
	float d = wane_room_distance(world);
	// Half a texel of the room's field: the gradient's step follows the bake's resolution.
	float e = 0.5 * wane_room_rect.z / float(textureSize(wane_room_sdf, 0).x);
	vec2 g = vec2(
			wane_room_distance(world + vec2(e, 0.0)) - wane_room_distance(world - vec2(e, 0.0)),
			wane_room_distance(world + vec2(0.0, e)) - wane_room_distance(world - vec2(0.0, e)));
	float len = length(g);
	vec2 out_dir = len > 0.0001 ? g / len : vec2(0.0);
	float bevel = 1.0 - smoothstep(0.0, bevel_u, max(-d, 0.0));
	float tilt = wane_shape.y * bevel;
	return normalize(vec3(out_dir * tilt, 1.0 - 0.5 * tilt));
}

// What light `index` delivers to `world` before the surface's angle: rgb * energy * attenuation *
// visibility, or zero out of its reach. `world` is a point of the picture plane.
vec3 wane_light_reach(int index, vec2 world, vec2 screen_uv) {
	vec4 a = texelFetch(wane_light_table, ivec2(index, 0), 0);
	float dist = length(a.xy - world);
	if (dist >= a.z) {
		return vec3(0.0);
	}
	vec4 b = texelFetch(wane_light_table, ivec2(index, 1), 0);
	float falloff = texelFetch(wane_light_table, ivec2(index, 2), 0).x;
	int flags = int(b.w + 0.5);
	float atten = pow(1.0 - dist / a.z, falloff);
	if ((flags & WANE_FLAG_UP_ONLY) != 0) {
		atten *= smoothstep(-wane_shape.w, wane_shape.w, a.y - world.y);
	}
	float vis = 1.0;
	if ((flags & WANE_FLAG_SHADOW) != 0) {
		vis = wane_visibility(screen_uv, (flags >> 1) & 3);
	}
	return b.rgb * (atten * vis);
}

// One light's contribution at `world` for normal `n`: its reach times (flat + (1 - flat) N.L), or
// zero. `index` is the table column.
vec3 wane_light_shaded(int index, vec2 world, vec3 n, vec2 screen_uv, float flat_share) {
	vec3 reach = wane_light_reach(index, world, screen_uv);
	if (reach.r + reach.g + reach.b <= 0.0) {
		return vec3(0.0);
	}
	vec4 a = texelFetch(wane_light_table, ivec2(index, 0), 0);
	vec3 l = normalize(vec3(a.xy - world, a.w));
	float ndl = max(dot(n, l), 0.0);
	return reach * (flat_share + (1.0 - flat_share) * ndl);
}

// Ambient plus every light: what a surface at `world` with normal `n` is lit by.
vec3 wane_radiance(vec2 world, vec3 n, vec2 screen_uv) {
	vec3 rad = wane_ambient.rgb;
	for (int i = 0; i < WANE_MAX_LIGHTS; i++) {
		if (i >= wane_light_count) {
			break;
		}
		rad += wane_light_shaded(i, world, n, screen_uv, wane_shape.x);
	}
	return rad;
}

float wane_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// The form direction toward a light: the in-plane direction to it, at the elevation the light really
// stands at (its height over its distance) but never lower than the style's. A flat surface is
// then lit the same wherever it is (no ring of distance), a surface tilted away from the light
// falls to shadow, and near a light the real elevation rules.
vec3 wane_form_dir(vec2 to_light, float height) {
	float dist = length(to_light);
	float sin_e = max(height * inversesqrt(dist * dist + height * height), sin(wane_shape.z));
	vec2 dir = dist > 0.0001 ? to_light / dist : normalize(wane_key.xy + vec2(0.0001));
	return vec3(dir * sqrt(max(1.0 - sin_e * sin_e, 0.0)), sin_e);
}

// The room key's form direction.
vec3 wane_key_dir() {
	return vec3(normalize(wane_key.xy + vec2(0.0001)) * cos(wane_shape.z), sin(wane_shape.z));
}

// How lit the surface at `world` with normal `n` is by its best light, from 0 (its shadow value) to
// 1 (its lit value): the surface is lit where a light has reached it (its energy before N.L above
// the gate) and the surface faces it (N.L of the form direction above `threshold`, `soft` wide,
// with `jitter` breaking the terminator like a brush edge). Distance does not enter the form, so
// the terminator follows the shape; distance only fades the light itself (wane_radiance).
// A sprite that carries its own ember is lit by it whole, from the key's direction: its own ember
// is at the sprite and has no direction of its own.
float wane_key_lit(vec2 world, vec3 n, vec2 screen_uv, bool carrier, float threshold, float soft, float jitter) {
	float best = 0.0;
	for (int i = 0; i < WANE_MAX_LIGHTS; i++) {
		if (i >= wane_light_count) {
			break;
		}
		vec4 a = texelFetch(wane_light_table, ivec2(i, 0), 0);
		float presence;
		vec3 l;
		if (carrier && i == 0) {
			presence = wane_luma(texelFetch(wane_light_table, ivec2(i, 1), 0).rgb);
			l = wane_key_dir();
		} else {
			presence = wane_luma(wane_light_reach(i, world, screen_uv));
			l = wane_form_dir(a.xy - world, a.w);
		}
		float gate = smoothstep(wane_gate.x, wane_gate.y, presence);
		best = max(best, gate * smoothstep(threshold - soft, threshold + soft, dot(n, l) + jitter));
	}
	float key_gate = smoothstep(wane_gate.x, wane_gate.y, wane_key.z * wane_dark);
	best = max(best, key_gate * smoothstep(threshold - soft, threshold + soft, dot(n, wane_key_dir()) + jitter));
	return best;
}

// The light that weights a sprite's line, its rim and its gloss (Decision 3.3): xy is the unit
// direction toward the strongest light reaching it (the room's key when none does, and for a sprite
// carrying its own ember, which has no direction of its own, the key's), z is that light's strength,
// 0 where no light reaches and 1 where one does in full (the gate), so that a sprite beyond every
// light draws the heavy line all round.
vec3 wane_line_light(vec2 world, vec2 screen_uv, bool carrier) {
	float best = wane_key.z * wane_dark;
	vec2 dir = normalize(wane_key.xy + vec2(0.0001));
	for (int i = 0; i < WANE_MAX_LIGHTS; i++) {
		if (i >= wane_light_count) {
			break;
		}
		vec4 a = texelFetch(wane_light_table, ivec2(i, 0), 0);
		vec2 to_light = a.xy - world;
		float dist = length(to_light);
		float s;
		if (carrier && i == 0) {
			s = wane_luma(texelFetch(wane_light_table, ivec2(i, 1), 0).rgb);
		} else {
			if (dist < 0.001) {
				continue;
			}
			s = wane_luma(wane_light_reach(i, world, screen_uv));
		}
		if (s > best) {
			best = s;
			if (!(carrier && i == 0)) {
				dir = to_light / dist;
			}
		}
	}
	return vec3(dir, smoothstep(wane_gate.x, wane_gate.y, best));
}

// How much light reaches `world`, as a share of the ember's energy: the open line's drop-out.
float wane_light_reaching(vec2 world, vec2 screen_uv) {
	vec3 total = vec3(0.0);
	for (int i = 0; i < WANE_MAX_LIGHTS; i++) {
		if (i >= wane_light_count) {
			break;
		}
		total += wane_light_shaded(i, world, vec3(0.0, 0.0, 1.0), screen_uv, wane_shape.x);
	}
	return wane_luma(total) / max(wane_ember.w, 0.001);
}

#endif
