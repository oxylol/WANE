class_name RenderChecks
extends SceneTree
## What the render tests share (needs a display; docs/adr/0026): the artbuild probe
## (tests/screenshot/data/probe) at 1x and 2x, the ink tuning, the probe's parts in u from its feet,
## a check list and the reading of a shot (a world point to its pixel at the shot's camera). A test
## script extends this, calls [method _begin], runs its checks through [method _check] and ends with
## [method _finish].

const PROBE_DIR: String = "res://tests/screenshot/data/probe"
## The probe's parts from its feet, in u (tools/artbuild/tests/data/probe/parts.svg, origin 32 61).
const HEAD_REL: Vector2 = Vector2(0.0, -45.5)
const HEAD_RADIUS_U: float = 9.0
const EMBER_REL: Vector2 = Vector2(-1.0, -28.0)
const EMBER_RADIUS_U: float = 2.3
const BLADE_PIVOT_REL: Vector2 = Vector2(12.0, -22.0)

var _failures: PackedStringArray = []
var _checks: int = 0
var _noise: Texture2D
var _sheet1: SpriteSheet
var _sheet2: SpriteSheet
var _ink: InkTuning
## The camera of the shot being read, for [method _px].
var _centre: Vector2 = Vector2.ZERO
var _zoom: float = 1.0


## Loads the probe and the ink tuning; false (and quits with 2) if the probe's sheets are not valid.
func _begin(what: String) -> bool:
	RenderingServer.set_default_clear_color(Color.BLACK)
	_noise = SpriteSheet.load_noise()
	_sheet1 = SpriteSheet.open(PROBE_DIR, "probe", 1, _noise)
	_sheet2 = SpriteSheet.open(PROBE_DIR, "probe", 2, _noise)
	if not _sheet1.is_valid() or not _sheet2.is_valid():
		printerr("%s: the probe's sheets are not valid: %s" % [what, "; ".join(_sheet1.errors)])
		quit(2)
		return false
	_ink = load(InkTuning.PATH) as InkTuning
	InkGlobals.apply(_ink)
	return true


## Prints "<what>: N checks, M failed" and every failure, and quits (1 if any failed).
func _finish(what: String) -> void:
	print("%s: %d checks, %d failed" % [what, _checks, _failures.size()])
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
	rig: ArtRig,
	tick: int,
	level: float,
	ember: Vector2,
	zoom: float,
	centre: Vector2,
	hdr: bool = false
) -> Image:
	_zoom = zoom
	_centre = centre
	return await rig.shot(tick, level, ember, zoom, centre, hdr)


## The largest luminance over the world rectangle [param r] of [param img].
func _max(img: Image, r: Rect2) -> float:
	var a: Vector2i = _px(img, r.position)
	var b: Vector2i = _px(img, r.end)
	var most: float = 0.0
	for y: int in range(a.y, b.y):
		for x: int in range(a.x, b.x):
			most = maxf(most, _lum(img.get_pixel(x, y)))
	return most


## The mean difference in luminance of [param a] and [param b] over the world rectangle [param r].
func _mean_diff(a: Image, b: Image, r: Rect2) -> float:
	var p: Vector2i = _px(a, r.position)
	var q: Vector2i = _px(a, r.end)
	var total: float = 0.0
	var n: int = 0
	for y: int in range(p.y, q.y):
		for x: int in range(p.x, q.x):
			total += absf(_lum(a.get_pixel(x, y)) - _lum(b.get_pixel(x, y)))
			n += 1
	return total / float(maxi(n, 1))


func _rig(tuning: LightingTuning = null, backdrop: bool = true) -> ArtRig:
	var rig := ArtRig.new(self, _noise, tuning, backdrop)
	await rig.settle()
	return rig


## How many pixels darker than 0.25 lie in the wedge of angles [param from_deg] to [param to_deg]
## about [param pivot], [param from_u] to [param to_u] out.
func _dark_pixels(
	img: Image,
	pivot: Vector2,
	from_deg: float,
	to_deg: float,
	from_u: float = 6.0,
	to_u: float = 26.0
) -> int:
	var n: int = 0
	for deg: int in range(int(from_deg), int(to_deg) + 1):
		for r10: int in range(int(from_u * 10.0), int(to_u * 10.0) + 1, 2):
			var a: float = deg_to_rad(float(deg))
			var p: Vector2 = pivot + Vector2(cos(a), sin(a)) * (float(r10) / 10.0)
			var c: Color = _at(img, p)
			if _lum(c) < 0.25 and c.a > 0.5:
				n += 1
	return n
