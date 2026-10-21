class_name RoomView
extends Node2D
## The grey-box room: its tiles, its solid boxes and the solid beyond its edge, drawn from the
## simulation's collision world in the lighting pass (BUILD.md section 10, Lighting). A placeholder
## until the tileset art (section 10); it reads the core and never writes it. Its colours are
## content (`tile_*` and `box_*` in content/feedback.tres, CLAUDE.md rule 6).

## How far past the room's edge the solid is drawn: more than the camera's margin can reveal.
const BEYOND_U: float = 8192.0

## The tuning the tiles' and boxes' grey-box shapes and colours come from, loaded once
## ([method look]).
static var _look_cache: FeedbackTuning

var world: CollisionWorld
var doors: Array[RoomData.Door] = []
## The solid boxes, redrawn every tick (a wax wall burns away).
var _solids: Node2D
var _backdrop: Node2D
## What gives off light (pogo-able surfaces are emissive, BUILD.md section 10, Lighting): the
## spikes' teeth, drawn once a room, and the bells' strike marks, redrawn with the boxes.
var _tile_glow: Node2D
var _box_glow: Node2D


func _ready() -> void:
	# Lit grey boxes until the tileset art: the tiles take a bevel normal from the room's distance
	# field so the ember rakes across their edges, the air behind the room is flat, and the solid
	# boxes are flat and keep their hue, because their colour says what they do (the ember's
	# 2400 K would make the smooth box's tan and the wax's amber one colour). game/lighting.
	LightSurfaces.make_lit(self, true)
	_backdrop = _layer("Backdrop", _draw_backdrop)
	_backdrop.show_behind_parent = true
	LightSurfaces.make_lit(_backdrop, false)
	_solids = _layer("Solids", _draw_solids)
	LightSurfaces.make_lit(_solids, false, true)
	_tile_glow = _layer("TileGlow", _draw_tile_glow)
	LightSurfaces.make_emissive(_tile_glow)
	_box_glow = _layer("BoxGlow", _draw_box_glow)
	LightSurfaces.make_emissive(_box_glow)


func _layer(layer_name: String, drawer: Callable) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	add_child(n)
	n.draw.connect(drawer)
	return n


## Shows [param p_world]'s room, its [param p_doors] open onto the beyond.
func show_world(p_world: CollisionWorld, p_doors: Array[RoomData.Door] = []) -> void:
	world = p_world
	doors = p_doors
	queue_redraw()
	if _backdrop != null:
		_backdrop.queue_redraw()
		_tile_glow.queue_redraw()
	refresh()


## Redraws what can change during play.
func refresh() -> void:
	if _solids != null:
		_solids.queue_redraw()
		_box_glow.queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var grid: TileGrid = world.grid
	var t: float = float(TileGrid.TILE)
	var size := Vector2(grid.width, grid.height) * t
	var c: FeedbackTuning = look()
	# The solid beyond the room, as four bands around it.
	draw_rect(Rect2(-BEYOND_U, -BEYOND_U, size.x + BEYOND_U * 2.0, BEYOND_U), c.tile_beyond_colour)
	draw_rect(Rect2(-BEYOND_U, size.y, size.x + BEYOND_U * 2.0, BEYOND_U), c.tile_beyond_colour)
	draw_rect(Rect2(-BEYOND_U, 0, BEYOND_U, size.y), c.tile_beyond_colour)
	draw_rect(Rect2(size.x, 0, BEYOND_U, size.y), c.tile_beyond_colour)
	# A door's way through the solid beyond the room (docs/adr/0014).
	for d: RoomData.Door in doors:
		var from: float = float(d.from_u)
		var span: float = float(d.span_u())
		match d.side:
			RoomData.LEFT:
				draw_rect(Rect2(-BEYOND_U, from, BEYOND_U, span), c.tile_passage_colour)
			RoomData.RIGHT:
				draw_rect(Rect2(size.x, from, BEYOND_U, span), c.tile_passage_colour)
			RoomData.TOP:
				draw_rect(Rect2(from, -BEYOND_U, span, BEYOND_U), c.tile_passage_colour)
			RoomData.BOTTOM:
				draw_rect(Rect2(from, size.y, span, BEYOND_U), c.tile_passage_colour)
	for j: int in range(grid.height):
		for i: int in range(grid.width):
			var tile: int = grid.get_tile(i, j)
			if not glows(tile):
				draw_tile(self, tile, Vector2(i, j) * t, t)


## The tuning the tiles' and boxes' grey-box shapes and colours come from
## (content/feedback.tres), loaded once.
static func look() -> FeedbackTuning:
	if _look_cache == null:
		_look_cache = load(FeedbackTuning.PATH) as FeedbackTuning
	return _look_cache


## Whether tile kind [param tile] gives off light in the game: a pogo-able tile does (the spikes;
## BUILD.md section 10, Lighting: "pogo-able surfaces are emissive"). A pit is a hazard with
## nothing in it to pogo off, so it does not.
static func glows(tile: int) -> bool:
	return tile == TileGrid.SPIKES


## [param colour] as a pogo-able surface gives it off ([member FeedbackTuning.pogo_glow] of it;
## the emissive material multiplies it by the lighting's boost).
static func glow_colour(colour: Color) -> Color:
	var g: float = look().pogo_glow
	return Color(colour.r * g, colour.g * g, colour.b * g, colour.a)


## Draws [param tile] on [param canvas] with its top-left at [param at], [param t] units square,
## in its colour (shared with the room editor, so a room has the same colours in both: the editor
## shows them as they are, the game lit, with what [method glows] drawn as light).
static func draw_tile(canvas: CanvasItem, tile: int, at: Vector2, t: float) -> void:
	var c: FeedbackTuning = look()
	if tile == TileGrid.SOLID:
		canvas.draw_rect(Rect2(at, Vector2(t, t)), c.tile_solid_colour)
	elif tile == TileGrid.SMOOTH:
		canvas.draw_rect(Rect2(at, Vector2(t, t)), c.tile_smooth_colour)
	elif tile == TileGrid.ONE_WAY:
		canvas.draw_rect(Rect2(at, Vector2(t, c.tile_one_way_u)), c.tile_one_way_colour)
	elif tile == TileGrid.SPIKES:
		draw_spikes(canvas, at, t, c.tile_spikes_colour)
	elif tile == TileGrid.PIT:
		canvas.draw_rect(Rect2(at, Vector2(t, t)), c.tile_pit_colour)
		canvas.draw_rect(Rect2(at, Vector2(t, c.tile_pit_lip_u)), c.tile_pit_lip_colour)
	elif TileGrid.is_slope(tile):
		var edges: Vector2i = TileGrid.slope_edge_heights(tile)
		var hl: float = float(edges.x) / Fx.SUB
		var hr: float = float(edges.y) / Fx.SUB
		canvas.draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(at.x, at.y + t),
					Vector2(at.x + t, at.y + t),
					Vector2(at.x + t, at.y + t - hr),
					Vector2(at.x, at.y + t - hl)
				]
			),
			c.tile_solid_colour
		)


## Draws a spike tile's teeth on [param canvas], its top-left at [param at], [param t] units square,
## in [param colour].
static func draw_spikes(canvas: CanvasItem, at: Vector2, t: float, colour: Color) -> void:
	var c: FeedbackTuning = look()
	var w: float = t / c.tile_spike_teeth
	for k: int in range(c.tile_spike_teeth):
		var x0: float = at.x + k * w
		canvas.draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(x0, at.y + t),
					Vector2(x0 + w, at.y + t),
					Vector2(x0 + w * 0.5, at.y + t * c.tile_spike_peak)
				]
			),
			colour
		)


## A filled rectangle of a solid box's grey-box drawing; [member glow] if it is a pogo-able
## surface, which the game draws as light.
class BoxFill:
	extends RefCounted
	var rect: Rect2
	var colour: Color
	var glow: bool

	func _init(p_rect: Rect2, p_colour: Color, p_glow: bool = false) -> void:
		rect = p_rect
		colour = p_colour
		glow = p_glow


## The fills that draw box [param s] over [param r] (the box in units), by function: wax is
## amber, a pogo-able box is cyan steel with a pale mark along its top edge (the surface struck,
## a [member BoxFill.glow] fill), any other is a lighter shade of the wall of its kind (smooth when
## it cannot be clung to); a wax or bell box that cannot be clung to also has smooth-coloured side
## strips. The colours are in content/feedback.tres.
static func box_fills(s: SolidBox, r: Rect2) -> Array[BoxFill]:
	var c: FeedbackTuning = look()
	var out: Array[BoxFill] = []
	if s.tag == "wax":
		out.append(BoxFill.new(r, c.box_wax_colour))
	elif s.tag == "pogo":
		out.append(BoxFill.new(r, c.box_pogo_colour))
		var mark := Rect2(r.position, Vector2(r.size.x, minf(c.box_mark_u, r.size.y)))
		out.append(BoxFill.new(mark, c.box_pogo_mark_colour, true))
	else:
		out.append(BoxFill.new(r, c.box_solid_colour if s.clingable else c.box_smooth_colour))
		return out
	if not s.clingable:
		# Wax and a bell paint over the cling flag, so a strip of the smooth colour down each side
		# shows the wall cannot be clung to.
		var w: float = minf(c.box_side_u, r.size.x * 0.5)
		out.append(BoxFill.new(Rect2(r.position, Vector2(w, r.size.y)), c.box_smooth_colour))
		var right := Vector2(r.end.x - w, r.position.y)
		out.append(BoxFill.new(Rect2(right, Vector2(w, r.size.y)), c.box_smooth_colour))
	return out


## Draws box [param s] over [param r] on [param canvas] (shared with the room editor), every fill
## in its colour.
static func draw_box(canvas: CanvasItem, s: SolidBox, r: Rect2) -> void:
	for f: BoxFill in box_fills(s, r):
		canvas.draw_rect(f.rect, f.colour)


func _draw_backdrop() -> void:
	if world == null:
		return
	var t: float = float(TileGrid.TILE)
	var room := Rect2(0.0, 0.0, world.grid.width * t, world.grid.height * t)
	_backdrop.draw_rect(room, look().tile_air_colour)


func _draw_tile_glow() -> void:
	if world == null:
		return
	var grid: TileGrid = world.grid
	var t: float = float(TileGrid.TILE)
	var light: Color = glow_colour(look().tile_spikes_colour)
	for j: int in range(grid.height):
		for i: int in range(grid.width):
			if glows(grid.get_tile(i, j)):
				draw_spikes(_tile_glow, Vector2(i, j) * t, t, light)


func _draw_solids() -> void:
	for f: BoxFill in _box_fills():
		if not f.glow:
			_solids.draw_rect(f.rect, f.colour)


func _draw_box_glow() -> void:
	for f: BoxFill in _box_fills():
		if f.glow:
			_box_glow.draw_rect(f.rect, glow_colour(f.colour))


## The fills of every enabled solid box of the world shown.
func _box_fills() -> Array[BoxFill]:
	var out: Array[BoxFill] = []
	if world == null:
		return out
	for s: SolidBox in world.solids:
		if not s.enabled:
			continue
		var r := Rect2(
			float(s.left) / Fx.SUB,
			float(s.top) / Fx.SUB,
			float(s.right - s.left) / Fx.SUB,
			float(s.bottom - s.top) / Fx.SUB
		)
		out.append_array(box_fills(s, r))
	return out
