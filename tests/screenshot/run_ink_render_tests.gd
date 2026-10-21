extends SceneTree
## Renders the ink shaders through the game's own materials and checks what they draw
## (BUILD.md section 10, Style; docs/adr/0023 Decision 2 and 6): a render is deterministic for a
## fixed tick, the boil step changes the line and nothing else, the silhouette is the baked one at
## every scale, the line is thin on the lit side and thick on the shadow side (flipped or not),
## the ember is a light and carries no ink, Pitch is dark where Dusk is not and the ember is the
## same at both, and per-instance values ride on one shared material. Needs a display:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 --script tests/screenshot/run_ink_render_tests.gd
## Exits 0 when every check passes, 1 otherwise.

const FLAT_BG: Color = Color(0.02, 0.015, 0.03)
## How the wobble's two octaves share its amplitude (ADR-0023 Decision 2.2): the first, at wave1_u,
## carries this share and the second, at wave2_u, the rest.
const WOBBLE_FIRST_OCTAVE_WEIGHT: float = 0.66
const WOBBLE_FIRST_OCTAVE_CELLS: float = 16.0
const WOBBLE_SECOND_OCTAVE_CELLS: float = 32.0
const NOISE_PX: float = 256.0

var _failures: PackedStringArray = []
var _checks: int = 0
var _tuning: InkTuning
var _noise: ImageTexture
var _fig1: SpriteSheet
var _fig4: SpriteSheet
var _stage: SpriteSheet


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_tuning = load(InkTuning.PATH) as InkTuning
	_noise = InkProbe.noise_texture()
	_fig1 = InkProbe.figure_sheet(1, _noise)
	_fig4 = InkProbe.figure_sheet(4, _noise)
	_stage = InkProbe.stage_sheet(_noise)
	await _test_determinism_and_boil()
	await _test_silhouette_is_the_bake()
	await _test_the_wobble_is_the_two_octave_noise()
	await _test_line_follows_the_light()
	await _test_pitch_and_ember()
	await _test_instance_values_on_one_material()
	await _test_scales_agree()
	await _test_tuning_reaches_the_shader()
	print("ink render: %d checks, %d failed" % [_checks, _failures.size()])
	for f: String in _failures:
		printerr("  FAIL ", f)
	quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)


## Renders the figure alone (or with the stage) and returns the picture. [param setup] may change
## the sprites.
func _shot(
	sheet: SpriteSheet, zoom: float, tick: int, dark: float, with_stage: bool, mode: int = 0
) -> Image:
	var size: Vector2i = InkRender.VIEW_1X if zoom == 1.0 else InkRender.VIEW_4X
	var centre: Vector2 = (
		Vector2(size) * 0.5 if zoom == 1.0 else InkProbe.STAGE_MARK_U + Vector2(10.0, -38.0)
	)
	var ember: Vector2 = InkRender.ember_world()
	InkRender.set_globals(_tuning, tick, ember, dark)
	var vp: SubViewport = InkRender.viewport(root, size, zoom, centre)
	var fig: InkSprite = InkRender.add_stage_and_figure(vp, _stage, sheet, with_stage)
	fig.mode = mode as InkSprite.Mode
	var img: Image = await InkRender.capture(self, vp)
	vp.queue_free()
	return img


func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


func _bytes_equal(a: Image, b: Image) -> bool:
	return a.get_data() == b.get_data()


func _diff_count(a: Image, b: Image) -> int:
	var n: int = 0
	var da: PackedByteArray = a.get_data()
	var db: PackedByteArray = b.get_data()
	for i: int in range(0, da.size(), 4):
		if da[i] != db[i] or da[i + 1] != db[i + 1] or da[i + 2] != db[i + 2]:
			n += 1
	return n


func _test_determinism_and_boil() -> void:
	var a: Image = await _shot(_fig1, 1.0, 7, InkRender.DUSK, true)
	var b: Image = await _shot(_fig1, 1.0, 7, InkRender.DUSK, true)
	_check(_bytes_equal(a, b), "a render at a fixed tick is byte-identical (ADR-0023 Decision 6)")
	# 12 Hz boil at 60 ticks a second: ticks 5 to 9 are one step, so tick 7 equals tick 5.
	var same_step: Image = await _shot(_fig1, 1.0, 5, InkRender.DUSK, true)
	_check(_bytes_equal(a, same_step), "ticks of one boil step draw the same frame")
	# The next step redraws the line and nothing else: every pixel that changed lies within 3 u of
	# a visible edge of the figure (the baked U channel).
	var fa: Image = await _shot(_fig1, 1.0, 5, InkRender.DUSK, false)
	var fb: Image = await _shot(_fig1, 1.0, 10, InkRender.DUSK, false)
	var baked: Image = InkProbe.bake(InkProbe.figure_prims(), InkProbe.FIGURE_CELL_U, 1)[&"shape"]
	var origin: Vector2i = Vector2i(InkProbe.STAGE_MARK_U - InkProbe.FIGURE_ORIGIN_U)
	var changed: int = 0
	var far_from_edges: int = 0
	for y: int in range(fa.get_height()):
		for x: int in range(fa.get_width()):
			if fa.get_pixel(x, y) == fb.get_pixel(x, y):
				continue
			changed += 1
			var bx: int = x - origin.x
			var by: int = y - origin.y
			var near: bool = false
			if bx >= 0 and by >= 0 and bx < baked.get_width() and by < baked.get_height():
				near = baked.get_pixel(bx, by).g * 255.0 / 16.0 <= 3.0
			if not near:
				far_from_edges += 1
	_check(changed > 20, "a new boil step redraws the line (changed %d pixels)" % changed)
	_check(
		far_from_edges == 0,
		(
			"a new boil step changes edges only (%d of %d pixels changed away from an edge)"
			% [far_from_edges, changed]
		)
	)


func _test_silhouette_is_the_bake() -> void:
	var baked: Image = InkProbe.bake(InkProbe.figure_prims(), InkProbe.FIGURE_CELL_U, 1)[&"shape"]
	var inside: int = 0
	for y: int in range(baked.get_height()):
		for x: int in range(baked.get_width()):
			if baked.get_pixel(x, y).r * 255.0 < 128.0:
				inside += 1
	var sil: Image = await _shot(_fig1, 1.0, 0, InkRender.DUSK, false, InkSprite.Mode.SILHOUETTE)
	var white: float = 0.0
	var clear: float = _lum(sil.get_pixel(2, 2))
	for y: int in range(sil.get_height()):
		for x: int in range(sil.get_width()):
			white += (_lum(sil.get_pixel(x, y)) - clear) / (1.0 - clear)
	var ratio: float = white / float(inside)
	_check(absf(ratio - 1.0) < 0.03, "silhouette mode's area is the baked area (ratio %f)" % ratio)
	# Silhouette mode is white on the clear colour: no ink, no fill.
	_check(_lum(sil.get_pixel(2, 2)) < 0.1, "silhouette mode leaves the background alone")


## One bilinear sample of the noise texture's [param channel] (0 r, 1 g, 2 b, 3 a) at [param uv],
## repeating, at the level of detail 0: the twin of the shader's texture() on the shared noise.
func _noise_at(img: Image, uv: Vector2, channel: int) -> float:
	var p: Vector2 = uv * NOISE_PX - Vector2(0.5, 0.5)
	var x0: int = floori(p.x)
	var y0: int = floori(p.y)
	var fx: float = p.x - float(x0)
	var fy: float = p.y - float(y0)
	var v: Array[float] = []
	for k: int in range(4):
		var px: int = posmod(x0 + (k % 2), int(NOISE_PX))
		var py: int = posmod(y0 + (k / 2), int(NOISE_PX))
		v.append(img.get_pixel(px, py)[channel])
	return lerpf(lerpf(v[0], v[1], fx), lerpf(v[2], v[3], fx), fy)


## The wobble at [param p_u] (u from the feet) on boil step [param boil]: ink_wobble() of
## shaders/ink/ink_common.gdshaderinc, as 0.5 + 0.5 w / wobble_u.
func _wobble_twin(img: Image, p_u: Vector2, boil: float) -> float:
	var off := Vector2(0.7548776662, 0.5698402909) * fmod(boil, 4096.0)
	off = Vector2(off.x - floorf(off.x), off.y - floorf(off.y))
	var a: float = _noise_at(img, p_u / (_tuning.wave1_u * WOBBLE_FIRST_OCTAVE_CELLS) + off, 2)
	var b: float = _noise_at(
		img, p_u / (_tuning.wave2_u * WOBBLE_SECOND_OCTAVE_CELLS) + Vector2(off.y, off.x), 3
	)
	var w: float = (
		(a - 0.5) * 2.0 * WOBBLE_FIRST_OCTAVE_WEIGHT
		+ (b - 0.5) * 2.0 * (1.0 - WOBBLE_FIRST_OCTAVE_WEIGHT)
	)
	return 0.5 + 0.5 * w


func _test_the_wobble_is_the_two_octave_noise() -> void:
	# Shader mode 4 draws the wobble field as a grey; the CPU twin of it from the noise image must
	# agree at every sample: the octaves' wavelengths, their share of the amplitude, which noise
	# channel each reads, and the boil step's offset (an edit to any of them moves a pixel).
	var tick: int = 17
	var boil: float = InkGlobals.boil_step(
		tick, (load(LightingTuning.PATH) as LightingTuning).boil_hz
	)
	var ember: Vector2 = InkRender.ember_world()
	InkRender.set_globals(_tuning, tick, ember, InkRender.DUSK)
	var centre: Vector2 = InkProbe.STAGE_MARK_U + Vector2(0.0, -20.0)
	var zoom: float = 8.0
	var vp: SubViewport = InkRender.viewport(root, InkRender.VIEW_4X, zoom, centre)
	var fig: InkSprite = InkRender.add_stage_and_figure(vp, _stage, _fig4, false)
	fig.mode = InkSprite.Mode.WOBBLE
	var img: Image = await InkRender.capture(self, vp)
	vp.queue_free()
	var noise_img: Image = _noise.get_image()
	var worst: float = 0.0
	var spread_lo: float = 1.0
	var spread_hi: float = 0.0
	var n: int = 0
	for dy: int in range(-9, 3, 2):
		for dx: int in range(-5, 6, 2):
			var p_u := Vector2(float(dx), float(dy) - 20.0)
			var px := Vector2i(Vector2(img.get_size()) * 0.5 + Vector2(p_u.x, p_u.y + 20.0) * zoom)
			var got: float = img.get_pixelv(px).r
			var want: float = _wobble_twin(noise_img, p_u, boil)
			worst = maxf(worst, absf(got - want))
			spread_lo = minf(spread_lo, want)
			spread_hi = maxf(spread_hi, want)
			n += 1
	_check(
		worst < 0.02,
		"the wobble the shader draws is its CPU twin's at %d points (worst %.4f)" % [n, worst]
	)
	_check(
		spread_hi - spread_lo > 0.15,
		(
			"the wobble moves over the samples, so the comparison means something (%.3f to %.3f)"
			% [spread_lo, spread_hi]
		)
	)


## Counts the pixels along row [param y] of [param img] from x0 to x1 (inclusive) darker than
## [param limit] times [param fill_lum].
func _dark_run(img: Image, y: int, x0: int, x1: int, fill_lum: float, limit: float) -> int:
	var n: int = 0
	for x: int in range(x0, x1 + 1):
		if _lum(img.get_pixel(x, y)) < limit * fill_lum:
			n += 1
	return n


func _test_line_follows_the_light() -> void:
	# The key light is toward the upper left, so a head's left edge is the lit side and its right
	# edge the shadow side. At 4x the head's row is y = 232 - 54 = 178 world; the view centre is
	# (250, 194), 4 px a u, so screen y = (178 - 194) * 4 + 180 = 116 and x = (wx - 250) * 4 + 320.
	for facing: int in [1, -1]:
		var img: Image = await _shot_facing(facing, _tuning, 0)
		var widths: Vector2i = _head_widths(img)
		var left: int = widths.x
		var right: int = widths.y
		_check(
			right >= left + 3,
			(
				"the line is heavier on the shadow side than the lit side, facing %d (left %d, right %d px)"
				% [facing, left, right]
			)
		)
		_check(left >= 1, "the lit side keeps a hairline, facing %d" % facing)
	# The line never falls under line_min_px: at 1x the lit side is still at least a pixel of ink.
	var one: Image = await _shot(_fig1, 1.0, 0, InkRender.DUSK, false)
	var row: int = 232 - 54
	var hx: int = 240
	var fill1: float = _lum(one.get_pixel(hx, row))
	var darker: int = _dark_run(one, row, hx - 11, hx - 9, fill1, 0.75)
	_check(darker >= 1, "at 1x the lit side's line is at least a pixel")


func _shot_facing(facing: int, tuning: InkTuning, tick: int) -> Image:
	var ember: Vector2 = InkRender.ember_world()
	InkRender.set_globals(tuning, tick, ember, InkRender.DUSK)
	var vp: SubViewport = InkRender.viewport(
		root, InkRender.VIEW_4X, 4.0, InkProbe.STAGE_MARK_U + Vector2(10.0, -38.0)
	)
	var fig: InkSprite = InkRender.add_stage_and_figure(vp, _stage, _fig4, false)
	fig.facing = facing
	var img: Image = await InkRender.capture(self, vp)
	vp.queue_free()
	return img


func _test_pitch_and_ember() -> void:
	# With the ember far away only ambient lights the pillar: Pitch is 0.15 of Dusk's ambient.
	var far: Vector2 = Vector2(240.0, 5000.0)
	InkRender.set_globals(_tuning, 0, far, InkRender.DUSK)
	var vp_d: SubViewport = InkRender.viewport(
		root, InkRender.VIEW_1X, 1.0, Vector2(InkRender.VIEW_1X) * 0.5
	)
	InkRender.add_stage_and_figure(vp_d, _stage, _fig1, true)
	var amb_dusk: Image = await InkRender.capture(self, vp_d, true)
	vp_d.queue_free()
	InkRender.set_globals(_tuning, 0, far, InkRender.PITCH)
	# Hold the key's own Dark at Dusk: at Pitch the key falls under the lit threshold and the
	# surface drops to its shadow value (the two-value choice, checked by the lighting GPU check).
	# This check is the ambient colour's multiplier alone.
	RenderingServer.global_shader_parameter_set(&"wane_dark", 1.0)
	var vp_p: SubViewport = InkRender.viewport(
		root, InkRender.VIEW_1X, 1.0, Vector2(InkRender.VIEW_1X) * 0.5
	)
	InkRender.add_stage_and_figure(vp_p, _stage, _fig1, true)
	var amb_pitch: Image = await InkRender.capture(self, vp_p, true)
	vp_p.queue_free()
	var sum_d: float = 0.0
	var sum_p: float = 0.0
	for y: int in range(20, 120):
		for x: int in range(404, 420):
			sum_d += _lum(amb_dusk.get_pixel(x, y))
			sum_p += _lum(amb_pitch.get_pixel(x, y))
	_check(sum_d > 0.0, "Dusk's ambient lights the pillar")
	var ratio: float = sum_p / sum_d
	_check(ratio > 0.1 and ratio < 0.25, "Pitch ambient is 0.15 of Dusk's (ratio %f)" % ratio)
	# The ember itself (white-hot, an emissive) is the same at both and carries no ink ring.
	var dusk: Image = await _shot(_fig1, 1.0, 0, InkRender.DUSK, true)
	var pitch: Image = await _shot(_fig1, 1.0, 0, InkRender.PITCH, true)
	var e: Vector2i = Vector2i(240, 202)
	_check(_lum(dusk.get_pixel(e.x, e.y)) > 0.95, "the ember is white-hot at Dusk")
	_check(
		_lum(pitch.get_pixel(e.x, e.y)) > 0.95,
		"the ember is white-hot at Pitch: ambient does not touch it"
	)
	_check(_lum(pitch.get_pixel(e.x + 2, e.y)) > 0.9, "the ember has no ink ring")
	# At Pitch the world is the ember: the floor under it is lit, the floor far away is not.
	var near_floor: float = _lum(pitch.get_pixel(240, 250))
	var far_floor: float = _lum(pitch.get_pixel(20, 250))
	_check(
		near_floor > 2.0 * far_floor,
		(
			"at Pitch the floor is lit near the ember (%f) and dark far from it (%f)"
			% [near_floor, far_floor]
		)
	)


func _instance_shot(values: bool) -> Image:
	var ember: Vector2 = InkRender.ember_world()
	InkRender.set_globals(_tuning, 0, ember, InkRender.DUSK)
	var vp: SubViewport = InkRender.viewport(root, InkRender.VIEW_1X, 1.0, Vector2(240.0, 135.0))
	var bg := ColorRect.new()
	bg.color = FLAT_BG
	bg.position = Vector2(-100, -100)
	bg.size = Vector2(1000, 1000)
	vp.add_child(bg)
	var sprites: Array[InkSprite] = []
	for i: int in range(4):
		var s := InkSprite.new()
		s.carries_ember = true
		vp.add_child(s)
		s.setup(_fig1, &"idle")
		s.position = Vector2(140.0 + 60.0 * float(i), 232.0)
		sprites.append(s)
	if values:
		sprites[1].flash = 1.0
		sprites[2].opacity = 0.5
		sprites[3].dissolve = 1.0
		_check(
			(
				sprites[0].material == sprites[1].material
				and sprites[1].material == sprites[3].material
			),
			"four sprites of one family share one material"
		)
	var img: Image = await InkRender.capture(self, vp)
	vp.queue_free()
	return img


func _test_instance_values_on_one_material() -> void:
	var ref: Image = await _instance_shot(false)
	var img: Image = await _instance_shot(true)
	# Body pixel of each (17 u above the feet, under the ember).
	var y: int = 215
	var plain: Color = img.get_pixel(140, y)
	_check(
		_lum(plain) > 0.15 and _lum(plain) < 0.95,
		"the plain figure is drawn (lum %f)" % _lum(plain)
	)
	_check(
		img.get_pixel(140, y).is_equal_approx(ref.get_pixel(140, y)),
		"a figure with neutral values is unchanged"
	)
	_check(
		_lum(img.get_pixel(200, y)) > 0.97,
		"flash 1 turns the figure white (lum %f)" % _lum(img.get_pixel(200, y))
	)
	var want: float = 0.5 * _lum(ref.get_pixel(260, y)) + 0.5 * _lum(FLAT_BG)
	var got: float = _lum(img.get_pixel(260, y))
	_check(absf(got - want) < 0.03, "opacity 0.5 blends half (lum %f, want %f)" % [got, want])
	_check(
		absf(_lum(img.get_pixel(320, y)) - _lum(FLAT_BG)) < 0.02,
		"dissolve 1 leaves nothing (lum %f)" % _lum(img.get_pixel(320, y))
	)
	# A palette variant is another row of the palette.
	var hurt: Image = await _shot_row(1)
	var rest: Image = await _shot_row(0)
	var h: Color = hurt.get_pixel(240, y)
	var r: Color = rest.get_pixel(240, y)
	_check((h.r - h.g) > (r.r - r.g) + 0.05, "palette row 1 is redder than row 0")


func _shot_row(row: int) -> Image:
	var ember: Vector2 = InkRender.ember_world()
	InkRender.set_globals(_tuning, 0, ember, InkRender.DUSK)
	var vp: SubViewport = InkRender.viewport(root, InkRender.VIEW_1X, 1.0, Vector2(240.0, 135.0))
	var fig: InkSprite = InkRender.add_stage_and_figure(vp, _stage, _fig1, false)
	fig.palette_row = row
	var img: Image = await InkRender.capture(self, vp)
	vp.queue_free()
	return img


func _test_scales_agree() -> void:
	# The 1x sheet drawn at 4x zoom against the 4x master: the same shapes (the distance fields
	# interpolate, so the line stays crisp), the same line weight in u.
	var ember: Vector2 = InkRender.ember_world()
	var shots: Array[Image] = []
	for sheet: SpriteSheet in [_fig1, _fig4]:
		InkRender.set_globals(_tuning, 0, ember, InkRender.DUSK)
		var vp: SubViewport = InkRender.viewport(
			root, InkRender.VIEW_4X, 4.0, InkProbe.STAGE_MARK_U + Vector2(10.0, -38.0)
		)
		var fig: InkSprite = InkRender.add_stage_and_figure(vp, _stage, sheet, false)
		fig.mode = InkSprite.Mode.SILHOUETTE
		shots.append(await InkRender.capture(self, vp))
		vp.queue_free()
	var a: float = 0.0
	var b: float = 0.0
	for y: int in range(shots[0].get_height()):
		for x: int in range(shots[0].get_width()):
			a += _lum(shots[0].get_pixel(x, y))
			b += _lum(shots[1].get_pixel(x, y))
	_check(
		absf(a / b - 1.0) < 0.02,
		"the 1x and 4x sheets agree on the silhouette (area ratio %f)" % (a / b)
	)
	var diff: float = 0.0
	for y: int in range(shots[0].get_height()):
		for x: int in range(shots[0].get_width()):
			diff += absf(_lum(shots[0].get_pixel(x, y)) - _lum(shots[1].get_pixel(x, y)))
	_check(
		diff / b < 0.12,
		"the 1x sheet at 4x zoom is the 4x master's shape (diff share %f)" % (diff / b)
	)


## The ink widths in pixels on the head's lit (left) and shadow (right) edges of a 4x frame. 44 px
## is the head's radius: pixel cx - 44 is the first inside on the left and cx + 43 the last on the
## right. Ink is what is darker than 0.45 of the fill 14 px in from that edge (the head's own
## shadow value is darker than its lit one, so one reference for both sides would count it).
func _head_widths(img: Image) -> Vector2i:
	var y: int = 116
	var cx: int = int((240.0 - 250.0) * 4.0 + 320.0)
	var lit_fill: float = _lum(img.get_pixel(cx - 30, y))
	var shadow_fill: float = _lum(img.get_pixel(cx + 29, y))
	return Vector2i(
		_dark_run(img, y, cx - 44, cx - 34, lit_fill, 0.45),
		_dark_run(img, y, cx + 34, cx + 43, shadow_fill, 0.45)
	)


func _test_tuning_reaches_the_shader() -> void:
	var base: Vector2i = _head_widths(await _shot_facing(1, _tuning, 0))
	var heavy: InkTuning = _tuning.duplicate() as InkTuning
	heavy.line_shadow_u = 2.6
	var wide: Vector2i = _head_widths(await _shot_facing(1, heavy, 0))
	_check(
		wide.y >= base.y + 3,
		(
			"line_shadow_u reaches the shader: the shadow side doubles (%d px to %d px)"
			% [base.y, wide.y]
		)
	)
	var calm: InkTuning = _tuning.duplicate() as InkTuning
	calm.wobble_u = 0.0
	var still_a: Image = await _shot_facing(1, calm, 5)
	var still_b: Image = await _shot_facing(1, calm, 10)
	_check(
		_bytes_equal(still_a, still_b),
		"with no wobble amplitude a new boil step draws the same frame: the boil is the only clock"
	)
