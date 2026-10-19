extends GdUnitTestSuite
## [method PlayerWall.met] tries this tick's move on a copy of the body (movement review 5, M4, M5
## and L6): asked anything, at any point of a run, it must change nothing, not the player's jump
## state its gravity reads and puts back, nor wax a kindle-dash would burn. The fixtures where a
## press on the wall matters are played tick by tick and asked about both walls between ticks;
## the state hash must not move.

const DIRS: Array[String] = ["res://tests/replay/movement/", "res://tests/replay/tech/"]
## Fixtures with walls, dashes, wax and jumps: where the prediction runs through every branch.
const PICK: Array[String] = ["wall", "cling", "dash", "wax", "kindle", "jump", "kick", "toss"]


func _fixtures() -> Array[String]:
	var out: Array[String] = []
	for dir: String in DIRS:
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".fixture"):
				continue
			for word: String in PICK:
				if file.contains(word):
					out.append(dir + file)
					break
	return out


func test_asking_about_a_wall_changes_nothing() -> void:
	var paths: Array[String] = _fixtures()
	assert_int(paths.size()).is_greater(40)
	var asked: int = 0
	var met: int = 0
	for path: String in paths:
		var fx: Fixture = Fixture.parse_file(path)
		var sim := Simulation.new(fx.scenario)
		for i: int in range(fx.frame_total):
			sim.step(fx.input_frame(i))
			var hash_before: int = sim.state_hash()
			for dx: int in [-1, 1]:
				for dy: int in [-1, 0]:
					asked += 1
					if PlayerWall.met(sim.player, sim.input, dx, dy) != 0:
						met += 1
			(
				assert_int(sim.state_hash())
				. override_failure_message(
					"%s frame %d: asking about the walls changed the state" % [path, i]
				)
				. is_equal(hash_before)
			)
	# The sweep reaches walls, not only open air.
	assert_int(met).is_greater(20)
	assert_int(asked).is_greater(10000)
