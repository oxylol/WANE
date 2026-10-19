class_name ZoneDef
extends Resource
## A zone as content (BUILD.md section 3, The zones; CLAUDE.md: every zone is a `.tres` resource
## with a schema): its rooms, linked by their doors, and the room a run starts in. The rooms are
## text files (docs/adr/0009); the doors between them make the zone's map (docs/adr/0014).

## The zone's id and the name shown to the player.
@export var id: String = ""
@export var display_name: String = ""
## The room a run of this zone starts in (a room id, as in content/rooms/<id>.room).
@export var start_room: String = ""
## Every room of the zone, in the order they are listed in tools; each must be reachable from
## [member start_room] through doors, and no door may lead out of the zone.
@export var rooms: Array[String] = []


## Everything wrong with the zone: its rooms' own problems, broken or one-way doors, a room that
## cannot be reached from the start, and a door leading to a room the zone does not list.
func validate() -> PackedStringArray:
	var e: PackedStringArray = []
	if id == "":
		e.append("a zone needs an id")
	if not rooms.has(start_room):
		e.append("start room '%s' is not one of the zone's rooms" % start_room)
		return e
	var found: RoomSet = RoomSet.reach(start_room)
	for problem: String in found.rooms[start_room].errors:
		e.append("%s: %s" % [start_room, problem])
	e.append_array(found.errors)
	for room_id: String in found.order:
		if not rooms.has(room_id):
			e.append("a door leads to %s, which the zone does not list" % room_id)
	for room_id: String in rooms:
		if not found.rooms.has(room_id):
			e.append("%s cannot be reached from %s" % [room_id, start_room])
	return e
