// STUB of the lighting builder's file (ADR-0023 Decision 7.4: "Lighting delivers
// light_common.gdshaderinc with stub lights on day one so that 7.2 compiles against it").
// It exists so the ink shaders compile and render in this tree before the lighting pass lands; the
// lighting builder's real file replaces it whole. The API below is ADR-0023 Decision 7.3's, and
// what each function returns is what shaders/ink/ink_common.gdshaderinc relies on:
//
//   wane_radiance        ambient + the sum of light colour x energy x attenuation x visibility
//                        x (0.35 + 0.65 N.L), a linear RGB multiplier of the fill's value.
//   wane_key_irradiance  the sum of energy x attenuation x visibility x max(N.L, 0) over the
//                        lights that decide the two values, without ambient. Unitless, near 1 at
//                        the ember's centre; the fill turns lit where it reaches lit_threshold.
//   wane_line_dir        the direction toward the line light in world space (y down), scaled to
//                        its strength: the length is 0 to 1 (0 where no light reaches). For a
//                        carrier (a sprite with its own ember) it is the room's key, not its own
//                        ember (Decision 3.3).
//   wane_light_reaching  the energy reaching a point as a share of the ember's own, 0 to 1.
//   wane_visibility      the shadow buffer's channel for a caster, 0 (in shadow) to 1.
//
// This stub knows one light (the ember, from wane_ember) and no shadows. Its numbers (height 40 u,
// falloff power 1.6, the 0.35 + 0.65 wrap, the ember colour) are the ADR's; the real file reads
// them from content/lighting.tres. Do not tune anything here.

global uniform vec4 wane_ambient;
global uniform vec4 wane_ember; // x, y (world), radius (u), energy
global uniform vec4 wane_key; // xy toward the key light, z strength

const float WANE_STUB_HEIGHT_U = 40.0;
const float WANE_STUB_FALLOFF = 1.6;
const float WANE_STUB_KEY_HEIGHT = 0.8;
const vec3 WANE_STUB_EMBER_COLOUR = vec3(1.0, 0.61, 0.24);

float wane_stub_attenuation(vec2 world) {
	float d = length(wane_ember.xy - world);
	return pow(clamp(1.0 - d / max(wane_ember.z, 1.0), 0.0, 1.0), WANE_STUB_FALLOFF);
}

float wane_stub_n_dot_l(vec2 world, vec3 n) {
	vec3 l = normalize(vec3(wane_ember.xy - world, WANE_STUB_HEIGHT_U));
	return max(dot(n, l), 0.0);
}

float wane_visibility(vec2 screen_uv, int caster) {
	return 1.0;
}

vec3 wane_radiance(vec2 world, vec3 n, vec2 screen_uv) {
	float lit = wane_stub_attenuation(world) * wane_ember.w * (0.35 + 0.65 * wane_stub_n_dot_l(world, n));
	return wane_ambient.rgb + WANE_STUB_EMBER_COLOUR * lit;
}

float wane_key_irradiance(vec2 world, vec3 n, vec2 screen_uv, bool carrier) {
	if (carrier) {
		// A carrier's own ember lights it from inside, so every surface would be lit: its two
		// values follow the room's key instead (wane_key: xy toward the key, z strength).
		vec3 to_key = normalize(vec3(wane_key.xy, WANE_STUB_KEY_HEIGHT));
		return clamp(wane_key.z, 0.0, 1.0) * max(dot(n, to_key), 0.0);
	}
	return wane_stub_attenuation(world) * wane_ember.w * wane_stub_n_dot_l(world, n);
}

vec2 wane_line_dir(vec2 world, bool carrier) {
	if (carrier) {
		return normalize(wane_key.xy + vec2(0.00001, 0.0)) * clamp(wane_key.z, 0.0, 1.0);
	}
	vec2 to_light = wane_ember.xy - world;
	float strength = clamp(wane_stub_attenuation(world) * wane_ember.w, 0.0, 1.0);
	return normalize(to_light + vec2(0.00001, 0.0)) * strength;
}

float wane_light_reaching(vec2 world, vec2 screen_uv) {
	return wane_stub_attenuation(world);
}
