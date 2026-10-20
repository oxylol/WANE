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
	await _check_buffer(field, sdf)
	await _check_surfaces(field)
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


func _pixel(at: Vector2) -> Color:
	var shot: Image = root.get_viewport().get_texture().get_image()
	return shot.get_pixel(int(at.x), int(at.y))


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
			dusk_far = _pixel(far_at).get_luminance()
			dusk_near = _pixel(near_at).get_luminance()
		else:
			pitch_far = _pixel(far_at).get_luminance()
			pitch_near = _pixel(near_at).get_luminance()
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
	var shadowed: float = _pixel(behind).get_luminance()
	var open_lum: float = _pixel(beside).get_luminance()
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


func _finish() -> void:
	if _failures.is_empty():
		print("LIGHTING GPU CHECK PASSED")
		quit(0)
	else:
		print("LIGHTING GPU CHECK FAILED: %d" % _failures.size())
		quit(1)
