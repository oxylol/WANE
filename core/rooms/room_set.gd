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


## The rooms reachable from [param start_id].
static func reach(start_id: String) -> RoomSet:
	var found := RoomSet.new()
	found._add(start_id)
	var at: int = 0
	while at < found.order.size():
		var room: RoomData = found.rooms[found.order[at]]
		if at > 0:
			for problem: String in room.errors:
				found.errors.append("%s: %s" % [room.id, problem])
		for d: RoomData.Door in room.doors:
			if not found.rooms.has(d.target_room):
				found._add(d.target_room)
		at += 1
	for room_id: String in found.order:
		found._check_pairs(found.rooms[room_id])
	return found


func _add(room_id: String) -> void:
	rooms[room_id] = RoomData.load_id(room_id)
	order.append(room_id)


func _check_pairs(room: RoomData) -> void:
	for d: RoomData.Door in room.doors:
		var label: String = "%s: door '%s'" % [room.id, d.name]
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
