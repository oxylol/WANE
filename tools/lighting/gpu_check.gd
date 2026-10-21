extends SceneTree
## The lighting pass's GPU half (docs/adr/0023 Decisions 4.1, 4.3, 4.5; BUILD.md section 13, Testing
## and CI): what the headless unit suite cannot see because the dummy renderer draws nothing. Under
## a display it holds
##   1. the room distance field the GPU bakes to the exact CPU field (the twin);
##   2. the shadow buffer the GPU marches to the twin's march, texel by texel, in all four
##      channels (the ember, a Beacon, a fire, the Gutter Ember), the penumbras apart;
##   3. the lit surface shader to its numbers: ambient times the Dark at Pitch and Dusk, the ember's
##      light brighter near it than far, a wall between it and the light shadowing a surface, and
##      each other kind of light read from its own shadow channel, the Gutter Ember lighting only
##      what is above it (BUILD.md section 10: "the only light that casts up");
##   4. the post pass (tools/lighting/post_check.gd);
##   5. every shader of the pass compiling (a compile error is an engine error: ci/lighting.sh
##      fails on any).
## It prints LIGHTING GPU CHECK PASSED and exits 0, or the failures and exits 1.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 --script tools/lighting/gpu_check.gd

const ROOM_ROWS: Array[String] = [
	"................",
	"................",
	"................",
	"......#.........",
	"......#.....a...",
	"......#....###..",
	"...a.../...####.",
	"################",
]
const SAMPLES: int = 1500
## The bake's half-float field is exact to better than this at the distances of a room, in u.
const BAKE_MEAN_MAX: float = 0.08
## The field has ridges (the medial axis of a corridor or a wall) that bilinear sampling rounds off
## by
## up to 0.7 of a texel; the worst error is held to that, which is below the penumbra's width.
const BAKE_RIDGE_TEXELS: float = 0.7
## The buffer against the twin: mean error, the share of points off by more than 0.1.
const BUFFER_MEAN_MAX: float = 0.01
const BUFFER_OFF_SHARE_MAX: float = 0.02
## The buffer against the twin where the twin is in a penumbra (0.02 to 0.98), at the texels'
## centres: the march's smoothing of the penumbra is held here (measured 0.001 to 0.002; the march
## without its smoothstep is 0.02 to 0.04 off). The RGBA8 buffer's step is 0.004.
const PENUMBRA_MEAN_MAX: float = 0.008
const PENUMBRA_POINTS_MIN: int = 60
## The other lights of the buffer check, by shadow channel (1 a Beacon, 2 a fire, 3 the Gutter
## Ember), each in the open of ROOM_ROWS.
const CHANNEL_LIGHTS: Array[Vector2] = [
	Vector2(80.0, 200.0), Vector2(400.0, 60.0), Vector2(150.0, 100.0), Vector2(300.0, 150.0)
]
## Where the ember waits when another light is under test: beyond its reach of everything.
const EMBER_AWAY: Vector2 = Vector2(-4000.0, -4000.0)

## The flicker is 4% either way, so crest over trough is about 1.08 of the ember's light.
const FLICKER_RATIO_MIN: float = 1.03
const FLICKER_RATIO_MAX: float = 1.2
## A door crossing, pointing the lighting at a room already built and baked, must cost under this
## (content/perf/budget.tres door_max_us).
const CROSSING_MAX_USEC: int = 2000
## A surface's light against the CPU's maths of the same numbers, as a share, and as a floor for a
## surface that only the ambient reaches at Pitch (a few hundredths).
const SHADING_TOLERANCE: float = 0.04
const KIND_FLOOR: float = 0.003
## BUILD.md section 10's ember, checked on the screen against the spec's own numbers: "radius 420 u
## at base, warm 2400 K, flicker at 0.5 Hz" (120 ticks a period, its crest at 0.5 s, tick 30). The
## reach is read from the light at two distances; a surface a little past it, and one far beyond,
## get nothing from it.
const SPEC_RADIUS_U: float = 420.0
const SPEC_RADIUS_TOLERANCE_U: float = 6.0
const SPEC_KELVIN: float = 2400.0
const SPEC_HUE_TOLERANCE: float = 0.03
const SPEC_NEAR_U: float = 150.0
const SPEC_FAR_U: float = 330.0
const SPEC_BEYOND_U: float = 880.0
const SPEC_CREST_TICK: int = 30
const SPEC_PERIOD_TICKS: int = 120
## The room of the wall checks: a pillar at column 10, rows 4 to 6.
const WALLED: Array[String] = [
	"................",
	"................",
	"................",
	"................",
	"..........#.....",
	"..........#.....",
	"..........#.....",
]

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _fail(line: String) -> void:
	_failures.append(line)
	printerr("FAIL: %s" % line)


func _run() -> void:
	var grid: TileGrid = TileGrid.from_rows(PackedStringArray(ROOM_ROWS))
	var field := LightField.new()
	field.set_dark_factor(1.0)
	root.add_child(field)
	field.show_world(CollisionWorld.new(grid), "check")
	await field.settle()
	var sdf: RoomSdf = field.shown_field()
	if not sdf.baked:
		_fail("the room's distance field was not baked")
		_finish()
		return
	_check_bake(sdf)
	await _check_crossing(field)
	await _check_buffer(field, sdf)
	await _check_surfaces(field)
	await _check_shading_maths(field)
	await _check_light_kinds(field)
	await _check_unbaked_room(field)
	field.queue_free()
	var post := PostCheck.new(self)
	await post.run()
	_failures.append_array(post.failures)
	_finish()


## 1. The baked field against the exact one.
func _check_bake(sdf: RoomSdf) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var total: float = 0.0
	var worst: float = 0.0
	var wrong_sign: int = 0
	for _i: int in range(SAMPLES):
		var p := Vector2(
			rng.randf_range(sdf.rect.position.x + 2.0, sdf.rect.end.x - 2.0),
			rng.randf_range(sdf.rect.position.y + 2.0, sdf.rect.end.y - 2.0)
		)
		var exact: float = sdf.distance(p)
		var baked: float = sdf.sample(p)
		var err: float = absf(exact - baked)
		total += err
		worst = maxf(worst, err)
		if absf(exact) > sdf.texel_u and (exact < 0.0) != (baked < 0.0):
			wrong_sign += 1
	var mean: float = total / float(SAMPLES)
	print(
		(
			("bake: %d shapes, %dx%d texels, mean error %.4f u, worst %.3f u, %d sign mismatches")
			% [sdf.count(), sdf.size_px.x, sdf.size_px.y, mean, worst, wrong_sign]
		)
	)
	if mean > BAKE_MEAN_MAX or worst > sdf.texel_u * BAKE_RIDGE_TEXELS or wrong_sign > 0:
		_fail(
			(
				"the baked field differs from the exact one (mean %.4f, worst %.3f, %d signs)"
				% [mean, worst, wrong_sign]
			)
		)


## A door crossing costs no bake: rooms prebuilt and baked ahead are only pointed at.
func _check_crossing(field: LightField) -> void:
	var a := TileGrid.from_rows(PackedStringArray(["....", "####"]))
	var b := TileGrid.from_rows(PackedStringArray(["....", "....", "#..#", "####"]))
	field.prebuild("crossing_a", a)
	field.prebuild("crossing_b", b)
	await field.settle()
	var worst: int = 0
	for i: int in range(20):
		var t: int = Time.get_ticks_usec()
		field.show_world(
			CollisionWorld.new(a if i % 2 == 0 else b), "crossing_a" if i % 2 == 0 else "crossing_b"
		)
		worst = maxi(worst, Time.get_ticks_usec() - t)
	print(
		(
			"crossing: worst %.3f ms of 20 (gate %.1f ms)"
			% [float(worst) / 1000.0, float(CROSSING_MAX_USEC) / 1000.0]
		)
	)
	if worst > CROSSING_MAX_USEC:
		_fail("a door crossing into a baked room costs %.2f ms" % [float(worst) / 1000.0])
	field.show_world(CollisionWorld.new(TileGrid.from_rows(PackedStringArray(ROOM_ROWS))), "check")


## 2. The shadow buffer against the twin, channel by channel: the ember (R) and a Beacon (G), a
## fire (B) and the Gutter Ember (A), each read at its texels' centres (where the march ran).
func _check_buffer(field: LightField, sdf: RoomSdf) -> void:
	var kinds: Array[LightKind] = [
		field.tuning.beacon, field.tuning.fire, field.tuning.gutter_ember
	]
	var others: Array[WaneLight] = []
	for i: int in range(kinds.size()):
		var l: WaneLight = field.spawn_light(kinds[i], CHANNEL_LIGHTS[kinds[i].shadow_channel])
		others.append(l)
	field.freeze(0, 1.0)
	field.present(0, 0.0, CHANNEL_LIGHTS[0])
	for _f: int in range(3):
		await RenderingServer.frame_post_draw
	var buf: Image = field.shadow_buffer().texture().get_image()
	var view: Rect2 = field.view_rect()
	var twin := ShadowTwin.new(sdf, field.tuning)
	twin.use_baked = true
	for ch: int in range(4):
		var c: Vector4 = field.casters[ch]
		if Vector2(c.x, c.y) != CHANNEL_LIGHTS[ch]:
			_fail("shadow channel %d is not its light's (%s)" % [ch, c])
			continue
		_check_channel(buf, view, twin, ch, Vector2(c.x, c.y), c.z)
	for l: WaneLight in others:
		field.remove_light(l)


## One channel of the buffer against the twin for the light at [param light] of reach
## [param reach].
func _check_channel(
	buf: Image, view: Rect2, twin: ShadowTwin, ch: int, light: Vector2, reach: float
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + ch
	var total: float = 0.0
	var off: int = 0
	var counted: int = 0
	var lit: int = 0
	var dark: int = 0
	var pen_total: float = 0.0
	var pen: int = 0
	var size := Vector2(buf.get_size())
	for _i: int in range(SAMPLES * 2):
		var p := Vector2(rng.randf_range(0.0, 16.0 * 32.0), rng.randf_range(0.0, 8.0 * 32.0))
		if p.distance_to(light) > reach - 4.0:
			continue
		var uv: Vector2 = (p - view.position) / view.size
		var px := Vector2i(
			clampi(int(uv.x * size.x), 0, buf.get_width() - 1),
			clampi(int(uv.y * size.y), 0, buf.get_height() - 1)
		)
		var centre: Vector2 = view.position + (Vector2(px) + Vector2(0.5, 0.5)) / size * view.size
		var gpu: float = buf.get_pixel(px.x, px.y)[ch]
		var cpu: float = twin.visibility(centre, light, reach)
		var err: float = absf(gpu - cpu)
		total += err
		counted += 1
		if err > 0.1:
			off += 1
		if cpu > 0.95:
			lit += 1
		elif cpu < 0.05:
			dark += 1
		if cpu > 0.02 and cpu < 0.98:
			pen_total += err
			pen += 1
	var mean: float = total / float(maxi(counted, 1))
	var share: float = float(off) / float(maxi(counted, 1))
	var pen_mean: float = pen_total / float(maxi(pen, 1))
	print(
		(
			(
				"buffer %s: %d points (%d lit, %d dark), mean error %.4f, %.1f%% off by more "
				+ "than 0.1; %d in a penumbra, mean error %.4f"
			)
			% ["RGBA"[ch], counted, lit, dark, mean, share * 100.0, pen, pen_mean]
		)
	)
	if counted < 200 or lit < 20 or dark < 20 or pen < PENUMBRA_POINTS_MIN:
		_fail(
			(
				"the buffer check of channel %d needs lit, dark and penumbra points (%d, %d, %d, %d)"
				% [ch, counted, lit, dark, pen]
			)
		)
	if mean > BUFFER_MEAN_MAX or share > BUFFER_OFF_SHARE_MAX:
		_fail(
			(
				"shadow channel %d differs from the twin (mean %.4f, %.1f%% off)"
				% [ch, mean, share * 100.0]
			)
		)
	if pen_mean > PENUMBRA_MEAN_MAX:
		_fail(
			(
				"shadow channel %d's penumbra differs from the twin's (mean %.4f): the march's soft edge"
				% [ch, pen_mean]
			)
		)


## A flat lit rectangle, and its pixel at the middle.
func _surface(at: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.5, 0.5, 0.5)
	r.position = at - Vector2(6.0, 6.0)
	r.size = Vector2(12.0, 12.0)
	LightSurfaces.make_lit(r, false)
	return r


## The mean luminance of the 8 x 8 pixels around [param at] on the screen (the post's grain averages
## out).
func _lum(at: Vector2) -> float:
	var shot: Image = root.get_viewport().get_texture().get_image()
	var total: float = 0.0
	for dy: int in range(-4, 4):
		for dx: int in range(-4, 4):
			total += shot.get_pixel(int(at.x) + dx, int(at.y) + dy).get_luminance()
	return total / 64.0


## 3. The lit surface shader against its numbers.
func _check_surfaces(field: LightField) -> void:
	# Open ground (a room with no walls), so only distance and the Dark matter.
	var open_row: String = ".".repeat(32)
	var open := TileGrid.from_rows(PackedStringArray([open_row, open_row, open_row, open_row]))
	field.show_world(CollisionWorld.new(open), "open")
	await field.settle()
	var ember := Vector2(100.0, 64.0)
	var near_at := Vector2(160.0, 64.0)
	var far_at := Vector2(900.0, 64.0)
	var near_rect: ColorRect = _surface(near_at)
	var far_rect: ColorRect = _surface(far_at)
	root.add_child(near_rect)
	root.add_child(far_rect)
	var dusk_far: float = 0.0
	var pitch_far: float = 0.0
	var dusk_near: float = 0.0
	var pitch_near: float = 0.0
	for pass_i: int in range(2):
		field.freeze(0, 1.0 if pass_i == 0 else 0.15)
		field.present(0, 0.0, ember)
		for _f: int in range(3):
			await RenderingServer.frame_post_draw
		if pass_i == 0:
			dusk_far = _lum(far_at)
			dusk_near = _lum(near_at)
		else:
			pitch_far = _lum(far_at)
			pitch_near = _lum(near_at)
	print(
		(
			"surfaces: far %.3f (Dusk) %.3f (Pitch), near %.3f (Dusk) %.3f (Pitch)"
			% [dusk_far, pitch_far, dusk_near, pitch_near]
		)
	)
	if not (pitch_far < dusk_far * 0.6):
		_fail(
			(
				"Pitch is not darker than Dusk where no light reaches (%.3f against %.3f)"
				% [pitch_far, dusk_far]
			)
		)
	if not (pitch_near > pitch_far * 2.0):
		_fail(
			(
				"the ember does not light the near surface at Pitch (%.3f against %.3f)"
				% [pitch_near, pitch_far]
			)
		)
	if not (pitch_near > dusk_near * 0.5):
		_fail(
			(
				"the ember's light is lost at Dusk and Pitch alike (%.3f, %.3f)"
				% [pitch_near, dusk_near]
			)
		)
	# The flicker shows on a surface: the ember's crest (tick 30) against its trough (tick 90), at
	# Pitch, where the ember is nearly all the light there is.
	var lum_crest: float = 0.0
	var lum_trough: float = 0.0
	for tick: int in [30, 90]:
		field.freeze(tick, 0.15)
		field.present(tick, 0.0, ember)
		for _f: int in range(3):
			await RenderingServer.frame_post_draw
		if tick == 30:
			lum_crest = _lum(near_at)
		else:
			lum_trough = _lum(near_at)
	var swing: float = lum_crest / maxf(lum_trough, 0.0001)
	print("flicker: crest %.4f, trough %.4f, ratio %.3f" % [lum_crest, lum_trough, swing])
	if not (swing > FLICKER_RATIO_MIN and swing < FLICKER_RATIO_MAX):
		_fail("the ember's flicker does not show on a surface at Pitch (ratio %.3f)" % swing)
	# A wall between the ember and a surface shadows it.
	var walled := TileGrid.from_rows(PackedStringArray(WALLED))
	field.show_world(CollisionWorld.new(walled), "walled")
	await field.settle()
	field.freeze(0, 0.15)
	var behind := Vector2(11.5 * 32.0, 200.0)
	var beside := Vector2(11.5 * 32.0, 64.0)
	var side_ember := Vector2(9.0 * 32.0, 150.0)
	near_rect.position = behind - Vector2(6.0, 6.0)
	far_rect.position = beside - Vector2(6.0, 6.0)
	field.present(0, 0.0, side_ember)
	for _f: int in range(3):
		await RenderingServer.frame_post_draw
	var shadowed: float = _lum(behind)
	var open_lum: float = _lum(beside)
	print("walled: behind the wall %.3f, in sight %.3f" % [shadowed, open_lum])
	if not (shadowed < open_lum * 0.6):
		_fail(
			(
				"a wall between the ember and a surface does not shadow it (%.3f against %.3f)"
				% [shadowed, open_lum]
			)
		)
	near_rect.queue_free()
	far_rect.queue_free()


## The radiance the shader should give a surface at [param at] with normal [param n]: ambient plus
## each light of the table as it was written this frame (rgb x energy x falloff, the table's own
## numbers, the Gutter Ember's above-only edge from its flag) times flat + (1 - flat) N.L, in the
## tuning's flat share (the shader's formula, from the tuning's numbers, on the CPU), light i seen
## through [param visibility][i] of the shadow march (1 where it has no entry).
func _radiance(
	field: LightField, at: Vector2, n: Vector3, visibility: Dictionary[int, float]
) -> Color:
	var amb: Color = field.globals["wane_ambient"]
	var rgb := Vector3(amb.r, amb.g, amb.b)
	var soft: float = field.tuning.up_only_soft_u
	for i: int in range(field.lights_in_table):
		var pos := Vector2(_cell(field, 0, i, 0), _cell(field, 0, i, 1))
		var reach: float = _cell(field, 0, i, 2)
		var height: float = _cell(field, 0, i, 3)
		var d: float = pos.distance_to(at)
		if d >= reach:
			continue
		var atten: float = pow(1.0 - d / reach, _cell(field, 2, i, 0))
		var flags: int = int(_cell(field, 1, i, 3) + 0.5)
		if flags & LightField.FLAG_UP_ONLY:
			atten *= smoothstep(-soft, soft, pos.y - at.y)
		var l: Vector3 = Vector3(pos.x - at.x, pos.y - at.y, height).normalized()
		var ndl: float = maxf(n.dot(l), 0.0)
		var share: float = field.tuning.flat_share + (1.0 - field.tuning.flat_share) * ndl
		var col := Vector3(_cell(field, 1, i, 0), _cell(field, 1, i, 1), _cell(field, 1, i, 2))
		var vis: float = visibility.get(i, 1.0)
		rgb += col * (atten * vis * share)
	return Color(rgb.x, rgb.y, rgb.z)


func _cell(field: LightField, row: int, col: int, k: int) -> float:
	return field.table[(row * LightField.TABLE_COLUMNS + col) * 4 + k]


## One pixel of the screen.
func _pixel(at: Vector2) -> Color:
	var shot: Image = root.get_viewport().get_texture().get_image()
	return shot.get_pixel(int(at.x), int(at.y))


## 5. The shading's numbers: a flat surface at three distances from the ember, and a wall's bevel
## normal, against the maths on the CPU from the tuning (so that an edit to the flat share, the
## attenuation, the bevel's tilt or how the normal is built moves a reading).
func _check_shading_maths(field: LightField) -> void:
	field.set_post_enabled(false)
	var open_row: String = ".".repeat(32)
	var open := TileGrid.from_rows(PackedStringArray([open_row, open_row, open_row, open_row]))
	field.show_world(CollisionWorld.new(open), "open2")
	await field.settle()
	var ember := Vector2(100.0, 64.0)
	var grey := Color(0.25, 0.25, 0.25)
	var rects: Array[ColorRect] = []
	var spots: Array[Vector2] = [Vector2(160.0, 64.0), Vector2(250.0, 64.0), Vector2(400.0, 64.0)]
	for at: Vector2 in spots:
		var r: ColorRect = _surface(at)
		r.color = grey
		root.add_child(r)
		rects.append(r)
	field.freeze(0, 0.15)
	field.present(0, 0.0, ember)
	for _f: int in range(3):
		await RenderingServer.frame_post_draw
	var worst: float = 0.0
	for at: Vector2 in spots:
		var want_c: Color = _radiance(field, at, Vector3(0.0, 0.0, 1.0), {}) * grey.r
		var want: float = Color(want_c.r, want_c.g, want_c.b).get_luminance()
		var got: float = _lum(at)
		worst = maxf(worst, absf(got - want) / maxf(want, 0.0001))
		print(
			(
				"shading: flat surface %d u from the ember: %.4f (maths %.4f)"
				% [int(at.x - ember.x), got, want]
			)
		)
	if worst > SHADING_TOLERANCE:
		_fail(
			(
				"a flat surface's light differs from the maths by %.1f%% (flat share, falloff)"
				% (worst * 100.0)
			)
		)
	for r: ColorRect in rects:
		r.queue_free()
	# A wall's top face: the bevel normal tilts toward the open by bevel_tilt, falling off to flat
	# bevel_u inside. The pillar is column 10 of a six-row room; the probe is 2.5 u under its top.
	var walled := TileGrid.from_rows(PackedStringArray(WALLED))
	field.show_world(CollisionWorld.new(walled), "bevel")
	await field.settle()
	var sdf: RoomSdf = field.shown_field()
	var probe := Vector2(10.5 * 32.0, 4.0 * 32.0 + 2.5)
	var wall_ember := Vector2(7.0 * 32.0, 2.0 * 32.0)
	var bevel_rect := ColorRect.new()
	bevel_rect.color = grey
	bevel_rect.position = probe - Vector2(1.0, 1.0)
	bevel_rect.size = Vector2(2.0, 2.0)
	LightSurfaces.make_lit(bevel_rect, true)
	root.add_child(bevel_rect)
	field.freeze(0, 0.15)
	field.present(0, 0.0, wall_ember)
	for _f: int in range(3):
		await RenderingServer.frame_post_draw
	var d: float = sdf.distance(probe)
	var bevel_u: float = field.tuning.wall_bevel_u
	var s01: float = clampf((-d) / bevel_u, 0.0, 1.0)
	var tilt: float = field.tuning.bevel_tilt * (1.0 - s01 * s01 * (3.0 - 2.0 * s01))
	var grad: Vector2 = Vector2(
		sdf.distance(probe + Vector2(2, 0)) - sdf.distance(probe - Vector2(2, 0)),
		sdf.distance(probe + Vector2(0, 2)) - sdf.distance(probe - Vector2(0, 2))
	)
	var out_dir: Vector2 = grad.normalized() if grad.length() > 0.0001 else Vector2.ZERO
	var n: Vector3 = Vector3(out_dir.x * tilt, out_dir.y * tilt, 1.0 - 0.5 * tilt).normalized()
	var twin := ShadowTwin.new(sdf, field.tuning)
	twin.use_baked = true
	var vis: float = twin.visibility(probe, wall_ember, field.tuning.ember_radius_u)
	var want_wall_c: Color = _radiance(field, probe, n, {0: vis}) * grey.r
	var want_wall: float = Color(want_wall_c.r, want_wall_c.g, want_wall_c.b).get_luminance()
	var got_wall: float = _pixel(probe).get_luminance()
	var flat_c: Color = _radiance(field, probe, Vector3(0.0, 0.0, 1.0), {0: vis}) * grey.r
	var flat_wall: float = Color(flat_c.r, flat_c.g, flat_c.b).get_luminance()
	print(
		(
			"shading: wall bevel at depth %.1f u, tilt %.2f: %.4f (maths %.4f, flat normal %.4f)"
			% [-d, tilt, got_wall, want_wall, flat_wall]
		)
	)
	if absf(got_wall - want_wall) / maxf(want_wall, 0.0001) > SHADING_TOLERANCE:
		_fail(
			(
				"a wall's bevel does not light as its normal says (%.4f against %.4f)"
				% [got_wall, want_wall]
			)
		)
	if absf(flat_wall - want_wall) / maxf(want_wall, 0.0001) < 0.08:
		_fail(
			(
				"the check cannot tell a bevelled wall from a flat one here (%.4f, %.4f)"
				% [flat_wall, want_wall]
			)
		)
	bevel_rect.queue_free()
	await _check_ember_against_the_spec(field, ember)
	field.set_post_enabled(true)


## The ember on the screen against BUILD.md section 10's own numbers ("radius 420 u at base, warm
## 2400 K, flicker at 0.5 Hz with ±4% amplitude"), not the tuning's: what it adds to a flat grey
## surface at Pitch (the surface minus the same surface far beyond its reach), in open ground,
## falls off to the reach the spec gives and ends there, has the colour of a 2400 K black body, and
## its flicker comes round again after 2 s.
func _check_ember_against_the_spec(field: LightField, ember: Vector2) -> void:
	var open_row: String = ".".repeat(32)
	var open := TileGrid.from_rows(PackedStringArray([open_row, open_row, open_row, open_row]))
	field.show_world(CollisionWorld.new(open), "open3")
	await field.settle()
	var grey := Color(0.25, 0.25, 0.25)
	var spots: Array[Vector2] = [
		ember + Vector2(SPEC_NEAR_U, 0.0),
		ember + Vector2(SPEC_FAR_U, 0.0),
		ember + Vector2(SPEC_RADIUS_U + 10.0, 0.0),
		ember + Vector2(SPEC_BEYOND_U, 0.0)
	]
	var rects: Array[ColorRect] = []
	for at: Vector2 in spots:
		var r: ColorRect = _surface(at)
		r.color = grey
		root.add_child(r)
		rects.append(r)
	field.freeze(0, 0.15)
	field.present(0, 0.0, ember)
	for _f: int in range(3):
		await RenderingServer.frame_post_draw
	var base: Color = _mean_colour(spots[3])
	var near_c: Color = _mean_colour(spots[0]) - base
	var far_c: Color = _mean_colour(spots[1]) - base
	var past_c: Color = _mean_colour(spots[2]) - base
	# What a flat surface keeps of a light d away at height h: flat + (1 - flat) N.L.
	var h: float = field.tuning.light_height_u
	var flat: float = field.tuning.flat_share
	var s_near: float = flat + (1.0 - flat) * h / Vector2(SPEC_NEAR_U, h).length()
	var s_far: float = flat + (1.0 - flat) * h / Vector2(SPEC_FAR_U, h).length()
	var k: float = pow(
		(near_c.get_luminance() / s_near) / maxf(far_c.get_luminance() / s_far, 0.000001),
		1.0 / field.tuning.falloff_power
	)
	var reach: float = (k * SPEC_FAR_U - SPEC_NEAR_U) / maxf(k - 1.0, 0.000001)
	var spec_colour: Color = LightKind.kelvin_colour(SPEC_KELVIN)
	var hue := Vector2(near_c.g / near_c.r, near_c.b / near_c.r)
	var spec_hue := Vector2(spec_colour.g / spec_colour.r, spec_colour.b / spec_colour.r)
	print(
		(
			"ember: reach %.1f u on the screen (spec %d), %.5f past it; g/r %.3f b/r %.3f (%d K: %s)"
			% [
				reach,
				int(SPEC_RADIUS_U),
				past_c.get_luminance(),
				hue.x,
				hue.y,
				int(SPEC_KELVIN),
				spec_hue
			]
		)
	)
	if absf(reach - SPEC_RADIUS_U) > SPEC_RADIUS_TOLERANCE_U:
		_fail("the ember's light reaches %.1f u on the screen, not section 10's 420" % reach)
	if absf(past_c.get_luminance()) > KIND_FLOOR * 0.1:
		_fail("the ember lights a surface past its reach (%.5f)" % past_c.get_luminance())
	if (hue - spec_hue).length() > SPEC_HUE_TOLERANCE:
		_fail("the ember's light is not 2400 K on the screen (%s against %s)" % [hue, spec_hue])
	# The flicker's period: the crest at 0.5 s comes round again at 2.5 s (0.5 Hz), and 1.5 s is
	# the trough between.
	var swings: Array[float] = []
	var ticks: Array[int] = [
		SPEC_CREST_TICK,
		SPEC_CREST_TICK + SPEC_PERIOD_TICKS,
		SPEC_CREST_TICK + SPEC_PERIOD_TICKS / 2
	]
	for tick: int in ticks:
		field.freeze(tick, 0.15)
		field.present(tick, 0.0, ember)
		for _f: int in range(3):
			await RenderingServer.frame_post_draw
		swings.append((_mean_colour(spots[0]) - base).get_luminance())
	print("ember: flicker %.5f at 0.5 s, %.5f at 2.5 s, %.5f at 1.5 s" % swings)
	if absf(swings[1] - swings[0]) > 0.002 * swings[0] or swings[2] > swings[0] * 0.95:
		_fail("the ember's flicker does not come round every 2 s (%s)" % [swings])
	for r: ColorRect in rects:
		r.queue_free()


## The mean colour of the 8 x 8 pixels around [param at] on the screen.
func _mean_colour(at: Vector2) -> Color:
	var shot: Image = root.get_viewport().get_texture().get_image()
	var total := Color(0, 0, 0, 0)
	for dy: int in range(-4, 4):
		for dx: int in range(-4, 4):
			total += shot.get_pixel(int(at.x) + dx, int(at.y) + dy)
	return total / 64.0


## The twin's visibility of the light at [param light] (reach [param reach]) averaged over the 8 x 8
## pixel centres that [method _lum] reads around [param at].
func _block_visibility(twin: ShadowTwin, at: Vector2, light: Vector2, reach: float) -> float:
	var total: float = 0.0
	for dy: int in range(-4, 4):
		for dx: int in range(-4, 4):
			var p := Vector2(float(int(at.x) + dx) + 0.5, float(int(at.y) + dy) + 0.5)
			total += twin.visibility(p, light, reach)
	return total / 64.0


## A lit grey surface's luminance at [param at] against the maths, as a failure line or "".
func _shading_off(at: Vector2, want_c: Color, what: String) -> String:
	var want: float = want_c.get_luminance()
	var got: float = _lum(at)
	print("kinds: %s: %.4f (maths %.4f)" % [what, got, want])
	if absf(got - want) > SHADING_TOLERANCE * want + KIND_FLOOR:
		return "%s: %.4f against the maths' %.4f" % [what, got, want]
	return ""


## 3b. Every kind of light reads its own shadow channel (the table's flags, docs/adr/0023 Decision
## 3.1) and the Gutter Ember lights only what is above it (BUILD.md section 10: "the only light
## that casts up"). Each kind alone (the ember away) lights a surface behind the pillar of WALLED
## and one in its sight; the shadow comes from its own channel, so a light that read another's
## (each other channel sees everything) would light the surface behind the wall.
func _check_light_kinds(field: LightField) -> void:
	field.set_post_enabled(false)
	field.show_world(CollisionWorld.new(TileGrid.from_rows(PackedStringArray(WALLED))), "kinds")
	await field.settle()
	var twin := ShadowTwin.new(field.shown_field(), field.tuning)
	twin.use_baked = true
	var grey := Color(0.5, 0.5, 0.5)
	var rects: Array[ColorRect] = [_surface(Vector2.ZERO), _surface(Vector2.ZERO)]
	for r: ColorRect in rects:
		root.add_child(r)
	# A kind, where it stands (left of the pillar), a surface behind the pillar from it and one in
	# its sight. The Gutter Ember stands lower than the surfaces it lights, which are above it.
	var kinds: Array[LightKind] = [
		field.tuning.beacon, field.tuning.fire, field.tuning.gutter_ember
	]
	var places: Array[Vector2] = [
		Vector2(288.0, 150.0), Vector2(288.0, 150.0), Vector2(288.0, 190.0)
	]
	var behinds: Array[Vector2] = [
		Vector2(368.0, 200.0), Vector2(368.0, 200.0), Vector2(368.0, 170.0)
	]
	var seen: Array[Vector2] = [Vector2(368.0, 64.0), Vector2(368.0, 64.0), Vector2(300.0, 60.0)]
	var problems: PackedStringArray = []
	for i: int in range(kinds.size()):
		var kind: LightKind = kinds[i]
		var at: Vector2 = places[i]
		var spots: Array[Vector2] = [behinds[i], seen[i]]
		for k: int in range(2):
			rects[k].position = spots[k] - Vector2(6.0, 6.0)
		var l: WaneLight = field.spawn_light(kind, at)
		field.freeze(0, 0.15)
		field.present(0, 0.0, EMBER_AWAY)
		for _f: int in range(3):
			await RenderingServer.frame_post_draw
		var flat := Vector3(0.0, 0.0, 1.0)
		for p: Vector2 in spots:
			var vis: float = _block_visibility(twin, p, at, kind.radius_u)
			var want: Color = _radiance(field, p, flat, {1: vis}) * grey.r
			var line: String = _shading_off(
				p, want, "%s, visibility %.2f at %s" % [kind.id, vis, p]
			)
			if line != "":
				problems.append(line)
		field.remove_light(l)
	# The Gutter Ember in the open: lit above it, dark below it.
	var open_row: String = ".".repeat(32)
	var open := TileGrid.from_rows(PackedStringArray([open_row, open_row, open_row, open_row]))
	field.show_world(CollisionWorld.new(open), "kinds_open")
	await field.settle()
	var gutter_at := Vector2(400.0, 64.0)
	var above := Vector2(400.0, 24.0)
	var below := Vector2(400.0, 104.0)
	rects[0].position = above - Vector2(6.0, 6.0)
	rects[1].position = below - Vector2(6.0, 6.0)
	var g: WaneLight = field.spawn_light(field.tuning.gutter_ember, gutter_at)
	field.present(0, 0.0, EMBER_AWAY)
	for _f: int in range(3):
		await RenderingServer.frame_post_draw
	var flat_n := Vector3(0.0, 0.0, 1.0)
	var lum_above: float = _lum(above)
	var lum_below: float = _lum(below)
	for p: Vector2 in [above, below]:
		var line: String = _shading_off(
			p, _radiance(field, p, flat_n, {}) * grey.r, "the Gutter Ember at %s" % p
		)
		if line != "":
			problems.append(line)
	if not (lum_above > lum_below * 2.0):
		problems.append(
			(
				"the Gutter Ember lights below it as well as above (%.4f above, %.4f below)"
				% [lum_above, lum_below]
			)
		)
	field.remove_light(g)
	for r: ColorRect in rects:
		r.queue_free()
	for line: String in problems:
		_fail("a light of another kind: " + line)
	field.set_post_enabled(true)


## 6. A room whose field is not baked yet does not borrow the last room's walls: the field of no
## walls stands in until it binds.
func _check_unbaked_room(field: LightField) -> void:
	var a := TileGrid.from_rows(PackedStringArray(["....", "####"]))
	var b := TileGrid.from_rows(PackedStringArray(["........", "........", "#......#", "########"]))
	field.show_world(CollisionWorld.new(a), "bound_a")
	await field.settle()
	var rect_a: Vector4 = field.globals["wane_room_rect"]
	field.show_world(CollisionWorld.new(b), "bound_b")
	var rect_now: Vector4 = field.globals["wane_room_rect"]
	if rect_now != Vector4(0, 0, 1, 1):
		_fail("a room shown before its field is baked still has the last room's rect %s" % rect_now)
	await field.settle()
	var rect_b: Vector4 = field.globals["wane_room_rect"]
	if rect_b == Vector4(0, 0, 1, 1) or rect_b == rect_a:
		_fail("a room's own field was not bound once baked (%s)" % rect_b)


func _finish() -> void:
	if _failures.is_empty():
		print("LIGHTING GPU CHECK PASSED")
		quit(0)
	else:
		print("LIGHTING GPU CHECK FAILED: %d" % _failures.size())
		quit(1)
