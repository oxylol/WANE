class_name RoomSet
extends RefCounted
## The rooms a run can reach from its first: that room, every room its doors lead to, and theirs,
## each loaded once when the simulation is built, in the order first reached (breadth first,
## doors in file order). The run never reads a room file after that, and the content hash covers
## them all (docs/adr/0014).
##
## Every door must lead to a door of the room beyond on the facing side, of the same length, that
## leads back: walking through and back always returns the player where they came from.

var rooms: Dictionary[String, RoomData] = {}
## Room ids in the order first reached; the first is the run's first room.
var order: Array[String] = []
## Problems with the rooms reached after the first (each prefixed with its id) and with the doors
## between rooms. The first room's own problems are in its [member RoomData.errors].
var errors: PackedStringArray = PackedStringArray()


## The rooms reachable from [param start_id]. Each is loaded from its file, or, with a
## [param cache], taken from it: a batch of runs that share rooms parses each once.
static func reach(start_id: String, cache: SimCache = null) -> RoomSet:
	var found := RoomSet.new()
	found._add(start_id, cache)
	var at: int = 0
	while at < found.order.size():
		var room: RoomData = found.rooms[found.order[at]]
		if at > 0:
			for problem: String in room.errors:
				found.errors.append("%s: %s" % [room.id, problem])
		for d: RoomData.Door in room.doors:
			if not found.rooms.has(d.target_room):
				found._add(d.target_room, cache)
		at += 1
	for room_id: String in found.order:
		found._check_pairs(found.rooms[room_id])
	return found


## Problems with [param room]'s doors against the rooms they lead to, read from their files (the
## room itself is taken as given, so an unsaved edit is checked). A door whose room has no file
## is skipped: the caller reports that. The same checks as a run makes when it loads the rooms.
static func check_doors(room: RoomData) -> PackedStringArray:
	var found := RoomSet.new()
	found.rooms[room.id] = room
	found.order.append(room.id)
	for d: RoomData.Door in room.doors:
		if (
			not found.rooms.has(d.target_room)
			and FileAccess.file_exists(RoomData.path_for(d.target_room))
		):
			found._add(d.target_room)
	found._check_pairs(room)
	return found.errors


func _add(room_id: String, cache: SimCache = null) -> void:
	rooms[room_id] = cache.room(room_id) if cache != null else RoomData.load_id(room_id)
	order.append(room_id)


func _check_pairs(room: RoomData) -> void:
	for d: RoomData.Door in room.doors:
		var label: String = "%s: door '%s'" % [room.id, d.name]
		if not rooms.has(d.target_room):
			continue
		var beyond: RoomData = rooms[d.target_room]
		var back: RoomData.Door = beyond.door(d.target_door)
		if back == null:
			errors.append(
				"%s leads to door '%s' of %s, which has none" % [label, d.target_door, beyond.id]
			)
		elif back.side != d.facing_side():
			(
				errors
				. append(
					(
						"%s on the %s leads to a door on the %s; it must be on the %s"
						% [
							label,
							RoomData.SIDE_NAMES[d.side],
							RoomData.SIDE_NAMES[back.side],
							RoomData.SIDE_NAMES[d.facing_side()],
						]
					)
				)
			)
		elif back.span_u() != d.span_u():
			errors.append(
				(
					"%s is %d u long; door '%s' of %s is %d u"
					% [label, d.span_u(), back.name, beyond.id, back.span_u()]
				)
			)
		elif back.target_room != room.id or back.target_door != d.name:
			errors.append(
				(
					"%s leads to door '%s' of %s, which does not lead back"
					% [label, back.name, beyond.id]
				)
			)
