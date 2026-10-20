class_name RoomView
extends Node2D
## The grey-box room: its tiles, its solid boxes and the solid beyond its edge, drawn from the
## simulation's collision world. A placeholder until the tileset art (BUILD.md section 10); it
## reads the core and never writes it.

const SOLID := Color(0.30, 0.30, 0.34)
const SMOOTH := Color(0.36, 0.33, 0.30)
const ONE_WAY := Color(0.60, 0.60, 0.64)
const SPIKES := Color(0.80, 0.30, 0.24)
## A pit: darker than the solid beyond the room, with a red lip, so a drop reads as a hazard.
const PIT := Color(0.06, 0.04, 0.05)
const PIT_LIP := Color(0.55, 0.18, 0.15)
const BEYOND := Color(0.20, 0.20, 0.23)
## A door's way through the solid beyond the room: the room's own empty colour (the project's
## clear colour), so an opening reads as a passage on to the next room (docs/adr/0014).
const PASSAGE := Color(0.07, 0.07, 0.08)
## How far past the room's edge the solid is drawn: more than the camera's margin can reveal.
const BEYOND_U: float = 8192.0

## The tuning the tiles' and boxes' grey-box shapes come from, loaded once ([method _look]).
static var _look_cache: FeedbackTuning

var world: CollisionWorld
var doors: Array[RoomData.Door] = []
## The solid boxes, redrawn every tick (a wax wall burns away).
var _solids: Node2D


func _ready() -> void:
	_solids = Node2D.new()
	_solids.name = "Solids"
	add_child(_solids)
	_solids.draw.connect(_draw_solids)


## Shows [param p_world]'s room, its [param p_doors] open onto the beyond.
func show_world(p_world: CollisionWorld, p_doors: Array[RoomData.Door] = []) -> void:
	world = p_world
	doors = p_doors
	queue_redraw()
	refresh()


## Redraws what can change during play.
func refresh() -> void:
	if _solids != null:
		_solids.queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var grid: TileGrid = world.grid
	var t: float = float(TileGrid.TILE)
	var size := Vector2(grid.width, grid.height) * t
	# The solid beyond the room, as four bands around it.
	draw_rect(Rect2(-BEYOND_U, -BEYOND_U, size.x + BEYOND_U * 2.0, BEYOND_U), BEYOND)
	draw_rect(Rect2(-BEYOND_U, size.y, size.x + BEYOND_U * 2.0, BEYOND_U), BEYOND)
	draw_rect(Rect2(-BEYOND_U, 0, BEYOND_U, size.y), BEYOND)
	draw_rect(Rect2(size.x, 0, BEYOND_U, size.y), BEYOND)
	for d: RoomData.Door in doors:
		var from: float = float(d.from_u)
		var span: float = float(d.span_u())
		match d.side:
			RoomData.LEFT:
				draw_rect(Rect2(-BEYOND_U, from, BEYOND_U, span), PASSAGE)
			RoomData.RIGHT:
				draw_rect(Rect2(size.x, from, BEYOND_U, span), PASSAGE)
			RoomData.TOP:
				draw_rect(Rect2(from, -BEYOND_U, span, BEYOND_U), PASSAGE)
			RoomData.BOTTOM:
				draw_rect(Rect2(from, size.y, span, BEYOND_U), PASSAGE)
	for j: int in range(grid.height):
		for i: int in range(grid.width):
			draw_tile(self, grid.get_tile(i, j), Vector2(i, j) * t, t)


## The tuning the tiles' and boxes' grey-box shapes come from (content/feedback.tres), loaded once.
static func _look() -> FeedbackTuning:
	if _look_cache == null:
		_look_cache = load(FeedbackTuning.PATH) as FeedbackTuning
	return _look_cache


## Draws [param tile] on [param canvas] with its top-left at [param at], [param t] units square
## (shared with the room editor, so a room looks the same in both).
static func draw_tile(canvas: CanvasItem, tile: int, at: Vector2, t: float) -> void:
	var look: FeedbackTuning = _look()
	if tile == TileGrid.SOLID:
		canvas.draw_rect(Rect2(at, Vector2(t, t)), SOLID)
	elif tile == TileGrid.SMOOTH:
		canvas.draw_rect(Rect2(at, Vector2(t, t)), SMOOTH)
	elif tile == TileGrid.ONE_WAY:
		canvas.draw_rect(Rect2(at, Vector2(t, look.tile_one_way_u)), ONE_WAY)
	elif tile == TileGrid.SPIKES:
		var teeth: int = look.tile_spike_teeth
		var w: float = t / teeth
		for k: int in range(teeth):
			var x0: float = at.x + k * w
			canvas.draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(x0, at.y + t),
						Vector2(x0 + w, at.y + t),
						Vector2(x0 + w * 0.5, at.y + t * look.tile_spike_peak)
					]
				),
				SPIKES
			)
	elif tile == TileGrid.PIT:
		canvas.draw_rect(Rect2(at, Vector2(t, t)), PIT)
		canvas.draw_rect(Rect2(at, Vector2(t, look.tile_pit_lip_u)), PIT_LIP)
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
			SOLID
		)


## A filled rectangle of a solid box's grey-box drawing.
class BoxFill:
	extends RefCounted
	var rect: Rect2
	var colour: Color

	func _init(p_rect: Rect2, p_colour: Color) -> void:
		rect = p_rect
		colour = p_colour


## The fills that draw box [param s] over [param r] (the box in units), by function: wax is
## amber, a pogo-able box is steel with a mark along its top edge, any other is near the wall
## of its kind (smooth when it cannot be clung to). The colours are in content/feedback.tres.
static func box_fills(s: SolidBox, r: Rect2) -> Array[BoxFill]:
	var look: FeedbackTuning = _look()
	var out: Array[BoxFill] = []
	if s.tag == "wax":
		out.append(BoxFill.new(r, look.box_wax_colour))
	elif s.tag == "pogo":
		out.append(BoxFill.new(r, look.box_pogo_colour))
		var mark := Rect2(r.position, Vector2(r.size.x, minf(look.box_mark_u, r.size.y)))
		out.append(BoxFill.new(mark, look.box_pogo_mark_colour))
	else:
		out.append(BoxFill.new(r, look.box_solid_colour if s.clingable else look.box_smooth_colour))
	return out


## Draws box [param s] over [param r] on [param canvas] (shared with the room editor).
static func draw_box(canvas: CanvasItem, s: SolidBox, r: Rect2) -> void:
	for f: BoxFill in box_fills(s, r):
		canvas.draw_rect(f.rect, f.colour)


func _draw_solids() -> void:
	if world == null:
		return
	for s: SolidBox in world.solids:
		if not s.enabled:
			continue
		var r := Rect2(
			float(s.left) / Fx.SUB,
			float(s.top) / Fx.SUB,
			float(s.right - s.left) / Fx.SUB,
			float(s.bottom - s.top) / Fx.SUB
		)
		draw_box(_solids, s, r)
