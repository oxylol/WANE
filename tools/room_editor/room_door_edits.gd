class_name RoomDoorEdits
extends RefCounted
## The room editor's edits of a room's doors (docs/adr/0014), each one undoable through the
## [RoomDocument] it belongs to (`document.doors()`).

var _doc: RoomDocument


func _init(doc: RoomDocument) -> void:
	_doc = doc


## The length of side [param side] in units (the doors on it are measured along it).
func edge_u(side: int) -> int:
	return _doc.height_u() if side == RoomData.LEFT or side == RoomData.RIGHT else _doc.width_u()


## Adds a door on [param side] over [param from_u]..[param to_u] (whole tiles, at least two),
## named [param door_name] or the first free "<side>", "<side>2", ... It leads nowhere until its
## target is set. Returns its index.
func add(side: int, from_u: int, to_u: int, door_name: String = "") -> int:
	_doc.begin_edit()
	var d := RoomData.Door.new()
	d.name = door_name if door_name != "" else _free_name(side)
	d.side = side
	d.from_u = from_u
	d.to_u = to_u
	d.target_room = RoomDocument.UNSET
	d.target_door = RoomDocument.UNSET
	_doc.room.doors.append(d)
	_doc.room.door_notes.append(PackedStringArray())
	_doc.edited()
	return _doc.room.doors.size() - 1


func _free_name(side: int) -> String:
	var base: String = RoomData.SIDE_NAMES[side]
	var n: int = 1
	while _doc.room.door(base if n == 1 else "%s%d" % [base, n]) != null:
		n += 1
	return base if n == 1 else "%s%d" % [base, n]


func remove(index: int) -> void:
	_doc.begin_edit()
	_doc.room.doors.remove_at(index)
	if index < _doc.room.door_notes.size():
		_doc.room.door_notes.remove_at(index)
	_doc.edited()


## Sets door [param index]'s opening to [param from_u]..[param to_u] along its side, as given
## (a bad span is a problem, not refused).
func set_span(index: int, from_u: int, to_u: int) -> void:
	var d: RoomData.Door = _doc.room.doors[index]
	if d.from_u == from_u and d.to_u == to_u:
		return
	_doc.begin_edit()
	d.from_u = from_u
	d.to_u = to_u
	_doc.edited()


## Moves door [param index] along its side by [param delta_u], keeping its length and staying on
## the side.
func slide(index: int, delta_u: int) -> void:
	var d: RoomData.Door = _doc.room.doors[index]
	var from_u: int = clampi(d.from_u + delta_u, 0, maxi(edge_u(d.side) - d.span_u(), 0))
	set_span(index, from_u, from_u + d.span_u())


## Puts door [param index] on [param side]; its opening is kept if it fits, or pulled back
## inside the side.
func set_side(index: int, side: int) -> void:
	var d: RoomData.Door = _doc.room.doors[index]
	if d.side == side:
		return
	_doc.begin_edit()
	d.side = side
	d.to_u = mini(d.to_u, edge_u(side))
	d.from_u = clampi(d.from_u, 0, maxi(d.to_u - RoomData.DOOR_DEPTH_TILES * TileGrid.TILE, 0))
	_doc.edited()


func rename(index: int, door_name: String) -> void:
	if _doc.room.doors[index].name == door_name:
		return
	_doc.begin_edit()
	_doc.room.doors[index].name = door_name
	_doc.edited()


## Sets where door [param index] leads: door [param target_door] of room [param target_room].
func set_target(index: int, target_room: String, target_door: String) -> void:
	var d: RoomData.Door = _doc.room.doors[index]
	if d.target_room == target_room and d.target_door == target_door:
		return
	_doc.begin_edit()
	d.target_room = target_room
	d.target_door = target_door
	_doc.edited()


## Clears what door [param index] needs clear (its strip and the strip's depth again beyond it,
## ADR-0014) and lays floor under a side door's strip, so the door stands as the loader wants
## it. Solid boxes are left where they are.
func carve(index: int) -> void:
	var d: RoomData.Door = _doc.room.doors[index]
	var clear: Rect2i = d.clear_u(_doc.width_u(), _doc.height_u())
	var strip: Rect2i = d.strip_u(_doc.width_u(), _doc.height_u())
	_doc.begin_edit()
	var cells := Rect2i(clear.position / TileGrid.TILE, clear.size / TileGrid.TILE)
	for j: int in range(cells.position.y, cells.end.y):
		for i: int in range(cells.position.x, cells.end.x):
			_doc.room.grid.set_tile(i, j, TileGrid.EMPTY)
	if d.side == RoomData.LEFT or d.side == RoomData.RIGHT:
		var floor_row: int = (strip.position.y + strip.size.y) / TileGrid.TILE
		for i: int in range(cells.position.x, cells.end.x):
			if not TileGrid.is_wall(_doc.room.grid.get_tile(i, floor_row)):
				_doc.room.grid.set_tile(i, floor_row, TileGrid.SOLID)
	_doc.edited()
