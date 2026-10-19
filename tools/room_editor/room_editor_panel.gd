@tool
class_name RoomEditorPanel
extends VBoxContainer
## The room editor's main screen (Phase 1 task 7; CLAUDE.md: "Rooms are authored in the room
## editor plugin (`tools/room_editor/`) and stored as text"). A toolbar to open, create, save,
## undo, resize and play rooms; a palette of tools and tiles with an inspector for the selected
## door, box or entity; the [RoomCanvas]; and every problem the loader would find, live. Saving is
## refused while the room has problems. Rooms opened and edited stay open (with their undo
## history) when another room is picked, and the picker marks the ones with unsaved edits.
## Built in code so it reads the same in a diff as the rest of the project.

## Emitted to ask the editor to run the game in [param room_id] (the plugin does the running).
signal play_requested(room_id: String)

const TILE_NAMES: Dictionary[int, String] = {
	TileGrid.EMPTY: "Empty",
	TileGrid.SOLID: "Wall",
	TileGrid.SMOOTH: "Smooth wall (no cling)",
	TileGrid.ONE_WAY: "One-way platform",
	TileGrid.SLOPE_R: "Slope up-right 45",
	TileGrid.SLOPE_L: "Slope up-left 45",
	TileGrid.SLOPE_R_LO: "Slope up-right 1:2, low",
	TileGrid.SLOPE_R_HI: "Slope up-right 1:2, high",
	TileGrid.SLOPE_L_HI: "Slope up-left 1:2, high",
	TileGrid.SLOPE_L_LO: "Slope up-left 1:2, low",
	TileGrid.SPIKES: "Spikes",
	TileGrid.PIT: "Pit (hazard, nothing to pogo)",
}
const TOOL_NAMES: Dictionary[int, String] = {
	RoomCanvas.Tool.PAINT: "Paint tiles",
	RoomCanvas.Tool.RECT: "Fill rectangle",
	RoomCanvas.Tool.LINE: "Line of tiles",
	RoomCanvas.Tool.SOLID: "Solid box",
	RoomCanvas.Tool.ENTITY: "Entity",
	RoomCanvas.Tool.DOOR: "Door (drag along an edge)",
	RoomCanvas.Tool.SPAWN: "Spawn point",
	RoomCanvas.Tool.MOVE: "Select and move",
}
## The ids a room may have: lower-case words joined by slashes (a path under content/rooms/,
## or test/<name> for tests/replay/rooms/).
const ID_PATTERN: String = "^[a-z0-9_]+(/[a-z0-9_]+)*$"
const ANCHOR_NAMES: Array[String] = ["Resize right and down", "Resize left and up", "Resize both"]
const ANCHORS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, 1), Vector2i(0, 0)]
const FACING_NAMES: Array[String] = ["Default", "Left", "Right"]
const FACING_VALUES: Array[String] = ["", "-1", "1"]

var document: RoomDocument
var canvas: RoomCanvas
var room_picker: OptionButton
var problems_list: ItemList
var status: Label
var save_button: Button
var tile_list: ItemList
var tool_list: ItemList
var kind_edit: LineEdit
var tag_edit: LineEdit
var new_id_edit: LineEdit
var width_box: SpinBox
var height_box: SpinBox
var anchor_picker: OptionButton
## The inspector: one section for each kind of selection.
var door_section: VBoxContainer
var door_name_edit: LineEdit
var door_side_picker: OptionButton
var door_from_box: SpinBox
var door_to_box: SpinBox
var door_room_edit: LineEdit
var door_target_edit: LineEdit
var door_hint: Label
var solid_section: VBoxContainer
var solid_tag_edit: LineEdit
var solid_cling_box: CheckBox
var entity_section: VBoxContainer
var entity_title: Label
var entity_form: VBoxContainer
var entity_props_edit: LineEdit
## The controls of the selected entity's properties, by key (see [EntityKinds]).
var entity_controls: Dictionary[String, Control] = {}

var _paths: PackedStringArray = []
var _docs: Dictionary[String, RoomDocument] = {}
var _hover_text: String = ""
var _message: String = ""
var _syncing: bool = false
var _refresh_queued: bool = false
var _form_for: String = ""


func _ready() -> void:
	if canvas == null:
		build()


## Builds the controls, once (separate from _ready so the plugin can build it off-tree).
func build() -> void:
	if canvas != null:
		return
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_toolbar())
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_palette())
	canvas = RoomCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.clip_contents = true
	canvas.custom_minimum_size = Vector2(400, 300)
	canvas.hovered.connect(_on_hovered)
	canvas.selection_changed.connect(_sync_inspector)
	body.add_child(canvas)
	add_child(body)
	status = Label.new()
	add_child(status)
	problems_list = ItemList.new()
	problems_list.custom_minimum_size = Vector2(0, 110)
	add_child(problems_list)
	refresh_rooms()


## Lists every room file in the repository in the picker, and any room open but not yet saved.
func refresh_rooms() -> void:
	_paths.clear()
	for root: String in [RoomData.CONTENT_ROOT, RoomData.TEST_ROOT]:
		for p: String in FileWalk.find(root, [".room"]):
			_paths.append(p)
	for p: String in _docs:
		if not _paths.has(p):
			_paths.append(p)
	room_picker.clear()
	for p: String in _paths:
		room_picker.add_item(_picker_text(p))
	if document != null:
		var i: int = _paths.find(document.path)
		if i >= 0:
			room_picker.select(i)


func _picker_text(p: String) -> String:
	var dirty: bool = _docs.has(p) and _docs[p].dirty
	return "%s%s" % [p.trim_prefix("res://"), "  *" if dirty else ""]


## Opens the room file at [param path] (the open copy, with its unsaved edits, if there is one).
func open(path: String) -> void:
	if not _docs.has(path):
		if not FileAccess.file_exists(path):
			_say("No room file at %s." % path)
			return
		_docs[path] = RoomDocument.open(path)
	_attach(_docs[path])


## Starts a new room [param id] of [param w] x [param h] tiles (not saved until Save).
func create(id: String, w: int, h: int) -> void:
	var doc: RoomDocument = RoomDocument.create(id, w, h)
	_docs[doc.path] = doc
	_attach(doc)


## Saves; returns the result (refused with ERR_INVALID_DATA while there are problems).
func save() -> Error:
	if document == null:
		return ERR_UNCONFIGURED
	var err: Error = document.save()
	if err == OK and not _paths.has(document.path):
		refresh_rooms()
	refresh()
	return err


func _attach(doc: RoomDocument) -> void:
	if document != null and document.changed.is_connected(_queue_refresh):
		document.changed.disconnect(_queue_refresh)
	document = doc
	document.changed.connect(_queue_refresh)
	canvas.set_document(document)
	width_box.set_value_no_signal(document.room.grid.width)
	height_box.set_value_no_signal(document.room.grid.height)
	refresh_rooms()
	refresh()


func _toolbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	room_picker = OptionButton.new()
	room_picker.custom_minimum_size = Vector2(320, 0)
	room_picker.item_selected.connect(func(i: int) -> void: open(_paths[i]))
	bar.add_child(room_picker)
	new_id_edit = LineEdit.new()
	new_id_edit.placeholder_text = "new room id (zone1/r01)"
	new_id_edit.custom_minimum_size = Vector2(190, 0)
	bar.add_child(new_id_edit)
	bar.add_child(_button("New", func() -> void: _on_new()))
	save_button = _button("Save", func() -> void: save())
	bar.add_child(save_button)
	bar.add_child(_button("Undo", func() -> void: _with_doc(func() -> void: document.undo())))
	bar.add_child(_button("Redo", func() -> void: _with_doc(func() -> void: document.redo())))
	bar.add_child(_button("Fit", func() -> void: canvas.fit()))
	width_box = _spin(8, 400)
	height_box = _spin(8, 400)
	bar.add_child(_label("Size (tiles)"))
	bar.add_child(width_box)
	bar.add_child(height_box)
	anchor_picker = OptionButton.new()
	for n: String in ANCHOR_NAMES:
		anchor_picker.add_item(n)
	bar.add_child(anchor_picker)
	bar.add_child(_button("Resize", func() -> void: _on_resize()))
	bar.add_child(_button("Play", func() -> void: _on_play()))
	return bar


func _palette() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	tool_list = ItemList.new()
	tool_list.auto_height = true
	for t: int in TOOL_NAMES:
		tool_list.add_item(TOOL_NAMES[t])
	tool_list.select(0)
	tool_list.item_selected.connect(func(i: int) -> void: canvas.tool = TOOL_NAMES.keys()[i])
	box.add_child(tool_list)
	tile_list = ItemList.new()
	tile_list.auto_height = true
	for t: int in TILE_NAMES:
		tile_list.add_item(TILE_NAMES[t], _tile_icon(t))
	tile_list.select(TileGrid.SOLID)
	tile_list.item_selected.connect(func(i: int) -> void: canvas.tile = TILE_NAMES.keys()[i])
	box.add_child(tile_list)
	tag_edit = _field(box, "New solid box tag (pogo, wax)")
	tag_edit.text_changed.connect(func(t: String) -> void: canvas.solid_tag = t.strip_edges())
	kind_edit = _field(box, "New entity kind")
	kind_edit.text = EntityKinds.DUMMY
	kind_edit.text_changed.connect(func(t: String) -> void: canvas.entity_kind = t.strip_edges())
	box.add_child(HSeparator.new())
	box.add_child(_door_inspector())
	box.add_child(_solid_inspector())
	box.add_child(_entity_inspector())
	return scroll


func _door_inspector() -> VBoxContainer:
	door_section = VBoxContainer.new()
	door_section.visible = false
	door_section.add_child(_label("Door"))
	door_name_edit = _field(door_section, "name")
	_on_commit(door_name_edit, _on_door_name)
	door_side_picker = OptionButton.new()
	for n: String in RoomData.SIDE_NAMES:
		door_side_picker.add_item(n)
	door_side_picker.item_selected.connect(func(i: int) -> void: _on_door_side(i))
	door_section.add_child(door_side_picker)
	var span := HBoxContainer.new()
	span.add_child(_label("Tiles"))
	door_from_box = _spin(0, 400)
	door_to_box = _spin(0, 400)
	door_from_box.value_changed.connect(func(_v: float) -> void: _on_door_span())
	door_to_box.value_changed.connect(func(_v: float) -> void: _on_door_span())
	span.add_child(door_from_box)
	span.add_child(_label("to"))
	span.add_child(door_to_box)
	door_section.add_child(span)
	door_room_edit = _field(door_section, "leads to room (zone1/r02)")
	door_target_edit = _field(door_section, "leads to door")
	_on_commit(door_room_edit, _on_door_target)
	_on_commit(door_target_edit, _on_door_target)
	door_hint = _label("")
	door_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	door_section.add_child(door_hint)
	door_section.add_child(_button("Carve opening", func() -> void: _on_carve_door()))
	door_section.add_child(_button("Delete door", func() -> void: canvas.delete_selected()))
	return door_section


func _solid_inspector() -> VBoxContainer:
	solid_section = VBoxContainer.new()
	solid_section.visible = false
	solid_section.add_child(_label("Solid box"))
	solid_tag_edit = _field(solid_section, "tag (pogo, wax)")
	_on_commit(solid_tag_edit, _on_solid_options)
	solid_cling_box = CheckBox.new()
	solid_cling_box.text = "Wall-cling holds (off is cling=0)"
	solid_cling_box.toggled.connect(func(_on: bool) -> void: _on_solid_options(""))
	solid_section.add_child(solid_cling_box)
	solid_section.add_child(_button("Delete box", func() -> void: canvas.delete_selected()))
	return solid_section


func _entity_inspector() -> VBoxContainer:
	entity_section = VBoxContainer.new()
	entity_section.visible = false
	entity_title = _label("Entity")
	entity_section.add_child(entity_title)
	entity_form = VBoxContainer.new()
	entity_section.add_child(entity_form)
	entity_props_edit = _field(entity_section, "all properties: key=value ...")
	_on_commit(entity_props_edit, _on_entity_text)
	entity_section.add_child(_button("Delete entity", func() -> void: canvas.delete_selected()))
	return entity_section


## A swatch for tile [param t], drawn the way [RoomView] draws it.
static func _tile_icon(t: int) -> ImageTexture:
	var n: int = 24
	var img: Image = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.07, 0.07, 0.08))
	var fill: Color = RoomView.SOLID
	if t == TileGrid.SMOOTH:
		fill = RoomView.SMOOTH
	if t == TileGrid.SOLID or t == TileGrid.SMOOTH:
		img.fill(fill)
	elif t == TileGrid.ONE_WAY:
		img.fill_rect(Rect2i(0, 0, n, 3), RoomView.ONE_WAY)
	elif t == TileGrid.SPIKES:
		for x: int in range(n):
			var tooth: int = n / 3 - absi((x % 8) - 4) * 2 + 2
			img.fill_rect(Rect2i(x, n - 1 - tooth, 1, tooth + 1), RoomView.SPIKES)
	elif t == TileGrid.PIT:
		img.fill(RoomView.PIT)
		img.fill_rect(Rect2i(0, 0, n, 2), RoomView.PIT_LIP)
	elif TileGrid.is_slope(t):
		var edges: Vector2i = TileGrid.slope_edge_heights(t)
		for x: int in range(n):
			var h: float = lerpf(float(edges.x), float(edges.y), (x + 0.5) / n) / TileGrid.TILE_SP
			var rows: int = int(roundf(h * n))
			img.fill_rect(Rect2i(x, n - rows, 1, rows), RoomView.SOLID)
	return ImageTexture.create_from_image(img)


func _field(box: VBoxContainer, hint: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	box.add_child(e)
	return e


## Calls [param handler] with the text when Enter is pressed or the field loses focus.
static func _on_commit(edit: LineEdit, handler: Callable) -> void:
	edit.text_submitted.connect(func(t: String) -> void: handler.call(t))
	edit.focus_exited.connect(func() -> void: handler.call(edit.text))


static func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


static func _button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(pressed)
	return b


static func _spin(lo: int, hi: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.rounded = true
	return s


func _with_doc(action: Callable) -> void:
	if document != null:
		action.call()


func _on_new() -> void:
	var id: String = new_id_edit.text.strip_edges()
	var path: String = RoomData.path_for(id)
	if id == "" or not RegEx.create_from_string(ID_PATTERN).search(id):
		_say(
			"A room id is lower-case words joined by slashes (zone1/r01, or test/name for a test)."
		)
	elif FileAccess.file_exists(path) or _docs.has(path):
		_say("There is a room %s already: pick it in the list to edit it." % id)
	else:
		create(id, int(width_box.value), int(height_box.value))


func _on_resize() -> void:
	if document != null:
		document.resize(
			int(width_box.value), int(height_box.value), ANCHORS[anchor_picker.selected]
		)
		canvas.fit()


func _on_play() -> void:
	if document == null:
		return
	if save() != OK:
		_say("Fix the problems below before playing: the game loads the saved room.")
		return
	play_requested.emit(document.room.id)


# --- the inspector --------------------------------------------------------------------------------


func _on_door_name(text: String) -> void:
	if not _syncing and canvas.selected_door >= 0:
		document.doors().rename(canvas.selected_door, text.strip_edges())


func _on_door_side(side: int) -> void:
	if not _syncing and canvas.selected_door >= 0:
		document.doors().set_side(canvas.selected_door, side)


func _on_door_span() -> void:
	if not _syncing and canvas.selected_door >= 0:
		document.doors().set_span(
			canvas.selected_door,
			int(door_from_box.value) * TileGrid.TILE,
			int(door_to_box.value) * TileGrid.TILE
		)


func _on_door_target(_text: String = "") -> void:
	if not _syncing and canvas.selected_door >= 0:
		var room_id: String = door_room_edit.text.strip_edges()
		var door_id: String = door_target_edit.text.strip_edges()
		document.doors().set_target(
			canvas.selected_door,
			room_id if room_id != "" else RoomDocument.UNSET,
			door_id if door_id != "" else RoomDocument.UNSET
		)


func _on_carve_door() -> void:
	if canvas.selected_door >= 0:
		document.doors().carve(canvas.selected_door)


func _on_solid_options(_text: String = "") -> void:
	if not _syncing and canvas.selected_solid >= 0:
		document.objects().set_solid_options(
			canvas.selected_solid, solid_tag_edit.text.strip_edges(), solid_cling_box.button_pressed
		)


## Sets the selected entity's properties from "key=value key=value" text.
func _on_entity_text(text: String) -> void:
	if _syncing or canvas.selected_entity < 0:
		return
	var props: Dictionary[String, String] = {}
	for pair: String in text.split(" ", false):
		var kv: PackedStringArray = pair.split("=")
		if kv.size() == 2:
			props[kv[0]] = kv[1]
	document.objects().set_entity_props(canvas.selected_entity, props)


## Sets the selected entity's properties from the form (the controls of its kind's properties;
## properties the form does not know are kept).
func _on_entity_form() -> void:
	if _syncing or canvas.selected_entity < 0:
		return
	var e: RoomData.RoomEntity = document.room.entities[canvas.selected_entity]
	var props: Dictionary[String, String] = e.props.duplicate()
	for spec: EntityKinds.PropSpec in EntityKinds.props_of(e.kind):
		var value: String = _form_value(spec, entity_controls[spec.key])
		if value == "":
			props.erase(spec.key)
		else:
			props[spec.key] = value
	document.objects().set_entity_props(canvas.selected_entity, props)


## The text a property control stands for: "" for off, default or unset.
static func _form_value(spec: EntityKinds.PropSpec, control: Control) -> String:
	if spec.type == EntityKinds.Type.FLAG:
		return "1" if (control as CheckBox).button_pressed else ""
	if spec.type == EntityKinds.Type.COUNT:
		var n: int = int((control as SpinBox).value)
		return str(n) if n > 0 else ""
	return FACING_VALUES[(control as OptionButton).selected]


## Shows the inspector section for the selection, with its values.
func _sync_inspector() -> void:
	_syncing = true
	door_section.visible = canvas.selected_door >= 0
	solid_section.visible = canvas.selected_solid >= 0
	entity_section.visible = canvas.selected_entity >= 0
	if door_section.visible and canvas.selected_door < document.room.doors.size():
		_sync_door(document.room.doors[canvas.selected_door])
	if solid_section.visible and canvas.selected_solid < document.room.solids.size():
		var s: SolidBox = document.room.solids[canvas.selected_solid]
		solid_tag_edit.text = s.tag
		solid_cling_box.button_pressed = s.clingable
	if entity_section.visible and canvas.selected_entity < document.room.entities.size():
		_sync_entity(document.room.entities[canvas.selected_entity])
	_syncing = false


func _sync_door(d: RoomData.Door) -> void:
	door_name_edit.text = d.name
	door_side_picker.select(d.side)
	door_from_box.value = d.from_u / TileGrid.TILE
	door_to_box.value = d.to_u / TileGrid.TILE
	var unset: bool = d.target_room == RoomDocument.UNSET
	door_room_edit.text = "" if unset else d.target_room
	door_target_edit.text = "" if d.target_door == RoomDocument.UNSET else d.target_door
	door_hint.text = _door_hint(d)


## Which doors the room a door leads to has, so its target can be typed without opening it.
static func _door_hint(d: RoomData.Door) -> String:
	if d.target_room == RoomDocument.UNSET:
		return "Type the room this door leads to; its doors are listed here."
	if not FileAccess.file_exists(RoomData.path_for(d.target_room)):
		return (
			"No room %s yet: create it, with a door on the %s."
			% [d.target_room, RoomData.SIDE_NAMES[d.facing_side()]]
		)
	var beyond: RoomData = RoomData.load_id(d.target_room)
	var names: PackedStringArray = []
	for other: RoomData.Door in beyond.doors:
		names.append(
			(
				"%s (%s, %d tiles)"
				% [other.name, RoomData.SIDE_NAMES[other.side], other.span_u() / TileGrid.TILE]
			)
		)
	return "%s has: %s" % [d.target_room, ", ".join(names) if not names.is_empty() else "no doors"]


func _sync_entity(e: RoomData.RoomEntity) -> void:
	entity_title.text = "Entity: %s at %d, %d" % [e.kind, e.x_u, e.y_u]
	var pairs: PackedStringArray = []
	var keys: Array[String] = []
	for k: String in e.props:
		keys.append(k)
	keys.sort()
	for k: String in keys:
		pairs.append("%s=%s" % [k, e.props[k]])
	entity_props_edit.text = " ".join(pairs)
	if (
		_form_for != e.kind
		or entity_controls.is_empty() and not EntityKinds.props_of(e.kind).is_empty()
	):
		_build_entity_form(e.kind)
	for spec: EntityKinds.PropSpec in EntityKinds.props_of(e.kind):
		var value: String = e.props.get(spec.key, "")
		var control: Control = entity_controls[spec.key]
		if spec.type == EntityKinds.Type.FLAG:
			(control as CheckBox).button_pressed = value.is_valid_int() and value.to_int() != 0
		elif spec.type == EntityKinds.Type.COUNT:
			(control as SpinBox).value = value.to_int() if value.is_valid_int() else 0
		else:
			(control as OptionButton).select(maxi(FACING_VALUES.find(value), 0))


func _build_entity_form(kind: String) -> void:
	for child: Node in entity_form.get_children():
		entity_form.remove_child(child)
		child.queue_free()
	entity_controls.clear()
	_form_for = kind
	for spec: EntityKinds.PropSpec in EntityKinds.props_of(kind):
		var row := HBoxContainer.new()
		var control: Control
		if spec.type == EntityKinds.Type.FLAG:
			var check := CheckBox.new()
			check.text = spec.label
			check.toggled.connect(func(_on: bool) -> void: _on_entity_form())
			control = check
		elif spec.type == EntityKinds.Type.COUNT:
			var box: SpinBox = _spin(0, spec.max_value)
			box.value_changed.connect(func(_v: float) -> void: _on_entity_form())
			row.add_child(_label("%s (0 = default)" % spec.label))
			control = box
		else:
			var pick := OptionButton.new()
			for n: String in FACING_NAMES:
				pick.add_item(n)
			pick.item_selected.connect(func(_i: int) -> void: _on_entity_form())
			row.add_child(_label(spec.label))
			control = pick
		row.add_child(control)
		entity_form.add_child(row)
		entity_controls[spec.key] = control


# --- status and problems --------------------------------------------------------------------------


func _on_hovered(tile: Vector2i, units: Vector2i) -> void:
	if document == null:
		return
	var t: String = "-"
	if document.room.grid.in_bounds(tile.x, tile.y):
		t = TILE_NAMES[document.room.grid.get_tile(tile.x, tile.y)]
	_hover_text = "tile %d, %d (%s)   %d, %d u" % [tile.x, tile.y, t, units.x, units.y]
	_update_status()


## Updates the problems and the inspector once, after the edits of this frame (a drag makes
## many).
func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()


## Recomputes the room's problems, the status line and the inspector.
func refresh() -> void:
	_refresh_queued = false
	_message = ""
	if document == null:
		return
	problems_list.clear()
	var problems: PackedStringArray = document.problems()
	for p: String in problems:
		problems_list.add_item(p)
	if problems.is_empty():
		problems_list.add_item("No problems: the room can be saved.")
	for note: String in document.warnings():
		problems_list.add_item("Note: %s" % note)
	save_button.disabled = not problems.is_empty()
	canvas.flagged_doors = _flagged_doors(problems)
	canvas.queue_redraw()
	_update_status()
	_sync_inspector()
	var i: int = _paths.find(document.path)
	if i >= 0:
		room_picker.set_item_text(i, _picker_text(document.path))
		room_picker.select(i)


## The names of the doors problems are about ("door 'name' ..." or "door 'name'" in the text).
func _flagged_doors(problems: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for d: RoomData.Door in document.room.doors:
		for p: String in problems:
			if p.contains("door '%s'" % d.name):
				out.append(d.name)
				break
	return out


## Shows [param text] beside the room's name until the next edit.
func _say(text: String) -> void:
	_message = text
	_update_status()


func _update_status() -> void:
	if document == null:
		status.text = _message
		return
	status.text = (
		(
			"%s%s   %s   %s"
			% [document.room.id, " (unsaved)" if document.dirty else "", _hover_text, _message]
		)
		. strip_edges()
	)
