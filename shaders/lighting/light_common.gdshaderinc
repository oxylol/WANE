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

// The light table (RGBA32F, 16 x 4). Column i is light i.
//   row 0: x, y (u), radius (u), height (u)
//   row 1: rgb * energy, flags (bit 0 casts a shadow, bits 1-2 its shadow-buffer channel,
//          bit 3 lights only points above it)
//   row 2: falloff power, light radius for the penumbra (u), 0, 0
//   row 3: reserved
const int WANE_MAX_LIGHTS = 16;
const int WANE_FLAG_SHADOW = 1;
const int WANE_FLAG_UP_ONLY = 8;
// 0.35 + 0.65 N.L: the flat share of a light that a surface keeps whatever way it faces.
const float WANE_FLAT_SHARE = 0.35;

// The world position of a screen uv: wane_view is (world x, world y of the view's top left, world
// units per screen pixel); the screen is wane_view.zw-scaled from the viewport size.
vec2 wane_world_of(vec2 screen_uv, vec2 viewport_px) {
	return wane_view.xy + screen_uv * viewport_px * wane_view.zw;
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
	float e = 2.0;
	vec2 g = vec2(
			wane_room_distance(world + vec2(e, 0.0)) - wane_room_distance(world - vec2(e, 0.0)),
			wane_room_distance(world + vec2(0.0, e)) - wane_room_distance(world - vec2(0.0, e)));
	float len = length(g);
	vec2 out_dir = len > 0.0001 ? g / len : vec2(0.0);
	float bevel = 1.0 - smoothstep(0.0, bevel_u, max(-d, 0.0));
	float tilt = 0.95 * bevel;
	return normalize(vec3(out_dir * tilt, 1.0 - 0.5 * tilt));
}

// One light's contribution at `world` for normal `n`: rgb * energy * attenuation * visibility *
// (flat + (1 - flat) N.L), or zero. `index` is the table column.
vec3 wane_light_shaded(int index, vec2 world, vec3 n, vec2 screen_uv, float flat_share) {
	vec4 a = texelFetch(wane_light_table, ivec2(index, 0), 0);
	vec2 to_light = a.xy - world;
	float dist = length(to_light);
	if (dist >= a.z) {
		return vec3(0.0);
	}
	vec4 b = texelFetch(wane_light_table, ivec2(index, 1), 0);
	float falloff = texelFetch(wane_light_table, ivec2(index, 2), 0).x;
	int flags = int(b.w + 0.5);
	float atten = pow(1.0 - dist / a.z, falloff);
	if ((flags & WANE_FLAG_UP_ONLY) != 0) {
		atten *= smoothstep(-8.0, 8.0, a.y - world.y);
	}
	float vis = 1.0;
	if ((flags & WANE_FLAG_SHADOW) != 0) {
		vis = wane_visibility(screen_uv, (flags >> 1) & 3);
	}
	vec3 l = normalize(vec3(to_light, a.w));
	float ndl = max(dot(n, l), 0.0);
	return b.rgb * (atten * vis * (flat_share + (1.0 - flat_share) * ndl));
}

// Ambient plus every light: what a surface at `world` with normal `n` is lit by.
vec3 wane_radiance(vec2 world, vec3 n, vec2 screen_uv) {
	vec3 rad = wane_ambient.rgb;
	for (int i = 0; i < WANE_MAX_LIGHTS; i++) {
		if (i >= wane_light_count) {
			break;
		}
		rad += wane_light_shaded(i, world, n, screen_uv, WANE_FLAT_SHARE);
	}
	return rad;
}

float wane_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// The key light's irradiance at `world`: what the two-value choice (lit or shadow) thresholds.
// It is the strongest single light, N.L included (the first light is skipped for a sprite that
// carries its own ember), or the room's directional key, scaled by the Dark, if that is stronger.
float wane_key_irradiance(vec2 world, vec3 n, vec2 screen_uv, bool carrier) {
	float best = 0.0;
	for (int i = 0; i < WANE_MAX_LIGHTS; i++) {
		if (i >= wane_light_count) {
			break;
		}
		if (carrier && i == 0) {
			continue;
		}
		best = max(best, wane_luma(wane_light_shaded(i, world, n, screen_uv, 0.0)));
	}
	vec3 kd = normalize(vec3(wane_key.xy, 0.8));
	best = max(best, wane_key.z * wane_dark * max(dot(n, kd), 0.0));
	return best;
}

// The direction (unit, in world axes) toward the light that weights a sprite's line (Decision 3.3):
// the strongest light reaching it, skipping the first for a carrier of its own ember, else the
// room's key.
vec2 wane_line_dir(vec2 world, bool carrier) {
	float best = 0.0;
	vec2 dir = normalize(wane_key.xy + vec2(0.0001));
	for (int i = 0; i < WANE_MAX_LIGHTS; i++) {
		if (i >= wane_light_count) {
			break;
		}
		if (carrier && i == 0) {
			continue;
		}
		vec4 a = texelFetch(wane_light_table, ivec2(i, 0), 0);
		vec2 to_light = a.xy - world;
		float dist = length(to_light);
		if (dist >= a.z || dist < 0.001) {
			continue;
		}
		vec4 b = texelFetch(wane_light_table, ivec2(i, 1), 0);
		float s = wane_luma(b.rgb) * pow(1.0 - dist / a.z, 1.6);
		if (s > best) {
			best = s;
			dir = to_light / dist;
		}
	}
	return dir;
}

// How much light reaches `world`, as a share of the ember's energy: the open line's drop-out.
float wane_light_reaching(vec2 world, vec2 screen_uv) {
	vec3 total = vec3(0.0);
	for (int i = 0; i < WANE_MAX_LIGHTS; i++) {
		if (i >= wane_light_count) {
			break;
		}
		total += wane_light_shaded(i, world, vec3(0.0, 0.0, 1.0), screen_uv, WANE_FLAT_SHARE);
	}
	return wane_luma(total) / max(wane_ember.w, 0.001);
}

#endif
