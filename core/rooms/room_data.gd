class_name RoomData
extends RefCounted
## A room as authored: its tile grid, spawn point, solid boxes and entity markers, parsed from a
## `.room` text file (format in docs/adr/0009). Its geometry must pass
## [method TileGrid.validate]. Rooms under
## content/rooms/ are game content; ids starting with "test/" resolve to tests/replay/rooms/.

const CONTENT_ROOT: String = "res://content/rooms/"
const TEST_ROOT: String = "res://tests/replay/rooms/"
const TEST_PREFIX: String = "test/"

var id: String = ""
var grid: TileGrid = TileGrid.new()
## Default spawn: bottom-centre of the player, in units.
var spawn_x_u: int = 0
var spawn_y_u: int = 0
var solids: Array[SolidBox] = []
var entities: Array[RoomEntity] = []
var errors: PackedStringArray = PackedStringArray()
## The comment lines of the text, kept so the room editor can save a room without losing them:
## those before the tiles block, those just above each solid box and entity (aligned with
## [member solids] and [member entities]), and those after the last line.
var header_notes: PackedStringArray = PackedStringArray()
var solid_notes: Array[PackedStringArray] = []
var entity_notes: Array[PackedStringArray] = []
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
		if words[0] == "solid" or words[0] == "entity":
			if words[0] == "solid":
				room.solid_notes.append(notes)
			else:
				room.entity_notes.append(notes)
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
