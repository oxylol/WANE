class_name ShadowTwin
extends RefCounted
## The shadow march in GDScript (docs/adr/0023 Decision 4.5): the same walk and the same sphere
## trace as shaders/lighting/shadow_march.gdshader, over a [RoomSdf], 0.2 to 0.4 ms a query. For
## tests only: the core knows nothing of light. It turns BUILD.md section 15's "At Pitch ambient,
## the ember's light reveals a Clinger 30 frames before it drops" into a headless test, and an
## xvfb test holds the GPU buffer to it. Change the shader, change this.

var sdf: RoomSdf
var tuning: LightingTuning
## Dynamic occluders as the shader takes them: a box is (centre x, centre y, half width, half
## height), a circle is (centre x, centre y, radius, -1).
var occluders: Array[Vector4] = []
## Whether [method scene] reads the baked texture's bilinear field (as the GPU does) instead of
## the exact one.
var use_baked: bool = false


func _init(p_sdf: RoomSdf, p_tuning: LightingTuning) -> void:
	sdf = p_sdf
	tuning = p_tuning


## The scene's signed distance at [param p]: the room's field and the dynamic occluders.
func scene(p: Vector2) -> float:
	var d: float = sdf.sample(p) if use_baked else sdf.distance(p)
	for o: Vector4 in occluders:
		var od: float = 0.0
		if o.w < 0.0:
			od = p.distance_to(Vector2(o.x, o.y)) - o.z
		else:
			var q := Vector2(absf(p.x - o.x) - o.z, absf(p.y - o.y) - o.w)
			od = (Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0))
		d = minf(d, od)
	return d


## The outward direction of the face nearest [param p]: the scene's gradient by four taps half a
## texel of the room's field apart, as the shader's scene_normal.
func scene_normal(p: Vector2) -> Vector2:
	var e: float = 0.5 * sdf.texel_u
	var g := Vector2(
		scene(p + Vector2(e, 0.0)) - scene(p - Vector2(e, 0.0)),
		scene(p + Vector2(0.0, e)) - scene(p - Vector2(0.0, e))
	)
	var g_len: float = g.length()
	return g / g_len if g_len > 0.0001 else Vector2(0.0, -1.0)


## How much of a light at [param light] with reach [param reach] shows at [param p], 0 to 1: the
## shader's visibility_from. A point inside a wall is lit within [member LightingTuning.skin_u] of
## its nearest face, by the field's own depth (square to the face, so the skin is as deep wherever
## the light is along it), as far as that face sees the light. The penumbra radius is held within
## the light's clearance from the nearest surface ([member LightingTuning.light_r_min_u] at least),
## so a light set low over a floor does not shadow its own pool.
func visibility(p: Vector2, light: Vector2, reach: float) -> float:
	if reach <= 0.0:
		return 1.0
	var dist: float = (light - p).length()
	if dist >= reach or dist < 0.001:
		return 1.0
	var skin: float = 1.0
	var q: Vector2 = p
	var d: float = scene(p)
	if d < 0.0:
		if -d >= tuning.skin_u:
			return 0.0
		skin = 1.0 + d / tuning.skin_u
		q = p - scene_normal(p) * d
	var to_light: Vector2 = light - q
	var total: float = to_light.length()
	if total < 0.001:
		return skin
	var dir: Vector2 = to_light / total
	var r: float = clampf(scene(light), tuning.light_r_min_u, tuning.light_r_u)
	var res: float = 1.0
	var t: float = tuning.min_step_u
	for i: int in range(tuning.max_steps):
		if t >= total:
			break
		var h: float = scene(q + dir * t)
		res = minf(res, h * total / (r * t))
		if res < 0.001:
			return 0.0
		t += maxf(h, tuning.min_step_u)
	res = clampf(res, 0.0, 1.0)
	return res * res * (3.0 - 2.0 * res) * skin


## How much of a light at [param light] (reach [param reach], falloff [param falloff]) reaches
## [param p]: its visibility times its attenuation, 0 to 1. A thing is revealed by the ember when
## this is at least [member LightingTuning.reveal_threshold] (BUILD.md section 15: a Clinger is a
## shadow before it is a sprite).
func revealed(p: Vector2, light: Vector2, reach: float, falloff: float) -> float:
	var dist: float = p.distance_to(light)
	if dist >= reach:
		return 0.0
	return visibility(p, light, reach) * pow(1.0 - dist / reach, falloff)
