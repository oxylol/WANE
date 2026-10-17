extends GdUnitTestSuite
## How Ash reads the stick (docs/adr/0010): equal 8-way sectors for dashes and the toss and equal
## 4-way sectors for strikes (task 3 review round 3, M4), taken from the frame a buffered press was
## made (task 3 review round 2, H2); and the teleport's fit search, whose bit masks must pick
## exactly what trying every offset in turn would.

const T: int = 64


func test_eight_way_sectors_are_equal() -> void:
	# Count, over a full-tilt circle sampled every quarter degree, how many samples land in each
	# of the eight directions: each sector is 45 degrees, within the stick's rounding.
	var counts: Dictionary[Vector2i, int] = {}
	for k: int in range(1440):
		var a: float = TAU * float(k) / 1440.0
		var d: Vector2i = PlayerInput.dir8(roundi(127.0 * cos(a)), roundi(127.0 * sin(a)), T)
		counts[d] = counts.get(d, 0) + 1
	assert_int(counts.size()).is_equal(8)
	for d: Vector2i in counts:
		assert_int(counts[d]).is_between(176, 184)


func test_inside_the_dead_zone_is_neutral_and_digital_diagonals_are_diagonal() -> void:
	assert_object(PlayerInput.dir8(63, 63, T)).is_equal(Vector2i.ZERO)
	assert_object(PlayerInput.dir8(127, -127, T)).is_equal(Vector2i(1, -1))
	assert_object(PlayerInput.dir8(-127, 0, T)).is_equal(Vector2i(-1, 0))
	# 20 degrees above horizontal is still straight; 25 is diagonal.
	assert_object(PlayerInput.dir8(119, -43, T)).is_equal(Vector2i(1, 0))
	assert_object(PlayerInput.dir8(115, -54, T)).is_equal(Vector2i(1, -1))


func test_four_way_strike_sectors_are_equal() -> void:
	# The Taper is 4-directional: up, down and each side take 90 degrees of a full-tilt circle.
	var counts: Dictionary[Vector2i, int] = {}
	for k: int in range(1440):
		var a: float = TAU * float(k) / 1440.0
		var d: Vector2i = PlayerInput.dir4(roundi(127.0 * cos(a)), roundi(127.0 * sin(a)), T)
		counts[d] = counts.get(d, 0) + 1
	assert_int(counts.size()).is_equal(4)
	for d: Vector2i in counts:
		assert_int(counts[d]).is_between(356, 364)


func test_a_strike_reads_a_diagonal_as_vertical_and_a_lean_as_level() -> void:
	assert_object(PlayerInput.dir4(63, -63, T)).is_equal(Vector2i.ZERO)
	# A d-pad diagonal (both axes full) is up or down.
	assert_object(PlayerInput.dir4(127, -127, T)).is_equal(Vector2i(0, -1))
	assert_object(PlayerInput.dir4(-127, 127, T)).is_equal(Vector2i(0, 1))
	# 23.6 degrees above level (the third review's case) is a side strike; 45.4 is up.
	assert_object(PlayerInput.dir4(80, -35, T)).is_equal(Vector2i(1, 0))
	assert_object(PlayerInput.dir4(80, -81, T)).is_equal(Vector2i(0, -1))
	# Past the threshold on the longer axis only: a short vertical lean on a full side is side.
	assert_object(PlayerInput.dir4(-127, 70, T)).is_equal(Vector2i(-1, 0))


func test_a_buffered_press_keeps_the_stick_of_its_own_frame() -> void:
	var ring := InputRing.new()
	ring.push(InputFrame.make(InputFrame.ATTACK, InputFrame.ATTACK, 0, 127))
	ring.push(InputFrame.make(0, 0, 0, 0))
	ring.push(InputFrame.make(0, 0, 127, 0))
	assert_object(PlayerInput.press_dir(ring, InputFrame.ATTACK, 8, T)).is_equal(Vector2i(0, 1))
	# With no press in the buffer it reads the stick now.
	assert_object(PlayerInput.press_dir(ring, InputFrame.DASH, 8, T)).is_equal(Vector2i(1, 0))


func test_the_masked_fit_search_finds_what_trying_every_offset_finds() -> void:
	var rng: Rng = Rng.seeded(31, 2)
	var sim := Simulation.new(Scenario.make(1, "test/flat"))
	var pl: Player = sim.player
	var offsets: PackedInt32Array = pl.kit.toss_fit_offsets
	for room: int in range(40):
		var grid := TileGrid.new(12, 10)
		for j: int in range(10):
			for i: int in range(12):
				grid.set_tile(i, j, TileGrid.SOLID if rng.below(3) == 0 else TileGrid.EMPTY)
		var w := CollisionWorld.new(grid)
		for _s: int in range(rng.below(4)):
			var l: int = rng.between(0, 340) * Fx.SUB
			var t: int = rng.between(0, 280) * Fx.SUB
			w.solids.append(
				SolidBox.make(
					l, t, l + rng.between(4, 60) * Fx.SUB, t + rng.between(4, 60) * Fx.SUB
				)
			)
		pl.world = w
		for _e: int in range(10):
			pl.toss.x = rng.between(16, 368) * Fx.SUB + rng.between(0, 255)
			pl.toss.y = rng.between(16, 304) * Fx.SUB + rng.between(0, 255)
			for height: int in [pl.p.height, pl.p.crouch_height]:
				var cy: int = pl.toss.y + height / 2
				var expected: int = -1
				for i: int in range(0, offsets.size(), 2):
					if w.body_fits(
						pl.toss.x + offsets[i], cy + offsets[i + 1], pl.p.half_w, height
					):
						expected = i
						break
				var got: int = pl.toss._first_fit(pl, cy, pl.p.half_w, height)
				if got != expected:
					fail(
						(
							"room %d, ember (%d, %d), height %d: %d, expected %d"
							% [room, pl.toss.x, pl.toss.y, height, got, expected]
						)
					)
					return
