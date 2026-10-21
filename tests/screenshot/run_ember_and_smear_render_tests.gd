extends RenderChecks
## The ember and the smear on the pictures the review draws (docs/adr/0026; BUILD.md section 10,
## Style: "The ember: a single orange-white point in every Wick's chest, a soft bloom over the ink";
## Animation: "a fast blade is stretched along its motion arc and its ink line becomes a motion
## ribbon"): a [LightField] with its halos and post pass, the painted backdrop and the artbuild
## probe in the lit test room. The ember is warm, keeps its hue past the shoulder, carries no dark
## ring, has a halo, and is a hot core grading out with no flat disc and no step at its edge, a
## point at 1x; a smear's fill fades smoothly along its arc to nothing at the tail, its outer line
## thins toward the tail, its tail edge is open, nothing beside it is opaque, it thins by its width
## and it is all one value.
## Needs a display:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 \
##     --script tests/screenshot/run_ember_and_smear_render_tests.gd
## Exits 0 when every check passes, 1 otherwise.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _begin("ember and smear render"):
		return
	await _test_the_ember()
	await _test_a_smear_is_a_ribbon()
	_finish("ember and smear render")


# --- the ember --------------------------------------------------------------------------------


func _test_the_ember() -> void:
	var rig: ArtRig = await _rig()
	rig.sprite.carries_ember = true
	rig.sprite.setup(_sheet1, &"idle")
	var centre := Vector2(320.0, 192.0)
	var ember: Vector2 = ArtRig.MARK + EMBER_REL
	var img: Image = await _shot(rig, 0, 3.0, ember, 1.0, centre, true)
	# The core is HDR, brighter than 1: only the post pass's shoulder gives it a colour on screen
	# (a per-channel clip would make it white, or turn its orange yellow). It reaches the screen at
	# the top of its own hue's range: its strongest channel at the screen's 1, no channel over it
	# (one over it would clip alone and turn the hue), and the hue it had before the post pass.
	rig.field.set_post_enabled(true)
	var toned: Image = await _shot(rig, 0, 3.0, ember, 1.0, centre, true)
	rig.field.set_post_enabled(false)
	var core_in: Color = _at(img, ember)
	var core: Color = _at(toned, ember)
	var peak: float = maxf(core.r, maxf(core.g, core.b))
	# The grain rides on top, half its width either way.
	var grain_top: float = 1.0 + 0.5 * rig.tuning.grain + 0.0005
	_check(
		peak > 0.9 and peak < grain_top,
		"the ember's core is as bright as its colour can be shown (strongest channel %.3f)" % peak
	)
	_check(
		core.r - core.b > 0.1,
		(
			"the ember's core is warm, not white: the shoulder keeps its hue (r %.2f b %.2f)"
			% [core.r, core.b]
		)
	)
	var hue_out := Vector2(core.g / core.r, core.b / core.r)
	var hue_in := Vector2(core_in.g / core_in.r, core_in.b / core_in.r)
	_check(
		absf(hue_out.x - hue_in.x) < 0.08 and absf(hue_out.y - hue_in.y) < 0.08,
		(
			"the ember keeps its orange past the shoulder: g/r and b/r %s, before the post pass %s"
			% [hue_out, hue_in]
		)
	)
	# Its halo: the same picture with the halos off is darker just outside the body.
	var plain: LightingTuning = rig.tuning.duplicate() as LightingTuning
	plain.glow_strength = 0.0
	rig.free_all()
	var rig2: ArtRig = await _rig(plain)
	rig2.sprite.carries_ember = true
	rig2.sprite.setup(_sheet1, &"idle")
	var bare: Image = await _shot(rig2, 0, 3.0, ember, 1.0, centre, true)
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
	await _test_the_ember_is_a_hot_core()


## The luminance and the whiteness (blue over red) of [param img] at world point [param w].
func _lum_white(img: Image, w: Vector2) -> Vector2:
	var c: Color = _at(img, w)
	return Vector2(_lum(c), c.b / maxf(c.r, 0.0001))


## BUILD.md section 10 (The ember): "a single orange-white point in every Wick's chest, a soft bloom
## over the ink". On screen (post on, Pitch), magnified and at 1x: the ember is hottest and whitest
## at its core and grades out over its own part into the halo, with no flat disc and no cliff at
## its edge (the probe's ember is 2.3 u across; the step is read on its lit side, toward the key,
## where the robe beyond it is in its lit value: the crescent on the other side is the robe's own
## two values). Measured before the core: a flat disc of 0.74 to 0.75 out to 2.2 u with a 0.10
## step at its edge, one whiteness (b/r 0.42) across it, and a 4 x 4 block at 1x.
func _test_the_ember_is_a_hot_core() -> void:
	var rig: ArtRig = await _rig()
	rig.sprite.carries_ember = true
	rig.sprite.setup(_sheet2, &"idle")
	rig.field.set_post_enabled(true)
	var ember: Vector2 = ArtRig.MARK + EMBER_REL
	var img: Image = await _shot(rig, 0, 3.0, ember, 4.0, ember)
	var core: Vector2 = _lum_white(img, ember)
	var steepest: float = 0.0
	var mid_lum: float = 0.0
	var rim_white: float = 0.0
	var dirs: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	for d: Vector2 in dirs:
		mid_lum += _lum_white(img, ember + d * 1.5).x / float(dirs.size())
		rim_white += _lum_white(img, ember + d * 1.75).y / float(dirs.size())
	for d: Vector2 in [Vector2(-1, 0), Vector2(0, -1)]:
		var inside: float = _lum_white(img, ember + d * (EMBER_RADIUS_U - 0.25)).x
		var outside: float = _lum_white(img, ember + d * (EMBER_RADIUS_U + 0.25)).x
		steepest = maxf(steepest, absf(inside - outside))
	_check(
		core.x > mid_lum + 0.05,
		(
			"the ember is a hot core grading out, not a flat disc (core %.3f, 1.5 u out %.3f)"
			% [core.x, mid_lum]
		)
	)
	_check(
		core.y > rim_white + 0.15,
		"the ember's core is whiter than its rim (b/r %.2f against %.2f)" % [core.y, rim_white]
	)
	_check(
		steepest < 0.04,
		"the ember grades into its halo with no step at its edge (%.3f across it)" % steepest
	)
	# At 1x it is a point: one or two pixels at its hottest, whiter than the ring around them.
	rig.sprite.setup(_sheet1, &"idle")
	var one: Image = await _shot(rig, 0, 3.0, ember, 1.0, ember)
	var c: Vector2i = _px(one, ember)
	var hottest: float = 0.0
	for dy: int in range(-3, 4):
		for dx: int in range(-3, 4):
			hottest = maxf(hottest, _lum(one.get_pixel(c.x + dx, c.y + dy)))
	var at_top: int = 0
	var white_top: float = 0.0
	var ring_white: float = 0.0
	var ring_n: int = 0
	for dy: int in range(-3, 4):
		for dx: int in range(-3, 4):
			var px: Color = one.get_pixel(c.x + dx, c.y + dy)
			if _lum(px) > hottest - 0.02:
				at_top += 1
				white_top = maxf(white_top, px.b / maxf(px.r, 0.0001))
			elif maxi(absi(dx), absi(dy)) == 3:
				ring_white += px.b / maxf(px.r, 0.0001)
				ring_n += 1
	ring_white /= float(maxi(ring_n, 1))
	_check(
		at_top <= 4 and white_top > ring_white + 0.15,
		(
			"at 1x the ember is a point: %d pixels at its hottest (b/r %.2f, the ring around %.2f)"
			% [at_top, white_top, ring_white]
		)
	)
	rig.free_all()


# --- the smear --------------------------------------------------------------------------------


## BUILD.md section 10 (Animation): "a fast blade is stretched along its motion arc and its ink
## line becomes a motion ribbon". The probe's swing frame 1 sweeps the blade 40 degrees, from its
## tail at -62.6 to its own pose at -22.6, about its pivot (tools/artbuild/tests/data/probe). Its
## fill fades along the arc toward the tail, smoothly (no V where the half nearest the tail edge
## was empty: measured 0 then 0.85 across the fan's bisector); its outer edge carries a line that
## thins toward the tail; its tail edge, across the motion, carries none (it drew a radial
## hairline); and nothing beside the faint tail is opaque (ink specks of 0.90 there).
func _test_a_smear_is_a_ribbon() -> void:
	var rig: ArtRig = await _rig(null, false)
	rig.sprite.setup(_sheet2, &"swing")
	rig.sprite.show_frame(&"swing", 1)
	rig.sprite.mode = InkSprite.Mode.SILHOUETTE
	var pivot: Vector2 = ArtRig.MARK + BLADE_PIVOT_REL
	var img: Image = await _shot(rig, 0, 1.0, Vector2(-500.0, 0.0), 4.0, pivot)
	# The fill along the arc, 10, 14 and 18 u out, from the tail to the blade, 2 degrees a step.
	var worst_fall: float = 0.0
	var worst_jump: float = 0.0
	var tail_most: float = 0.0
	var mid: Array[float] = []
	for r: float in [10.0, 14.0, 18.0]:
		var last: float = -1.0
		var deg: float = -60.0
		while deg <= -26.0:
			var a: float = _lum(_at(img, pivot + Vector2.from_angle(deg_to_rad(deg)) * r))
			if last >= 0.0:
				worst_fall = maxf(worst_fall, last - a)
				worst_jump = maxf(worst_jump, absf(a - last))
			if deg == -60.0:
				tail_most = maxf(tail_most, a)
			if deg == -44.0:
				mid.append(a)
			last = a
			deg += 2.0
	_check(
		worst_fall < 0.04 and worst_jump < 0.15,
		(
			"a smear's fill fades smoothly along its arc toward the tail (falls by %.2f, jumps by %.2f)"
			% [worst_fall, worst_jump]
		)
	)
	_check(tail_most < 0.12, "the smear's fill is faint at its tail (%.2f)" % tail_most)
	var mid_lo: float = mid[0]
	var mid_hi: float = mid[0]
	for v: float in mid:
		mid_lo = minf(mid_lo, v)
		mid_hi = maxf(mid_hi, v)
	_check(
		mid_lo > 0.15 and mid_hi < 0.65,
		"halfway along its arc the smear is half faded (%s)" % [mid]
	)
	# Beside the tail, over its anti-aliased fringe, nothing is opaque (from 10 u out: nearer the
	# pivot the fan is no wider than the blade itself).
	var speck: float = 0.0
	for deg10: int in range(-760, -590, 5):
		for r10: int in range(100, 280, 4):
			var w: Vector2 = (
				pivot + Vector2.from_angle(deg_to_rad(float(deg10) / 10.0)) * (float(r10) / 10.0)
			)
			speck = maxf(speck, _lum(_at(img, w)))
	_check(speck < 0.3, "no opaque ink beside the smear's faint tail (%.2f at most)" % speck)
	# Its line is a ribbon's: along the outer edge (the tip's path) it thins out toward the tail, and
	# its tail edge, across the motion, carries no line. Lit, over grey.
	rig.sprite.mode = InkSprite.Mode.LIT
	RenderingServer.set_default_clear_color(Color(0.5, 0.5, 0.5))
	var lit: Image = await _shot(rig, 0, 1.0, pivot + Vector2(-120.0, 0.0), 4.0, pivot)
	RenderingServer.set_default_clear_color(Color.BLACK)
	var outer_tail: int = _dark_pixels(lit, pivot, -60.0, -50.0, 22.0, 28.0)
	var outer_blade: int = _dark_pixels(lit, pivot, -34.0, -24.0, 22.0, 28.0)
	_check(
		outer_blade >= 8 and outer_tail < outer_blade / 3,
		(
			"the smear's outer line thins out toward the tail (%d dark pixels there, %d at the blade)"
			% [outer_tail, outer_blade]
		)
	)
	var tail_edge: int = _dark_pixels(lit, pivot, -72.0, -60.0, 6.0, 22.0)
	var lead_edge: int = _dark_pixels(lit, pivot, -24.0, -14.0, 6.0, 22.0)
	_check(
		lead_edge >= 8 and tail_edge * 10 < lead_edge,
		(
			"the smear's tail edge is open (%d dark pixels across the motion, %d on the blade's edge)"
			% [tail_edge, lead_edge]
		)
	)
	# It thins by its width, not only its coverage (ADR-0026 Decision 5). Beyond every light (the
	# key off, the ember far) every line is the heavy one; with the coverage nearly held along the
	# arc (smear_tail_pow at its least, 0.1) and no pressure taper (taper_floor 1), only the age can
	# thin the ribbon's outer edge toward the tail (measured 27 dark pixels against 222 at the blade
	# end; 88 against 224 without the age).
	var bare: InkTuning = _ink.duplicate() as InkTuning
	bare.smear_tail_pow = 0.1
	bare.taper_floor = 1.0
	InkGlobals.apply(bare)
	var key: Vector4 = rig.field.key
	rig.field.key = Vector4(key.x, key.y, 0.0, 0.0)
	RenderingServer.set_default_clear_color(Color(0.5, 0.5, 0.5))
	var aged: Image = await _shot(rig, 0, 1.0, Vector2(-2000.0, 0.0), 4.0, pivot)
	RenderingServer.set_default_clear_color(Color.BLACK)
	rig.field.key = key
	InkGlobals.apply(_ink)
	var tail_aged: int = _dark_pixels(aged, pivot, -64.0, -41.0, 17.0, 27.0)
	var head_aged: int = _dark_pixels(aged, pivot, -28.0, -17.0, 17.0, 27.0)
	_check(
		float(tail_aged) < 0.25 * float(head_aged),
		(
			"the smear's line thins with its age (%d dark px at the tail, %d at the blade)"
			% [tail_aged, head_aged]
		)
	)
	# A smear is all one value (ADR-0026 Decision 5): its lit one, even at Pitch beyond every light
	# where the key alone gives a surface a fraction of it. The two-value choice over the
	# silhouette's alpha is the value itself.
	var away := Vector2(-2000.0, 0.0)
	rig.sprite.mode = InkSprite.Mode.VALUE
	var values: Image = await _shot(rig, 0, 3.0, away, 4.0, pivot, true)
	rig.sprite.mode = InkSprite.Mode.SILHOUETTE
	var cover: Image = await _shot(rig, 0, 3.0, away, 4.0, pivot, true)
	var lowest: float = 1.0
	var read: int = 0
	for deg: int in range(-60, -24, 4):
		for r: int in range(8, 21, 3):
			var a_rad: float = deg_to_rad(float(deg))
			var at: Vector2 = pivot + Vector2(cos(a_rad), sin(a_rad)) * float(r)
			var a: float = _lum(_at(cover, at))
			if a > 0.05:
				lowest = minf(lowest, _lum(_at(values, at)) / a)
				read += 1
	_check(
		read >= 12 and lowest > 0.97,
		"a smear is all one value, its lit one (lowest %.2f over %d points)" % [lowest, read]
	)
	rig.free_all()
