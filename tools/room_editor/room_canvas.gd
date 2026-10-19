@tool
class_name RoomCanvas
extends Control
## The room editor's drawing surface: the room's tiles, solid boxes, doors, entities and spawn
## point, with a tile grid, zoom and pan. It turns the mouse into [RoomDocument] edits for the
## current tool, and draws the room the same way the grey-box game does (colours and tiles from
## [RoomView]).
##
## Mouse: the left button applies the tool, the right button erases (paints empty tiles or
## removes the entity, door or box under the cursor), the middle button pans, the wheel zooms
## about the cursor. Delete removes the selection; Ctrl+Z and Ctrl+Y (or Ctrl+Shift+Z) undo and
## redo. Doors are drawn along an edge with the door tool; the select tool moves a door along its
## side and drags its ends to resize it.

signal hovered(tile: Vector2i, units: Vector2i)
## The selected box, entity or door changed (the panel shows its properties).
signal selection_changed

enum Tool { PAINT, RECT, LINE, SOLID, ENTITY, DOOR, SPAWN, MOVE }

## What a drag on a selected door does: slide it, or move one end.
enum DoorDrag { NONE, SLIDE, FROM_END, TO_END }

const GRID := Color(1.0, 1.0, 1.0, 0.06)
const GRID_MAJOR := Color(1.0, 1.0, 1.0, 0.14)
const SPAWN := Color(0.35, 0.7, 1.0)
const ENTITY := Color(1.0, 0.75, 0.3)
const PREVIEW := Color(1.0, 1.0, 1.0, 0.35)
const SELECTED := Color(1.0, 0.9, 0.2)
const DOOR := Color(0.3, 0.85, 0.8)
const DOOR_BAD := Color(1.0, 0.35, 0.3)
const MIN_ZOOM: float = 0.05
const MAX_ZOOM: float = 4.0
## How close (screen pixels) the pointer must be to a door's end to take that end.
const HANDLE_PX: float = 10.0

var document: RoomDocument
var tool: int = Tool.PAINT
var tile: int = TileGrid.SOLID
## The entity kind the entity tool places, and the tag of new solid boxes.
var entity_kind: String = "dummy"
var solid_tag: String = ""
## Screen pixels per unit, and the screen position of the room's origin.
var zoom: float = 0.25
var origin: Vector2 = Vector2(40, 40)
## The selection (an index), -1 for none; at most one of the three is set.
var selected_solid: int = -1
var selected_entity: int = -1
var selected_door: int = -1
## The doors the room's problems name, drawn in red (set by the panel).
var flagged_doors: PackedStringArray = PackedStringArray()

var _drag_from_tile: Vector2i = Vector2i(-1, -1)
var _last_tile: Vector2i = Vector2i(-1, -1)
var _drag_from_u: Vector2 = Vector2.ZERO
var _hover_u: Vector2 = Vector2.ZERO
var _dragging: int = MOUSE_BUTTON_NONE
var _panning: bool = false
var _door_drag: int = DoorDrag.NONE
var _door_origin: Vector2i = Vector2i.ZERO


func _init() -> void:
	focus_mode = Control.FOCUS_ALL


func set_document(doc: RoomDocument) -> void:
	if document != null and document.changed.is_connected(_on_document_changed):
		document.changed.disconnect(_on_document_changed)
	document = doc
	_select(-1, -1, -1)
	if document != null:
		document.changed.connect(_on_document_changed)
	fit()


## Zooms and pans so the whole room fits the canvas.
func fit() -> void:
	if document == null or size.x <= 0.0 or size.y <= 0.0:
		queue_redraw()
		return
	var room_u: Vector2 = _room_size_u()
	# Leave room around the room for the doors' passages, drawn outside it.
	var margin: float = 2.0 * TileGrid.TILE * 2.0
	zoom = clampf(
		minf((size.x - 40.0) / (room_u.x + margin), (size.y - 40.0) / (room_u.y + margin)),
		MIN_ZOOM,
		MAX_ZOOM
	)
	origin = (size - room_u * zoom) * 0.5
	queue_redraw()


## Screen position to room units.
func to_units(screen: Vector2) -> Vector2:
	return (screen - origin) / zoom


## Room units to the tile under them.
static func tile_at(units: Vector2) -> Vector2i:
	return Vector2i((units / float(TileGrid.TILE)).floor())


func _room_size_u() -> Vector2:
	return Vector2(document.room.grid.width, document.room.grid.height) * float(TileGrid.TILE)


func _select(solid: int, entity: int, door: int) -> void:
	if solid == selected_solid and entity == selected_entity and door == selected_door:
		return
	selected_solid = solid
	selected_entity = entity
	selected_door = door
	selection_changed.emit()
	queue_redraw()


## Redraws, and drops a selection that an undo (or any edit) has taken away.
func _on_document_changed() -> void:
	var room: RoomData = document.room
	if (
		selected_solid >= room.solids.size()
		or selected_entity >= room.entities.size()
		or selected_door >= room.doors.size()
	):
		_select(-1, -1, -1)
	queue_redraw()


## Selects solid box [param index] (the panel shows its properties).
func select_solid(index: int) -> void:
	_select(index, -1, -1)


func select_entity(index: int) -> void:
	_select(-1, index, -1)


func select_door(index: int) -> void:
	_select(-1, -1, index)


## Removes the selected box, entity or door.
func delete_selected() -> void:
	if document == null:
		return
	if selected_entity >= 0:
		document.objects().remove_entity(selected_entity)
	elif selected_door >= 0:
		document.doors().remove(selected_door)
	elif selected_solid >= 0:
		document.objects().remove_solid(selected_solid)
	_select(-1, -1, -1)


func _gui_input(event: InputEvent) -> void:
	if document == null:
		return
	var button := event as InputEventMouseButton
	if button != null:
		_on_button(button)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_on_motion(motion)
		accept_event()
		return
	var key := event as InputEventKey
	if key != null and key.pressed:
		_on_key(key)


func _on_key(e: InputEventKey) -> void:
	if e.keycode == KEY_DELETE or e.keycode == KEY_BACKSPACE:
		delete_selected()
		accept_event()
	elif e.keycode == KEY_Z and e.is_command_or_control_pressed():
		if e.shift_pressed:
			document.redo()
		else:
			document.undo()
		accept_event()
	elif e.keycode == KEY_Y and e.is_command_or_control_pressed():
		document.redo()
		accept_event()


func _on_button(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if e.pressed:
			var factor: float = 1.15 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			zoom_about(e.position, factor)
		return
	if e.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = e.pressed
		return
	if e.button_index != MOUSE_BUTTON_LEFT and e.button_index != MOUSE_BUTTON_RIGHT:
		return
	var u: Vector2 = to_units(e.position)
	if e.pressed:
		grab_focus()
		press(e.button_index, u)
	else:
		release(e.button_index, u)


func _on_motion(e: InputEventMouseMotion) -> void:
	if _panning:
		origin += e.relative
		queue_redraw()
		return
	drag_to(to_units(e.position))


## Zooms by [param factor] keeping the room point under [param screen] still.
func zoom_about(screen: Vector2, factor: float) -> void:
	var u: Vector2 = to_units(screen)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	origin = screen - u * zoom
	queue_redraw()


## A button goes down at [param u] (units): starts the tool's action. Public so tests and the
## panel's keyboard shortcuts can drive the canvas without a mouse.
func press(button: int, u: Vector2) -> void:
	_dragging = button
	_drag_from_u = u
	_drag_from_tile = tile_at(u)
	_last_tile = _drag_from_tile
	_door_drag = DoorDrag.NONE
	document.history.begin_stroke()
	var erase: bool = button == MOUSE_BUTTON_RIGHT
	match tool:
		Tool.PAINT:
			document.set_tile(_last_tile.x, _last_tile.y, TileGrid.EMPTY if erase else tile)
		Tool.SOLID, Tool.ENTITY, Tool.DOOR, Tool.MOVE:
			if erase:
				_erase_object_at(u)
			elif tool == Tool.ENTITY:
				var at: Vector2i = _snap(u)
				var index: int = document.objects().add_entity(entity_kind, at.x, at.y)
				_select(-1, index, -1)
			elif tool == Tool.MOVE:
				_select_at(u)
		Tool.SPAWN:
			var at: Vector2i = _snap(u)
			document.set_spawn(at.x, at.y)
	queue_redraw()


## The mouse moves to [param u] (units) with or without a button down.
func drag_to(u: Vector2) -> void:
	_hover_u = u
	var t: Vector2i = tile_at(u)
	hovered.emit(t, Vector2i(u.floor()))
	if _dragging == MOUSE_BUTTON_NONE:
		queue_redraw()
		return
	var erase: bool = _dragging == MOUSE_BUTTON_RIGHT
	if tool == Tool.PAINT and t != _last_tile:
		document.line(_last_tile, t, TileGrid.EMPTY if erase else tile)
		_last_tile = t
	elif tool == Tool.MOVE and not erase:
		if _door_drag != DoorDrag.NONE:
			_drag_door(u)
		else:
			_drag_object(u)
	queue_redraw()


func _drag_object(u: Vector2) -> void:
	var step: Vector2i = _snap(u) - _snap(_drag_from_u)
	if step == Vector2i.ZERO:
		return
	if selected_solid >= 0:
		document.objects().move_solid(selected_solid, step)
	elif selected_entity >= 0:
		var e: RoomData.RoomEntity = document.room.entities[selected_entity]
		document.objects().move_entity(selected_entity, e.x_u + step.x, e.y_u + step.y)
	_drag_from_u = u


## Slides the selected door, or moves one end, by the pointer's travel along its side in whole
## tiles from where the drag began.
func _drag_door(u: Vector2) -> void:
	var d: RoomData.Door = document.room.doors[selected_door]
	var delta: int = _tiles_u(_along(d.side, u) - _along(d.side, _drag_from_u))
	var edge: int = document.doors().edge_u(d.side)
	var min_span: int = RoomData.DOOR_DEPTH_TILES * TileGrid.TILE
	var from_u: int = _door_origin.x
	var to_u: int = _door_origin.y
	if _door_drag == DoorDrag.SLIDE:
		from_u = clampi(_door_origin.x + delta, 0, edge - (_door_origin.y - _door_origin.x))
		to_u = from_u + (_door_origin.y - _door_origin.x)
	elif _door_drag == DoorDrag.FROM_END:
		from_u = clampi(_door_origin.x + delta, 0, _door_origin.y - min_span)
	else:
		to_u = clampi(_door_origin.y + delta, _door_origin.x + min_span, edge)
	document.doors().set_span(selected_door, from_u, to_u)


## The mouse button comes up at [param u]: finishes rectangles, lines, boxes and doors.
func release(button: int, u: Vector2) -> void:
	if _dragging != button:
		return
	var erase: bool = button == MOUSE_BUTTON_RIGHT
	var t: Vector2i = tile_at(u)
	match tool:
		Tool.RECT:
			document.fill(
				Rect2i(_drag_from_tile, t - _drag_from_tile), TileGrid.EMPTY if erase else tile
			)
		Tool.LINE:
			document.line(_drag_from_tile, t, TileGrid.EMPTY if erase else tile)
		Tool.SOLID:
			if not erase:
				var a: Vector2i = _snap(_drag_from_u)
				var b: Vector2i = _snap(u)
				var r := Rect2i(a, b - a).abs()
				if r.size.x > 0 and r.size.y > 0:
					_select(document.objects().add_solid(r, solid_tag), -1, -1)
		Tool.DOOR:
			if not erase:
				_finish_door(u)
	document.history.end_stroke()
	_dragging = MOUSE_BUTTON_NONE
	_door_drag = DoorDrag.NONE
	queue_redraw()


## Adds the door dragged out from where the button went down to [param u], and carves its
## opening, as one step.
func _finish_door(u: Vector2) -> void:
	var side: int = side_at(_drag_from_u)
	var span: Vector2i = door_span(side, _along(side, _drag_from_u), _along(side, u))
	var index: int = document.doors().add(side, span.x, span.y)
	document.doors().carve(index)
	_select(-1, -1, index)


## The side of the room nearest to [param u] (units): left, right, top or bottom.
func side_at(u: Vector2) -> int:
	var room_u: Vector2 = _room_size_u()
	var nearest: int = RoomData.LEFT
	var best: float = u.x
	if room_u.x - u.x < best:
		nearest = RoomData.RIGHT
		best = room_u.x - u.x
	if u.y < best:
		nearest = RoomData.TOP
		best = u.y
	if room_u.y - u.y < best:
		nearest = RoomData.BOTTOM
	return nearest


## The opening, as units from..to on whole tiles, a drag from [param a_u] to [param b_u] along
## side [param side] covers: every tile the drag touches, at least the door's minimum length,
## kept inside the side.
func door_span(side: int, a_u: float, b_u: float) -> Vector2i:
	var edge: int = document.doors().edge_u(side)
	var min_span: int = RoomData.DOOR_DEPTH_TILES * TileGrid.TILE
	var t: int = TileGrid.TILE
	var from_u: int = int(floorf(minf(a_u, b_u) / t)) * t
	var to_u: int = int(ceilf(maxf(a_u, b_u) / t)) * t
	if to_u - from_u < min_span:
		to_u = from_u + min_span
	to_u = mini(to_u, edge)
	from_u = clampi(from_u, 0, maxi(to_u - min_span, 0))
	return Vector2i(from_u, to_u)


## The coordinate of [param u] along side [param side]: y for the left and right sides.
static func _along(side: int, u: Vector2) -> float:
	return u.y if side == RoomData.LEFT or side == RoomData.RIGHT else u.x


## [param value] rounded to a whole number of tiles, in units.
static func _tiles_u(value: float) -> int:
	return int(roundf(value / TileGrid.TILE)) * TileGrid.TILE


## Snaps a point to the half-tile grid (16 u), where solid boxes and entities are placed.
static func _snap(u: Vector2) -> Vector2i:
	var half: float = TileGrid.TILE * 0.5
	return Vector2i((u / half).round() * half)


func _select_at(u: Vector2) -> void:
	var e: int = _entity_at(u)
	if e >= 0:
		_select(-1, e, -1)
		return
	var d: int = _door_at(u)
	if d >= 0:
		_select(-1, -1, d)
		var door: RoomData.Door = document.room.doors[d]
		_door_origin = Vector2i(door.from_u, door.to_u)
		_door_drag = _door_grab(door, _along(door.side, u))
		return
	_select(_solid_at(u), -1, -1)


## Which part of [param door] the pointer, [param a_u] units along its side, takes: an end if
## it is within [constant HANDLE_PX] of one, else the whole door.
func _door_grab(door: RoomData.Door, a_u: float) -> int:
	var reach: float = minf(HANDLE_PX / zoom, float(door.span_u()) * 0.25)
	if absf(a_u - door.from_u) <= reach:
		return DoorDrag.FROM_END
	if absf(a_u - door.to_u) <= reach:
		return DoorDrag.TO_END
	return DoorDrag.SLIDE


func _erase_object_at(u: Vector2) -> void:
	var e: int = _entity_at(u)
	if e >= 0:
		document.objects().remove_entity(e)
		_select(-1, -1, -1)
		return
	var d: int = _door_at(u)
	if d >= 0:
		document.doors().remove(d)
		_select(-1, -1, -1)
		return
	var s: int = _solid_at(u)
	if s >= 0:
		document.objects().remove_solid(s)
		_select(-1, -1, -1)


## The topmost entity marker within 16 u of [param u], or -1.
func _entity_at(u: Vector2) -> int:
	for i: int in range(document.room.entities.size() - 1, -1, -1):
		var e: RoomData.RoomEntity = document.room.entities[i]
		if Vector2(e.x_u, e.y_u).distance_to(u) <= TileGrid.TILE * 0.5:
			return i
	return -1


## The topmost door whose strip, or the passage beyond it, is under [param u], or -1.
func _door_at(u: Vector2) -> int:
	for i: int in range(document.room.doors.size() - 1, -1, -1):
		if _door_rect(document.room.doors[i], true).has_point(u):
			return i
	return -1


## The topmost solid box under [param u], or -1.
func _solid_at(u: Vector2) -> int:
	for i: int in range(document.room.solids.size() - 1, -1, -1):
		if _solid_rect(document.room.solids[i]).has_point(u):
			return i
	return -1


static func _solid_rect(s: SolidBox) -> Rect2:
	return Rect2(
		float(s.left) / Fx.SUB,
		float(s.top) / Fx.SUB,
		float(s.right - s.left) / Fx.SUB,
		float(s.bottom - s.top) / Fx.SUB
	)


## A door's strip in units; with [param with_passage], the passage beyond the room's edge as
## well (the same depth outside).
func _door_rect(d: RoomData.Door, with_passage: bool = false) -> Rect2:
	var strip := Rect2(d.strip_u(document.width_u(), document.height_u()))
	if not with_passage:
		return strip
	var depth: float = float(RoomData.DOOR_DEPTH_TILES * TileGrid.TILE)
	match d.side:
		RoomData.LEFT:
			return strip.grow_individual(depth, 0.0, 0.0, 0.0)
		RoomData.RIGHT:
			return strip.grow_individual(0.0, 0.0, depth, 0.0)
		RoomData.TOP:
			return strip.grow_individual(0.0, depth, 0.0, 0.0)
	return strip.grow_individual(0.0, 0.0, 0.0, depth)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), RoomView.BEYOND)
	if document == null:
		return
	var grid: TileGrid = document.room.grid
	var t: float = float(TileGrid.TILE)
	draw_set_transform(origin, 0.0, Vector2(zoom, zoom))
	draw_rect(Rect2(Vector2.ZERO, _room_size_u()), RoomView.PASSAGE)
	for d: RoomData.Door in document.room.doors:
		var passage: Rect2 = _door_rect(d, true)
		draw_rect(passage, RoomView.PASSAGE)
	for j: int in range(grid.height):
		for i: int in range(grid.width):
			RoomView.draw_tile(self, grid.get_tile(i, j), Vector2(i, j) * t, t)
	_draw_grid(grid, t)
	for k: int in range(document.room.solids.size()):
		var r: Rect2 = _solid_rect(document.room.solids[k])
		draw_rect(r, RoomView.BOX)
		draw_rect(r, SELECTED if k == selected_solid else Color.WHITE, false, 2.0 / zoom)
		var tag: String = document.room.solids[k].tag
		if tag != "":
			_label(r.position + Vector2(4, 4), tag, Color.WHITE)
	for k: int in range(document.room.doors.size()):
		_draw_door(k)
	for k: int in range(document.room.entities.size()):
		var e: RoomData.RoomEntity = document.room.entities[k]
		var at := Vector2(e.x_u, e.y_u)
		draw_circle(at, 10.0, SELECTED if k == selected_entity else ENTITY)
		_label(at + Vector2(14, -4), e.kind, ENTITY)
	var spawn := Vector2(document.room.spawn_x_u, document.room.spawn_y_u)
	draw_rect(Rect2(spawn - Vector2(10, 44), Vector2(20, 44)), SPAWN, false, 2.0 / zoom)
	_label(spawn + Vector2(14, -44), "spawn", SPAWN)
	_draw_preview(t)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A door: its strip filled and outlined (red when the room's problems name it), the passage
## beyond the edge outlined, and its name and target written beside it.
func _draw_door(k: int) -> void:
	var d: RoomData.Door = document.room.doors[k]
	var strip: Rect2 = _door_rect(d)
	var bad: bool = flagged_doors.has(d.name)
	var color: Color = DOOR_BAD if bad else DOOR
	draw_rect(strip, Color(color, 0.22))
	draw_rect(strip, SELECTED if k == selected_door else color, false, 3.0 / zoom)
	draw_rect(_door_rect(d, true), Color(color, 0.7), false, 1.0 / zoom)
	if k == selected_door:
		_draw_handles(d, strip)
	var label: String = "%s -> %s : %s" % [d.name, d.target_room, d.target_door]
	var font_size: int = int(16.0 / zoom)
	var width: float = (
		ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	)
	var gap: float = 10.0 / zoom
	var at: Vector2 = strip.get_center() + Vector2(0.0, font_size * 0.35)
	match d.side:
		RoomData.LEFT:
			at.x = strip.end.x + gap
		RoomData.RIGHT:
			at.x = strip.position.x - gap - width
		RoomData.TOP:
			at = Vector2(strip.get_center().x - width * 0.5, strip.end.y + gap + font_size)
		RoomData.BOTTOM:
			at = Vector2(strip.get_center().x - width * 0.5, strip.position.y - gap)
	_label(at, label, color)


## The two ends of the selected door's opening, the squares a drag takes to resize it.
func _draw_handles(d: RoomData.Door, strip: Rect2) -> void:
	var half: float = 5.0 / zoom
	var horizontal: bool = d.side == RoomData.LEFT or d.side == RoomData.RIGHT
	var ends: Array[Vector2] = []
	if horizontal:
		ends = [
			Vector2(strip.get_center().x, strip.position.y),
			Vector2(strip.get_center().x, strip.end.y)
		]
	else:
		ends = [
			Vector2(strip.position.x, strip.get_center().y),
			Vector2(strip.end.x, strip.get_center().y)
		]
	for end: Vector2 in ends:
		draw_rect(Rect2(end - Vector2(half, half), Vector2(half, half) * 2.0), SELECTED)


func _label(at: Vector2, text: String, color: Color) -> void:
	draw_string(
		ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 / zoom), color
	)


func _draw_grid(grid: TileGrid, t: float) -> void:
	if zoom * t < 6.0:
		return
	var w: float = 1.0 / zoom
	for i: int in range(grid.width + 1):
		draw_line(
			Vector2(i * t, 0),
			Vector2(i * t, grid.height * t),
			GRID_MAJOR if i % 10 == 0 else GRID,
			w
		)
	for j: int in range(grid.height + 1):
		draw_line(
			Vector2(0, j * t),
			Vector2(grid.width * t, j * t),
			GRID_MAJOR if j % 10 == 0 else GRID,
			w
		)


## The tile under the cursor, and the rectangle, box or door being dragged out.
func _draw_preview(t: float) -> void:
	var hover: Vector2i = tile_at(_hover_u)
	draw_rect(Rect2(Vector2(hover) * t, Vector2(t, t)), PREVIEW, false, 2.0 / zoom)
	if _dragging == MOUSE_BUTTON_NONE:
		return
	if tool == Tool.RECT or tool == Tool.LINE:
		var a: Vector2 = Vector2(_drag_from_tile) * t
		var b: Vector2 = Vector2(hover) * t
		var r := Rect2(a, b - a).abs()
		r.size += Vector2(t, t)
		draw_rect(r, PREVIEW, false, 2.0 / zoom)
	elif tool == Tool.SOLID:
		var a2 := Vector2(_snap(_drag_from_u))
		var b2 := Vector2(_snap(_hover_u))
		draw_rect(Rect2(a2, b2 - a2).abs(), PREVIEW)
	elif tool == Tool.DOOR:
		var side: int = side_at(_drag_from_u)
		var span: Vector2i = door_span(side, _along(side, _drag_from_u), _along(side, _hover_u))
		var probe := RoomData.Door.new()
		probe.side = side
		probe.from_u = span.x
		probe.to_u = span.y
		draw_rect(_door_rect(probe), Color(DOOR, 0.4))
