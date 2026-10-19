extends GdUnitTestSuite
## docs/adr/0008 decision 12 ([RoomJoins]): a solid box's top is open ground, flush with the
## terrain, a lip above it, out of every foot's reach under it, or a top a slope rises out of; a
## one-way beside a box's top is level with it or out of reach above it. Physics review 6 (H1, M5,
## L5) found the walk leaving the ground over door tops buried a few units in a ramp or a plateau,
## and dropping through a one-way shelf a few units over a box: such rooms are refused at load.
## Physics review 7 found a shelf across a gap narrower than a body missed (L1) and a trapdoor at a
## ramp's foot refused though the walk handles it (L2).

const U: int = PhysicsKit.U
const BAND: int = 12 * PhysicsKit.U
const REACH: int = 24 * PhysicsKit.U
## A 45-degree ramp rising right from x 96 (y 128) to x 224 (y 0), the plateau beyond.
const RAMP: Array[String] = [
	"......./##",
	"....../###",
	"...../####",
	"..../#####",
	"##########",
]


func _room(rows: Array[String], boxes: Array[SolidBox]) -> RoomData:
	var room := RoomData.new()
	room.grid = TileGrid.from_rows(PackedStringArray(rows))
	room.solids = boxes
	return room


func _errors(rows: Array[String], boxes: Array[SolidBox]) -> PackedStringArray:
	return RoomJoins.errors(_room(rows, boxes), BAND, REACH)


func test_a_door_flush_with_the_ramps_foot_and_open_above_is_ground() -> void:
	# Top y 128 is the floor's top: the ramp starts from it at x 128.
	var door: SolidBox = SolidBox.make(40 * U, 128 * U, 128 * U, 160 * U)
	assert_array(_errors(RAMP, [door])).is_empty()


func test_a_door_buried_a_unit_under_a_ramp_is_refused() -> void:
	# Review 6 H1: the walk down the ramp read the buried top as a floor and flew the rest of it.
	for depth_q: int in [1, 4, 8, 40]:
		var top: int = 96 * U + depth_q * U / 4
		var door: SolidBox = SolidBox.make(160 * U, top, 200 * U, top + 40 * U)
		var problems: PackedStringArray = _errors(RAMP, [door])
		assert_int(problems.size()).override_failure_message("depth %d/4 u" % depth_q).is_equal(1)
		assert_str(problems[0]).contains("buried")


func test_a_door_sunk_into_a_plateau_within_the_band_is_refused_and_beyond_it_is_terrain() -> void:
	# Review 6 M5: a door sunk 1 to 9 u under the plateau just past the crest lifted the walk onto
	# the crest's own top and left it hovering.
	for depth_u: int in [1, 3, 9, 12]:
		var door: SolidBox = SolidBox.make(256 * U, depth_u * U, 300 * U, 60 * U)
		assert_int(_errors(RAMP, [door]).size()).is_equal(1)
	var deep: SolidBox = SolidBox.make(256 * U, 13 * U, 300 * U, 60 * U)
	assert_array(_errors(RAMP, [deep])).is_empty()


func test_a_door_filling_a_corridor_up_to_its_ceiling_is_fine() -> void:
	var rows: Array[String] = ["##########", "##########", "..........", "..........", "##########"]
	var door: SolidBox = SolidBox.make(140 * U, 64 * U, 156 * U, 128 * U)
	assert_array(_errors(rows, [door])).is_empty()


func test_lips_above_the_floor_and_a_step_of_two_boxes_are_ground() -> void:
	var rows: Array[String] = ["..........", "..........", "..........", "..........", "##########"]
	var lip: SolidBox = SolidBox.make(40 * U, 126 * U, 120 * U, 128 * U)
	var lower: SolidBox = SolidBox.make(160 * U, 124 * U, 260 * U, 128 * U)
	var upper: SolidBox = SolidBox.make(200 * U, 120 * U, 240 * U, 126 * U)
	assert_array(_errors(rows, [lip, lower, upper])).is_empty()


func test_a_one_way_shelf_just_above_a_box_beside_it_is_refused() -> void:
	# Review 6 L5: walking back off the box passed under the shelf and fell through it.
	var rows: Array[String] = ["..........", "..........", "...=......", "..........", "##########"]
	for rise_u: int in [1, 4, 12]:
		var box: SolidBox = SolidBox.make(128 * U, (64 + rise_u) * U, 200 * U, 128 * U)
		var problems: PackedStringArray = _errors(rows, [box])
		assert_int(problems.size()).override_failure_message("rise %d u" % rise_u).is_equal(1)
		assert_str(problems[0]).contains("one-way")
	for ok_u: int in [0, 13, 40]:
		var box: SolidBox = SolidBox.make(128 * U, (64 + ok_u) * U, 200 * U, 128 * U)
		assert_array(_errors(rows, [box])).override_failure_message("rise %d u" % ok_u).is_empty()


func test_a_one_way_shelf_across_a_gap_narrower_than_a_body_is_refused() -> void:
	# Review 7 L1: a box ending mid-column, 16 u short of a one-way 4 u above its top. The 20 u body
	# bridges the gap, passes under the shelf and drops through it, as beside a box flush with it.
	var rows: Array[String] = [
		"..............",
		"..............",
		".............=",
		"..............",
		"##############",
	]
	for end_u: int in [416, 400, 393]:
		var box: SolidBox = SolidBox.make(300 * U, 68 * U, end_u * U, 128 * U)
		var problems: PackedStringArray = _errors(rows, [box])
		assert_int(problems.size()).override_failure_message("end %d u" % end_u).is_equal(1)
		assert_str(problems[0]).contains("one-way")
	# Wider than any Wick: the gap is a drop, not a shelf.
	var far: SolidBox = SolidBox.make(300 * U, 68 * U, 392 * U, 128 * U)
	assert_array(_errors(rows, [far])).is_empty()
	# Mirrored, beside the box's left edge.
	var left_rows: Array[String] = [
		"..............", "..............", "=.............", "..", "##"
	]
	var mirrored: SolidBox = SolidBox.make(48 * U, 68 * U, 200 * U, 128 * U)
	assert_int(_errors(left_rows, [mirrored]).size()).is_equal(1)


func test_a_trapdoor_running_under_a_ramps_foot_is_ground() -> void:
	# Review 7 L2: a door flush with the floor over a pit, running 16 u under the foot of a ramp: the
	# slope rises out of its top, and the walk plays it frame for frame as the door ending at the
	# foot (decision 5).
	var rows: Array[String] = [
		"..........",
		"..........",
		"...../####",
		"####.#####",
		"##########",
	]
	for end_u: int in [160, 176, 190]:
		var door: SolidBox = SolidBox.make(128 * U, 96 * U, end_u * U, 104 * U)
		assert_array(_errors(rows, [door])).override_failure_message("end %d u" % end_u).is_empty()


func test_a_box_under_a_ramps_rise_is_ground_when_its_far_end_is_deep() -> void:
	# The slope crosses the box's top mid-run (decision 5, the physics sheet's panel 8): the top runs
	# on as open ground on one side, and on the other it is deeper than the band under the ramp.
	var rows: Array[String] = ["..........", "..........", "..#\\......", "##########"]
	var deep_end: SolidBox = SolidBox.make(96 * U, 86 * U, 250 * U, 120 * U)
	assert_array(_errors(rows, [deep_end])).is_empty()
	# Its far end a few units under the slope: the H1 join again, refused.
	for start_u: int in [107, 110, 117]:
		var shallow: SolidBox = SolidBox.make(start_u * U, 86 * U, 250 * U, 120 * U)
		(
			assert_int(_errors(rows, [shallow]).size())
			. override_failure_message("start %d u" % start_u)
			. is_equal(1)
		)
	# Ending where the slope meets its top: nothing under the ground at all.
	var flush: SolidBox = SolidBox.make(118 * U, 86 * U, 250 * U, 120 * U)
	assert_array(_errors(rows, [flush])).is_empty()


func test_the_simulation_refuses_a_room_with_a_buried_top() -> void:
	var sim := Simulation.new(Scenario.make(1, "test/invalid_buried_door"))
	assert_bool(sim.load_errors.size() > 0).is_true()
	assert_str(" ".join(sim.load_errors)).contains("buried")


func test_a_box_top_inside_a_pit_or_spike_tile_is_refused() -> void:
	# Physics review 8, L1: standing on such a top is standing in the hazard. Level with the tile's
	# top (a bridge) or above it is ground.
	for room_id: String in ["test/invalid_pit_lid", "test/invalid_spike_lid"]:
		var sim := Simulation.new(Scenario.make(1, room_id))
		assert_str(" ".join(sim.load_errors)).override_failure_message(room_id).contains(
			"must be level with the tile's top or above it"
		)
	for hazard: String in ["~", "^"]:
		var rows: Array[String] = ["........", "........", "##" + hazard.repeat(3) + "###"]
		for top_u: int in [63, 64, 65, 70]:
			var lid: SolidBox = SolidBox.make(64 * U, top_u * U, 160 * U, 96 * U)
			var problems: PackedStringArray = _errors(rows, [lid])
			var label: String = "%s lid top %d" % [hazard, top_u]
			if top_u <= 64:
				assert_array(problems).override_failure_message(label).is_empty()
			else:
				assert_int(problems.size()).override_failure_message(label).is_equal(1)


func test_every_room_in_the_repo_has_clean_joins() -> void:
	var tuning: WorldTuning = load(WorldTuning.PATH) as WorldTuning
	var checked: int = 0
	for dir_path: String in ["res://tests/replay/rooms/", "res://content/rooms/"]:
		for file: String in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".room") or file.begins_with("invalid_"):
				continue
			var room: RoomData = RoomData.parse(FileAccess.get_file_as_string(dir_path + file))
			var problems: PackedStringArray = RoomJoins.errors(
				room, Fx.units(tuning.join_band_u), Fx.units(tuning.join_reach_u)
			)
			assert_array(problems).override_failure_message(file).is_empty()
			checked += 1
	assert_int(checked).is_greater(100)
