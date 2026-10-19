class_name ContactSheet
extends RefCounted
## Grey-box contact sheets drawn on the CPU into an [Image], so they render headless and the same
## everywhere (CLAUDE.md working method: "play the fixture and capture a contact sheet"). One panel
## per sampled frame: the room around a focus point, every body's box with a fading trail of where
## it has been, marks for events, and the frame number in the corner.

const BG := Color(0.07, 0.07, 0.09)
const WALL := Color(0.34, 0.34, 0.38)
const SMOOTH := Color(0.42, 0.4, 0.5)
const ONE_WAY := Color(0.62, 0.62, 0.66)
const SPIKE := Color(0.8, 0.22, 0.2)
## A pit: near-black with a red lip (a hazard you fall into, not a floor).
const PIT := Color(0.03, 0.02, 0.03)
const SOLID_BOX := Color(0.32, 0.42, 0.55)
const TEXT := Color(0.9, 0.9, 0.85)
const GRID := Color(0.12, 0.12, 0.15)

## 3x5 pixel glyphs for 0-9 and "-", five 3-bit rows packed top row first (bit 2 of a row is
## its left column).
const GLYPHS: PackedInt32Array = [
	31599, 11415, 29671, 29647, 23497, 31183, 31215, 29257, 31727, 31695, 448
]

## Pixels per world unit.
var scale: int = 1
var world: CollisionWorld


func _init(p_world: CollisionWorld, p_scale: int = 1) -> void:
	world = p_world
	scale = p_scale


## The room within [param region] (world units) as an image.
func room_image(region: Rect2i) -> Image:
	var img := Image.create_empty(
		region.size.x * scale, region.size.y * scale, false, Image.FORMAT_RGBA8
	)
	img.fill(BG)
	var t: int = TileGrid.TILE
	for c: int in range(Fx.div_floor(region.position.x, t), Fx.div_floor(region.end.x - 1, t) + 1):
		for j: int in range(
			Fx.div_floor(region.position.y, t), Fx.div_floor(region.end.y - 1, t) + 1
		):
			_draw_tile(img, region, c, j)
	for s: SolidBox in world.solids:
		var r := Rect2i(
			Fx.div_floor(s.left, Fx.SUB),
			Fx.div_floor(s.top, Fx.SUB),
			Fx.div_floor(s.right - s.left, Fx.SUB),
			Fx.div_floor(s.bottom - s.top, Fx.SUB)
		)
		if s.enabled:
			fill(img, region, r, SOLID_BOX)
		else:
			# Broken or burned during the run: where it was.
			outline(img, region, r, SOLID_BOX)
	return img


func _draw_tile(img: Image, region: Rect2i, c: int, j: int) -> void:
	var tile: int = world.grid.get_tile(c, j)
	var t: int = TileGrid.TILE
	var cell := Rect2i(c * t, j * t, t, t)
	if tile == TileGrid.SOLID:
		fill(img, region, cell, WALL)
	elif tile == TileGrid.SMOOTH:
		fill(img, region, cell, SMOOTH)
	elif tile == TileGrid.ONE_WAY:
		fill(img, region, Rect2i(cell.position, Vector2i(t, 2)), ONE_WAY)
	elif tile == TileGrid.SPIKES:
		var inset: int = Fx.div_floor(world.spike_inset_sp, Fx.SUB)
		for x: int in range(t):
			var h: int = (t - inset) * (8 - absi(x % 8 * 2 - 7)) / 8
			fill(img, region, Rect2i(cell.position.x + x, cell.end.y - h, 1, h), SPIKE)
	elif tile == TileGrid.PIT:
		fill(img, region, cell, PIT)
		fill(img, region, Rect2i(cell.position, Vector2i(t, 1)), SPIKE)
	elif TileGrid.is_slope(tile):
		for x: int in range(t):
			var sx: int = Fx.units(c * t + x)
			var s: int = Fx.div_floor(TileGrid.slope_surface(tile, c, j, sx), Fx.SUB)
			fill(img, region, Rect2i(c * t + x, s, 1, cell.end.y - s), WALL)


## Fills [param r] (world units) clipped to [param region].
func fill(img: Image, region: Rect2i, r: Rect2i, color: Color) -> void:
	var clipped: Rect2i = r.intersection(region)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	img.fill_rect(Rect2i((clipped.position - region.position) * scale, clipped.size * scale), color)


## Outlines [param r] (world units), [param width] pixels thick.
func outline(img: Image, region: Rect2i, r: Rect2i, color: Color, width: int = 1) -> void:
	var px := Rect2i((r.position - region.position) * scale, r.size * scale)
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	for edge: Rect2i in [
		Rect2i(px.position, Vector2i(px.size.x, width)),
		Rect2i(px.position.x, px.end.y - width, px.size.x, width),
		Rect2i(px.position, Vector2i(width, px.size.y)),
		Rect2i(px.end.x - width, px.position.y, width, px.size.y),
	]:
		var e: Rect2i = edge.intersection(bounds)
		if e.size.x > 0 and e.size.y > 0:
			img.fill_rect(e, color)


## A body's box in world units from its sub-pixel bottom-centre.
static func box_rect(x: int, y: int, half_w: int, height: int) -> Rect2i:
	var l: int = Fx.div_floor(x - half_w, Fx.SUB)
	var t: int = Fx.div_floor(y - height, Fx.SUB)
	return Rect2i(l, t, Fx.div_floor(x + half_w, Fx.SUB) - l, Fx.div_floor(y, Fx.SUB) - t)


## Draws [param number] in 3x5 digits scaled by [param size], top-left at [param at] pixels.
static func digits(img: Image, at: Vector2i, number: int, color: Color, size: int = 2) -> void:
	var text: String = str(number)
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	for k: int in range(text.length()):
		var glyph: int = GLYPHS[10] if text[k] == "-" else GLYPHS[text.unicode_at(k) - 48]
		for row: int in range(5):
			for col: int in range(3):
				if (glyph >> ((4 - row) * 3 + 2 - col)) & 1 == 1:
					var p := Vector2i(at.x + (k * 4 + col) * size, at.y + row * size)
					var cell := Rect2i(p, Vector2i(size, size)).intersection(bounds)
					if cell.size.x > 0 and cell.size.y > 0:
						img.fill_rect(cell, color)


## Lays [param panels] out in a grid of [param columns] with a 4 px gutter; each column is as
## wide as its widest panel and each row as tall as its tallest.
static func sheet(panels: Array[Image], columns: int) -> Image:
	if panels.is_empty():
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var gap: int = 4
	var rows: int = (panels.size() + columns - 1) / columns
	var widths: PackedInt32Array = PackedInt32Array()
	widths.resize(columns)
	widths.fill(0)
	var heights: PackedInt32Array = PackedInt32Array()
	heights.resize(rows)
	heights.fill(0)
	for i: int in range(panels.size()):
		widths[i % columns] = maxi(widths[i % columns], panels[i].get_width())
		heights[i / columns] = maxi(heights[i / columns], panels[i].get_height())
	var total_w: int = gap
	for w: int in widths:
		total_w += w + gap
	var total_h: int = gap
	for h: int in heights:
		total_h += h + gap
	var out := Image.create_empty(total_w, total_h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.02, 0.02, 0.03))
	var y: int = gap
	for row: int in range(rows):
		var x: int = gap
		for col: int in range(columns):
			var i: int = row * columns + col
			if i < panels.size():
				out.blit_rect(
					panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(x, y)
				)
			x += widths[col] + gap
		y += heights[row] + gap
	return out
