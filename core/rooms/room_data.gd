class_name RoomData
extends RefCounted
## A room as authored: its tile grid, spawn point, solid boxes and entity markers, parsed from a
## `.room` text file (format in docs/adr/0009). Its geometry must pass
## [method TileGrid.validate]. Rooms under
## content/rooms/ are game content; ids starting with "test/" resolve to tests/replay/rooms/.

## A door's side of the room (the names the text uses are [constant SIDE_NAMES]).
enum { LEFT, RIGHT, TOP, BOTTOM }

const CONTENT_ROOT: String = "res://content/rooms/"
const TEST_ROOT: String = "res://tests/replay/rooms/"
const TEST_PREFIX: String = "test/"
## The names the text uses for a door's side, in the order of the enum.
const SIDE_NAMES: Array[String] = ["left", "right", "top", "bottom"]
## How deep into the room a door's strip reaches, in tiles: the player goes through a door when
## the whole body is inside its strip, so the strip must hold a standing body (44 u tall) at a
## top or bottom door (docs/adr/0014).
const DOOR_DEPTH_TILES: int = 2

var id: String = ""
var grid: TileGrid = TileGrid.new()
## Default spawn: bottom-centre of the player, in units.
var spawn_x_u: int = 0
var spawn_y_u: int = 0
var solids: Array[SolidBox] = []
var entities: Array[RoomEntity] = []
var doors: Array[Door] = []
var errors: PackedStringArray = PackedStringArray()
## The comment lines of the text, kept so the room editor can save a room without losing them:
## those before the tiles block, those just above each solid box and entity (aligned with
## [member solids] and [member entities]), and those after the last line.
var header_notes: PackedStringArray = PackedStringArray()
var solid_notes: Array[PackedStringArray] = []
var entity_notes: Array[PackedStringArray] = []
var door_notes: Array[PackedStringArray] = []
var footer_notes: PackedStringArray = PackedStringArray()


## An entity marker: a kind, a position in units, and integer or string properties.
class RoomEntity:
	var kind: String = ""
	var x_u: int = 0
	var y_u: int = 0
	var props: Dictionary[String, String] = {}

	func prop_int(key: String, default_value: int = 0) -> int:
		return (
			props[key].to_int() if props.has(key) and props[key].is_valid_int() else default_value
		)


## A door: an opening [member from_u]..[member to_u] units along one side of the room that leads
## to door [member target_door] of room [member target_room] (docs/adr/0014).
class Door:
	var name: String = ""
	var side: int = LEFT
	var from_u: int = 0
	var to_u: int = 0
	var target_room: String = ""
	var target_door: String = ""

	func span_u() -> int:
		return to_u - from_u

	## The side across from this one: a door on the right leads to one on the left.
	func facing_side() -> int:
		return [RIGHT, LEFT, BOTTOM, TOP][side]

	## The door's strip in units: [member DOOR_DEPTH_TILES] tiles deep from its side of a room
	## [param w_u] by [param h_u] units, along the opening.
	func strip_u(w_u: int, h_u: int) -> Rect2i:
		var depth: int = DOOR_DEPTH_TILES * TileGrid.TILE
		match side:
			LEFT:
				return Rect2i(0, from_u, depth, span_u())
			RIGHT:
				return Rect2i(w_u - depth, from_u, depth, span_u())
			TOP:
				return Rect2i(from_u, 0, span_u(), depth)
		return Rect2i(from_u, h_u - depth, span_u(), depth)


static func path_for(room_id: String) -> String:
	if room_id.begins_with(TEST_PREFIX):
		return TEST_ROOT + room_id.substr(TEST_PREFIX.length()) + ".room"
	return CONTENT_ROOT + room_id + ".room"


## Loads room [param room_id]; check [member errors] before use.
static func load_id(room_id: String) -> RoomData:
	var path: String = path_for(room_id)
	if not FileAccess.file_exists(path):
		var missing := RoomData.new()
		missing.id = room_id
		missing.errors.append("no room file at %s" % path)
		return missing
	var room: RoomData = parse(FileAccess.get_file_as_string(path))
	if room.id != room_id:
		room.errors.append("room file %s declares id '%s'" % [path, room.id])
	return room


static func parse(text: String) -> RoomData:
	var room := RoomData.new()
	var rows: PackedStringArray = []
	var in_tiles: bool = false
	var width: int = -1
	var height: int = -1
	var line_number: int = 0
	var seen_tiles: bool = false
	var notes: PackedStringArray = []
	for raw: String in text.split("\n"):
		line_number += 1
		if in_tiles:
			var row: String = raw.strip_edges()
			if row == "end":
				in_tiles = false
			elif row != "":
				rows.append(row)
			continue
		var hash_at: int = raw.find("#")
		var line: String = (raw.substr(0, hash_at) if hash_at >= 0 else raw).strip_edges()
		if hash_at >= 0 and line == "":
			notes.append(raw.substr(hash_at).strip_edges())
		if line == "":
			continue
		var words: PackedStringArray = line.split(" ", false)
		if words[0] == "solid" or words[0] == "entity" or words[0] == "door":
			if words[0] == "solid":
				room.solid_notes.append(notes)
			elif words[0] == "entity":
				room.entity_notes.append(notes)
			else:
				room.door_notes.append(notes)
			notes = []
		elif not seen_tiles:
			room.header_notes.append_array(notes)
			notes = []
		seen_tiles = seen_tiles or words[0] == "tiles"
		match words[0]:
			"room":
				room.id = words[1] if words.size() > 1 else ""
			"size":
				width = _int(words, 1, room, line_number)
				height = _int(words, 2, room, line_number)
			"spawn":
				room.spawn_x_u = _int(words, 1, room, line_number)
				room.spawn_y_u = _int(words, 2, room, line_number)
			"tiles":
				in_tiles = true
			"solid":
				room._parse_solid(words, line_number)
			"entity":
				room._parse_entity(words, line_number)
			"door":
				room._parse_door(words, line_number)
			_:
				room.errors.append("line %d: unknown directive '%s'" % [line_number, words[0]])
	room.footer_notes = notes
	if in_tiles:
		room.errors.append("tiles block has no 'end'")
	room.grid = TileGrid.from_rows(rows, room.errors)
	room.errors.append_array(room.grid.validate())
	if width >= 0 and (room.grid.width != width or room.grid.height != height):
		room.errors.append(
			(
				"size says %dx%d but the tiles are %dx%d"
				% [width, height, room.grid.width, room.grid.height]
			)
		)
	if room.id == "":
		room.errors.append("missing 'room <id>'")
	room._check_doors()
	return room


static func _int(words: PackedStringArray, i: int, room: RoomData, line_number: int) -> int:
	if i >= words.size() or not words[i].is_valid_int():
		room.errors.append("line %d: expected an integer" % line_number)
		return 0
	return words[i].to_int()


func _parse_solid(words: PackedStringArray, line_number: int) -> void:
	if words.size() < 5:
		errors.append("line %d: solid <l> <t> <r> <b> [tag=..] [cling=0]" % line_number)
		return
	var s := SolidBox.make(
		Fx.units(_int(words, 1, self, line_number)),
		Fx.units(_int(words, 2, self, line_number)),
		Fx.units(_int(words, 3, self, line_number)),
		Fx.units(_int(words, 4, self, line_number))
	)
	for i: int in range(5, words.size()):
		var kv: PackedStringArray = words[i].split("=")
		if kv.size() != 2:
			errors.append("line %d: bad option '%s'" % [line_number, words[i]])
		elif kv[0] == "tag":
			s.tag = kv[1]
		elif kv[0] == "cling":
			s.clingable = kv[1] != "0"
		else:
			errors.append("line %d: unknown solid option '%s'" % [line_number, kv[0]])
	if s.right <= s.left or s.bottom <= s.top:
		errors.append("line %d: solid has no area" % line_number)
	solids.append(s)


func _parse_entity(words: PackedStringArray, line_number: int) -> void:
	if words.size() < 4:
		errors.append("line %d: entity <kind> <x> <y> [key=value]..." % line_number)
		return
	var e := RoomEntity.new()
	e.kind = words[1]
	e.x_u = _int(words, 2, self, line_number)
	e.y_u = _int(words, 3, self, line_number)
	for i: int in range(4, words.size()):
		var kv: PackedStringArray = words[i].split("=")
		if kv.size() != 2:
			errors.append("line %d: bad property '%s'" % [line_number, words[i]])
		else:
			e.props[kv[0]] = kv[1]
	entities.append(e)


func _parse_door(words: PackedStringArray, line_number: int) -> void:
	if words.size() != 7:
		errors.append(
			"line %d: door <name> <left|right|top|bottom> <from> <to> <room> <door>" % line_number
		)
		return
	var d := Door.new()
	d.name = words[1]
	d.side = SIDE_NAMES.find(words[2])
	if d.side < 0:
		errors.append("line %d: a door's side is left, right, top or bottom" % line_number)
		d.side = LEFT
	d.from_u = _int(words, 3, self, line_number)
	d.to_u = _int(words, 4, self, line_number)
	d.target_room = words[5]
	d.target_door = words[6]
	doors.append(d)


## The door named [param door_name], or null.
func door(door_name: String) -> Door:
	for d: Door in doors:
		if d.name == door_name:
			return d
	return null


## Every door: a unique name; an opening on whole tiles, at least [member DOOR_DEPTH_TILES]
## long, inside its side; and its strip empty (no wall tile, no solid box), so the body can reach
## the whole strip and go through.
func _check_doors() -> void:
	var w_u: int = grid.width * TileGrid.TILE
	var h_u: int = grid.height * TileGrid.TILE
	var seen: Dictionary[String, bool] = {}
	for d: Door in doors:
		var label: String = "door '%s'" % d.name
		if seen.has(d.name):
			errors.append("%s is named twice" % label)
		seen[d.name] = true
		var edge_u: int = h_u if d.side == LEFT or d.side == RIGHT else w_u
		if d.from_u % TileGrid.TILE != 0 or d.to_u % TileGrid.TILE != 0:
			errors.append(
				"%s: the opening %d..%d is not on whole tiles" % [label, d.from_u, d.to_u]
			)
			continue
		if d.span_u() < DOOR_DEPTH_TILES * TileGrid.TILE:
			errors.append("%s: the opening is shorter than %d tiles" % [label, DOOR_DEPTH_TILES])
			continue
		if d.from_u < 0 or d.to_u > edge_u:
			errors.append("%s: the opening %d..%d leaves its side" % [label, d.from_u, d.to_u])
			continue
		# The strip and as much again inward: the player arrives just beyond a door's strip.
		var strip: Rect2i = d.strip_u(w_u, h_u)
		var reach_u: int = DOOR_DEPTH_TILES * TileGrid.TILE
		var clear: Rect2i = strip
		match d.side:
			LEFT:
				clear = strip.grow_individual(0, 0, reach_u, 0)
			RIGHT:
				clear = strip.grow_individual(reach_u, 0, 0, 0)
			TOP:
				clear = strip.grow_individual(0, 0, 0, reach_u)
			BOTTOM:
				clear = strip.grow_individual(0, reach_u, 0, 0)
		var blocked: bool = false
		var cells: Rect2i = _cells(strip)
		var clear_cells: Rect2i = _cells(clear)
		for j: int in range(clear_cells.position.y, clear_cells.end.y):
			for i: int in range(clear_cells.position.x, clear_cells.end.x):
				blocked = blocked or grid.get_tile(i, j) != TileGrid.EMPTY
		for s: SolidBox in solids:
			var box := Rect2i(
				Fx.div_floor(s.left, Fx.SUB),
				Fx.div_floor(s.top, Fx.SUB),
				Fx.div_floor(s.right - s.left, Fx.SUB),
				Fx.div_floor(s.bottom - s.top, Fx.SUB)
			)
			blocked = blocked or box.intersects(clear)
		if blocked:
			errors.append(
				"%s: its strip and the %d tiles beyond it are not empty" % [label, DOOR_DEPTH_TILES]
			)
		elif d.side == LEFT or d.side == RIGHT:
			_check_door_floor(cells, label)
		elif d.side == TOP:
			_check_door_landing(cells, label)


## A side door stands on floor: the tiles under its strip are walls, so a player who walks
## through arrives on the ground of the room beyond, a safe place to come back to after a hazard.
func _check_door_floor(cells: Rect2i, label: String) -> void:
	for i: int in range(cells.position.x, cells.end.x):
		if not TileGrid.is_wall(grid.get_tile(i, cells.end.y)):
			errors.append("%s: no floor under its opening at column %d" % [label, i])
			return


## A fall through a top door lands on safe ground: straight down from the strip, the first tile
## that is not empty is no hazard, and there is one before the room ends.
func _check_door_landing(cells: Rect2i, label: String) -> void:
	for i: int in range(cells.position.x, cells.end.x):
		var j: int = cells.end.y
		while j < grid.height and grid.get_tile(i, j) == TileGrid.EMPTY:
			j += 1
		var landing: int = grid.get_tile(i, j)
		if j >= grid.height or landing == TileGrid.SPIKES or landing == TileGrid.PIT:
			errors.append("%s: a fall at column %d lands on no safe ground" % [label, i])
			return


## The tiles [param rect_u] (in units, on whole tiles) covers.
static func _cells(rect_u: Rect2i) -> Rect2i:
	return Rect2i(
		Fx.div_floor(rect_u.position.x, TileGrid.TILE),
		Fx.div_floor(rect_u.position.y, TileGrid.TILE),
		Fx.div_floor(rect_u.size.x, TileGrid.TILE),
		Fx.div_floor(rect_u.size.y, TileGrid.TILE)
	)


## A fresh collision world for this room (solid boxes copied, so a run can break them).
func build_world() -> CollisionWorld:
	var w := CollisionWorld.new(grid.copy())
	for s: SolidBox in solids:
		var c: SolidBox = SolidBox.make(s.left, s.top, s.right, s.bottom)
		c.tag = s.tag
		c.clingable = s.clingable
		w.solids.append(c)
	return w


## Text form, the inverse of [method parse] (used by the room editor).
func to_text() -> String:
	var lines: PackedStringArray = ["room %s" % id]
	lines.append_array(header_notes)
	lines.append_array(
		["size %d %d" % [grid.width, grid.height], "spawn %d %d" % [spawn_x_u, spawn_y_u], "tiles"]
	)
	lines.append_array(grid.to_rows())
	lines.append("end")
	for i: int in range(solids.size()):
		var s: SolidBox = solids[i]
		if i < solid_notes.size():
			lines.append_array(solid_notes[i])
		var line: String = (
			"solid %d %d %d %d"
			% [
				Fx.div_floor(s.left, Fx.SUB),
				Fx.div_floor(s.top, Fx.SUB),
				Fx.div_floor(s.right, Fx.SUB),
				Fx.div_floor(s.bottom, Fx.SUB),
			]
		)
		if s.tag != "":
			line += " tag=%s" % s.tag
		if not s.clingable:
			line += " cling=0"
		lines.append(line)
	for i: int in range(doors.size()):
		var d: Door = doors[i]
		if i < door_notes.size():
			lines.append_array(door_notes[i])
		lines.append(
			(
				"door %s %s %d %d %s %s"
				% [d.name, SIDE_NAMES[d.side], d.from_u, d.to_u, d.target_room, d.target_door]
			)
		)
	for i: int in range(entities.size()):
		var e: RoomEntity = entities[i]
		if i < entity_notes.size():
			lines.append_array(entity_notes[i])
		var parts: PackedStringArray = ["entity", e.kind, str(e.x_u), str(e.y_u)]
		var keys: Array[String] = []
		for k: String in e.props.keys():
			keys.append(k)
		keys.sort()
		for k: String in keys:
			parts.append("%s=%s" % [k, e.props[k]])
		lines.append(" ".join(parts))
	lines.append_array(footer_notes)
	return "\n".join(lines) + "\n"
