extends SceneTree
## What the lit pictures must show (docs/adr/0026; BUILD.md section 10, Style, Lighting, Animation),
## measured on the pictures the review draws: a [LightField] with its halos, the painted backdrop
## through the background shader, and the artbuild probe (tests/screenshot/data/probe) standing in
## the lit test room. Each check is a number the director's eye reads off the review:
##   two values follow the shape (and not a ring of distance); a Wick stays lit at Pitch and stands
##   off its ground; the ember is warm, carries no dark ring and has a halo; a smear is a ribbon
##   that fades toward its tail; a hairline is lighter than a heavy line at 1x and a sprite beyond
##   every light draws the heavy line all round; the background's line is open and drops out where
##   the light is, over a brushed, grained surface; gloss reaches the shader.
## Needs a display:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 \
##     --script tests/screenshot/run_form_render_tests.gd
## Exits 0 when every check passes, 1 otherwise.

const PROBE_DIR: String = "res://tests/screenshot/data/probe"
## The probe's parts from its feet, in u (tools/artbuild/tests/data/probe/parts.svg, origin 32 61).
const HEAD_REL: Vector2 = Vector2(0.0, -45.5)
const HEAD_RADIUS_U: float = 9.0
const EMBER_REL: Vector2 = Vector2(-1.0, -28.0)
const BLADE_PIVOT_REL: Vector2 = Vector2(12.0, -22.0)
## The blade's rest direction, from its pivot to its tip, in degrees (y down), and the swing's
## sub-poses around it (tools/artbuild/tests/data/probe/pose.json: the arc is -20, 0 and +20).
const BLADE_REST_DEG: float = -42.6

var _failures: PackedStringArray = []
var _checks: int = 0
var _noise: Texture2D
var _sheet1: SpriteSheet
var _sheet2: SpriteSheet
var _ink: InkTuning
## The camera of the shot being read, for [method _px].
var _centre: Vector2 = Vector2.ZERO
var _zoom: float = 1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	_noise = SpriteSheet.load_noise()
	_sheet1 = SpriteSheet.open(PROBE_DIR, "probe", 1, _noise)
	_sheet2 = SpriteSheet.open(PROBE_DIR, "probe", 2, _noise)
	if not _sheet1.is_valid() or not _sheet2.is_valid():
		printerr("form render: the probe's sheets are not valid: %s" % "; ".join(_sheet1.errors))
		quit(2)
		return
	_ink = load(InkTuning.PATH) as InkTuning
	InkGlobals.apply(_ink)
	await _test_two_values_follow_the_shape()
	await _test_a_wick_stays_lit_at_pitch_and_stands_off_its_ground()
	await _test_the_ember()
	await _test_a_smear_is_a_ribbon()
	await _test_hairlines_and_the_line_light()
	await _test_the_background_line_and_surface()
	await _test_gloss_reaches_the_shader()
	print("form render: %d checks, %d failed" % [_checks, _failures.size()])
	for f: String in _failures:
		printerr("  FAIL ", f)
	quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## The screen pixel of world point [param w] in the shot last taken.
func _px(img: Image, w: Vector2) -> Vector2i:
	return Vector2i(Vector2(img.get_size()) * 0.5 + (w - _centre) * _zoom)


func _at(img: Image, w: Vector2) -> Color:
	return img.get_pixelv(_px(img, w))


## The mean luminance of the world rectangle [param r] in [param img].
func _mean(img: Image, r: Rect2) -> float:
	var a: Vector2i = _px(img, r.position)
	var b: Vector2i = _px(img, r.end)
	var total: float = 0.0
	var n: int = 0
	for y: int in range(a.y, b.y):
		for x: int in range(a.x, b.x):
			total += _lum(img.get_pixel(x, y))
			n += 1
	return total / float(maxi(n, 1))


func _shot(
	rig: ArtRig, tick: int, level: float, ember: Vector2, zoom: float, centre: Vector2
) -> Image:
	_zoom = zoom
	_centre = centre
	return await rig.shot(tick, level, ember, zoom, centre)


func _rig(tuning: LightingTuning = null, backdrop: bool = true) -> ArtRig:
	var rig := ArtRig.new(self, _noise, tuning, backdrop)
	await rig.settle()
	return rig


# --- two values -------------------------------------------------------------------------------


## Where the head's row steps from its lit value to its shadow value, and the two values: the
## biggest drop in the mean of three pixels against the mean of the next three, over the interior
## of the row (at 4x), as a position from the head's centre in head radii (0 centre, 1 the right
## edge), with the value left of the step and the value right of it. The step is where the form
## turns from the light; a slow gradient (the light's own falloff) does not make one.
func _head_split(img: Image, head: Vector2) -> Vector3:
	var c: Vector2i = _px(img, head)
	var inner: int = int((HEAD_RADIUS_U - 1.8) * _zoom)
	var lums: Array[float] = []
	for dx: int in range(-inner, inner + 1):
		lums.append(_lum(img.get_pixel(c.x + dx, c.y)))
	var best: float = 0.0
	var at: int = 0
	for i: int in range(3, lums.size() - 3):
		var left: float = (lums[i - 3] + lums[i - 2] + lums[i - 1]) / 3.0
		var right: float = (lums[i] + lums[i + 1] + lums[i + 2]) / 3.0
		if left - right > best:
			best = left - right
			at = i
	var lit: float = (lums[at - 3] + lums[at - 2] + lums[at - 1]) / 3.0
	var shadow: float = (lums[at] + lums[at + 1] + lums[at + 2]) / 3.0
	return Vector3(float(at - inner) / float(inner), lit, shadow)


func _test_two_values_follow_the_shape() -> void:
	var rig: ArtRig = await _rig()
	rig.sprite.setup(_sheet2, &"idle")
	var head: Vector2 = ArtRig.MARK + HEAD_REL
	var steps: Array[float] = []
	# At Pitch the ember is the only light (the room's key is off), so what the head shows is the
	# ember's form alone, at three distances.
	for d: float in [50.0, 80.0, 130.0]:
		var img: Image = await _shot(rig, 0, 3.0, head + Vector2(-d, 0.0), 4.0, head)
		var split: Vector3 = _head_split(img, head)
		steps.append(split.x)
		_check(
			split.z < 0.8 * split.y,
			(
				"the head shows two values with the ember %d u away (lit %.2f, shadow %.2f)"
				% [int(d), split.y, split.z]
			)
		)
		_check(
			split.x > 0.0 and split.x < 0.7,
			(
				"the shadow is a crescent on the far side of the head, the ember %d u away (step at %.2f radii)"
				% [int(d), split.x]
			)
		)
	_check(
		absf(steps[0] - steps[2]) < 0.15 and absf(steps[0] - steps[1]) < 0.15,
		(
			"the terminator follows the shape, not the distance: the step is at %s radii (50, 80, 130 u)"
			% [steps]
		)
	)
	rig.free_all()


func _test_a_wick_stays_lit_at_pitch_and_stands_off_its_ground() -> void:
	var rig: ArtRig = await _rig()
	rig.sprite.carries_ember = true
	rig.sprite.setup(_sheet1, &"idle")
	var centre := Vector2(320.0, 192.0)
	var ember: Vector2 = ArtRig.MARK + EMBER_REL
	var dusk: Image = await _shot(rig, 0, 1.0, ember, 1.0, centre)
	var pitch: Image = await _shot(rig, 0, 3.0, ember, 1.0, centre)
	var robe := Rect2(342.0, 300.0, 16.0, 14.0)
	var wall := Rect2(300.0, 267.0, 25.0, 45.0)
	var robe_dusk: float = _mean(dusk, robe)
	var robe_pitch: float = _mean(pitch, robe)
	var wall_pitch: float = _mean(pitch, wall)
	_check(
		robe_pitch > 0.5 * robe_dusk,
		(
			"a Wick is lit by its own ember at Pitch, not dropped to its shadow value (%.3f of %.3f)"
			% [robe_pitch, robe_dusk]
		)
	)
	_check(
		robe_pitch > 1.5 * wall_pitch,
		(
			"a Wick's body stands off the wall behind it at Pitch (%.3f against %.3f)"
			% [robe_pitch, wall_pitch]
		)
	)
	rig.free_all()


# --- the ember --------------------------------------------------------------------------------


func _test_the_ember() -> void:
	var rig: ArtRig = await _rig()
	rig.sprite.carries_ember = true
	rig.sprite.setup(_sheet1, &"idle")
	var centre := Vector2(320.0, 192.0)
	var ember: Vector2 = ArtRig.MARK + EMBER_REL
	var img: Image = await _shot(rig, 0, 3.0, ember, 1.0, centre)
	# The core is HDR, brighter than 1: only the post pass's shoulder gives it a colour on screen
	# (a per-channel clip would make it white).
	rig.field.set_post_enabled(true)
	var toned: Image = await _shot(rig, 0, 3.0, ember, 1.0, centre)
	rig.field.set_post_enabled(false)
	var core: Color = _at(toned, ember)
	_check(_lum(core) > 0.75, "the ember's core is bright (%.2f)" % _lum(core))
	_check(
		core.r - core.b > 0.1,
		(
			"the ember's core is warm, not white: the shoulder keeps its hue (r %.2f b %.2f)"
			% [core.r, core.b]
		)
	)
	# Its halo: the same picture with the halos off is darker just outside the body.
	var plain: LightingTuning = rig.tuning.duplicate() as LightingTuning
	plain.glow_strength = 0.0
	rig.free_all()
	var rig2: ArtRig = await _rig(plain)
	rig2.sprite.carries_ember = true
	rig2.sprite.setup(_sheet1, &"idle")
	var bare: Image = await _shot(rig2, 0, 3.0, ember, 1.0, centre)
	# No ring of ink around the ember (looked for without the halo, which would brighten it): the
	# pixels next to the core are not darker than the robe around them.
	var body: float = _mean(bare, Rect2(342.0, 300.0, 16.0, 14.0))
	var darkest: float = 1.0
	for off: Vector2 in [
		Vector2(-3, 0),
		Vector2(-3.5, 0),
		Vector2(-2, -2.5),
		Vector2(-2, 2.5),
		Vector2(0, 3),
		Vector2(0, -3)
	]:
		darkest = minf(darkest, _lum(_at(bare, ember + off)))
	_check(
		darkest > 0.6 * body,
		"the ember has no dark ring (darkest next to it %.2f, the robe %.2f)" % [darkest, body]
	)
	var spot := Rect2(335.0, 289.0, 4.0, 5.0)
	var with_halo: float = _mean(img, spot)
	var without: float = _mean(bare, spot)
	_check(
		with_halo > 1.06 * without,
		"a light draws a halo over the wall beside it (%.3f against %.3f)" % [with_halo, without]
	)
	rig2.free_all()


# --- the smear --------------------------------------------------------------------------------


func _test_a_smear_is_a_ribbon() -> void:
	var rig: ArtRig = await _rig(null, false)
	rig.sprite.setup(_sheet2, &"swing")
	rig.sprite.show_frame(&"swing", 1)
	rig.sprite.mode = InkSprite.Mode.SILHOUETTE
	var pivot: Vector2 = ArtRig.MARK + BLADE_PIVOT_REL
	var img: Image = await _shot(rig, 0, 1.0, Vector2(-500.0, 0.0), 4.0, pivot)
	var alphas: Array[float] = []
	for deg: float in [-62.0, -54.0, -46.0, -38.0, -30.0, -25.0]:
		var a: float = deg_to_rad(deg)
		var at: Vector2 = pivot + Vector2(cos(a), sin(a)) * 14.0
		alphas.append(_lum(_at(img, at)))
	var mono: bool = true
	for i: int in range(1, alphas.size()):
		mono = mono and alphas[i] >= alphas[i - 1] - 0.05
	_check(mono, "a smear fades toward its tail: opacity along the arc %s" % [alphas])
	_check(alphas[0] < 0.4, "the tail of the smear is faint (%.2f)" % alphas[0])
	_check(
		alphas[alphas.size() - 1] > 0.7, "the blade end of the smear is solid (%.2f)" % alphas[-1]
	)
	# Its line is a ribbon's: at the tail edge there is no closed outline. Lit, the picture's
	# tail end holds no near-black line pixels while the blade end does.
	rig.sprite.mode = InkSprite.Mode.LIT
	RenderingServer.set_default_clear_color(Color(0.5, 0.5, 0.5))
	var lit: Image = await _shot(rig, 0, 1.0, pivot + Vector2(-120.0, 0.0), 4.0, pivot)
	RenderingServer.set_default_clear_color(Color.BLACK)
	var tail_dark: int = _dark_pixels(lit, pivot, -62.0, -52.0)
	var head_dark: int = _dark_pixels(lit, pivot, -30.0, -20.0)
	_check(
		tail_dark < head_dark,
		(
			"the smear's line thins out toward the tail (%d dark pixels there, %d at the blade)"
			% [tail_dark, head_dark]
		)
	)
	rig.free_all()


## How many pixels darker than 0.25 lie in the wedge of angles [param from_deg] to [param to_deg]
## about [param pivot], 6 to 26 u out.
func _dark_pixels(img: Image, pivot: Vector2, from_deg: float, to_deg: float) -> int:
	var n: int = 0
	for deg: int in range(int(from_deg), int(to_deg) + 1):
		for r10: int in range(60, 261, 2):
			var a: float = deg_to_rad(float(deg))
			var p: Vector2 = pivot + Vector2(cos(a), sin(a)) * (float(r10) / 10.0)
			var c: Color = _at(img, p)
			if _lum(c) < 0.25 and c.a > 0.5:
				n += 1
	return n


# --- hairlines --------------------------------------------------------------------------------


## How much ink a window of the picture holds: the sum, over world x in [param x0, x1] and the rows
## about [param y], of the picture [param drawn] over the same picture with the ink black.
func _ink_sum(drawn: Image, black: Image, x0: float, x1: float, y: float) -> float:
	var total: float = 0.0
	var x: float = x0
	while x <= x1:
		for dy: int in range(-1, 2):
			var w := Vector2(x, y + float(dy))
			total += _lum(_at(drawn, w)) - _lum(_at(black, w))
		x += 1.0
	return total


## The darkest luminance over world x in [param x0, x1] (just inside the edge, where the line is) on
## row [param y], over the luminance at x = [param ref_x]: how much of the fill's value the line
## leaves.
func _line_ratio(img: Image, y: float, x0: float, x1: float, ref_x: float) -> float:
	var lowest: float = 10.0
	var x: float = x0
	while x <= x1:
		lowest = minf(lowest, _lum(_at(img, Vector2(x, y))))
		x += 0.5
	return lowest / maxf(_lum(_at(img, Vector2(ref_x, y))), 0.0001)


func _test_hairlines_and_the_line_light() -> void:
	var rig: ArtRig = await _rig()
	rig.sprite.setup(_sheet1, &"idle")
	var head: Vector2 = ArtRig.MARK + HEAD_REL
	var left_edge: float = head.x - HEAD_RADIUS_U
	var right_edge: float = head.x + HEAD_RADIUS_U
	var near: Image = await _shot(rig, 0, 1.0, head + Vector2(-120.0, 0.0), 1.0, head)
	var lit_side: float = _line_ratio(near, head.y, left_edge, left_edge + 2.0, left_edge + 5.0)
	var shadow_side: float = _line_ratio(
		near, head.y, right_edge - 2.0, right_edge, right_edge - 5.0
	)
	_check(
		lit_side > 0.55 and shadow_side < 0.45 and lit_side > shadow_side + 0.25,
		(
			"at 1x the hairline is lighter than the heavy line (lit side keeps %.2f, shadow side %.2f)"
			% [lit_side, shadow_side]
		)
	)
	# The line's weight follows the light: the ink on the lit side is a fraction of the shadow side's.
	var inkless: InkTuning = _ink.duplicate() as InkTuning
	inkless.ink_value = 0.0
	inkless.ink_over_fill = 0.0
	InkGlobals.apply(inkless)
	var near_black: Image = await _shot(rig, 0, 1.0, head + Vector2(-120.0, 0.0), 1.0, head)
	InkGlobals.apply(_ink)
	var ink_lit: float = _ink_sum(near, near_black, left_edge - 1.0, left_edge + 2.0, head.y)
	var ink_shadow: float = _ink_sum(near, near_black, right_edge - 2.0, right_edge + 1.0, head.y)
	_check(
		ink_lit < 0.6 * ink_shadow,
		(
			"the line is lighter on the lit side (ink %.3f against %.3f on the shadow side)"
			% [ink_lit, ink_shadow]
		)
	)
	# Beyond every light (the room's key is off and the ember is far) the line is the heavy one on
	# both sides: the line light returns no strength, not a unit vector.
	var far_ember: Vector2 = head + Vector2(-1000.0, 0.0)
	rig.field.key = Vector4(rig.field.key.x, rig.field.key.y, 0.0, 0.0)
	var dark: Image = await _shot(rig, 0, 1.0, far_ember, 1.0, head)
	InkGlobals.apply(inkless)
	var dark_black: Image = await _shot(rig, 0, 1.0, far_ember, 1.0, head)
	InkGlobals.apply(_ink)
	var dark_lit: float = _ink_sum(dark, dark_black, left_edge - 1.0, left_edge + 2.0, head.y)
	var dark_shadow: float = _ink_sum(dark, dark_black, right_edge - 2.0, right_edge + 1.0, head.y)
	_check(
		dark_lit > 0.7 * dark_shadow,
		(
			"a sprite beyond every light draws the heavy line on its lit side too (ink %.3f against %.3f)"
			% [dark_lit, dark_shadow]
		)
	)
	rig.free_all()


# --- the background ---------------------------------------------------------------------------


## How much ink the background draws in each column x0..x1 of the window [y0, y1]: the picture
## against the same picture with the ink drawn black, so that only the line differs (the fill, the
## rim and the grain are the same in both), as the largest difference in luminance in the column.
func _ink_columns(
	drawn: Image, black: Image, x0: int, x1: int, y0: float, y1: float
) -> Array[float]:
	var out: Array[float] = []
	for x: int in range(x0, x1 + 1):
		var most: float = 0.0
		var y: float = y0
		while y <= y1:
			var w := Vector2(float(x), y)
			most = maxf(most, _lum(_at(drawn, w)) - _lum(_at(black, w)))
			y += 1.0
		out.append(most)
	return out


## The share of [param cols] at least [param lo] and under [param hi].
func _share(cols: Array[float], lo: float, hi: float) -> float:
	var n: int = 0
	for v: float in cols:
		if v >= lo and v < hi:
			n += 1
	return float(n) / float(cols.size())


func _test_the_background_line_and_surface() -> void:
	var rig: ArtRig = await _rig()
	rig.sprite.visible = false
	var centre := Vector2(224.0, 176.0)
	var far_ember := Vector2(1400.0, 176.0)
	var near_ember := Vector2(224.0, 215.0)
	# The ledge's underside, y = 192, from x = 172 to 276: with the ember far, then right below it.
	# The same shots with the ink black: what differs is the line, and only the line.
	var far: Image = await _shot(rig, 0, 1.0, far_ember, 1.0, centre)
	var near: Image = await _shot(rig, 0, 1.0, near_ember, 1.0, centre)
	var inkless: InkTuning = _ink.duplicate() as InkTuning
	inkless.ink_value = 0.0
	inkless.ink_over_fill = 0.0
	InkGlobals.apply(inkless)
	var far_black: Image = await _shot(rig, 0, 1.0, far_ember, 1.0, centre)
	var near_black: Image = await _shot(rig, 0, 1.0, near_ember, 1.0, centre)
	InkGlobals.apply(_ink)
	var line_far: Array[float] = _ink_columns(far, far_black, 172, 276, 186.0, 198.0)
	var line_near: Array[float] = _ink_columns(near, near_black, 172, 276, 186.0, 198.0)
	var strongest: float = line_far.max()
	_check(
		strongest > 0.02,
		"a background draws a line at its edge (strongest column %.3f)" % strongest
	)
	var whole: float = _share(line_far, 0.6 * strongest, 10.0)
	var broken: float = _share(line_far, 0.0, 0.6 * strongest)
	_check(
		whole > 0.3 and broken > 0.15,
		(
			"a background's line is open: whole along %.2f of the edge, broken along %.2f"
			% [whole, broken]
		)
	)
	var left_in_light: float = _share(line_near, 0.2 * strongest, 10.0)
	_check(
		left_in_light < 0.1,
		(
			"a background's line drops out where the light hits it (%.2f of the edge keeps it there)"
			% left_in_light
		)
	)
	# The surface: a brushed, grained back wall, at 4x so that a streak is wider than a pixel.
	# Horizontal streaks (the part's major axis) correlate along a row far more than down a column.
	var wall: Image = await _shot(rig, 0, 1.0, far_ember, 4.0, Vector2(330.0, 60.0))
	var c: Vector2i = Vector2i(wall.get_size() / 2)
	var along: float = 0.0
	var across: float = 0.0
	var total: float = 0.0
	for y: int in range(c.y - 60, c.y + 60):
		for x: int in range(c.x - 60, c.x + 60):
			var v: float = _lum(wall.get_pixel(x, y))
			along += absf(_lum(wall.get_pixel(x + 1, y)) - v)
			across += absf(_lum(wall.get_pixel(x, y + 1)) - v)
			total += v
	_check(
		across > 1.25 * along,
		(
			"the back wall is brushed along its major axis (a row changes %.1f, a column %.1f)"
			% [along, across]
		)
	)
	var mean: float = total / 14400.0
	_check(
		(along + across) / 28800.0 > 0.002 * mean,
		(
			"the back wall carries paper grain and brush (step %.5f of %.3f)"
			% [(along + across) / 28800.0, mean]
		)
	)
	rig.free_all()


# --- gloss ------------------------------------------------------------------------------------


func _test_gloss_reaches_the_shader() -> void:
	var rig: ArtRig = await _rig(null, false)
	rig.sprite.setup(_sheet2, &"idle")
	var body: Vector2 = ArtRig.MARK + Vector2(0.0, -25.0)
	var glossy: Image = await _shot(rig, 0, 1.0, body + Vector2(-60.0, -20.0), 4.0, body)
	var matte: InkTuning = _ink.duplicate() as InkTuning
	matte.gloss_strength = 0.0
	InkGlobals.apply(matte)
	var flat: Image = await _shot(rig, 0, 1.0, body + Vector2(-60.0, -20.0), 4.0, body)
	InkGlobals.apply(_ink)
	var changed: int = 0
	var total: int = 0
	for y: int in range(0, glossy.get_height(), 2):
		for x: int in range(0, glossy.get_width(), 2):
			if glossy.get_pixel(x, y).is_equal_approx(flat.get_pixel(x, y)):
				continue
			changed += 1
		total += glossy.get_width() / 2
	_check(
		changed > 40,
		"gloss_strength reaches the shader: a glossy part's highlight changes %d pixels" % changed
	)
	_check(
		changed < total / 6,
		"the highlight is a highlight, not the whole picture (%d of %d pixels)" % [changed, total]
	)
	rig.free_all()
