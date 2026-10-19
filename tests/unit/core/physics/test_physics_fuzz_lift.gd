extends GdUnitTestSuite
## Randomised invariants for the corner correction on the ground and for landings on a ledge's
## far edge (the fourth physics review, H1 to H3 and L3; docs/adr/0008). The walks use the
## player's 8 u corner lift, as the player always walks.

const U: int = PhysicsKit.U
const LIFT: int = 8 * U


func test_walking_over_lips_up_and_down_within_the_lift_never_leaves_the_ground() -> void:
	# A flat floor with solid boxes laid over it 1 to 8 u proud, and pits floored by solid boxes 1
	# to 8 u below it: a walk with the lift steps up and down every one, never airborne and never
	# stopped short of the room's walls.
	var rng: Rng = Rng.seeded(41, 3)
	for room: int in range(60):
		var w: CollisionWorld = _lip_world(rng)
		var b: Body = PhysicsKit.body(rng.between(80, 1800), 300)
		PhysicsKit.fall(w, b)
		if not b.on_ground:
			fail("lip room %d: the drop did not land" % room)
			return
		for move: int in range(80):
			var start := Vector2i(b.x, b.y)
			var d: int = rng.between(-22, 22) * U + rng.between(-255, 255)
			b.clear_contacts()
			var moved: int = w.walk(b, d, LIFT)
			var problem: String = ""
			if not b.on_ground:
				problem = "left the ground"
			elif PhysicsKit.embedded(w, b):
				problem = "embedded"
			elif b.hit_wall != 0 and b.left() > 64 * U and b.right() < (1920 - 64) * U:
				problem = "stopped by a lip after %d of %d" % [moved, d]
			if problem != "":
				fail(
					(
						"lip room %d, walk %d from %s by %d: %s at (%d, %d)"
						% [room, move, start, d, problem, b.x, b.y]
					)
				)
				return


func test_a_lip_at_a_ramps_crest_never_stops_a_walk_up_the_ramp() -> void:
	# A 45-degree or 1:2 ramp up to a plateau, with a lip 1 to 8 u proud of the plateau starting
	# anywhere from the crest edge to two tiles past it: walking (or dashing) up the ramp with the
	# lift reaches the far side of the lip.
	var rng: Rng = Rng.seeded(43, 5)
	for trial: int in range(120):
		var steep: bool = rng.below(2) == 0
		var w: CollisionWorld = PhysicsKit.world(_ramp_rows(steep))
		var crest: int = (12 if steep else 13) * TileGrid.TILE_SP
		var plateau: int = 9 * TileGrid.TILE_SP
		var start: int = crest + rng.between(0, 64) * U + rng.between(0, 255)
		var lip_top: int = plateau - rng.between(1, 8) * U + rng.between(0, 255) % U
		w.solids.append(SolidBox.make(start, lip_top, start + 96 * U, plateau))
		var b: Body = PhysicsKit.body(3 * 32, 13 * 32)
		w.refresh_ground(b)
		var speed: int = (20 if rng.below(2) == 0 else 9) * U
		for _tick: int in range(80):
			b.clear_contacts()
			w.walk(b, speed, LIFT)
		if b.x < start + 96 * U:
			fail(
				(
					"trial %d (%s, lip %d u high from %d): stopped at (%d, %d)"
					% [
						trial,
						"45" if steep else "1:2",
						Fx.div_floor(plateau - lip_top, U),
						start / U,
						b.x,
						b.y
					]
				)
			)
			return


func test_a_lip_on_a_ramp_is_walked_over_both_ways_on_the_ground() -> void:
	# A 45-degree or 1:2 ramp rising either way, with a solid box sunk into it whose top stands 0
	# to 8 u proud of the floor at one face (a door sunk flush at 0) and is buried, or no taller
	# than the lift, at the other: walking (or dashing) up the ramp over it and back down never
	# leaves the ground and never stops. Walking down off the lip, the floor under the centre is
	# up to half the box's width further below than the slope under its trailing edge (review 5,
	# H1: the step down measured from the centre, so the walk down flew the rest of the ramp).
	var rng: Rng = Rng.seeded(53, 9)
	var span: int = 40 * TileGrid.TILE_SP
	for trial: int in range(300):
		var steep: bool = rng.below(2) == 0
		var mirror: bool = rng.below(2) == 0
		var w: CollisionWorld = PhysicsKit.world(_ramp_rows(steep, mirror))
		var foot: int = (8 if steep else 5) * TileGrid.TILE_SP
		var crest: int = (12 if steep else 13) * TileGrid.TILE_SP
		var low_face: bool = rng.below(2) == 0
		var proud: int = rng.between(0, 8 * U if low_face else 7 * U)
		var lx: int = rng.between(foot, crest + 64 * U)
		var width: int = rng.between(4 * U, 120 * U)
		if not low_face:
			# The other face is the lift's height or less above the floor too.
			width = mini(width, (8 * U - proud) * (1 if steep else 2))
		var face: int = lx if low_face else lx + width - 1
		var top: int = _surface(w, face if not mirror else span - 1 - face) - proud
		var l: int = lx if not mirror else span - (lx + width)
		w.solids.append(SolidBox.make(l, top, l + width, top + 200 * U))
		var low_x: int = 2 * TileGrid.TILE_SP + 16 * U
		var high_x: int = 20 * TileGrid.TILE_SP
		if mirror:
			low_x = span - low_x
			high_x = span - high_x
		var b: Body = PhysicsKit.body(low_x / U, 13 * 32)
		w.refresh_ground(b)
		var speed: int = (20 if rng.below(2) == 0 else 9) * U
		for to: int in [high_x, low_x]:
			var problem: String = _walk_to(w, b, to, speed)
			if problem != "":
				fail(
					(
						"trial %d (%s%s, lip [%d, %d) top %d, %s face %d sp proud, %d u/f): %s"
						% [
							trial,
							"45" if steep else "1:2",
							" mirrored" if mirror else "",
							l,
							l + width,
							top,
							"low" if low_face else "high",
							proud,
							speed / U,
							problem
						]
					)
				)
				return


func test_a_lip_met_corner_to_corner_walking_down_a_ramp_never_stops_the_walk() -> void:
	# Review 8, H1: whole-unit lips laid at, before or on the foot of a 45-degree or 1:2 ramp
	# rising either way, their tops level with the feet at the moment the walk down the ramp brings
	# the leading edge to their uphill face (and in a third of trials 1 to 7 u either side of that):
	# walking or dashing down onto them with the lift carries on past them, never standing still on
	# the ground. The corner-to-corner touch used to read as the box's side, the step up was 0 u and
	# refused, and the walk stood at the face for good (135 of the 7,680 whole-unit lips the review
	# swept). Random sub-pixel tops, as the tests above use, almost never touch corner to corner.
	var tuning: WorldTuning = load(WorldTuning.PATH) as WorldTuning
	var band: int = Fx.units(tuning.join_band_u)
	var reach: int = Fx.units(tuning.join_reach_u)
	var span: int = 40 * TileGrid.TILE_SP
	var rng: Rng = Rng.seeded(73, 19)
	var checked: int = 0
	var corner: int = 0
	for trial: int in range(600):
		var steep: bool = rng.below(2) == 0
		var mirror: bool = rng.below(2) == 0
		var w: CollisionWorld = PhysicsKit.world(_ramp_rows(steep, mirror))
		var foot: int = (8 if steep else 5) * TileGrid.TILE
		var crest: int = (12 if steep else 13) * TileGrid.TILE
		# Unmirrored, the walk goes left down the ramp and meets the lip's right (uphill) face with
		# its left edge; mirrored, right, its right edge on the lip's left face.
		var dir: int = 1 if mirror else -1
		var face: int = rng.between(foot - 24, crest - 8) * U
		if mirror:
			face = span - face
		var width: int = [6, 20, 40][rng.below(3)] * U
		var l: int = face if mirror else face - width
		var k: int = 0 if rng.below(3) > 0 else rng.between(-7, 7) * U
		var top: int = _surface(w, face - dir * PhysicsKit.HALF_W) + k
		var lip: SolidBox = SolidBox.make(l, top, l + width, top + 80 * U)
		var room := RoomData.new()
		room.grid = w.grid
		room.solids = [lip]
		if not RoomJoins.errors(room, band, reach).is_empty():
			continue
		w.solids.append(lip)
		checked += 1
		corner += 1 if k == 0 else 0
		# On the plateau, a whole number of units plus any sub-pixel, so the touch falls anywhere in
		# a tick's step, its start included.
		var start: int = 24 * TileGrid.TILE_SP + rng.between(0, U - 1)
		var b: Body = PhysicsKit.body(0, 9 * TileGrid.TILE)
		b.x = span - start if mirror else start
		w.refresh_ground(b)
		var past: int = (l + width + PhysicsKit.HALF_W) if mirror else (l - PhysicsKit.HALF_W)
		var speed: int = (20 if rng.below(2) == 0 else 9) * U
		var problem: String = _walk_past(w, b, dir, past, speed)
		if problem != "":
			fail(
				(
					"trial %d (%s%s, lip [%d, %d) top %d, %d sp off the feet at the face, %d u/f): %s"
					% [
						trial,
						"45" if steep else "1:2",
						" mirrored" if mirror else "",
						l,
						l + width,
						top,
						k,
						speed / U,
						problem
					]
				)
			)
			return
	assert_int(checked).is_greater(250)
	assert_int(corner).is_greater(150)


func test_the_lift_off_a_ramp_counts_what_stands_ahead_not_the_crest_behind() -> void:
	# Review 8: on the 45-degree ramp the box's trailing foot zone rests in the crest wall uphill of
	# it, up to its half-width above the feet (the plateau's wall starts at x 384, its top y 288).
	# Walking, or moving through the air, downhill into a lip, the lift is to the lip's top, not the
	# plateau's: with the centre at x 375 (feet y 297) a lip 5 u proud is a 5 u step, not a refused
	# 9 u one that stood the walk at the lip's face for good; with the centre at x 377 (feet y 295) a
	# lip 2 u proud is a 2 u lift, not a 7 u one that popped the box 5 u above the lip it stepped
	# onto. Both moves step onto the lip's top and carry on along it, 9 u.
	for case: Vector2i in [Vector2i(375, 292), Vector2i(377, 293)]:
		for airborne: bool in [false, true]:
			var w: CollisionWorld = PhysicsKit.world(_ramp_rows(true))
			var face: int = case.x - 10
			w.solids.append(SolidBox.make((face - 20) * U, case.y * U, face * U, (case.y + 80) * U))
			var b: Body = PhysicsKit.body(case.x, 384 - case.x + 288)
			w.refresh_ground(b)
			assert_bool(b.on_ground and b.on_slope).is_true()
			b.clear_contacts()
			if airborne:
				b.on_ground = false
				w.move_x(b, -9 * U, LIFT)
			else:
				w.walk(b, -9 * U, LIFT)
			var how: String = "%s from x %d" % ["air" if airborne else "walk", case.x]
			assert_int(b.x).override_failure_message("%s: x %d" % [how, b.x]).is_equal(
				(case.x - 9) * U
			)
			assert_int(b.y).override_failure_message("%s: y %d" % [how, b.y]).is_equal(case.y * U)
			assert_int(b.hit_wall).override_failure_message(how).is_equal(0)
			assert_bool(PhysicsKit.embedded(w, b)).override_failure_message(how).is_false()


func test_an_air_move_rides_a_ramp_and_lifts_onto_a_lip_at_its_crest_in_one_tick() -> void:
	# A level air dash (20 u a tick) skimming up a 45-degree or 1:2 ramp onto a plateau with a lip
	# 1 to 8 u proud of it at the crest edge: the lift was measured from the feet before the ride
	# up the slope, so the dash stopped short at the lip for a tick (review 5, L1). It goes the
	# whole 20 u.
	var rng: Rng = Rng.seeded(67, 15)
	for trial: int in range(200):
		var steep: bool = rng.below(2) == 0
		var w: CollisionWorld = PhysicsKit.world(_ramp_rows(steep))
		var crest: int = (12 if steep else 13) * TileGrid.TILE_SP
		var plateau: int = 9 * TileGrid.TILE_SP
		var lip_top: int = plateau - rng.between(1 * U, 8 * U)
		w.solids.append(SolidBox.make(crest, lip_top, crest + 96 * U, plateau))
		var b: Body = PhysicsKit.body(0, 0)
		b.x = crest - b.half_w - rng.between(1, 16 * U)
		b.y = _surface(w, b.x) - rng.between(0, U)
		b.on_ground = false
		var start := Vector2i(b.x, b.y)
		var moved: int = w.move_x(b, 20 * U, LIFT, 6 * U)
		if moved != 20 * U:
			fail(
				(
					"trial %d (%s, lip %d sp proud) from %s: moved %d of %d"
					% [trial, "45" if steep else "1:2", plateau - lip_top, start, moved, 20 * U]
				)
			)
			return


func test_an_air_move_lifts_onto_two_lips_in_a_row() -> void:
	# A level air move meeting a lip within the lift and, beyond it, a second lip within the lift
	# of the first: as a walk steps up both, the move does (review 5, L1).
	var rng: Rng = Rng.seeded(71, 17)
	for trial: int in range(200):
		var rows: Array[String] = []
		for j: int in range(17):
			rows.append("#" + ".".repeat(38) + "#" if j < 14 else "#".repeat(40))
		rows[0] = "#".repeat(40)
		var w: CollisionWorld = PhysicsKit.world(rows)
		var floor_y: int = 14 * TileGrid.TILE_SP
		var first: int = 600 * U
		var second: int = first + rng.between(1 * U, 8 * U)
		var low: int = floor_y - rng.between(1 * U, 4 * U)
		var high: int = low - rng.between(1 * U, 4 * U)
		w.solids.append(SolidBox.make(first, low, 900 * U, floor_y))
		w.solids.append(SolidBox.make(second, high, 900 * U, low))
		var b: Body = PhysicsKit.body(0, 0)
		b.x = first - b.half_w - rng.between(0, 6 * U)
		b.y = floor_y - rng.between(0, U)
		b.on_ground = false
		var start := Vector2i(b.x, b.y)
		var moved: int = w.move_x(b, 20 * U, LIFT, 6 * U)
		if moved != 20 * U or b.y != high:
			fail(
				(
					"trial %d (lips %d and %d sp up, %d apart) from %s: moved %d to y %d"
					% [trial, floor_y - low, low - high, second - first, start, moved, b.y]
				)
			)
			return


func test_an_air_step_lands_wherever_its_straight_path_stands_on_a_ledge() -> void:
	# A box falling past a ledge's edge with sideways speed, moved as the player moves it (the
	# landing contact first, else across then down): wherever its straight path stands on the
	# ledge with at least a sixteenth of a unit over it, the step lands.
	var rng: Rng = Rng.seeded(47, 7)
	var checked: int = 0
	for trial: int in range(4000):
		var w: CollisionWorld = PhysicsKit.world(_ledge_rows())
		var top: int = 12 * TileGrid.TILE_SP
		var edge: int = (20 if rng.below(2) == 0 else 10) * TileGrid.TILE_SP
		var away: int = 1 if edge == 20 * TileGrid.TILE_SP else -1
		var b: Body = PhysicsKit.body(0, 0)
		b.x = edge - away * rng.between(-12, 16) * U + rng.between(-255, 255)
		b.y = top - rng.between(0, 12 * U)
		if not w.body_fits(b.x, b.y, b.half_w, b.height):
			continue
		var dx: int = away * rng.between(1, 20 * U)
		var dy: int = rng.between(1, 25 * U)
		var stands: bool = _path_stands(w, b, dx, dy, top)
		b.on_ground = false
		var contact: int = w.landing_contact(b, dx, dy)
		if contact != CollisionQueries.NONE:
			w.move_x(b, contact)
			w.move_y(b, dy)
		else:
			w.move_x(b, dx, LIFT)
			w.move_y(b, dy)
		if stands:
			checked += 1
			if not b.on_ground:
				fail(
					(
						"trial %d: the straight path stood on the ledge; the step ended in the air"
						% trial
					)
				)
				return
	assert_int(checked).is_greater(200)


func test_an_air_step_never_lands_lower_than_moving_across_first_would() -> void:
	# The far-edge landing (above) must leave the near side of a raised step alone (review 5,
	# M1): a box falling toward a block 1 to 24 u tall on a floor within a tick's fall, which
	# moving across first lands on (or lifts onto), landed on the floor in front of it instead,
	# 18 u lower and stopped against its face. Moved as the player moves it, a box never ends
	# lower than the plain across-then-down step would put it on the ground.
	var rng: Rng = Rng.seeded(61, 13)
	var checked: int = 0
	for trial: int in range(4000):
		var rows: Array[String] = []
		for j: int in range(17):
			rows.append("#" + ".".repeat(38) + "#" if j < 14 else "#".repeat(40))
		rows[0] = "#".repeat(40)
		var w: CollisionWorld = PhysicsKit.world(rows)
		var floor_y: int = 14 * TileGrid.TILE_SP
		var block_top: int = floor_y - rng.between(1 * U, 24 * U)
		w.solids.append(SolidBox.make(640 * U, block_top, 800 * U, floor_y))
		var b: Body = PhysicsKit.body(0, 0)
		b.x = 640 * U - b.half_w - rng.between(0, 20 * U)
		b.y = block_top - rng.between(-12 * U, 12 * U)
		if not w.body_fits(b.x, b.y, b.half_w, b.height):
			continue
		var dx: int = rng.between(1, 20 * U)
		var dy: int = rng.between(1, 25 * U)
		var start := Vector2i(b.x, b.y)
		var plain: Body = Body.make(b.x, b.y, b.half_w, b.height)
		w.move_x(plain, dx, LIFT, 6 * U)
		w.move_y(plain, dy, 6 * U)
		b.on_ground = false
		var contact: int = w.landing_contact(b, dx, dy)
		if contact != CollisionQueries.NONE:
			w.move_x(b, contact)
			w.move_y(b, dy)
		else:
			w.move_x(b, dx, LIFT, 6 * U)
			w.move_y(b, dy, 6 * U)
		if plain.on_ground:
			checked += 1
			if b.y > plain.y:
				fail(
					(
						"trial %d: from %s by (%d, %d) toward a block %d sp tall: landed at y %d, below %d"
						% [trial, start, dx, dy, floor_y - block_top, b.y, plain.y]
					)
				)
				return
	assert_int(checked).is_greater(200)


## True if the straight path from the body's position by ([param dx], [param dy]) reaches the
## ledge's top [param top] with the box standing on it there, at least a sixteenth of a unit of it
## over the ledge, and the box clear where it starts and there.
func _path_stands(w: CollisionWorld, b: Body, dx: int, dy: int, top: int) -> bool:
	if top < b.y or top > b.y + dy:
		return false
	var x: int = b.x + signi(dx) * Fx.div_floor(absi(dx) * (top - b.y), dy)
	if not w.body_fits(b.x, b.y, b.half_w, b.height) or not w.body_fits(x, top, b.half_w, b.height):
		return false
	for inset: int in [0, U / 16, -U / 16]:
		var probe: Body = Body.make(x + inset, top, b.half_w, b.height)
		w.refresh_ground(probe)
		if not probe.on_ground:
			return false
	return true


## A tile floor at row 12 across a 60-tile room, with lips: solid boxes 1 to 8 u proud of it
## and pits two to four tiles wide whose floor is a solid box 1 to 8 u below it.
func _lip_world(rng: Rng) -> CollisionWorld:
	var rows: Array[String] = []
	for j: int in range(16):
		rows.append("#" + ".".repeat(58) + "#" if j > 0 and j < 12 else "#".repeat(60))
	var pits: Array[Vector2i] = []
	var c: int = 6
	while c < 52:
		if rng.below(3) == 0:
			var width: int = rng.between(2, 4)
			pits.append(Vector2i(c, width))
			for k: int in range(width):
				rows[12] = rows[12].substr(0, c + k) + "." + rows[12].substr(c + k + 1)
			c += width + rng.between(2, 5)
		else:
			c += rng.between(2, 5)
	var w: CollisionWorld = PhysicsKit.world(rows)
	var floor_y: int = 12 * TileGrid.TILE_SP
	for pit: Vector2i in pits:
		var l: int = pit.x * TileGrid.TILE_SP
		var drop: int = rng.between(1, 8) * U - rng.between(0, 255) % U
		w.solids.append(
			SolidBox.make(
				l, floor_y + drop, l + pit.y * TileGrid.TILE_SP, floor_y + TileGrid.TILE_SP
			)
		)
	for _lip: int in range(rng.between(2, 6)):
		var l: int = rng.between(6, 50) * TileGrid.TILE_SP + rng.between(0, 31) * U
		var h: int = rng.between(1, 8) * U - rng.between(0, 255) % U
		var overlaps_pit: bool = false
		for pit: Vector2i in pits:
			var pl: int = pit.x * TileGrid.TILE_SP
			if l < pl + pit.y * TileGrid.TILE_SP + 32 * U and l + 128 * U > pl:
				overlaps_pit = true
		if not overlaps_pit:
			w.solids.append(SolidBox.make(l, floor_y - h, l + 96 * U, floor_y))
	return w


## Walks [param b] on the ground to x [param to] at [param speed] a tick with the lift: "" if it
## gets there without leaving the ground, stopping or embedding, else what happened first.
func _walk_to(w: CollisionWorld, b: Body, to: int, speed: int) -> String:
	var dir: int = signi(to - b.x)
	for tick: int in range(200):
		if (to - b.x) * dir <= 0:
			return ""
		var x0: int = b.x
		b.clear_contacts()
		w.walk(b, dir * mini(speed, absi(to - b.x)), LIFT)
		if not b.on_ground:
			return "left the ground on tick %d at (%d, %d) from x %d" % [tick, b.x, b.y, x0]
		if b.x == x0:
			return "stopped on tick %d at (%d, %d)" % [tick, b.x, b.y]
		if PhysicsKit.embedded(w, b):
			return "embedded on tick %d at (%d, %d)" % [tick, b.x, b.y]
	return "never got there"


## Walks [param b] in [param dir] at [param speed] a tick with the lift until its centre is past
## [param past]: "" if it gets there, else where it stood still on the ground. Off a lip's far end
## higher than the lift it falls, as the player would, and walks on from where it lands.
func _walk_past(w: CollisionWorld, b: Body, dir: int, past: int, speed: int) -> String:
	for tick: int in range(200):
		if (b.x - past) * dir > 0:
			return ""
		if not b.on_ground:
			PhysicsKit.fall(w, b)
		var x0: int = b.x
		b.clear_contacts()
		w.walk(b, dir * speed, LIFT)
		if b.x == x0:
			return "stood still on tick %d at (%d, %d)" % [tick, b.x, b.y]
		if PhysicsKit.embedded(w, b):
			return "embedded on tick %d at (%d, %d)" % [tick, b.x, b.y]
	return "never got past"


## The tile floor's top under the sub-pixel column at [param x].
func _surface(w: CollisionWorld, x: int) -> int:
	return w.floor_top_in(x, x + 1, 2 * TileGrid.TILE_SP, 14 * TileGrid.TILE_SP)


## A 45-degree ramp (four rows) or a 1:2 ramp (four rows, eight columns) rising right to a
## plateau whose top is row 9; [param mirror]ed, rising left.
func _ramp_rows(steep: bool, mirror: bool = false) -> Array[String]:
	var rows: Array[String] = []
	for j: int in range(16):
		rows.append("#" + ".".repeat(38) + "#")
	rows[0] = "#".repeat(40)
	for j: int in range(13, 16):
		rows[j] = "#".repeat(40)
	var first: int = 8
	for k: int in range(4):
		var j: int = 12 - k
		var row: String = rows[j]
		if steep:
			var c: int = first + k
			row = row.substr(0, c) + "/" + "#".repeat(40 - c - 1)
		else:
			var c: int = first + 2 * k - 3
			row = row.substr(0, c) + "ab" + "#".repeat(40 - c - 2)
		rows[j] = row
	for j: int in range(8, 13):
		rows[j] = rows[j].substr(0, 39) + "#"
	if mirror:
		var flip: Dictionary[String, String] = {"/": "\\", "a": "d", "b": "c"}
		for j: int in range(rows.size()):
			var m: String = ""
			for i: int in range(39, -1, -1):
				m += flip.get(rows[j][i], rows[j][i])
			rows[j] = m
	return rows


## A ledge from column 10 to column 19 (top at row 12) in open air over a floor at row 15.
func _ledge_rows() -> Array[String]:
	var rows: Array[String] = []
	for j: int in range(17):
		rows.append("#" + ".".repeat(38) + "#")
	rows[0] = "#".repeat(40)
	rows[16] = "#".repeat(40)
	rows[15] = "#".repeat(40)
	for j: int in range(12, 14):
		rows[j] = rows[j].substr(0, 10) + "#".repeat(10) + rows[j].substr(20)
	return rows
