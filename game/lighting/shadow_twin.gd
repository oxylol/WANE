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
			od = (
				Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
				+ minf(maxf(q.x, q.y), 0.0)
			)
		d = minf(d, od)
	return d


## How much of a light at [param light] with reach [param reach] shows at [param p], 0 to 1: the
## shader's visibility_from.
func visibility(p: Vector2, light: Vector2, reach: float) -> float:
	var to_light: Vector2 = light - p
	var dist: float = to_light.length()
	if reach <= 0.0 or dist >= reach or dist < 0.001:
		return 1.0
	var dir: Vector2 = to_light / dist
	var skin: float = 1.0
	var q: Vector2 = p
	var d: float = scene(q)
	if d < 0.0:
		var walked: float = 0.0
		for i: int in range(tuning.wall_walk_steps):
			if d >= 0.0:
				break
			var step_u: float = maxf(-d, tuning.min_step_u)
			q += dir * step_u
			walked += step_u
			d = scene(q)
		if d < 0.0 or walked > tuning.skin_u:
			return 0.0
		skin = 1.0 - walked / tuning.skin_u
	var total: float = (light - q).length()
	var res: float = 1.0
	var t: float = tuning.min_step_u
	for i: int in range(tuning.max_steps):
		if t >= total:
			break
		var h: float = scene(q + dir * t)
		res = minf(res, h * total / (tuning.light_r_u * t))
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
