class_name RoomObjectEdits
extends RefCounted
## The room editor's edits of a room's solid boxes and entity markers, each one undoable through
## the [RoomDocument] it belongs to (`document.objects()`).

var _doc: RoomDocument


func _init(doc: RoomDocument) -> void:
	_doc = doc


# --- solid boxes ----------------------------------------------------------------------------------


## Adds a solid box over [param rect_u] (units); returns its index, or -1 if [param tag] is not
## empty and not an option word (nothing changes).
func add_solid(rect_u: Rect2i, tag: String = "", clingable: bool = true) -> int:
	if tag != "" and not RoomDocument.is_option_word(tag):
		return -1
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
## Refused (false, nothing changes) if [param tag] is not empty and not an option word: the text
## is `tag=<word>`.
func set_solid_options(index: int, tag: String, clingable: bool) -> bool:
	if tag != "" and not RoomDocument.is_option_word(tag):
		return false
	var s: SolidBox = _doc.room.solids[index]
	if s.tag == tag and s.clingable == clingable:
		return true
	_doc.begin_edit()
	s.tag = tag
	s.clingable = clingable
	_doc.edited()
	return true


# --- entities -------------------------------------------------------------------------------------


## Adds an entity marker; returns its index, or -1 if [param kind] is not a word or a property is
## not `key=value` words (nothing changes).
func add_entity(kind: String, x_u: int, y_u: int, props: Dictionary[String, String] = {}) -> int:
	if not RoomDocument.is_word(kind) or not _props_fit(props):
		return -1
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
## Refused (false, nothing changes) unless [param key] and a non-empty [param value] are option
## words: the text is `key=value`.
func set_entity_prop(index: int, key: String, value: String) -> bool:
	if (
		not RoomDocument.is_option_word(key)
		or (value != "" and not RoomDocument.is_option_word(value))
	):
		return false
	var e: RoomData.RoomEntity = _doc.room.entities[index]
	if (value == "" and not e.props.has(key)) or (e.props.has(key) and e.props[key] == value):
		return true
	_doc.begin_edit()
	if value == "":
		e.props.erase(key)
	else:
		e.props[key] = value
	_doc.edited()
	return true


## Replaces all of entity [param index]'s properties at once (one undo step). Refused (false,
## nothing changes) unless every key and value is an option word.
func set_entity_props(index: int, props: Dictionary[String, String]) -> bool:
	if not _props_fit(props):
		return false
	if _doc.room.entities[index].props == props:
		return true
	_doc.begin_edit()
	_doc.room.entities[index].props = props.duplicate()
	_doc.edited()
	return true


## Whether every key and value of [param props] is an option word, so the properties parse back.
static func _props_fit(props: Dictionary[String, String]) -> bool:
	for k: String in props:
		if not RoomDocument.is_option_word(k) or not RoomDocument.is_option_word(props[k]):
			return false
	return true
