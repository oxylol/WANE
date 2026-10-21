class_name RoomSdf
extends RefCounted
## A room's signed distance field, the thing the shadows are marched through (docs/adr/0023
## Decision 4.1; BUILD.md section 10, Lighting: "2D ray-marched soft shadows from the ember against
## the collision layer").
##
## The room's [TileGrid] is partitioned into exact shapes: row runs of wall tiles and row runs of
## empty tiles (each merged downward while the next row's run matches), each slope tile as two solid
## and up to two empty triangles (a half-slope tile has one of one kind), and the border as four
## solid bands. Outside the walls the field is the
## distance to the nearest solid shape; inside, minus the distance to the nearest empty one, so
## merged runs leave no inner seams. [method distance] evaluates it exactly in GDScript (the CPU
## twin of the bake, for tests); [method bake] draws it once on the GPU into a half-float texture
## at [member LightingTuning.sdf_texel_u] world units a texel and keeps the read-back as an [RH]
## texture. It is built at prebuild, cached by room, never on a door frame.

## Emitted when a bake has finished (read back, or failed).
signal finished

## Shape kinds (the shader's, in the shape texture's second row).
const SOLID_RECT: int = 0
const EMPTY_RECT: int = 1
const SOLID_TRI: int = 2
const EMPTY_TRI: int = 3
## Floats a shape takes in [member shapes]: a.x a.y b.x b.y c.x c.y kind pad. A rectangle's a is its
## top left and b its bottom right.
const STRIDE: int = 8
## Triangles thinner than this (twice the area, in u squared) are dropped.
const MIN_AREA2: float = 0.001
## The widest the bake texture may be, in texels.
const MAX_TEXELS: int = 4096

const BAKE_SHADER: String = "res://shaders/lighting/room_sdf_bake.gdshader"

## The shapes, [constant STRIDE] floats each.
var shapes: PackedFloat32Array = PackedFloat32Array()
## The area the field covers, in world units: the room and its border.
var rect: Rect2 = Rect2()
## The texel size in world units and the texture size in texels.
var texel_u: float = 4.0
var size_px: Vector2i = Vector2i.ZERO
## The baked field (RH, world units; negative inside walls), once [method bake] has finished.
var texture: ImageTexture = null
var image: Image = null
var baked: bool = false

var _bake_viewport: SubViewport = null


## Builds the shapes for [param grid], with a solid border of [param border_u] world units and a
## field of [param p_texel_u] world units a texel.
static func from_grid(grid: TileGrid, border_u: float, p_texel_u: float) -> RoomSdf:
	var s := RoomSdf.new()
	var t: float = float(TileGrid.TILE)
	var w: float = float(grid.width) * t
	var h: float = float(grid.height) * t
	s.rect = Rect2(-border_u, -border_u, w + border_u * 2.0, h + border_u * 2.0)
	var texel: float = maxf(p_texel_u, maxf(s.rect.size.x, s.rect.size.y) / float(MAX_TEXELS))
	s.texel_u = texel
	s.size_px = Vector2i(ceili(s.rect.size.x / texel), ceili(s.rect.size.y / texel))
	# The covered rectangle is whole texels, so a texel's centre is at (i + 0.5) * texel.
	s.rect.size = Vector2(s.size_px) * texel
	s._partition(grid, border_u)
	return s


## How many shapes.
func count() -> int:
	return shapes.size() / STRIDE


## How many shapes of [param kind].
func count_of(kind: int) -> int:
	var n: int = 0
	for i: int in range(count()):
		if int(shapes[i * STRIDE + 6]) == kind:
			n += 1
	return n


func _partition(grid: TileGrid, border_u: float) -> void:
	var t: float = float(TileGrid.TILE)
	var w: float = float(grid.width) * t
	var h: float = float(grid.height) * t
	_runs(grid, true, SOLID_RECT)
	_runs(grid, false, EMPTY_RECT)
	for j: int in range(grid.height):
		for i: int in range(grid.width):
			var tile: int = grid.get_tile(i, j)
			if TileGrid.is_slope(tile):
				_slope(Vector2(float(i) * t, float(j) * t), t, TileGrid.slope_edge_heights(tile))
	_add_rect(Vector2(-border_u, -border_u), Vector2(w + border_u, 0.0), SOLID_RECT)
	_add_rect(Vector2(-border_u, h), Vector2(w + border_u, h + border_u), SOLID_RECT)
	_add_rect(Vector2(-border_u, 0.0), Vector2(0.0, h), SOLID_RECT)
	_add_rect(Vector2(w, 0.0), Vector2(w + border_u, h), SOLID_RECT)


## Row runs of wall tiles ([param walls] true) or of empty tiles (neither wall nor slope), merged
## downward while the next row has the same run.
func _runs(grid: TileGrid, walls: bool, kind: int) -> void:
	var t: float = float(TileGrid.TILE)
	var open: Dictionary[int, Vector3i] = {}
	for j: int in range(grid.height + 1):
		var runs: Array[Vector2i] = []
		if j < grid.height:
			runs = _row_runs(grid, j, walls)
		var next: Dictionary[int, Vector3i] = {}
		for run: Vector2i in runs:
			var key: int = run.x * 100000 + run.y
			next[key] = open[key] if open.has(key) else Vector3i(run.x, run.y, j)
		for key: int in open:
			if not next.has(key):
				var r: Vector3i = open[key]
				_add_rect(Vector2(r.x * t, r.z * t), Vector2((r.y + 1) * t, j * t), kind)
		open = next


func _row_runs(grid: TileGrid, j: int, walls: bool) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var start: int = -1
	for i: int in range(grid.width + 1):
		var on: bool = false
		if i < grid.width:
			var tile: int = grid.get_tile(i, j)
			on = (
				TileGrid.is_wall(tile)
				if walls
				else not (TileGrid.is_wall(tile) or TileGrid.is_slope(tile))
			)
		if on and start < 0:
			start = i
		elif not on and start >= 0:
			runs.append(Vector2i(start, i - 1))
			start = -1
	return runs


## A slope tile at [param at] ([param t] units square, edge heights [param edges] in sub-pixels at
## its left and right): the solid trapezoid below the surface as two triangles, the empty part above
## as two.
func _slope(at: Vector2, t: float, edges: Vector2i) -> void:
	var hl: float = float(edges.x) / Fx.SUB
	var hr: float = float(edges.y) / Fx.SUB
	var bl := Vector2(at.x, at.y + t)
	var br := Vector2(at.x + t, at.y + t)
	var top_left := Vector2(at.x, at.y)
	var top_right := Vector2(at.x + t, at.y)
	var d := Vector2(at.x, at.y + t - hl)
	var c := Vector2(at.x + t, at.y + t - hr)
	_add_tri(bl, br, c, SOLID_TRI)
	_add_tri(bl, c, d, SOLID_TRI)
	_add_tri(d, c, top_right, EMPTY_TRI)
	_add_tri(d, top_right, top_left, EMPTY_TRI)


func _add_rect(a: Vector2, b: Vector2, kind: int) -> void:
	shapes.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, 0.0, 0.0, float(kind), 0.0]))


func _add_tri(a: Vector2, b: Vector2, c: Vector2, kind: int) -> void:
	if absf((b - a).cross(c - a)) < MIN_AREA2:
		return
	shapes.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, c.x, c.y, float(kind), 0.0]))


## The shape data as the bake's texture: (count x 2) RGBA32F.
func shape_image() -> Image:
	var n: int = count()
	var row0 := PackedFloat32Array()
	var row1 := PackedFloat32Array()
	for i: int in range(n):
		var o: int = i * STRIDE
		row0.append_array(
			PackedFloat32Array([shapes[o], shapes[o + 1], shapes[o + 2], shapes[o + 3]])
		)
		row1.append_array(PackedFloat32Array([shapes[o + 4], shapes[o + 5], shapes[o + 6], 0.0]))
	row0.append_array(row1)
	return Image.create_from_data(n, 2, false, Image.FORMAT_RGBAF, row0.to_byte_array())


## The signed distance at [param p] in world units, exact (the twin of the bake): negative inside a
## wall, the distance to the nearest solid shape outside it.
func distance(p: Vector2) -> float:
	var solid: float = INF
	var empty: float = INF
	for i: int in range(count()):
		var o: int = i * STRIDE
		var kind: int = int(shapes[o + 6])
		var d: float = 0.0
		if kind == SOLID_RECT or kind == EMPTY_RECT:
			d = _rect_distance(p, shapes[o], shapes[o + 1], shapes[o + 2], shapes[o + 3])
		else:
			d = _tri_distance(
				p,
				Vector2(shapes[o], shapes[o + 1]),
				Vector2(shapes[o + 2], shapes[o + 3]),
				Vector2(shapes[o + 4], shapes[o + 5])
			)
		if kind == SOLID_RECT or kind == SOLID_TRI:
			solid = minf(solid, d)
		else:
			empty = minf(empty, d)
	# Beyond the border is solid too: the field is continuous across the edge of its own rectangle.
	if solid <= 0.0 or not rect.has_point(p):
		return -empty if empty < INF else 0.0
	return solid


## The baked field at [param p], bilinear as the shader reads it (clamped at the edge); the
## unbaked field is the exact one.
func sample(p: Vector2) -> float:
	if image == null:
		return distance(p)
	var u: float = (p.x - rect.position.x) / texel_u - 0.5
	var v: float = (p.y - rect.position.y) / texel_u - 0.5
	var x0: int = floori(u)
	var y0: int = floori(v)
	var fx: float = u - float(x0)
	var fy: float = v - float(y0)
	var a: float = _texel(x0, y0)
	var b: float = _texel(x0 + 1, y0)
	var c: float = _texel(x0, y0 + 1)
	var d: float = _texel(x0 + 1, y0 + 1)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func _texel(x: int, y: int) -> float:
	return image.get_pixel(clampi(x, 0, size_px.x - 1), clampi(y, 0, size_px.y - 1)).r


static func _rect_distance(p: Vector2, x0: float, y0: float, x1: float, y1: float) -> float:
	var dx: float = maxf(maxf(x0 - p.x, p.x - x1), 0.0)
	var dy: float = maxf(maxf(y0 - p.y, p.y - y1), 0.0)
	return sqrt(dx * dx + dy * dy)


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.dot(ab), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _tri_distance(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var d1: float = (b - a).cross(p - a)
	var d2: float = (c - b).cross(p - b)
	var d3: float = (a - c).cross(p - c)
	var neg: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var pos: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	if not (neg and pos):
		return 0.0
	return minf(
		_segment_distance(p, a, b), minf(_segment_distance(p, b, c), _segment_distance(p, c, a))
	)


## Whether the GPU bake can run: not under the dummy renderer (--headless).
static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Starts the bake on the GPU: one draw of the bake shader into a half-float [SubViewport] under
## [param host] (which must be in the tree), read back once, on the frame after the next draw, as an
## RH texture; [signal finished] fires then. A no-op under the dummy renderer or if baked.
func begin_bake(host: Node) -> void:
	if baked or _bake_viewport != null or not can_render():
		return
	var vp := SubViewport.new()
	vp.name = "RoomSdfBake"
	vp.size = size_px
	vp.use_hdr_2d = true
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var mat := ShaderMaterial.new()
	mat.shader = load(BAKE_SHADER) as Shader
	mat.set_shader_parameter("shapes", ImageTexture.create_from_image(shape_image()))
	mat.set_shader_parameter("shape_count", count())
	mat.set_shader_parameter(
		"bake_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	)
	var quad := ColorRect.new()
	quad.size = Vector2(size_px)
	quad.material = mat
	vp.add_child(quad)
	host.add_child(vp)
	_bake_viewport = vp
	RenderingServer.frame_post_draw.connect(_read_back, CONNECT_ONE_SHOT)


## Bakes the field and waits for it (tests, renders).
func bake(host: Node) -> void:
	if baked or not can_render():
		return
	begin_bake(host)
	await finished


func _read_back() -> void:
	var vp: SubViewport = _bake_viewport
	_bake_viewport = null
	if vp == null:
		return
	var img: Image = vp.get_texture().get_image()
	vp.get_parent().remove_child(vp)
	vp.free()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RH)
		image = img
		texture = ImageTexture.create_from_image(img)
		baked = true
	finished.emit()
