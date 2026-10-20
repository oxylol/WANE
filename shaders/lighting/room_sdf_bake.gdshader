// Bakes a room's signed distance field (docs/adr/0023 Decision 4.1): one draw into a half-float
// viewport, exact. Outside the walls: the distance to the nearest solid shape. Inside: minus the
// distance to the nearest empty one, so merged runs leave no inner seams. The shapes are in
// `shapes` (count x 2, RGBA32F): row 0 holds a and b, row 1 holds c and the kind (0 solid
// rectangle, 1 empty rectangle, 2 solid triangle, 3 empty triangle). game/lighting/room_sdf.gd is
// the CPU twin: change one, change the other.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D shapes : filter_nearest, repeat_disable;
uniform int shape_count = 0;
// World x, y of the top left and the size, in world units.
uniform vec4 bake_rect = vec4(0.0, 0.0, 1.0, 1.0);

float dist_rect(vec2 p, vec2 a, vec2 b) {
	vec2 d = max(max(a - p, p - b), vec2(0.0));
	return length(d);
}

float dist_segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.000001), 0.0, 1.0);
	return length(p - (a + ab * t));
}

float cross2(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

float dist_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	float d1 = cross2(b - a, p - a);
	float d2 = cross2(c - b, p - b);
	float d3 = cross2(a - c, p - c);
	bool neg = d1 < 0.0 || d2 < 0.0 || d3 < 0.0;
	bool pos = d1 > 0.0 || d2 > 0.0 || d3 > 0.0;
	if (!(neg && pos)) {
		return 0.0;
	}
	return min(dist_segment(p, a, b), min(dist_segment(p, b, c), dist_segment(p, c, a)));
}

void fragment() {
	vec2 p = bake_rect.xy + UV * bake_rect.zw;
	float solid = 1.0e9;
	float empty = 1.0e9;
	for (int i = 0; i < shape_count; i++) {
		vec4 r0 = texelFetch(shapes, ivec2(i, 0), 0);
		vec4 r1 = texelFetch(shapes, ivec2(i, 1), 0);
		int kind = int(r1.z + 0.5);
		float d;
		if (kind < 2) {
			d = dist_rect(p, r0.xy, r0.zw);
		} else {
			d = dist_tri(p, r0.xy, r0.zw, r1.xy);
		}
		if (kind == 0 || kind == 2) {
			solid = min(solid, d);
		} else {
			empty = min(empty, d);
		}
	}
	float s = solid;
	if (solid <= 0.0) {
		s = empty < 1.0e8 ? -empty : 0.0;
	}
	COLOR = vec4(s, 0.0, 0.0, 1.0);
}
