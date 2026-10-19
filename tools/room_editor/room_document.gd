class_name RoomDocument
extends RefCounted
## A room open in the room editor (CLAUDE.md: "Rooms are authored in the room editor plugin
## (`tools/room_editor/`) and stored as text"; docs/adr/0009, 0014, 0015). Every edit goes through
## this class: tiles, solid boxes, entities, doors, the spawn point and the size, each undoable
## through [member history] (a drag is one step between [method RoomHistory.begin_stroke] and
## [method RoomHistory.end_stroke]). [method save] writes exactly what [method RoomData.to_text]
## writes, comments included, and refuses a room with any problem the game's loader would find.

signal changed

## The target a new door has until the author sets one: a valid word in the text, a problem in
## [method problems].
const UNSET: String = "?"

var room: RoomData
## The file this room is saved to (res:// path).
var path: String = ""
var dirty: bool = false
var history: RoomHistory = RoomHistory.new()


func _init(p_room: RoomData, p_path: String = "") -> void:
	room = p_room
	path = p_path


## Opens [param p_path]; the document holds whatever the file says, problems included, so a
## broken room can still be opened and fixed.
static func open(p_path: String) -> RoomDocument:
	var contents: String = FileAccess.get_file_as_string(p_path)
	return RoomDocument.new(RoomData.parse(contents), p_path)


## A new room [param id] of [param w] x [param h] tiles: empty inside a solid border, the spawn
## on the floor near the left wall.
static func create(id: String, w: int, h: int) -> RoomDocument:
	var rows: PackedStringArray = []
	for j: int in range(h):
		var row: String = ""
		for i: int in range(w):
			var edge: bool = i == 0 or j == 0 or i == w - 1 or j >= h - 2
			row += "#" if edge else "."
		rows.append(row)
	var fresh := RoomData.new()
	fresh.id = id
	fresh.grid = TileGrid.from_rows(rows)
	fresh.spawn_x_u = TileGrid.TILE * 3
	fresh.spawn_y_u = (h - 2) * TileGrid.TILE
	var doc := RoomDocument.new(fresh, RoomData.path_for(id))
	doc.dirty = true  # it is in no file yet
	return doc


## Whether [param s] is one word of the room text: not empty, with no whitespace and no '#' (which
## starts a comment), so a line that holds it parses back to it. Names of doors, door targets and
## entity kinds are words.
static func is_word(s: String) -> bool:
	if s == "" or s.contains("#"):
		return false
	for k: int in range(s.length()):
		var c: int = s.unicode_at(k)
		if c <= 32 or c == 127 or c == 0xA0:
			return false
	return true


## Whether [param s] is a word that can stand either side of the '=' of a `key=value` option
## (solid tags, entity properties).
static func is_option_word(s: String) -> bool:
	return is_word(s) and not s.contains("=")


## The edits of this room's doors, and of its solid boxes and entities (two classes of their
## own, to keep each small); made on demand, since they point back at the document.
func doors() -> RoomDoorEdits:
	return RoomDoorEdits.new(self)


func objects() -> RoomObjectEdits:
	return RoomObjectEdits.new(self)


func text() -> String:
	return room.to_text()


func width_u() -> int:
	return room.grid.width * TileGrid.TILE


func height_u() -> int:
	return room.grid.height * TileGrid.TILE


## Everything wrong with the room as it would be saved, in the order a run meets it: the loader's
## own errors for the text (format, geometry, doors), the joins of boxes and tiles (ADR-0008),
## the doors' targets and pairs against the rooms they lead to when those exist (ADR-0014), and
## what only the editor can see: a spawn point outside the room or inside a wall, an entity outside
## the room or with a property its kind does not read, a path that is not the room's id.
func problems() -> PackedStringArray:
	var check: RoomData = RoomData.parse(text())
	var out: PackedStringArray = check.errors.duplicate()
	out.append_array(_join_problems(check))
	out.append_array(_door_problems(check))
	out.append_array(_spawn_problems())
	for i: int in range(room.entities.size()):
		var e: RoomData.RoomEntity = room.entities[i]
		if e.x_u < 0 or e.x_u > width_u() or e.y_u < 0 or e.y_u > height_u():
			out.append(
				"entity %d (%s) at %d, %d is outside the room" % [i + 1, e.kind, e.x_u, e.y_u]
			)
		out.append_array(EntityKinds.problems(e, i))
	if path != "" and room.id != "" and RoomData.path_for(room.id) != path:
		out.append(
			"room id '%s' belongs at %s, not %s" % [room.id, RoomData.path_for(room.id), path]
		)
	return out


func _join_problems(check: RoomData) -> PackedStringArray:
	var tuning: WorldTuning = ResourceLoader.load(WorldTuning.PATH) as WorldTuning
	if tuning == null:
		return PackedStringArray(["missing world tuning at %s" % WorldTuning.PATH])
	return RoomJoins.errors(check, Fx.units(tuning.join_band_u), Fx.units(tuning.join_reach_u))


func _door_problems(check: RoomData) -> PackedStringArray:
	var out: PackedStringArray = []
	for d: RoomData.Door in check.doors:
		if d.target_room == UNSET or d.target_door == UNSET:
			out.append("door '%s' has no target yet: set its room and door" % d.name)
	out.append_array(RoomSet.check_doors(check))
	return out


## What is worth knowing but does not stop a save: a door to a room that has no file yet (rooms
## that lead to each other are written one after the other, so the first has to be saved while
## the second does not exist; the pair is checked once both do).
func warnings() -> PackedStringArray:
	var out: PackedStringArray = []
	for d: RoomData.Door in room.doors:
		var known: bool = d.target_room != UNSET and d.target_room != room.id
		if known and not FileAccess.file_exists(RoomData.path_for(d.target_room)):
			out.append(
				(
					"door '%s' leads to room '%s', which has no file yet: its door must lead back"
					% [d.name, d.target_room]
				)
			)
	return out


func _spawn_problems() -> PackedStringArray:
	var out: PackedStringArray = []
	var label: String = "the spawn point (%d, %d)" % [room.spawn_x_u, room.spawn_y_u]
	if (
		room.spawn_x_u < 0
		or room.spawn_x_u >= width_u()
		or room.spawn_y_u <= 0
		or room.spawn_y_u > height_u()
	):
		out.append("%s is outside the room" % label)
	else:
		var i: int = Fx.div_floor(room.spawn_x_u, TileGrid.TILE)
		var j: int = Fx.div_floor(room.spawn_y_u - 1, TileGrid.TILE)
		if TileGrid.is_wall(room.grid.get_tile(i, j)):
			out.append("%s is inside a wall" % label)
	return out


## Writes the room; refuses (ERR_INVALID_DATA) while it has problems.
func save() -> Error:
	if not problems().is_empty():
		return ERR_INVALID_DATA
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text())
	f.close()
	dirty = false
	changed.emit()
	return OK


# --- tiles, spawn, id -----------------------------------------------------------------------------


func set_tile(i: int, j: int, tile: int) -> void:
	if not room.grid.in_bounds(i, j) or room.grid.get_tile(i, j) == tile:
		return
	begin_edit()
	room.grid.set_tile(i, j, tile)
	edited()


## Fills the tiles of [param area] (in tiles, inclusive of both corners' cells).
func fill(area: Rect2i, tile: int) -> void:
	var r: Rect2i = area.abs()
	var cells: Array[Vector2i] = []
	for j: int in range(r.position.y, r.end.y + 1):
		for i: int in range(r.position.x, r.end.x + 1):
			cells.append(Vector2i(i, j))
	_paint(cells, tile)


## Paints a straight line of tiles from [param a] to [param b] (a mouse drag between two
## events, so a fast stroke leaves no gaps).
func line(a: Vector2i, b: Vector2i, tile: int) -> void:
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	var cells: Array[Vector2i] = []
	for k: int in range(steps + 1):
		var t: float = 0.0 if steps == 0 else float(k) / float(steps)
		cells.append(Vector2i(Vector2(a).lerp(Vector2(b), t).round()))
	_paint(cells, tile)


## Sets [param cells] to [param tile] as one edit, if any of them (inside the room) differs.
func _paint(cells: Array[Vector2i], tile: int) -> void:
	var differs: bool = false
	for p: Vector2i in cells:
		differs = (
			differs or (room.grid.in_bounds(p.x, p.y) and room.grid.get_tile(p.x, p.y) != tile)
		)
	if not differs:
		return
	begin_edit()
	for p: Vector2i in cells:
		room.grid.set_tile(p.x, p.y, tile)
	edited()


func set_spawn(x_u: int, y_u: int) -> void:
	if room.spawn_x_u == x_u and room.spawn_y_u == y_u:
		return
	begin_edit()
	room.spawn_x_u = x_u
	room.spawn_y_u = y_u
	edited()


## Renames the room; the file it saves to follows the id. Refused (false) unless [param id] is a
## word.
func set_id(id: String) -> bool:
	if not is_word(id):
		return false
	if id == room.id:
		return true
	begin_edit()
	room.id = id
	path = RoomData.path_for(id)
	edited()
	return true


# --- size -----------------------------------------------------------------------------------------


## Resizes to [param w] x [param h] tiles. [param anchor] picks which side keeps its place:
## (-1, -1) keeps the top-left and grows or shrinks the bottom-right, (1, 1) the reverse, 0
## splits it. Growing copies the edge row or column (so walls, floors and door openings carry
## on); shrinking takes rows and columns just inside the edge (so the edge stays). Solids,
## entities, doors on the other sides and the spawn move with the content; a shrink across a door's
## side puts back that door's passage (strip, the same depth again, floor), which lies in the cells
## it takes.
func resize(w: int, h: int, anchor: Vector2i = Vector2i(-1, -1)) -> void:
	begin_edit()
	var old: TileGrid = room.grid
	var front := Vector2i(_front(old.width, w, anchor.x), _front(old.height, h, anchor.y))
	var rows: PackedStringArray = []
	for j: int in range(h):
		var row: String = ""
		var oj: int = _source(j, old.height, h, front.y)
		for i: int in range(w):
			row += TileGrid.CHARS[old.get_tile(_source(i, old.width, w, front.x), oj)]
		rows.append(row)
	room.grid = TileGrid.from_rows(rows)
	var du: Vector2i = front * TileGrid.TILE
	for s: SolidBox in room.solids:
		s.left += Fx.units(du.x)
		s.right += Fx.units(du.x)
		s.top += Fx.units(du.y)
		s.bottom += Fx.units(du.y)
	for e: RoomData.RoomEntity in room.entities:
		e.x_u += du.x
		e.y_u += du.y
	for d: RoomData.Door in room.doors:
		var along: int = du.y if d.side == RoomData.LEFT or d.side == RoomData.RIGHT else du.x
		d.from_u += along
		d.to_u += along
	room.spawn_x_u += du.x
	room.spawn_y_u += du.y
	for d: RoomData.Door in room.doors:
		_carry_passage(d, old, front)
	edited()


## After a shrink across door [param d]'s side, puts back what its passage (the strip, the same
## depth again, and the floor under a side door) was: the columns or rows just inside the edge
## are the ones a shrink takes, and the passage lies in them. [param old] is the grid before,
## [param front] the cells added or taken at the start of each axis.
func _carry_passage(d: RoomData.Door, old: TileGrid, front: Vector2i) -> void:
	var w: int = room.grid.width
	var h: int = room.grid.height
	var sideways: bool = d.side == RoomData.LEFT or d.side == RoomData.RIGHT
	if (w >= old.width) if sideways else (h >= old.height):
		return
	var clear: Rect2i = d.clear_u(width_u(), height_u())
	var cells := Rect2i(clear.position / TileGrid.TILE, clear.size / TileGrid.TILE)
	if sideways:
		cells.size.y += 1  # the floor row under the strip
	for j: int in range(cells.position.y, cells.end.y):
		for i: int in range(cells.position.x, cells.end.x):
			var src := Vector2i(i - front.x, j - front.y)
			match d.side:
				RoomData.LEFT:
					src.x = i
				RoomData.RIGHT:
					src.x = old.width - (w - i)
				RoomData.TOP:
					src.y = j
				_:
					src.y = old.height - (h - j)
			if old.in_bounds(src.x, src.y):
				room.grid.set_tile(i, j, old.get_tile(src.x, src.y))


func undo() -> void:
	var saved: String = history.undo(text())
	if saved != "":
		_restore(saved)


func redo() -> void:
	var saved: String = history.redo(text())
	if saved != "":
		_restore(saved)


## How many cells are added (positive) or taken (negative) at the start of an axis of
## [param old] cells that becomes [param new], for anchor [param anchor] (-1 keeps the start in
## place, 1 the end, 0 splits the change).
static func _front(old: int, new: int, anchor: int) -> int:
	if anchor < 0:
		return 0
	if anchor > 0:
		return new - old
	return (new - old) / 2


## The old cell a new cell [param i] of [param new] is copied from, when [param front] cells are
## added or taken at the start: added cells copy the edge, taken cells are the ones next to it.
static func _source(i: int, old: int, new: int, front: int) -> int:
	var j: int = i - front
	if front < 0 and i == 0:
		j = 0
	if new - old - front < 0 and i == new - 1:
		j = old - 1
	return clampi(j, 0, old - 1)


## Records an undo step (once per stroke): the edit helpers call it before they change the room.
func begin_edit() -> void:
	history.record(text())


func _restore(saved: String) -> void:
	# A path that followed the id (set_id) follows it back; a path chosen otherwise is kept.
	var follows_id: bool = path == RoomData.path_for(room.id)
	var keep_path: String = path
	room = RoomData.parse(saved)
	path = RoomData.path_for(room.id) if follows_id else keep_path
	edited()


## Marks the room changed and tells the views: the edit helpers call it after they change it.
func edited() -> void:
	dirty = true
	changed.emit()
