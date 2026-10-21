extends RenderChecks
## What the lit pictures must show (docs/adr/0026; BUILD.md section 10, Style, Lighting), measured
## on the pictures the review draws: a [LightField] with its halos, the painted backdrop through
## the background shader, and the artbuild probe (tests/screenshot/data/probe) standing in the lit
## test room. Each check is a number the director's eye reads off the review:
##   two values follow the shape (and not a ring of distance); the key fades with the Dark to
##   nothing at Pitch; a Wick stays lit at Pitch and stands off its ground, and its crescent comes
##   from the key, not from where its ember is; a hairline is lighter than a heavy line at 1x, a
##   sprite beyond every light (at Pitch, the key too) draws the heavy line all round, and the ink
##   is never lighter than the fill; the background's line is open and drops out where the light
##   is, at 1x and magnified, over a brushed, grained surface; the floor's lit lip has no lens;
##   gloss reaches the shader. The ember and the smear are run_ember_and_smear_render_tests.gd.
## Needs a display:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 \
##     --script tests/screenshot/run_form_render_tests.gd
## Exits 0 when every check passes, 1 otherwise.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _begin("form render"):
		return
	await _test_two_values_follow_the_shape()
	await _test_the_key_fades_with_the_dark_to_nothing_at_pitch()
	await _test_a_wick_stays_lit_at_pitch_and_stands_off_its_ground()
	await _test_a_carriers_crescent_comes_from_the_key()
	await _test_hairlines_and_the_line_light()
	await _test_the_background_line_and_surface()
	await _test_the_floor_lip_has_no_lens()
	await _test_gloss_reaches_the_shader()
	_finish("form render")


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


## Beyond every light (the ember far away) the two-value choice of a surface facing the viewer is
## the room key's gate alone: its strength times its share at the Dark, through gate_lo to gate_hi
## (ADR-0026 Decision 1: the key is one more light). At Dusk that is the lit value; at Pitch,
## where "only the ember and Beacons cast light" (BUILD.md section 8) and "the world is the ember"
## (section 10), the key gives nothing: the surface is in its shadow value. Between, the share
## falls from 1 at Dusk to 0 at the Dark's floor (level 2.3 is a little over a third of the way).
func _test_the_key_fades_with_the_dark_to_nothing_at_pitch() -> void:
	var rig: ArtRig = await _rig(null, false)
	rig.sprite.setup(_sheet1, &"idle")
	rig.sprite.mode = InkSprite.Mode.VALUE
	var centre := Vector2(320.0, 192.0)
	var far: Vector2 = ArtRig.MARK + Vector2(-2000.0, 0.0)
	var robe := Rect2(342.0, 300.0, 16.0, 14.0)
	var t: LightingTuning = rig.tuning
	var wants: Array[float] = [1.0, -1.0, 0.0]
	var levels: Array[float] = [1.0, 2.3, 3.0]
	for i: int in range(levels.size()):
		var level: float = levels[i]
		var img: Image = await _shot(rig, 0, level, far, 1.0, centre, true)
		var got: float = _max(img, robe)
		var share: float = t.key_share(t.dark_factor(level))
		var want: float = smoothstep(t.gate_lo, t.gate_hi, rig.field.key.z * share)
		_check(
			absf(got - want) < 0.03 and (wants[i] < 0.0 or absf(want - wants[i]) < 0.001),
			(
				"beyond every light, at level %.1f, a surface has %.2f of its lit value (the key's: %.2f)"
				% [level, got, want]
			)
		)
	rig.free_all()


## A Wick's own ember lights it from the key's direction (ADR-0026 Decision 2), so its shadow
## crescent is a fixed style: wherever the ember is about the Wick, the two values are the same, and
## the crescent is on the side away from the key. (The halos are off: the ember's own would move
## over the picture with it.)
func _test_a_carriers_crescent_comes_from_the_key() -> void:
	var haloless := (load(LightingTuning.PATH) as LightingTuning).duplicate() as LightingTuning
	haloless.glow_strength = 0.0
	var rig: ArtRig = await _rig(haloless, false)
	rig.sprite.carries_ember = true
	rig.sprite.setup(_sheet2, &"idle")
	rig.sprite.mode = InkSprite.Mode.VALUE
	var head: Vector2 = ArtRig.MARK + HEAD_REL
	var chest: Vector2 = ArtRig.MARK + EMBER_REL
	var r := Vector2(HEAD_RADIUS_U, HEAD_RADIUS_U)
	var box := Rect2(head - r, r * 2.0)
	var at_chest: Image = await _shot(rig, 0, 3.0, chest, 4.0, head, true)
	var worst: float = 0.0
	for off: Vector2 in [Vector2(-30.0, 0.0), Vector2(30.0, 0.0), Vector2(0.0, -40.0)]:
		var moved: Image = await _shot(rig, 0, 3.0, chest + off, 4.0, head, true)
		worst = maxf(worst, _mean_diff(at_chest, moved, box))
	_check(
		worst < 0.01,
		"a Wick's two values do not move as its ember moves about it (mean change %.3f)" % worst
	)
	var split: Vector3 = _head_split(at_chest, head)
	_check(
		split.x > 0.0 and split.z < 0.5 * split.y,
		(
			"a Wick's crescent is on the side away from the key (step at %.2f radii, %.2f to %.2f)"
			% [split.x, split.y, split.z]
		)
	)
	rig.free_all()


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


## How many pixels over world x in [param x0, x1] on row [param y] (at the shot's zoom) are darker
## than 0.45 of the fill at x = [param ref_x]: the line's width there, in pixels.
func _line_px(img: Image, y: float, x0: float, x1: float, ref_x: float) -> int:
	var fill: float = _lum(_at(img, Vector2(ref_x, y)))
	var a: Vector2i = _px(img, Vector2(x0, y))
	var b: Vector2i = _px(img, Vector2(x1, y))
	var n: int = 0
	for x: int in range(a.x, b.x + 1):
		if _lum(img.get_pixel(x, a.y)) < 0.45 * fill:
			n += 1
	return n


## Over the pixels of row [param y] from world x [param x0] to [param x1] that [param black] (the
## same picture with the ink black) covers whole with ink, the lightest of [param drawn] as a share
## of its fill at x = [param ref_x] (x), and how many such pixels there are (y).
func _ink_over_fill(
	drawn: Image, black: Image, y: float, x0: float, x1: float, ref_x: float
) -> Vector2:
	var fill: float = _lum(_at(drawn, Vector2(ref_x, y)))
	var fill_black: float = _lum(_at(black, Vector2(ref_x, y)))
	var a: Vector2i = _px(drawn, Vector2(x0, y))
	var b: Vector2i = _px(drawn, Vector2(x1, y))
	var lightest: float = 0.0
	var n: int = 0
	for x: int in range(a.x, b.x + 1):
		if _lum(black.get_pixel(x, a.y)) < 0.1 * fill_black:
			lightest = maxf(lightest, _lum(drawn.get_pixel(x, a.y)) / maxf(fill, 0.000001))
			n += 1
	return Vector2(lightest, float(n))


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
	var key: Vector4 = rig.field.key
	rig.field.key = Vector4(key.x, key.y, 0.0, 0.0)
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
	# At Pitch the key is the Dark's (ADR-0026 Decision 1): beyond every light it is too dim to
	# weight the line, which stays heavy all round. The width is read at 4x with the ink black (at
	# Pitch a line's ink is a share of its fill, which differs side to side). Measured 7 px on the
	# key's side against 9; a key the Dark did not scale thins it to 2.
	rig.field.key = key
	InkGlobals.apply(inkless)
	var pitch_black: Image = await _shot(rig, 0, 3.0, far_ember, 4.0, head, true)
	InkGlobals.apply(_ink)
	var lit_px: int = _line_px(
		pitch_black, head.y, left_edge - 0.5, left_edge + 2.5, left_edge + 5.0
	)
	var shadow_px: int = _line_px(
		pitch_black, head.y, right_edge - 2.5, right_edge + 0.5, right_edge - 5.0
	)
	_check(
		float(lit_px) >= 0.6 * float(shadow_px) and shadow_px >= 3,
		(
			"at Pitch the key does not thin the line beyond every light (%d px lit side, %d shadow)"
			% [lit_px, shadow_px]
		)
	)
	# Ink is never lighter than the fill it covers (ADR-0023 Decision 2.1): at Pitch the fill is
	# dark, and the line is darker still, not a grey outline. The line's pixels are the ones the
	# black-ink picture covers whole.
	var pitch4: Image = await _shot(rig, 0, 3.0, far_ember, 4.0, head, true)
	var over: Vector2 = _ink_over_fill(
		pitch4, pitch_black, head.y, right_edge - 2.5, right_edge + 0.5, right_edge - 5.0
	)
	_check(
		over.y >= 2.0 and over.x < 0.8,
		(
			"at Pitch the line is darker than the fill it covers (%.2f of the fill at most, %d px)"
			% [over.x, int(over.y)]
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
	# The same at every scale (BUILD.md section 10: the art is resolution-independent): magnified
	# four times, from the 2x sheet, the line is as open as at 1x and drops out where the light hits
	# it. Its drop-out comes from the light and its breaks, not from a line too thin for a 1x pixel
	# (measured before: inked on every column of the ledge's edges at 4x, on 3 of 117 at 1x).
	await _background_line_magnified(rig, far_ember, near_ember, whole, broken)
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


## BUILD.md section 10 (Lighting: soft shadows): the floor a Wick stands on, lit by its ember at
## Pitch, shows a lit skin as deep under the light as 60 u to either side, with no step along it.
## The march walked toward the light through the wall, so the skin thinned with the angle and
## stepped with the walk: a lens of nested terraces under every light near a floor (the review's
## Pitch picture stepped 6, 13 and 33 along one row).
func _test_the_floor_lip_has_no_lens() -> void:
	var rig: ArtRig = await _rig()
	rig.set_backdrop_scale(2)
	rig.sprite.carries_ember = true
	rig.sprite.setup(_sheet2, &"idle")
	var ember: Vector2 = ArtRig.MARK + EMBER_REL
	var top: float = ArtRig.MARK.y
	var img: Image = await _shot(rig, 0, 3.0, ember, 4.0, Vector2(ember.x, top + 8.0), true)
	var depths: Array[float] = []
	for dx: float in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		var x: float = ember.x + dx
		var lip: float = _lum(_at(img, Vector2(x, top + 1.0)))
		var depth: float = 1.0
		while depth < 20.0 and _lum(_at(img, Vector2(x, top + depth))) > 0.5 * lip:
			depth += 0.25
		depths.append(depth)
	var worst: float = 0.0
	var last: float = _lum(_at(img, Vector2(ember.x - 60.0, top + 4.0)))
	var at_x: float = ember.x - 60.0
	while at_x < ember.x + 60.0:
		at_x += 0.25
		var here: float = _lum(_at(img, Vector2(at_x, top + 4.0)))
		worst = maxf(worst, absf(here - last) / maxf(last, 0.0001))
		last = here
	var shallowest: float = depths[0]
	var deepest: float = depths[0]
	for d: float in depths:
		shallowest = minf(shallowest, d)
		deepest = maxf(deepest, d)
	_check(
		deepest - shallowest <= 1.5,
		"the floor's lit lip is as deep under the ember as beside it, no lens (%s u)" % [depths]
	)
	_check(
		worst < 0.08,
		"the floor's lit lip has no step along it (%.3f of its light between two pixels)" % worst
	)
	rig.set_backdrop_scale(1)
	rig.free_all()


## The ledge's underside at zoom 4 from the 2x backdrop sheet: as open as at 1x ([param whole_1x]
## and [param broken_1x] of its columns), and gone where the light hits it.
func _background_line_magnified(
	rig: ArtRig, far_ember: Vector2, near_ember: Vector2, whole_1x: float, broken_1x: float
) -> void:
	rig.set_backdrop_scale(2)
	var inkless: InkTuning = _ink.duplicate() as InkTuning
	inkless.ink_value = 0.0
	inkless.ink_over_fill = 0.0
	var centre := Vector2(224.0, 192.0)
	var far: Image = await _shot(rig, 0, 1.0, far_ember, 4.0, centre)
	var near: Image = await _shot(rig, 0, 1.0, near_ember, 4.0, centre)
	InkGlobals.apply(inkless)
	var far_black: Image = await _shot(rig, 0, 1.0, far_ember, 4.0, centre)
	var near_black: Image = await _shot(rig, 0, 1.0, near_ember, 4.0, centre)
	InkGlobals.apply(_ink)
	rig.set_backdrop_scale(1)
	var line_far: Array[float] = _ink_columns_fine(far, far_black, 172.0, 276.0, 188.0, 196.0)
	var line_near: Array[float] = _ink_columns_fine(near, near_black, 172.0, 276.0, 188.0, 196.0)
	var strongest: float = line_far.max()
	var whole: float = _share(line_far, 0.6 * strongest, 10.0)
	var broken: float = _share(line_far, 0.0, 0.6 * strongest)
	_check(
		strongest > 0.02 and broken > 0.15 and absf(whole - whole_1x) < 0.25,
		(
			(
				"magnified, a background's line is as open as at 1x: whole along %.2f (%.2f at 1x),"
				+ " broken along %.2f (%.2f)"
			)
			% [whole, whole_1x, broken, broken_1x]
		)
	)
	var kept: float = _share(line_near, 0.2 * strongest, 10.0)
	_check(
		kept < 0.1,
		"magnified, a background's line drops out where the light hits it (%.2f keeps it)" % kept
	)
	# The floor's top edge beside a Wick's ember at Dusk (the review's detail): the edge faces the
	# light, so it carries no line, not even on the pixels right on the edge, where the unsigned
	# distance's gradient turned the edge's normal over (a dashed black line at 4x).
	rig.set_backdrop_scale(2)
	var chest: Vector2 = ArtRig.MARK + EMBER_REL
	var floor_at := Vector2(chest.x + 50.0, ArtRig.MARK.y)
	var lit: Image = await _shot(rig, 0, 1.0, chest, 4.0, floor_at)
	InkGlobals.apply(inkless)
	var lit_black: Image = await _shot(rig, 0, 1.0, chest, 4.0, floor_at)
	InkGlobals.apply(_ink)
	rig.set_backdrop_scale(1)
	var floor_line: Array[float] = _ink_columns_fine(
		lit, lit_black, floor_at.x - 40.0, floor_at.x + 40.0, floor_at.y - 3.0, floor_at.y + 3.0
	)
	var on_floor: float = _share(floor_line, 0.2 * strongest, 10.0)
	_check(
		on_floor < 0.005,
		(
			"magnified, the floor's top edge in the ember's light has no line (%.2f keeps it)"
			% on_floor
		)
	)


## [method _ink_columns] at the shot's own pixels: one value per screen column over world x
## [param x0] to [param x1] and world y [param y0] to [param y1].
func _ink_columns_fine(
	drawn: Image, black: Image, x0: float, x1: float, y0: float, y1: float
) -> Array[float]:
	var a: Vector2i = _px(drawn, Vector2(x0, y0))
	var b: Vector2i = _px(drawn, Vector2(x1, y1))
	var out: Array[float] = []
	for x: int in range(a.x, b.x + 1):
		var most: float = 0.0
		for y: int in range(a.y, b.y + 1):
			most = maxf(most, _lum(drawn.get_pixel(x, y)) - _lum(black.get_pixel(x, y)))
		out.append(most)
	return out


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
