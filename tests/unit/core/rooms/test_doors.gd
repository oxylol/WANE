extends GdUnitTestSuite
## Doors between rooms (docs/adr/0014): the format and its checks, the rooms a run can reach and
## the pairs between them, the zone's schema, and what the simulation keeps and resets through a
## door. The walks, dashes, falls and jumps through doors are fixtures (tests/replay/doors/).

## A 12 x 8 room whose right door is 4 tiles tall over the floor (rows 3 to 6, floor at row 7).
const RIGHT_DOOR_ROOM: String = """room test/x
size 12 8
spawn 64 224
tiles
############
#..........#
#..........#
#...........
#...........
#...........
#...........
############
end
door east right 96 224 test/y west
"""


func _with_doors(door_lines: String, rows: PackedStringArray = []) -> RoomData:
	var text: String = RIGHT_DOOR_ROOM.replace("door east right 96 224 test/y west\n", door_lines)
	if not rows.is_empty():
		var tiles_at: int = text.find("tiles\n") + 6
		var end_at: int = text.find("end\n")
		text = text.substr(0, tiles_at) + "\n".join(rows) + "\n" + text.substr(end_at)
	return RoomData.parse(text)


func test_a_door_reads_and_writes_back() -> void:
	var room: RoomData = RoomData.parse(RIGHT_DOOR_ROOM)
	assert_array(Array(room.errors)).is_empty()
	assert_int(room.doors.size()).is_equal(1)
	var d: RoomData.Door = room.doors[0]
	assert_str(d.name).is_equal("east")
	assert_int(d.side).is_equal(RoomData.RIGHT)
	assert_int(d.from_u).is_equal(96)
	assert_int(d.to_u).is_equal(224)
	assert_str(d.target_room).is_equal("test/y")
	assert_str(d.target_door).is_equal("west")
	assert_int(d.facing_side()).is_equal(RoomData.LEFT)
	assert_object(room.door("east")).is_same(d)
	assert_object(room.door("west")).is_null()
	assert_str(RoomData.parse(room.to_text()).to_text()).is_equal(room.to_text())
	assert_bool(room.to_text().contains("door east right 96 224 test/y west")).is_true()


func test_a_doors_strip_is_two_tiles_deep_from_its_side() -> void:
	var d := RoomData.Door.new()
	d.from_u = 96
	d.to_u = 224
	for side: int in [RoomData.LEFT, RoomData.RIGHT, RoomData.TOP, RoomData.BOTTOM]:
		d.side = side
		var strip: Rect2i = d.strip_u(384, 256)
		var expected: Rect2i = [
			Rect2i(0, 96, 64, 128),
			Rect2i(320, 96, 64, 128),
			Rect2i(96, 0, 128, 64),
			Rect2i(96, 192, 128, 64),
		][side]
		assert_object(strip).is_equal(expected)


func test_a_door_that_breaks_the_rules_is_an_error() -> void:
	var cases: Dictionary[String, String] = {
		"door east middle 96 224 test/y west\n": "left, right, top or bottom",
		"door east right 100 224 test/y west\n": "not on whole tiles",
		"door east right 192 224 test/y west\n": "shorter than 2 tiles",
		"door east right 96 288 test/y west\n": "leaves its side",
		"door east right 96 224 test/y\n": "door <name>",
		"door east right 96 224 test/y west\ndoor east right 96 224 test/y west\n": "named twice",
	}
	for line: String in cases:
		var errors: String = "\n".join(_with_doors(line).errors)
		assert_str(errors).override_failure_message(line + errors).contains(cases[line])


func test_a_doors_strip_and_the_tiles_beyond_it_must_be_empty() -> void:
	var rows: PackedStringArray = [
		"############",
		"#..........#",
		"#..........#",
		"#...........",
		"#.......#...",
		"#...........",
		"#...........",
		"############",
	]
	var errors: String = "\n".join(_with_doors("door east right 96 224 test/y west\n", rows).errors)
	assert_str(errors).contains("not empty")
	var boxed: RoomData = RoomData.parse(RIGHT_DOOR_ROOM + "solid 340 150 350 160\n")
	assert_str("\n".join(boxed.errors)).contains("not empty")


func test_a_side_door_stands_on_floor() -> void:
	var rows: PackedStringArray = [
		"############",
		"#..........#",
		"#..........#",
		"#...........",
		"#...........",
		"#...........",
		"#...........",
		"##########..",
	]
	var errors: String = "\n".join(_with_doors("door east right 96 224 test/y west\n", rows).errors)
	assert_str(errors).contains("no floor under its opening")


func test_a_fall_through_a_top_door_lands_on_safe_ground() -> void:
	var rows: PackedStringArray = [
		"####....####",
		"#..........#",
		"#..........#",
		"#..........#",
		"#..........#",
		"#..........#",
		"#....^^....#",
		"############",
	]
	var room: RoomData = _with_doors("door up top 128 256 test/y down\n", rows)
	assert_str("\n".join(room.errors)).contains("lands on no safe ground")
	rows[6] = "#..........#"
	assert_array(Array(_with_doors("door up top 128 256 test/y down\n", rows).errors)).is_empty()


func test_a_run_reaches_every_room_through_doors_once_and_in_order() -> void:
	var found: RoomSet = RoomSet.reach("test/door_a")
	assert_array(Array(found.errors)).is_empty()
	assert_array(found.order).is_equal(["test/door_a", "test/door_b", "test/door_up"])
	var single: RoomSet = RoomSet.reach("test/camera")
	assert_array(single.order).is_equal(["test/camera"])


func test_broken_pairs_are_errors() -> void:
	var found := RoomSet.new()
	var a: RoomData = RoomData.parse(RIGHT_DOOR_ROOM)
	var b: RoomData = RoomData.parse(RIGHT_DOOR_ROOM.replace("room test/x", "room test/y"))
	found.rooms["test/x"] = a
	found.rooms["test/y"] = b
	found.order.assign(["test/x", "test/y"])
	found._check_pairs(a)
	assert_str("\n".join(found.errors)).contains("which has none")
	b.doors[0].name = "west"
	found.errors.clear()
	found._check_pairs(a)
	assert_str("\n".join(found.errors)).contains("it must be on the left")
	b.doors[0].side = RoomData.LEFT
	b.doors[0].to_u = 192
	found.errors.clear()
	found._check_pairs(a)
	assert_str("\n".join(found.errors)).contains("is 128 u long")
	b.doors[0].to_u = 224
	b.doors[0].target_door = "north"
	found.errors.clear()
	found._check_pairs(a)
	assert_str("\n".join(found.errors)).contains("does not lead back")
	b.doors[0].target_door = "east"
	b.doors[0].target_room = "test/x"
	found.errors.clear()
	found._check_pairs(a)
	assert_array(Array(found.errors)).is_empty()


func test_a_zone_lists_exactly_the_rooms_its_doors_join() -> void:
	var zone := ZoneDef.new()
	zone.id = "test"
	zone.start_room = "test/door_a"
	zone.rooms.assign(["test/door_a", "test/door_b", "test/door_up"])
	assert_array(Array(zone.validate())).is_empty()
	zone.rooms.assign(["test/door_a", "test/door_b"])
	assert_str("\n".join(zone.validate())).contains("which the zone does not list")
	zone.rooms.assign(["test/door_a", "test/door_b", "test/door_up", "test/camera"])
	assert_str("\n".join(zone.validate())).contains("cannot be reached")
	zone.start_room = "test/elsewhere"
	assert_str("\n".join(zone.validate())).contains("not one of the zone's rooms")


func test_the_content_hash_covers_every_room_a_run_can_reach() -> void:
	# The same first room hashes differently with and without the rooms beyond its doors.
	var whole := Simulation.new(Scenario.make(1, "test/door_a"))
	assert_array(Array(whole.load_errors)).is_empty()
	var alone := StateHasher.new()
	ContentHash.add_room(alone, whole.rooms.rooms["test/door_a"])
	var all := StateHasher.new()
	for room_id: String in whole.rooms.order:
		ContentHash.add_room(all, whole.rooms.rooms[room_id])
	assert_int(alone.value()).is_not_equal(all.value())


func test_a_door_changes_the_room_in_the_state_hash_and_the_probe() -> void:
	var fx: Fixture = (
		Fixture
		. parse_text(
			(
				"\n"
				. join(
					[
						"fixture through",
						"doc docs/adr/0014",
						"room test/door_a",
						"spawn 1100 416",
						"frames 17",
						"input",
						"  0..16 R",
						"end",
						"expect",
						"end",
					]
				)
			)
		)
	)
	var sim := Simulation.new(fx.scenario)
	for i: int in range(fx.frame_total):
		sim.step(fx.input_frame(i))
	assert_str(str(sim.probe("room"))).is_equal("test_door_b")
	assert_array(Array(sim.probe_words("room"))).contains(["test_door_a", "test_door_b"])
	assert_object(sim.player.world).is_same(sim.world)
	# Through on frame 16: dying now returns to door_b's spawn, and the arrival point is safe
	# ground until Ash stands on other ground.
	assert_int(sim.player.home_x).is_equal(Fx.units(200))
	assert_int(sim.player.safe_x).is_equal(Fx.units(74))
	# The same player state in another room hashes differently: the room is part of the state.
	var here: int = sim.state_hash()
	var elsewhere: RoomData = sim.rooms.rooms["test/door_a"]
	var was: RoomData = sim.room
	sim.room = elsewhere
	assert_int(sim.state_hash()).is_not_equal(here)
	sim.room = was
	assert_int(sim.state_hash()).is_equal(here)
