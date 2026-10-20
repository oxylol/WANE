class_name InkProbe
extends RefCounted
## Test textures for the ink shaders at the channel layout ADR-0023 Decision 1.3 fixes, built in
## GDScript until tools/artbuild/ lands: a Wick-like test figure (8 parts), a stage (floor, ledge,
## pillar, crate) for a background layer, the shared noise (Decision 1.7) and a palette. The
## distance fields are analytic (circles, boxes, tapered capsules), so they are exact for these
## shapes; "visible edge" follows the ADR: an edge covered by a part with a higher z is hidden.
## This is test data, not art, and is not judged as art. Pixel centres are evaluated exactly like
## artbuild does, so a frame at scale s is the same shape at every scale.

const KIND_CIRCLE: int = 0
const KIND_BOX: int = 1
const KIND_CONE: int = 2

## Where the figure's feet are inside its cell, in u, and the cell.
const FIGURE_CELL_U: Vector2 = Vector2(96.0, 128.0)
const FIGURE_ORIGIN_U: Vector2 = Vector2(48.0, 112.0)
const STAGE_CELL_U: Vector2 = Vector2(480.0, 270.0)
## Where the figure stands on the stage (the floor's top), in the stage's own cell, in u.
const STAGE_MARK_U: Vector2 = Vector2(240.0, 232.0)

const S_RANGE: float = 16.5
## A part's bevel when it gives none (ADR-0023 Decision 1.1's data-bevel-u default).
const BEVEL_U: float = 3.0
const TILT_DEG: float = 62.0
const TAPER_FULL_U: float = 2.5
const NOISE_PX: int = 256


## One analytic part: a circle, a box or a tapered capsule ("cone").
class Prim:
	extends RefCounted
	var kind: int = KIND_CIRCLE
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	var ra: float = 1.0
	var rb: float = 1.0
	var z: int = 0
	var column: int = 1
	var emissive: bool = false
	var angle: float = 0.0
	var flags: int = 0
	var bevel: float = BEVEL_U
	var _h: float = 0.0
	var _e: Vector2 = Vector2.ZERO
	var _k: float = 0.0
	var _c: float = 0.0

	static func circle(c: Vector2, r: float, zz: int, col: int) -> Prim:
		var p := Prim.new()
		p.kind = KIND_CIRCLE
		p.a = c
		p.ra = r
		p.rb = r
		p.z = zz
		p.column = col
		return p

	static func box(c: Vector2, half: Vector2, zz: int, col: int) -> Prim:
		var p := Prim.new()
		p.kind = KIND_BOX
		p.a = c
		p.b = half
		p.ra = 99.0
		p.rb = 99.0
		p.z = zz
		p.column = col
		return p

	static func cone(
		from: Vector2, to: Vector2, r_from: float, r_to: float, zz: int, col: int
	) -> Prim:
		var p := Prim.new()
		p.kind = KIND_CONE
		p.a = from
		p.b = to
		p.ra = r_from
		p.rb = r_to
		p.z = zz
		p.column = col
		p._h = from.distance_to(to)
		p._e = (to - from) / p._h
		p._k = (r_from - r_to) / p._h
		p._c = sqrt(1.0 - p._k * p._k)
		p.angle = fposmod(atan2(p._e.y, p._e.x), PI)
		return p

	## Signed distance to the shape, negative inside.
	func sd(p: Vector2) -> float:
		if kind == KIND_CIRCLE:
			return p.distance_to(a) - ra
		if kind == KIND_BOX:
			var q: Vector2 = (p - a).abs() - b
			return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0)
		var d: Vector2 = p - a
		var local := Vector2(absf(d.x * -_e.y + d.y * _e.x), d.dot(_e))
		var kk: float = local.dot(Vector2(-_k, _c))
		if kk < 0.0:
			return local.length() - ra
		if kk > _c * _h:
			return local.distance_to(Vector2(0.0, _h)) - rb
		return local.dot(Vector2(_c, _k)) - ra

	## Outward unit gradient at [param p]: analytic for a circle, central differences otherwise.
	func gradient(p: Vector2) -> Vector2:
		if kind == KIND_CIRCLE:
			var v: Vector2 = p - a
			return v / maxf(v.length(), 0.00001)
		var eps: float = 0.02
		var g := Vector2(
			sd(p + Vector2(eps, 0.0)) - sd(p - Vector2(eps, 0.0)),
			sd(p + Vector2(0.0, eps)) - sd(p - Vector2(0.0, eps))
		)
		return g / maxf(g.length(), 0.00001)

	## Half-thickness near [param p], for the pressure taper.
	func radius_at(p: Vector2) -> float:
		if kind != KIND_CONE:
			return ra
		return lerpf(ra, rb, clampf((p - a).dot(_e) / _h, 0.0, 1.0))


## Bakes [param prims] into the four images of a sheet frame of [param cell_u] at [param scale]
## texels per u: shape, normal, parts (palette is separate). Keys: &"shape", &"normal", &"parts".
static func bake(prims: Array[Prim], cell_u: Vector2, scale: int) -> Dictionary[StringName, Image]:
	var w: int = int(cell_u.x) * scale
	var h: int = int(cell_u.y) * scale
	var shape := PackedByteArray()
	var normal := PackedByteArray()
	var parts := PackedByteArray()
	shape.resize(w * h * 4)
	normal.resize(w * h * 4)
	parts.resize(w * h * 4)
	var n: int = prims.size()
	var d := PackedFloat32Array()
	d.resize(n)
	var tilt_max: float = deg_to_rad(TILT_DEG)
	for y: int in range(h):
		for x: int in range(w):
			var p := Vector2((float(x) + 0.5) / float(scale), (float(y) + 0.5) / float(scale))
			var s_dist: float = 1000.0
			var owner_idx: int = -1
			var owner_z: int = -1000
			var nearest: int = 0
			var emis: float = 0.0
			for i: int in range(n):
				var di: float = prims[i].sd(p)
				d[i] = di
				if di < s_dist:
					s_dist = di
					nearest = i
				if di < 0.0 and prims[i].z > owner_z:
					owner_z = prims[i].z
					owner_idx = i
				if prims[i].emissive:
					emis = maxf(emis, clampf(0.5 - di * float(scale), 0.0, 1.0))
			var o: int = owner_idx if owner_idx >= 0 else nearest
			var u_dist: float = 99.0
			var win: int = -1
			for i: int in range(n):
				var ad: float = absf(d[i])
				if ad >= minf(u_dist, S_RANGE):
					continue
				var q: Vector2 = p - prims[i].gradient(p) * d[i]
				var hidden: bool = false
				for j: int in range(n):
					if prims[j].z > prims[i].z and prims[j].sd(q) < -0.001:
						hidden = true
						break
				if not hidden:
					u_dist = ad
					win = i
			var at: int = (y * w + x) * 4
			shape[at] = clampi(roundi(128.0 + 16.0 * s_dist), 0, 255)
			shape[at + 1] = clampi(roundi(16.0 * u_dist), 0, 255)
			shape[at + 2] = 255 if win >= 0 and d[win] < 0.0 else 0
			shape[at + 3] = clampi(roundi(emis * 255.0), 0, 255)
			var po: Prim = prims[o]
			var depth: float = -d[o]
			var tilt: float = tilt_max * (1.0 - clampf(depth / po.bevel, 0.0, 1.0))
			var g: Vector2 = po.gradient(p)
			var nv := Vector3(sin(tilt) * g.x, sin(tilt) * g.y, cos(tilt))
			normal[at] = clampi(roundi((0.5 + 0.5 * nv.x) * 255.0), 0, 255)
			normal[at + 1] = clampi(roundi((0.5 + 0.5 * nv.y) * 255.0), 0, 255)
			normal[at + 2] = clampi(roundi((0.5 + 0.5 * nv.z) * 255.0), 0, 255)
			normal[at + 3] = 51
			parts[at] = po.column
			parts[at + 1] = clampi(roundi(po.angle / PI * 255.0), 0, 255)
			parts[at + 2] = clampi(roundi(po.radius_at(p) / TAPER_FULL_U * 255.0), 0, 255)
			parts[at + 3] = po.flags
	var out: Dictionary[StringName, Image] = {}
	out[&"shape"] = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, shape)
	out[&"normal"] = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, normal)
	out[&"parts"] = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, parts)
	return out


## The test figure's parts, in the figure cell (feet at FIGURE_ORIGIN_U).
static func figure_prims() -> Array[Prim]:
	var o: Vector2 = FIGURE_ORIGIN_U
	var list: Array[Prim] = []
	list.append(Prim.cone(o + Vector2(-5, -40), o + Vector2(-13, -27), 2.4, 1.8, 0, 1))
	var body: Prim = Prim.cone(o + Vector2(0, -9), o + Vector2(0, -40), 9.0, 5.5, 1, 2)
	body.bevel = 8.0
	list.append(body)
	list.append(Prim.cone(o + Vector2(1, -64), o + Vector2(4, -75), 1.6, 0.35, 2, 4))
	var head: Prim = Prim.circle(o + Vector2(0, -54), 11.0, 3, 3)
	head.bevel = 10.0
	list.append(head)
	list.append(Prim.cone(o + Vector2(4, -41), o + Vector2(13, -32), 2.6, 2.1, 4, 5))
	list.append(Prim.circle(o + Vector2(14, -31), 2.7, 5, 6))
	var blade: Prim = Prim.cone(o + Vector2(15, -31), o + Vector2(35, -53), 1.7, 0.25, 6, 7)
	blade.flags = 2
	list.append(blade)
	var ember: Prim = Prim.circle(o + Vector2(0, -30), 3.0, 7, 8)
	ember.emissive = true
	list.append(ember)
	return list


## The stage's parts: a floor with its top at STAGE_MARK_U.y, a pillar, a ledge and a crate.
static func stage_prims() -> Array[Prim]:
	var list: Array[Prim] = []
	list.append(Prim.box(Vector2(240, 252), Vector2(260, 20), 0, 1))
	list.append(Prim.box(Vector2(420, 120), Vector2(22, 130), 1, 2))
	list.append(Prim.box(Vector2(80, 130), Vector2(70, 8), 2, 3))
	list.append(Prim.box(Vector2(140, 216), Vector2(16, 16), 3, 4))
	return list


## A palette image: 16 columns, 4 rows a variant (lit, shadow, rim, emissive with its strength in
## alpha). Variant 0 is the figure at rest, 1 is the same figure hurt, 2 is the stage.
static func palette_image() -> Image:
	var img: Image = Image.create(16, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1, 1))
	# Per column: lit, shadow, rim.
	var figure: Array[PackedColorArray] = [
		PackedColorArray([Color(0.50, 0.42, 0.52), Color(0.20, 0.17, 0.26), Color(0.9, 0.7, 0.9)]),
		PackedColorArray([Color(0.62, 0.55, 0.62), Color(0.26, 0.22, 0.32), Color(1.0, 0.8, 0.6)]),
		PackedColorArray([Color(0.72, 0.52, 0.46), Color(0.30, 0.20, 0.26), Color(1.0, 0.7, 0.5)]),
		PackedColorArray([Color(0.96, 0.84, 0.66), Color(0.50, 0.36, 0.36), Color(1.0, 0.9, 0.7)]),
		PackedColorArray([Color(0.93, 0.74, 0.40), Color(0.50, 0.30, 0.20), Color(1.0, 0.9, 0.6)]),
		PackedColorArray([Color(0.58, 0.50, 0.56), Color(0.24, 0.20, 0.28), Color(1.0, 0.8, 0.7)]),
		PackedColorArray([Color(0.96, 0.84, 0.66), Color(0.50, 0.36, 0.36), Color(1.0, 0.9, 0.7)]),
		PackedColorArray([Color(0.80, 0.78, 0.82), Color(0.36, 0.34, 0.42), Color(1.0, 1.0, 1.0)]),
		PackedColorArray([Color(1.00, 0.92, 0.70), Color(0.80, 0.50, 0.30), Color(1.0, 1.0, 1.0)]),
	]
	var stage: Array[PackedColorArray] = [
		PackedColorArray([Color(0.46, 0.40, 0.44), Color(0.17, 0.15, 0.21), Color(0.9, 0.7, 0.6)]),
		PackedColorArray([Color(0.52, 0.45, 0.46), Color(0.19, 0.16, 0.21), Color(0.9, 0.7, 0.6)]),
		PackedColorArray([Color(0.50, 0.44, 0.40), Color(0.18, 0.15, 0.19), Color(0.9, 0.7, 0.6)]),
		PackedColorArray([Color(0.64, 0.50, 0.34), Color(0.24, 0.17, 0.17), Color(1.0, 0.8, 0.5)]),
	]
	for variant: int in range(2):
		for c: int in range(figure.size()):
			var lit: Color = figure[c][0]
			var shadow: Color = figure[c][1]
			if variant == 1:
				lit = Color(minf(lit.r + 0.25, 1.0), lit.g * 0.7, lit.b * 0.7)
				shadow = Color(shadow.r + 0.1, shadow.g * 0.6, shadow.b * 0.6)
			img.set_pixel(c + 1, variant * 4, lit)
			img.set_pixel(c + 1, variant * 4 + 1, shadow)
			img.set_pixel(c + 1, variant * 4 + 2, figure[c][2])
			img.set_pixel(c + 1, variant * 4 + 3, Color(0, 0, 0, 0))
		img.set_pixel(8, variant * 4 + 3, Color(1.0, 0.72, 0.30, 1.0))
	for c: int in range(stage.size()):
		img.set_pixel(c + 1, 8, stage[c][0])
		img.set_pixel(c + 1, 9, stage[c][1])
		img.set_pixel(c + 1, 10, stage[c][2])
		img.set_pixel(c + 1, 11, Color(0, 0, 0, 0))
	return img


## The test figure as a sheet at [param scale] (1, 2 or 4).
static func figure_sheet(scale: int, noise_tex: Texture2D) -> SpriteSheet:
	var images: Dictionary[StringName, Image] = bake(figure_prims(), FIGURE_CELL_U, scale)
	images[&"palette"] = palette_image()
	return SpriteSheet.from_images(images, scale, FIGURE_ORIGIN_U, noise_tex)


## The stage as a sheet at 1x (palette variant 2).
static func stage_sheet(noise_tex: Texture2D) -> SpriteSheet:
	var images: Dictionary[StringName, Image] = bake(stage_prims(), STAGE_CELL_U, 1)
	images[&"palette"] = palette_image()
	return SpriteSheet.from_images(images, 1, STAGE_MARK_U, noise_tex)


## The shared noise (ADR-0023 Decision 1.7): 256 x 256, tileable, from an integer hash with no RNG
## state. R paper grain (128 and 64 cells), G brush (32, 64 and 16 cells), B wobble octave 1
## (16 cells), A wobble octave 2 (32 cells). With mipmaps.
static func noise_texture() -> ImageTexture:
	var img: Image = Image.create(NOISE_PX, NOISE_PX, false, Image.FORMAT_RGBA8)
	for y: int in range(NOISE_PX):
		for x: int in range(NOISE_PX):
			var r: float = 0.5 * value_noise(x, y, 128, 1) + 0.5 * value_noise(x, y, 64, 2)
			var g: float = (
				0.45 * value_noise(x, y, 32, 3)
				+ 0.35 * value_noise(x, y, 64, 4)
				+ 0.2 * value_noise(x, y, 16, 5)
			)
			var b: float = value_noise(x, y, 16, 6)
			var a: float = value_noise(x, y, 32, 7)
			img.set_pixel(x, y, Color(r, g, b, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Tileable value noise at texel (x, y) of the 256 texture with [param cells] cells a side.
static func value_noise(x: int, y: int, cells: int, channel_seed: int) -> float:
	var fx: float = float(x) * float(cells) / float(NOISE_PX)
	var fy: float = float(y) * float(cells) / float(NOISE_PX)
	var ix: int = floori(fx)
	var iy: int = floori(fy)
	var tx: float = smoothstep(0.0, 1.0, fx - float(ix))
	var ty: float = smoothstep(0.0, 1.0, fy - float(iy))
	var x0: int = ix % cells
	var y0: int = iy % cells
	var x1: int = (ix + 1) % cells
	var y1: int = (iy + 1) % cells
	var top: float = lerpf(_hash(x0, y0, channel_seed), _hash(x1, y0, channel_seed), tx)
	var bottom: float = lerpf(_hash(x0, y1, channel_seed), _hash(x1, y1, channel_seed), tx)
	return lerpf(top, bottom, ty)


static func _hash(ix: int, iy: int, channel_seed: int) -> float:
	var n: int = (ix * 374761393 + iy * 668265263 + channel_seed * 1442695041) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0
