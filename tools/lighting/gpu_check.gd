extends SceneTree
## The lighting pass's GPU half (docs/adr/0023 Decisions 4.1, 4.3, 4.5; BUILD.md section 13, Testing
## and CI): what the headless unit suite cannot see because the dummy renderer draws nothing. Under
## a
## display it holds
##   1. the room distance field the GPU bakes to the exact CPU field (the twin);
##   2. the shadow buffer the GPU marches to the twin's march, point by point;
##   3. the lit surface shader to its numbers: ambient times the Dark at Pitch and Dusk, the ember's
##      light brighter near it than far, a wall between it and the light shadowing a surface;
##   4. every shader of the pass compiling (a compile error is an engine error: ci/lighting.sh
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

## The flicker is 4% either way, so crest over trough is about 1.08 of the ember's light.
const FLICKER_RATIO_MIN: float = 1.03
const FLICKER_RATIO_MAX: float = 1.2
## A door crossing, pointing the lighting at a room already built and baked, must cost under this
## (content/perf/budget.tres door_max_us).
const CROSSING_MAX_USEC: int = 2000
## A surface's light against the CPU's maths of the same numbers, as a share.
const SHADING_TOLERANCE: float = 0.04
## The bevel depth of a lit grey box with the distance field's normal (shaders/lighting/
## lit_flat.gdshader, bevel_u).
const LIT_BEVEL_U: float = 6.0

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
	await _check_unbaked_room(field)
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


## 2. The shadow buffer against the twin.
func _check_buffer(field: LightField, sdf: RoomSdf) -> void:
	var ember := Vector2(80.0, 200.0)
	field.freeze(0, 1.0)
	field.present(0, 0.0, ember)
	for _f: int in range(3):
		await RenderingServer.frame_post_draw
	var buf: Image = field.shadow_buffer().texture().get_image()
	var view: Rect2 = field.view_rect()
	var twin := ShadowTwin.new(sdf, field.tuning)
	twin.use_baked = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var total: float = 0.0
	var off: int = 0
	var counted: int = 0
	var lit: int = 0
	var dark: int = 0
	for _i: int in range(SAMPLES):
		var p := Vector2(rng.randf_range(0.0, 16.0 * 32.0), rng.randf_range(0.0, 8.0 * 32.0))
		if p.distance_to(ember) > field.tuning.ember_radius_u - 4.0:
			continue
		var uv: Vector2 = (p - view.position) / view.size
		var px := Vector2i(
			clampi(int(uv.x * float(buf.get_width())), 0, buf.get_width() - 1),
			clampi(int(uv.y * float(buf.get_height())), 0, buf.get_height() - 1)
		)
		var gpu: float = buf.get_pixel(px.x, px.y).r
		var cpu: float = twin.visibility(p, ember, field.tuning.ember_radius_u)
		total += absf(gpu - cpu)
		counted += 1
		if absf(gpu - cpu) > 0.1:
			off += 1
		if cpu > 0.95:
			lit += 1
		elif cpu < 0.05:
			dark += 1
	var mean: float = total / float(maxi(counted, 1))
	var share: float = float(off) / float(maxi(counted, 1))
	print(
		(
			"buffer: %d points (%d lit, %d dark), mean error %.4f, %.1f%% off by more than 0.1"
			% [counted, lit, dark, mean, share * 100.0]
		)
	)
	if counted < 200 or lit < 20 or dark < 20:
		_fail(
			(
				"the buffer check needs lit and dark points in the ember's reach (%d, %d, %d)"
				% [counted, lit, dark]
			)
		)
	if mean > BUFFER_MEAN_MAX or share > BUFFER_OFF_SHARE_MAX:
		_fail(
			(
				"the shadow buffer differs from the twin (mean %.4f, %.1f%% off)"
				% [mean, share * 100.0]
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
	var walled := TileGrid.from_rows(
		PackedStringArray(
			[
				"................",
				"................",
				"................",
				"................",
				"..........#.....",
				"..........#.....",
				"..........#....."
			]
		)
	)
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
## numbers) times flat + (1 - flat) N.L, in the tuning's flat share (the shader's formula, from the
## tuning's numbers, on the CPU), the ember seen through [param ember_visibility] of the shadow
## march.
func _radiance(field: LightField, at: Vector2, n: Vector3, ember_visibility: float = 1.0) -> Color:
	var amb: Color = field.globals["wane_ambient"]
	var rgb := Vector3(amb.r, amb.g, amb.b)
	for i: int in range(field.lights_in_table):
		var pos := Vector2(_cell(field, 0, i, 0), _cell(field, 0, i, 1))
		var reach: float = _cell(field, 0, i, 2)
		var height: float = _cell(field, 0, i, 3)
		var d: float = pos.distance_to(at)
		if d >= reach:
			continue
		var atten: float = pow(1.0 - d / reach, _cell(field, 2, i, 0))
		var l: Vector3 = Vector3(pos.x - at.x, pos.y - at.y, height).normalized()
		var ndl: float = maxf(n.dot(l), 0.0)
		var share: float = field.tuning.flat_share + (1.0 - field.tuning.flat_share) * ndl
		var col := Vector3(_cell(field, 1, i, 0), _cell(field, 1, i, 1), _cell(field, 1, i, 2))
		var vis: float = ember_visibility if i == 0 else 1.0
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
		var want_c: Color = _radiance(field, at, Vector3(0.0, 0.0, 1.0)) * grey.r
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
	var walled := TileGrid.from_rows(
		PackedStringArray(
			[
				"................",
				"................",
				"................",
				"................",
				"..........#.....",
				"..........#.....",
				"..........#....."
			]
		)
	)
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
	var bevel_u: float = LIT_BEVEL_U
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
	var want_wall_c: Color = _radiance(field, probe, n, vis) * grey.r
	var want_wall: float = Color(want_wall_c.r, want_wall_c.g, want_wall_c.b).get_luminance()
	var got_wall: float = _pixel(probe).get_luminance()
	var flat_c: Color = _radiance(field, probe, Vector3(0.0, 0.0, 1.0), vis) * grey.r
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
