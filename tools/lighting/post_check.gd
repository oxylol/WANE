class_name PostCheck
extends RefCounted
## The post pass on the GPU (shaders/post/post.gdshader; docs/adr/0026 Decision 3 and its
## 2026-10-21 addendum; BUILD.md section 10, Style: the ember "a soft bloom over the ink", the art
## "resolution-independent"; section 13, Frame budget: Post, bloom, grain, vignette). Run by
## tools/lighting/gpu_check.gd under a display. Each check renders a [LightField] with its post
## pass on, in a SubViewport whose canvas is 1920 x 1080 u stretched over the output's own pixels
## (what the project's canvas_items stretch does to the window), and reads the HDR picture against
## the CPU maths of content/lighting.tres:
##   1. the bloom reaches as far, and as brightly, in u at a 960 x 540, a 1920 x 1080 and a
##      2880 x 1620 output;
##   2. its reach follows bloom_radius_u, its light bloom_strength, and nothing under
##      bloom_threshold blooms;
##   3. the vignette darkens as vignette, vignette_start, vignette_end and vignette_squash say;
##   4. the grain is grain wide, the same within a boil step and new at the next;
##   5. a bright colour keeps its hue: past the shoulder it is the shoulder's maths of the bloomed
##      colour, and no channel leaves the screen's range to clip on its own.

## The canvas in u, and the outputs it is drawn at.
const CANVAS: Vector2i = Vector2i(1920, 1080)
const OUTPUTS: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1920, 1080), Vector2i(2880, 1620)]
## The bloom's source: a square this wide (u) at this HDR value, on black, at the canvas's centre.
const SOURCE_U: float = 40.0
const SOURCE_VALUE: float = 3.0
## Where the ember is: far from everything, so that only the post pass draws.
const FAR: Vector2 = Vector2(-9000.0, -9000.0)
## The bloom reaches a point where its luminance is above this.
const REACH_LUM: float = 0.02
## The farthest the profile is read beyond the source's edge, in u.
const PROFILE_U: float = 60.0
## Every output agrees with the canvas-sized one (1920 x 1080, OUTPUTS[1]) on the reach to within
## this (u): one pixel of the smallest output is 2 u.
const REACH_AGREE_U: float = 3.0
## ... and on the bloom's light beyond the edge (its integral over the profile) to this share: the
## screen's mip blocks fall on the source's edge differently at each output (measured 13% at
## 960 x 540, 6% at 2880 x 1620; a radius in the output's pixels is 50% and more off).
const LIGHT_AGREE: float = 0.2
## Doubling bloom_radius_u doubles the reach, within these.
const RADIUS_RATIO_MIN: float = 1.6
const RADIUS_RATIO_MAX: float = 2.4
## Halving bloom_strength halves the bloom 4 u beyond the edge, within this share.
const STRENGTH_TOLERANCE: float = 0.08
const STRENGTH_PROBE_U: float = 4.0
## A source this far under bloom_threshold blooms nothing (luminance beyond its edge).
const UNDER_THRESHOLD: float = 0.05
const NO_BLOOM_LUM: float = 0.002
## The vignette's darkening against its maths, as a ratio to the centre.
const VIGNETTE_TOLERANCE: float = 0.01
## The grain's spread against grain / sqrt(12) (a uniform noise), as a share.
const GRAIN_TOLERANCE: float = 0.2
const GRAIN_BLOCK_PX: int = 96
## Two boil steps' grain correlate under this.
const GRAIN_CORRELATION_MAX: float = 0.2
## The hue test's sources: squares this wide (so that every bloom tap at its middle lands inside),
## at these multiples of the ember's colour.
const HUE_SOURCE_U: float = 96.0
const HUE_GAINS: Array[float] = [0.5, 1.0, 1.5, 2.0, 3.0, 6.0]
const HUE_TOLERANCE: float = 0.01
## The screen's range: no channel may end above it (it would clip alone).
const SCREEN_MAX: float = 1.0005

var failures: PackedStringArray = PackedStringArray()
var _tree: SceneTree
var _field: LightField = null


func _init(tree: SceneTree) -> void:
	_tree = tree


## Runs every check; [member failures] holds what failed.
func run() -> void:
	await _check_bloom_reach_is_in_world_units()
	await _check_bloom_numbers()
	await _check_vignette()
	await _check_grain()
	await _check_hue_past_the_shoulder()


func _fail(line: String) -> void:
	failures.append(line)
	printerr("FAIL: %s" % line)


## The project's tuning with the halos off (the post pass alone draws around a source), and the
## vignette and the grain off unless [param keep_vignette] or [param keep_grain].
static func tuning(keep_vignette: bool = false, keep_grain: bool = false) -> LightingTuning:
	var t: LightingTuning = (
		(load(LightingTuning.PATH) as LightingTuning).duplicate(true) as LightingTuning
	)
	t.glow_strength = 0.0
	if not keep_vignette:
		t.vignette = 0.0
	if not keep_grain:
		t.grain = 0.0
	return t


## A SubViewport of [param out_px] pixels showing the canvas, with a backdrop of [param back] and a
## [LightField] of [param t] (its post pass on) whose camera is on the canvas's centre.
func _rig(out_px: Vector2i, t: LightingTuning, back: Color) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = out_px
	vp.size_2d_override = CANVAS
	vp.size_2d_override_stretch = true
	vp.use_hdr_2d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_tree.root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = back
	bg.position = Vector2(-100.0, -100.0)
	bg.size = Vector2(CANVAS) + Vector2(200.0, 200.0)
	vp.add_child(bg)
	_field = LightField.new(t)
	vp.add_child(_field)
	var cam := Camera2D.new()
	cam.position = Vector2(CANVAS) * 0.5
	vp.add_child(cam)
	cam.make_current()
	return vp


## An emissive square of HDR colour [param hdr], [param size_u] wide, centred at [param at].
func _source(vp: SubViewport, at: Vector2, size_u: float, hdr: Color) -> void:
	var boost: float = (load(LightingTuning.PATH) as LightingTuning).emissive_boost
	var r := ColorRect.new()
	r.color = Color(hdr.r / boost, hdr.g / boost, hdr.b / boost)
	r.position = at - Vector2(size_u, size_u) * 0.5
	r.size = Vector2(size_u, size_u)
	LightSurfaces.make_emissive(r)
	vp.add_child(r)


## The rig's picture at [param tick] (HDR, linear, the output's own pixels).
func _capture(vp: SubViewport, tick: int) -> Image:
	_field.freeze(tick, 1.0)
	_field.present(tick, 0.0, FAR)
	for _i: int in range(2):
		await _tree.process_frame
		await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## The bloom right of a source whose right edge is at [param edge_u] on the canvas's middle row:
## each output pixel column as (distance from the edge in u, luminance).
static func _profile(img: Image, edge_u: float) -> PackedVector2Array:
	var k: float = float(img.get_width()) / float(CANVAS.x)
	var y: int = int(float(CANVAS.y) * 0.5 * k)
	var out := PackedVector2Array()
	for x: int in range(int(edge_u * k), int((edge_u + PROFILE_U) * k)):
		var d: float = (float(x) + 0.5) / k - edge_u
		if d > 0.0:
			out.append(Vector2(d, _lum(img.get_pixel(x, y))))
	return out


## The farthest distance of [param prof] whose luminance passes [constant REACH_LUM].
static func _reach(prof: PackedVector2Array) -> float:
	var reach: float = 0.0
	for p: Vector2 in prof:
		if p.y > REACH_LUM:
			reach = p.x
	return reach


## The light of [param prof] beyond the edge: its integral over u.
static func _light(prof: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(1, prof.size()):
		total += prof[i].y * (prof[i].x - prof[i - 1].x)
	return total


## The luminance of [param prof] at [param d] u from the edge (the nearest column).
static func _at(prof: PackedVector2Array, d: float) -> float:
	var best: Vector2 = prof[0]
	for p: Vector2 in prof:
		if absf(p.x - d) < absf(best.x - d):
			best = p
	return best.y


## The bloom of the standard source at [param out_px] with [param t].
func _bloom(out_px: Vector2i, t: LightingTuning, value: float) -> PackedVector2Array:
	var vp: SubViewport = _rig(out_px, t, Color.BLACK)
	var mid := Vector2(CANVAS) * 0.5
	_source(vp, mid, SOURCE_U, Color(value, value, value))
	var img: Image = await _capture(vp, 0)
	vp.queue_free()
	return _profile(img, mid.x + SOURCE_U * 0.5)


## 1. The reach is in u: the same at every output size (ADR-0026 Decision 3).
func _check_bloom_reach_is_in_world_units() -> void:
	var reaches: Array[float] = []
	var lights: Array[float] = []
	for out_px: Vector2i in OUTPUTS:
		var prof: PackedVector2Array = await _bloom(out_px, tuning(), SOURCE_VALUE)
		reaches.append(_reach(prof))
		lights.append(_light(prof))
	var lines: PackedStringArray = []
	for i: int in range(OUTPUTS.size()):
		lines.append(
			"%dx%d %.1f u (light %.2f)" % [OUTPUTS[i].x, OUTPUTS[i].y, reaches[i], lights[i]]
		)
	print("post: bloom reach %s, bloom_radius_u %.0f" % [", ".join(lines), tuning().bloom_radius_u])
	for i: int in range(OUTPUTS.size()):
		if absf(reaches[i] - reaches[1]) > REACH_AGREE_U:
			_fail(
				(
					"the bloom reaches %.1f u at %s and %.1f u at %s: its radius is not in u"
					% [reaches[1], OUTPUTS[1], reaches[i], OUTPUTS[i]]
				)
			)
		if absf(lights[i] / maxf(lights[1], 0.0001) - 1.0) > LIGHT_AGREE:
			_fail(
				(
					"the bloom's light differs at %s and %s (%.3f against %.3f)"
					% [OUTPUTS[1], OUTPUTS[i], lights[1], lights[i]]
				)
			)


## 2. bloom_radius_u, bloom_strength and bloom_threshold reach the shader.
func _check_bloom_numbers() -> void:
	var out_px: Vector2i = OUTPUTS[1]
	var base: LightingTuning = tuning()
	var prof: PackedVector2Array = await _bloom(out_px, base, SOURCE_VALUE)
	var wide: LightingTuning = tuning()
	wide.bloom_radius_u = base.bloom_radius_u * 2.0
	var wide_prof: PackedVector2Array = await _bloom(out_px, wide, SOURCE_VALUE)
	var half: LightingTuning = tuning()
	half.bloom_strength = base.bloom_strength * 0.5
	var half_prof: PackedVector2Array = await _bloom(out_px, half, SOURCE_VALUE)
	var under: float = base.bloom_threshold - UNDER_THRESHOLD
	var under_prof: PackedVector2Array = await _bloom(out_px, base, under)
	var ratio: float = _reach(wide_prof) / maxf(_reach(prof), 0.0001)
	var near: float = _at(prof, STRENGTH_PROBE_U)
	var near_half: float = _at(half_prof, STRENGTH_PROBE_U)
	var under_lum: float = _at(under_prof, STRENGTH_PROBE_U)
	print(
		(
			(
				"post: reach %.1f u at bloom_radius_u %.0f, %.1f u at %.0f; %d u out %.4f at "
				+ "bloom_strength %.3f, %.4f at half; %.4f from a source under the threshold"
			)
			% [
				_reach(prof),
				base.bloom_radius_u,
				_reach(wide_prof),
				wide.bloom_radius_u,
				int(STRENGTH_PROBE_U),
				near,
				base.bloom_strength,
				near_half,
				under_lum
			]
		)
	)
	if _reach(prof) <= 0.0:
		_fail("a source of value %.1f draws no bloom" % SOURCE_VALUE)
	if ratio < RADIUS_RATIO_MIN or ratio > RADIUS_RATIO_MAX:
		_fail("bloom_radius_u doubled moves the reach by %.2f times, not about 2" % ratio)
	if absf(near_half / maxf(near, 0.0001) - 0.5) > STRENGTH_TOLERANCE:
		_fail("bloom_strength halved leaves %.3f of the bloom" % (near_half / maxf(near, 0.0001)))
	if under_lum > NO_BLOOM_LUM:
		_fail("a source under bloom_threshold blooms (%.4f beyond its edge)" % under_lum)


## The vignette's factor at screen uv [param uv], from [param t]'s numbers (post.gdshader).
static func vignette_at(t: LightingTuning, uv: Vector2) -> float:
	var v: float = ((uv - Vector2(0.5, 0.5)) * Vector2(1.0, t.vignette_squash)).length()
	return 1.0 - t.vignette * smoothstep(t.vignette_start, t.vignette_end, v)


## 3. The vignette is its numbers.
func _check_vignette() -> void:
	var t: LightingTuning = tuning(true, false)
	var out_px: Vector2i = OUTPUTS[1]
	var vp: SubViewport = _rig(out_px, t, Color(0.5, 0.5, 0.5))
	var img: Image = await _capture(vp, 0)
	vp.queue_free()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var centre := Vector2i(w / 2, h / 2)
	var spots: Array[Vector2i] = [
		Vector2i(2, 2),
		Vector2i(w - 3, h - 3),
		Vector2i(2, h / 2),
		Vector2i(w / 2, 2),
		Vector2i(w / 4, h / 4),
		Vector2i(w * 3 / 4, h / 2),
	]
	var ref: float = _lum(img.get_pixelv(centre))
	var ref_f: float = vignette_at(t, (Vector2(centre) + Vector2(0.5, 0.5)) / Vector2(w, h))
	var worst: float = 0.0
	var corner: float = 0.0
	for s: Vector2i in spots:
		var got: float = _lum(img.get_pixelv(s)) / maxf(ref, 0.0001)
		var want: float = vignette_at(t, (Vector2(s) + Vector2(0.5, 0.5)) / Vector2(w, h)) / ref_f
		worst = maxf(worst, absf(got - want))
		if s == spots[0]:
			corner = got
	print(
		"post: vignette, the corner %.3f of the centre, worst %.4f off its maths" % [corner, worst]
	)
	if worst > VIGNETTE_TOLERANCE:
		_fail("the vignette is %.3f off its maths (vignette, start, end, squash)" % worst)
	if corner > 1.0 - t.vignette * 0.5:
		_fail("the vignette does not darken the corner (%.3f of the centre)" % corner)


## The luminances of the block of [constant GRAIN_BLOCK_PX] at the middle of [param img].
static func _block(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x0: int = img.get_width() / 2 - GRAIN_BLOCK_PX / 2
	var y0: int = img.get_height() / 2 - GRAIN_BLOCK_PX / 2
	for y: int in range(y0, y0 + GRAIN_BLOCK_PX):
		for x: int in range(x0, x0 + GRAIN_BLOCK_PX):
			out.append(_lum(img.get_pixel(x, y)))
	return out


static func _mean(v: PackedFloat32Array) -> float:
	var total: float = 0.0
	for x: float in v:
		total += x
	return total / float(maxi(v.size(), 1))


static func _spread(v: PackedFloat32Array) -> float:
	var m: float = _mean(v)
	var total: float = 0.0
	for x: float in v:
		total += (x - m) * (x - m)
	return sqrt(total / float(maxi(v.size(), 1)))


static func _correlation(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var ma: float = _mean(a)
	var mb: float = _mean(b)
	var ab: float = 0.0
	for i: int in range(a.size()):
		ab += (a[i] - ma) * (b[i] - mb)
	return ab / float(a.size()) / maxf(_spread(a) * _spread(b), 0.000001)


## 4. The grain: its width, and its seed is the boil step (a frame is reproducible from its tick).
func _check_grain() -> void:
	var t: LightingTuning = tuning(false, true)
	var vp: SubViewport = _rig(OUTPUTS[1], t, Color(0.5, 0.5, 0.5))
	# Ticks 0 and 4 are one boil step at 12 Hz; tick 6 is the next.
	var first: PackedFloat32Array = _block(await _capture(vp, 0))
	var same: PackedFloat32Array = _block(await _capture(vp, 4))
	var next: PackedFloat32Array = _block(await _capture(vp, 6))
	vp.queue_free()
	var want: float = t.grain / sqrt(12.0)
	var got: float = _spread(first)
	var corr: float = _correlation(first, next)
	print(
		(
			"post: grain spread %.5f (grain %.3f gives %.5f), the next boil step correlates %.3f"
			% [got, t.grain, want, corr]
		)
	)
	if absf(got / want - 1.0) > GRAIN_TOLERANCE:
		_fail("the grain's spread is %.5f, grain %.3f says %.5f" % [got, t.grain, want])
	if first != same:
		_fail("two ticks of one boil step draw different grain")
	if absf(corr) > GRAIN_CORRELATION_MAX:
		_fail("the next boil step does not reseed the grain (correlation %.3f)" % corr)


## What the post pass makes of a uniform HDR colour [param c] whose bloom taps all land inside it:
## the bloom (centre and ring alike see c), the shoulder on the brightness, then the colour scaled
## whole into the screen's range (post.gdshader, on the CPU).
static func post_of(t: LightingTuning, c: Color) -> Color:
	var bright := Color(
		maxf(c.r - t.bloom_threshold, 0.0),
		maxf(c.g - t.bloom_threshold, 0.0),
		maxf(c.b - t.bloom_threshold, 0.0)
	)
	var k: float = (t.bloom_core + 8.0 * t.bloom_ring) * t.bloom_strength
	var v := Vector3(c.r + bright.r * k, c.g + bright.g * k, c.b + bright.b * k)
	var luma: float = 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z
	var rolled: float = luma
	if luma > t.shoulder_knee:
		var over: float = luma - t.shoulder_knee
		var room: float = 1.0 - t.shoulder_knee
		rolled = t.shoulder_knee + room * (over / (over + room))
	v *= rolled / maxf(luma, 0.0001)
	v /= maxf(maxf(v.x, maxf(v.y, v.z)), 1.0)
	return Color(v.x, v.y, v.z)


## 5. Past the shoulder a colour keeps its hue (ADR-0026 Decision 3: the ember stays orange).
func _check_hue_past_the_shoulder() -> void:
	var t: LightingTuning = tuning()
	var vp: SubViewport = _rig(OUTPUTS[1], t, Color.BLACK)
	var ember: Color = t.ember_colour()
	var spots: Array[Vector2] = []
	for i: int in range(HUE_GAINS.size()):
		var at := Vector2(240.0 + 288.0 * float(i), float(CANVAS.y) * 0.5)
		var g: float = HUE_GAINS[i]
		_source(vp, at, HUE_SOURCE_U, Color(ember.r * g, ember.g * g, ember.b * g))
		spots.append(at)
	var img: Image = await _capture(vp, 0)
	vp.queue_free()
	var worst: float = 0.0
	var peak: float = 0.0
	var lines: PackedStringArray = []
	for i: int in range(HUE_GAINS.size()):
		var g: float = HUE_GAINS[i]
		var got: Color = img.get_pixelv(Vector2i(spots[i]))
		var want: Color = post_of(t, Color(ember.r * g, ember.g * g, ember.b * g))
		worst = maxf(
			worst, maxf(absf(got.r - want.r), maxf(absf(got.g - want.g), absf(got.b - want.b)))
		)
		peak = maxf(peak, maxf(got.r, maxf(got.g, got.b)))
		lines.append("x%.1f (%.3f %.3f %.3f)" % [g, got.r, got.g, got.b])
	print("post: the ember's colour past the shoulder: %s" % ", ".join(lines))
	if worst > HUE_TOLERANCE:
		_fail("a bright colour is %.3f off the shoulder's maths (its hue moves)" % worst)
	if peak > SCREEN_MAX:
		_fail("a channel leaves the post pass at %.3f and clips alone: the hue turns" % peak)
