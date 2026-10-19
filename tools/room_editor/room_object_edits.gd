class_name RoomObjectEdits
extends RefCounted
## The room editor's edits of a room's solid boxes and entity markers, each one undoable through
## the [RoomDocument] it belongs to (`document.objects()`).

var _doc: RoomDocument


func _init(doc: RoomDocument) -> void:
	_doc = doc


# --- solid boxes ----------------------------------------------------------------------------------


## Adds a solid box over [param rect_u] (units); returns its index.
func add_solid(rect_u: Rect2i, tag: String = "", clingable: bool = true) -> int:
	_doc.begin_edit()
	var r: Rect2i = rect_u.abs()
	var s := SolidBox.make(
		Fx.units(r.position.x), Fx.units(r.position.y), Fx.units(r.end.x), Fx.units(r.end.y)
	)
	s.tag = tag
	s.clingable = clingable
	_doc.room.solids.append(s)
	_doc.room.solid_notes.append(PackedStringArray())
	_doc.edited()
	return _doc.room.solids.size() - 1


func remove_solid(index: int) -> void:
	_doc.begin_edit()
	_doc.room.solids.remove_at(index)
	if index < _doc.room.solid_notes.size():
		_doc.room.solid_notes.remove_at(index)
	_doc.edited()


## Moves solid [param index] by [param delta_u] units.
func move_solid(index: int, delta_u: Vector2i) -> void:
	_doc.begin_edit()
	var s: SolidBox = _doc.room.solids[index]
	s.left += Fx.units(delta_u.x)
	s.right += Fx.units(delta_u.x)
	s.top += Fx.units(delta_u.y)
	s.bottom += Fx.units(delta_u.y)
	_doc.edited()


## Sets solid [param index]'s tag (pogo, wax, or none) and whether the wall-cling holds on it.
func set_solid_options(index: int, tag: String, clingable: bool) -> void:
	var s: SolidBox = _doc.room.solids[index]
	if s.tag == tag and s.clingable == clingable:
		return
	_doc.begin_edit()
	s.tag = tag
	s.clingable = clingable
	_doc.edited()


# --- entities -------------------------------------------------------------------------------------


## Adds an entity marker; returns its index.
func add_entity(kind: String, x_u: int, y_u: int, props: Dictionary[String, String] = {}) -> int:
	_doc.begin_edit()
	var e := RoomData.RoomEntity.new()
	e.kind = kind
	e.x_u = x_u
	e.y_u = y_u
	e.props = props.duplicate()
	_doc.room.entities.append(e)
	_doc.room.entity_notes.append(PackedStringArray())
	_doc.edited()
	return _doc.room.entities.size() - 1


func remove_entity(index: int) -> void:
	_doc.begin_edit()
	_doc.room.entities.remove_at(index)
	if index < _doc.room.entity_notes.size():
		_doc.room.entity_notes.remove_at(index)
	_doc.edited()


func move_entity(index: int, x_u: int, y_u: int) -> void:
	_doc.begin_edit()
	_doc.room.entities[index].x_u = x_u
	_doc.room.entities[index].y_u = y_u
	_doc.edited()


## Sets (or with an empty [param value], removes) property [param key] of entity [param index].
func set_entity_prop(index: int, key: String, value: String) -> void:
	var e: RoomData.RoomEntity = _doc.room.entities[index]
	if (value == "" and not e.props.has(key)) or (e.props.has(key) and e.props[key] == value):
		return
	_doc.begin_edit()
	if value == "":
		e.props.erase(key)
	else:
		e.props[key] = value
	_doc.edited()


## Replaces all of entity [param index]'s properties at once (one undo step).
func set_entity_props(index: int, props: Dictionary[String, String]) -> void:
	if _doc.room.entities[index].props == props:
		return
	_doc.begin_edit()
	_doc.room.entities[index].props = props.duplicate()
	_doc.edited()
