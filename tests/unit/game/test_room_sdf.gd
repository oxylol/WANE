extends GdUnitTestSuite
## A room's distance field and the shadow march's CPU twin (game/lighting/room_sdf.gd,
## shadow_twin.gd; docs/adr/0023 Decisions 4.1 and 4.5; BUILD.md section 10, Lighting: "2D
## ray-marched soft shadows from the ember against the collision layer"; section 15: "At Pitch
## ambient, the ember's light reveals a Clinger 30 frames before it drops").

const STRESS_ROOM: String = "perf/stress"


func _grid(rows: Array[String]) -> TileGrid:
	return TileGrid.from_rows(PackedStringArray(rows))


func _tuning() -> LightingTuning:
	return load(LightingTuning.PATH) as LightingTuning


## Twice the signed area of the shape [param i] of [param s], as an absolute area in u squared.
func _area(s: RoomSdf, i: int) -> float:
	var o: int = i * RoomSdf.STRIDE
	var kind: int = int(s.shapes[o + 6])
	if kind == RoomSdf.SOLID_RECT or kind == RoomSdf.EMPTY_RECT:
		return (s.shapes[o + 2] - s.shapes[o]) * (s.shapes[o + 3] - s.shapes[o + 1])
	var a := Vector2(s.shapes[o], s.shapes[o + 1])
	var b := Vector2(s.shapes[o + 2], s.shapes[o + 3])
	var c := Vector2(s.shapes[o + 4], s.shapes[o + 5])
	return absf((b - a).cross(c - a)) * 0.5


func _empty_area(s: RoomSdf) -> float:
	var total: float = 0.0
	for i: int in range(s.count()):
		var kind: int = int(s.shapes[i * RoomSdf.STRIDE + 6])
		if kind == RoomSdf.EMPTY_RECT or kind == RoomSdf.EMPTY_TRI:
			total += _area(s, i)
	return total


func _solid_area(s: RoomSdf, rects: bool, tris: bool) -> float:
	var total: float = 0.0
	for i: int in range(s.count()):
		var kind: int = int(s.shapes[i * RoomSdf.STRIDE + 6])
		if (kind == RoomSdf.SOLID_RECT and rects) or (kind == RoomSdf.SOLID_TRI and tris):
			total += _area(s, i)
	return total


func _twin(rows: Array[String]) -> ShadowTwin:
	return ShadowTwin.new(RoomSdf.from_grid(_grid(rows), 64.0, 4.0), _tuning())


# --- The shapes of a room -------------------------------------------------------------------------


func test_wall_tiles_merge_into_the_fewest_rectangles() -> void:
	var g: TileGrid = _grid(["........", "..##....", "..##....", "########", "########"])
	var s: RoomSdf = RoomSdf.from_grid(g, 64.0, 4.0)
	# The two-by-two block is one rectangle, the floor another; plus the border's four bands.
	assert_int(s.count_of(RoomSdf.SOLID_RECT)).is_equal(2 + 4)
	var band: float = 2.0 * (8.0 * 32.0 + 128.0) * 64.0 + 2.0 * (5.0 * 32.0) * 64.0
	assert_float(_solid_area(s, true, false)).is_equal(float(4 + 16) * 32.0 * 32.0 + band)


func test_smooth_tiles_are_solid_and_one_ways_spikes_and_pits_are_not() -> void:
	var g: TileGrid = _grid(["S==^~", ".....", "#####"])
	var s: RoomSdf = RoomSdf.from_grid(g, 64.0, 4.0)
	# The smooth tile and the floor, and the border.
	assert_int(s.count_of(RoomSdf.SOLID_RECT)).is_equal(2 + 4)
	# Everything else of the middle row is empty and so is the row of one-way, spike and pit.
	assert_bool(s.distance(Vector2(3.5 * 32.0, 16.0)) > 0.0).is_true()
	assert_bool(s.distance(Vector2(2.5 * 32.0, 16.0)) > 0.0).is_true()
	assert_bool(s.distance(Vector2(0.5 * 32.0, 16.0)) < 0.0).is_true()


func test_a_slope_tile_is_triangles_of_solid_and_of_air() -> void:
	# 'a' is the low half of the 1:2 ramp: the ground rises 0 to 16 u across the tile. The solid
	# below the surface is one triangle, the air above it two.
	var low: RoomSdf = RoomSdf.from_grid(_grid(["a"]), 64.0, 4.0)
	assert_int(low.count_of(RoomSdf.SOLID_TRI)).is_equal(1)
	assert_int(low.count_of(RoomSdf.EMPTY_TRI)).is_equal(2)
	assert_float(_solid_area(low, false, true)).is_equal_approx(256.0, 0.01)
	assert_float(_empty_area(low)).is_equal_approx(768.0, 0.01)
	# The high half, 16 to 32 u: a trapezoid of two triangles, and one triangle of air.
	var high: RoomSdf = RoomSdf.from_grid(_grid(["b"]), 64.0, 4.0)
	assert_int(high.count_of(RoomSdf.SOLID_TRI)).is_equal(2)
	assert_int(high.count_of(RoomSdf.EMPTY_TRI)).is_equal(1)
	assert_float(_solid_area(high, false, true)).is_equal_approx(768.0, 0.01)
	# A full 45 degree slope leaves one triangle of each.
	var d: RoomSdf = RoomSdf.from_grid(_grid(["/"]), 64.0, 4.0)
	assert_int(d.count_of(RoomSdf.SOLID_TRI)).is_equal(1)
	assert_int(d.count_of(RoomSdf.EMPTY_TRI)).is_equal(1)
	assert_float(_solid_area(d, false, true)).is_equal_approx(512.0, 0.01)


func test_the_border_is_four_solid_bands_outside_the_room() -> void:
	var s: RoomSdf = RoomSdf.from_grid(_grid(["....", "...."]), 64.0, 4.0)
	assert_int(s.count_of(RoomSdf.SOLID_RECT)).is_equal(4)
	assert_float(s.rect.position.x).is_equal(-64.0)
	assert_float(s.rect.size.x).is_equal(4.0 * 32.0 + 128.0)
	# Inside the room, away from every wall, is the open; at the edge the border begins.
	assert_float(s.distance(Vector2(64.0, 32.0))).is_equal_approx(32.0, 0.001)
	assert_float(s.distance(Vector2(-10.0, 32.0))).is_equal_approx(-10.0, 0.001)


func test_the_distance_is_exact_beside_a_floor() -> void:
	var s: RoomSdf = RoomSdf.from_grid(_grid(["....", "....", "####"]), 64.0, 4.0)
	# The floor's top is y = 64: 10 u above it is +10, 16 u below it is -16 (the nearest air).
	assert_float(s.distance(Vector2(64.0, 54.0))).is_equal_approx(10.0, 0.001)
	assert_float(s.distance(Vector2(64.0, 80.0))).is_equal_approx(-16.0, 0.001)
	# Past the room's corner the nearest solid is the corner of the floor and the right wall.
	assert_float(s.distance(Vector2(100.0, 62.0))).is_equal_approx(2.0, 0.001)


func test_the_distance_to_a_slope_is_to_its_line() -> void:
	# A 45 degree slope up to the right in a 2 x 2 room: the line runs (0, 64) to (32, 32) ... build
	# one tile of ground, two of air above it, so the nearest solid is the slope and not the border.
	var g: TileGrid = _grid(["....", "....", "....", "...."])
	g.set_tile(1, 3, TileGrid.SLOPE_R)
	var s: RoomSdf = RoomSdf.from_grid(g, 64.0, 4.0)
	# The slope tile is x 32..64, y 96..128, surface from (32, 128) up to (64, 96): x + y = 160.
	var p := Vector2(40.0, 90.0)
	var expected: float = (160.0 - (p.x + p.y)) / sqrt(2.0)
	assert_float(s.distance(p)).is_equal_approx(expected, 0.01)
	# Inside the slope it is minus the distance to the nearest air, which is the surface.
	var inside := Vector2(44.0, 124.0)
	assert_float(s.distance(inside)).is_equal_approx(
		-((inside.x + inside.y) - 160.0) / sqrt(2.0), 0.01
	)


func test_the_field_is_lipschitz_and_agrees_with_the_tiles_on_the_sign() -> void:
	var g: TileGrid = _grid(["........", "..##....", "..#/....", ".\\##.../", "########"])
	var s: RoomSdf = RoomSdf.from_grid(g, 64.0, 4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lo := Vector2(-80.0, -80.0)
	var hi := Vector2(8.0 * 32.0 + 80.0, 5.0 * 32.0 + 80.0)
	for _i: int in range(300):
		var p := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		var q: Vector2 = p + Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0))
		assert_float(absf(s.distance(p) - s.distance(q))).is_less_equal(p.distance_to(q) + 0.001)
	for j: int in range(5):
		for i: int in range(8):
			var tile: int = g.get_tile(i, j)
			var centre := Vector2((float(i) + 0.5) * 32.0, (float(j) + 0.5) * 32.0)
			if tile == TileGrid.SOLID:
				assert_float(s.distance(centre)).is_less(0.0)
			elif tile == TileGrid.EMPTY:
				assert_float(s.distance(centre)).is_greater(0.0)


func test_the_stress_room_is_a_few_hundred_shapes() -> void:
	var room: RoomData = RoomData.load_id(STRESS_ROOM)
	var world: CollisionWorld = room.build_world()
	var s: RoomSdf = RoomSdf.from_grid(world.grid, 64.0, 4.0)
	# 128 x 30 tiles, ramps, tiers: merged runs, not one shape a tile.
	assert_int(s.count()).is_less(700)
	assert_int(s.count()).is_greater(20)
	assert_int(s.size_px.x * s.size_px.y).is_less(1000 * 400)


func test_the_shape_texture_carries_every_shape() -> void:
	var s: RoomSdf = RoomSdf.from_grid(_grid(["....", "/###"]), 64.0, 4.0)
	var img: Image = s.shape_image()
	assert_int(img.get_width()).is_equal(s.count())
	assert_int(img.get_height()).is_equal(2)
	for i: int in range(s.count()):
		assert_float(img.get_pixel(i, 1).b).is_equal(s.shapes[i * RoomSdf.STRIDE + 6])
		assert_float(img.get_pixel(i, 0).r).is_equal(s.shapes[i * RoomSdf.STRIDE])


# --- The shadow march (the CPU twin) --------------------------------------------------------------


func test_the_open_is_lit_and_behind_a_wall_is_dark() -> void:
	var tw: ShadowTwin = _twin(["........", "........", "..##....", "########"])
	var light := Vector2(40.0, 40.0)
	# In the open, in sight of the light.
	assert_float(tw.visibility(Vector2(200.0, 40.0), light, 420.0)).is_equal(1.0)
	# Behind the block: the line to the light crosses it.
	assert_float(tw.visibility(Vector2(150.0, 90.0), light, 420.0)).is_equal(0.0)
	# Past the reach nothing is asked of the march.
	assert_float(tw.visibility(Vector2(900.0, 40.0), light, 420.0)).is_equal(1.0)


func test_a_wall_face_turned_to_the_light_has_a_lit_skin_and_a_black_interior() -> void:
	var tw: ShadowTwin = _twin(["........", "........", "........", "########"])
	var light := Vector2(100.0, 40.0)
	# The floor's top is y = 96. Just inside it, under the light: lit, fading with depth.
	var shallow: float = tw.visibility(Vector2(100.0, 98.0), light, 420.0)
	var deeper: float = tw.visibility(Vector2(100.0, 106.0), light, 420.0)
	assert_float(shallow).is_greater(0.5)
	assert_float(deeper).is_less(shallow)
	assert_float(deeper).is_greater(0.0)
	# Beyond the skin it is black.
	assert_float(tw.visibility(Vector2(100.0, 112.0), light, 420.0)).is_equal(0.0)


func test_a_shadow_has_a_penumbra_that_widens_with_distance_from_the_occluder() -> void:
	var rows: Array[String] = []
	for j: int in range(14):
		rows.append("................" if j != 3 else "....#...........")
	var tw: ShadowTwin = _twin(rows)
	var light := Vector2(40.0, 40.0)
	# Sweep an arc around the light and measure, in world units along it, how wide the soft edge of
	# the pillar's shadow is (visibility between 2% and 98%), near and far.
	var widths: Array[float] = []
	for radius: float in [250.0, 500.0]:
		var soft: int = 0
		var last: float = -1.0
		var biggest_step: float = 0.0
		var steps: int = 900
		for k: int in range(steps):
			var a: float = deg_to_rad(float(k) * 90.0 / float(steps))
			var p: Vector2 = light + Vector2(cos(a), sin(a)) * radius
			var v: float = tw.visibility(p, light, 900.0)
			if v > 0.02 and v < 0.98:
				soft += 1
			if last >= 0.0:
				biggest_step = maxf(biggest_step, absf(v - last))
			last = v
		widths.append(float(soft) * (deg_to_rad(90.0 / float(steps)) * radius))
		# Soft: no jump from lit to dark between neighbouring samples.
		assert_float(biggest_step).is_less(0.35)
	assert_float(widths[0]).is_greater(2.0)
	assert_float(widths[1]).is_greater(widths[0] * 1.3)


func test_a_dynamic_box_casts_a_shadow() -> void:
	var tw: ShadowTwin = _twin(
		["................", "................", "................", "................"]
	)
	var light := Vector2(40.0, 64.0)
	var p := Vector2(300.0, 64.0)
	assert_float(tw.visibility(p, light, 600.0)).is_equal(1.0)
	tw.occluders = [Vector4(170.0, 64.0, 16.0, 16.0)]
	assert_float(tw.visibility(p, light, 600.0)).is_equal(0.0)
	# A circle does too, and a box off the line does not.
	tw.occluders = [Vector4(170.0, 64.0, 14.0, -1.0)]
	assert_float(tw.visibility(p, light, 600.0)).is_equal(0.0)
	tw.occluders = [Vector4(170.0, 120.0, 10.0, 6.0)]
	assert_float(tw.visibility(p, light, 600.0)).is_equal(1.0)


func test_the_baked_field_would_agree_with_the_exact_one() -> void:
	# sample() with no bake is the exact field; the GPU half of the check holds the real bake to it.
	var s: RoomSdf = RoomSdf.from_grid(_grid(["....", "....", "####"]), 64.0, 4.0)
	assert_float(s.sample(Vector2(64.0, 54.0))).is_equal(s.distance(Vector2(64.0, 54.0)))


func test_the_ember_reveals_a_clinger_thirty_ticks_before_it_drops() -> void:
	# BUILD.md section 15: "At Pitch ambient, the ember's light reveals a Clinger 30 frames before it
	# drops". A Clinger hangs under the ceiling, 8 u down; the player walks toward it along the floor
	# at 5 u a tick and it drops when the ember is within 96 u across. The ember's light must
	# reach it for the 30 ticks before. A wall hanging from the ceiling between them hides it.
	var open_rows: Array[String] = [
		"................",
		"................",
		"................",
		"................",
		"################",
	]
	var tw: ShadowTwin = _twin(open_rows)
	var clinger := Vector2(11.0 * 32.0, 8.0)
	var floor_y: float = 4.0 * 32.0 - 22.0
	var speed: float = 5.0
	var drop_tick: int = 100
	var x_at_drop: float = clinger.x - 96.0
	var t: LightingTuning = _tuning()
	for k: int in range(30):
		var tick: int = drop_tick - 30 + k
		var ember := Vector2(x_at_drop - speed * float(drop_tick - tick), floor_y)
		var seen: float = tw.revealed(clinger, ember, t.ember_radius_u, t.falloff_power)
		assert_float(seen).is_greater_equal(t.reveal_threshold)
	# Walled off from the same ember by a wall that hangs between them: not revealed.
	var walled_rows: Array[String] = [
		"........#.......",
		"........#.......",
		"........#.......",
		"................",
		"################",
	]
	var hidden: ShadowTwin = _twin(walled_rows)
	var near := Vector2(clinger.x - 150.0, floor_y)
	assert_float(hidden.revealed(clinger, near, t.ember_radius_u, t.falloff_power)).is_less(
		t.reveal_threshold
	)
	assert_float(tw.revealed(clinger, near, t.ember_radius_u, t.falloff_power)).is_greater(
		t.reveal_threshold
	)
