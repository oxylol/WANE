extends GdUnitTestSuite
## The lighting pass (game/lighting, shaders/lighting; docs/adr/0023; BUILD.md section 10,
## Lighting: ember radius 420 u, warm 2400 K, flicker 0.5 Hz at 4%, 2D ray-marched soft shadows
## against the collision layer, "a per-zone ambient colour multiplied by the Wane Clock's darkness
## factor ... At Pitch, ambient is 0.15 and the world is the ember"). Headless: the field's script
## work, the shapes, the table and the twin. The GPU half (the bake and the buffer against the twin,
## the shaders compiling) is tools/lighting/gpu_check.gd, run by ci/lighting.sh under a display.

const STRESS_ROOM: String = "perf/stress"


func _main_scene() -> PackedScene:
	return load("res://game/main.tscn") as PackedScene


func _grid(rows: Array[String]) -> TileGrid:
	return TileGrid.from_rows(PackedStringArray(rows))


func _tuning() -> LightingTuning:
	return load(LightingTuning.PATH) as LightingTuning


func _field(profile: int = LightingTuning.PROFILE_PC) -> LightField:
	var f := LightField.new(null, profile)
	auto_free(f)
	add_child(f)
	return f


## The table's value at [param row] and [param col], component [param k] (0 to 3).
func _global_float(f: LightField, global_name: String) -> float:
	var v: float = f.globals[global_name]
	return v


func _lit_main(word: String) -> Main:
	Main.lighting_word = word
	var made: Node = auto_free(_main_scene().instantiate())
	var main: Main = made as Main
	main.save_on_exit = false
	add_child(main)
	Main.lighting_word = ""
	return main


func _cell(f: LightField, row: int, col: int, k: int) -> float:
	return f.table()[(row * LightField.TABLE_COLUMNS + col) * 4 + k]


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


# --- The numbers ----------------------------------------------------------------------------------


func test_the_numbers_are_the_sections_and_validate() -> void:
	var t: LightingTuning = _tuning()
	assert_array(Array(t.validate())).is_empty()
	assert_float(t.ember_radius_u).is_equal(420.0)
	assert_float(t.ember_kelvin).is_equal(2400.0)
	assert_float(t.flicker_hz).is_equal(0.5)
	assert_float(t.flicker_amplitude).is_equal(0.04)
	assert_float(t.dark_floor).is_equal(0.15)
	assert_float(t.light_height_u).is_equal(40.0)
	assert_float(t.skin_u).is_equal(14.0)
	assert_int(t.max_steps).is_equal(48)
	assert_float(t.min_step_u).is_equal(1.5)
	assert_float(t.light_r_u).is_equal(8.0)
	assert_float(t.sdf_texel_u).is_equal(4.0)
	assert_float(t.beacon.radius_u).is_equal(900.0)
	assert_float(t.fire.radius_u).is_equal(160.0)
	assert_float(t.gutter_ember.radius_u).is_equal(600.0)
	assert_float(t.eye.radius_u).is_equal(24.0)
	assert_bool(t.gutter_ember.up_only).is_true()
	assert_bool(t.beacon.up_only).is_false()


func test_the_ember_is_a_2400_kelvin_black_body() -> void:
	var c: Color = _tuning().ember_colour()
	assert_float(c.r).is_equal_approx(1.0, 0.01)
	assert_float(c.g).is_equal_approx(0.61, 0.01)
	assert_float(c.b).is_equal_approx(0.24, 0.01)
	# Cooler is redder, hotter is bluer; a Beacon is near white.
	assert_float(LightKind.kelvin_colour(1800.0).b).is_less(c.b)
	var beacon: Color = _tuning().beacon.colour()
	assert_float(beacon.b).is_greater(0.95)
	assert_float(beacon.r).is_greater(0.9)


func test_the_flicker_swings_four_percent_at_half_a_hertz() -> void:
	var t: LightingTuning = _tuning()
	assert_float(t.energy_at(0.0)).is_equal_approx(t.ember_energy, 0.0001)
	# A quarter of the 2 s period is the crest, three quarters the trough.
	assert_float(t.energy_at(0.5)).is_equal_approx(t.ember_energy * 1.04, 0.0001)
	assert_float(t.energy_at(1.5)).is_equal_approx(t.ember_energy * 0.96, 0.0001)
	assert_float(t.energy_at(2.0)).is_equal_approx(t.ember_energy, 0.0001)
	var f: LightField = _field()
	assert_float(f.ember.energy_at(0.5)).is_equal_approx(t.energy_at(0.5), 0.0001)


func test_the_dark_factor_is_one_at_dusk_and_floors_at_pitch() -> void:
	# docs/adr/0023 Decision 3.5: 1 at D = 1, about 0.68 at Gloam (D = 1.6), the floor from Pitch.
	var t: LightingTuning = _tuning()
	assert_float(t.dark_factor(1.0)).is_equal(1.0)
	assert_float(t.dark_factor(1.6)).is_equal_approx(0.682, 0.001)
	assert_float(t.dark_factor(2.6)).is_equal_approx(0.15, 0.005)
	assert_float(t.dark_factor(4.0)).is_equal(0.15)
	assert_float(t.dark_factor(0.0)).is_greater(1.0)
	assert_float(t.dark_factor(10.0)).is_equal(0.15)


func test_a_bad_tuning_is_reported() -> void:
	var t := LightingTuning.new()
	t.dark_floor = 1.5
	t.ember_radius_u = 0.0
	t.max_lights = 40
	t.sdf_texel_u = 0.1
	# Four light kinds missing, and the four above.
	assert_int(t.validate().size()).is_equal(8)
	var k := LightKind.new()
	k.id = &"x"
	k.shadow_channel = 7
	k.flicker_amplitude = 2.0
	assert_int(k.validate().size()).is_equal(2)


func test_the_light_words_are_pitch_and_dusk() -> void:
	assert_float(LightField.level_for_word("pitch")).is_greater_equal(2.6)
	assert_float(LightField.level_for_word("dusk")).is_equal(1.0)
	assert_float(LightField.level_for_word("")).is_less(0.0)
	assert_float(LightField.level_for_word("off")).is_less(0.0)
	assert_float(_tuning().dark_factor(LightField.level_for_word("pitch"))).is_equal(0.15)
	assert_bool(LightField.is_word("pitch")).is_true()
	assert_bool(LightField.is_word("noon")).is_false()
	assert_bool(LightField.asks_for_pitch("pitch")).is_true()
	assert_bool(LightField.asks_for_pitch("dusk")).is_false()


func test_a_fixture_asks_for_pitch_and_the_stress_run_does() -> void:
	var run: Fixture = Fixture.parse_file("res://tests/perf/stress_run.fixture")
	assert_array(Array(run.errors)).is_empty()
	assert_str(run.lighting).is_equal("pitch")
	var pin: Fixture = Fixture.parse_file("res://tests/replay/perf/stress_pin.fixture")
	assert_str(pin.lighting).is_equal("")


# --- The shapes of a room -------------------------------------------------------------------------


func test_wall_tiles_merge_into_the_fewest_rectangles() -> void:
	var g: TileGrid = _grid(["........", "..##....", "..##....", "########", "########"])
	var s: RoomSdf = RoomSdf.from_grid(g, 64.0, 4.0)
	# The two-by-two block is one rectangle, the floor another; plus the border's four bands.
	assert_int(s.count_of(RoomSdf.SOLID_RECT)).is_equal(2 + 4)
	var band: float = (
		2.0 * (8.0 * 32.0 + 128.0) * 64.0 + 2.0 * (5.0 * 32.0) * 64.0
	)
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
	assert_float(s.distance(inside)).is_equal_approx(-((inside.x + inside.y) - 160.0) / sqrt(2.0), 0.01)


func test_the_field_is_lipschitz_and_agrees_with_the_tiles_on_the_sign() -> void:
	var g: TileGrid = _grid(
		["........", "..##....", "..#/....", ".\\##.../", "########"]
	)
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


func _twin(rows: Array[String]) -> ShadowTwin:
	return ShadowTwin.new(RoomSdf.from_grid(_grid(rows), 64.0, 4.0), _tuning())


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
	var tw: ShadowTwin = _twin(["................", "................", "................", "................"])
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


# --- The field ------------------------------------------------------------------------------------


func test_the_ember_is_the_first_light_and_follows_the_player() -> void:
	var f: LightField = _field()
	var t: LightingTuning = _tuning()
	f.present(30, 0.0, Vector2(100.0, 50.0))
	assert_int(f.lights_in_table).is_equal(1)
	assert_float(_cell(f, 0, 0, 0)).is_equal(100.0)
	assert_float(_cell(f, 0, 0, 1)).is_equal(50.0)
	assert_float(_cell(f, 0, 0, 2)).is_equal_approx(420.0, 0.0001)
	assert_float(_cell(f, 0, 0, 3)).is_equal_approx(40.0, 0.0001)
	# The tick is half a second: the crest of the flicker, in the ember's colour.
	var energy: float = t.ember_energy * 1.04
	var colour: Color = t.ember_colour()
	assert_float(_cell(f, 1, 0, 0)).is_equal_approx(colour.r * energy, 0.001)
	assert_float(_cell(f, 1, 0, 1)).is_equal_approx(colour.g * energy, 0.001)
	assert_float(_cell(f, 1, 0, 2)).is_equal_approx(colour.b * energy, 0.001)
	# It casts, on channel 0.
	assert_float(_cell(f, 1, 0, 3)).is_equal(float(LightField.FLAG_SHADOW))
	assert_float(_cell(f, 2, 0, 0)).is_equal_approx(t.falloff_power, 0.0001)
	assert_float(_cell(f, 2, 0, 1)).is_equal_approx(t.light_r_u, 0.0001)


func test_the_light_depends_on_the_tick_and_nothing_else() -> void:
	var a: LightField = _field()
	var b: LightField = _field()
	a.present(77, 0.25, Vector2(10.0, 20.0))
	b.present(76, 0.0, Vector2(10.0, 20.0))
	b.present(77, 0.25, Vector2(10.0, 20.0))
	assert_array(Array(a.table())).is_equal(Array(b.table()))
	# A later tick flickers differently.
	b.present(78, 0.25, Vector2(10.0, 20.0))
	assert_float(_cell(b, 1, 0, 0)).is_not_equal(_cell(a, 1, 0, 0))


func test_a_frozen_field_ignores_the_tick_it_is_given() -> void:
	var f: LightField = _field()
	f.freeze(30, 0.15)
	f.present(5, 0.5, Vector2.ZERO)
	var first: PackedFloat32Array = f.table().duplicate()
	f.present(900, 0.9, Vector2.ZERO)
	assert_array(Array(f.table())).is_equal(Array(first))
	assert_float(f.dark_factor).is_equal(0.15)
	f.thaw()
	f.present(900, 0.9, Vector2.ZERO)
	assert_array(Array(f.table())).is_not_equal(Array(first))


func test_lights_beyond_the_view_are_left_out_and_others_are_kept() -> void:
	var f: LightField = _field()
	var t: LightingTuning = _tuning()
	f.present(0, 0.0, Vector2(500.0, 500.0))
	var view: Rect2 = f.view_rect()
	var near: WaneLight = f.spawn_light(t.fire, view.get_center())
	var far: WaneLight = f.spawn_light(t.fire, view.end + Vector2(5000.0, 5000.0))
	f.present(0, 0.0, Vector2(500.0, 500.0))
	assert_int(f.lights_in_table).is_equal(2)
	assert_float(_cell(f, 0, 1, 0)).is_equal(near.position.x)
	f.remove_light(near)
	f.remove_light(far)
	f.present(0, 0.0, Vector2(500.0, 500.0))
	assert_int(f.lights_in_table).is_equal(1)


func test_the_table_holds_sixteen_ranked_ember_beacons_fire_gutter_eyes() -> void:
	var f: LightField = _field()
	var t: LightingTuning = _tuning()
	f.present(0, 0.0, Vector2(500.0, 500.0))
	var c: Vector2 = f.view_rect().get_center()
	# Twenty eyes first, then one of each other kind: the eyes lose their places.
	for i: int in range(20):
		f.spawn_light(t.eye, c + Vector2(float(i), 0.0))
	f.spawn_light(t.gutter_ember, c)
	f.spawn_light(t.fire, c)
	f.spawn_light(t.beacon, c)
	f.present(0, 0.0, Vector2(500.0, 500.0))
	assert_int(f.lights_in_table).is_equal(16)
	# Radius says which is which: ember, Beacon, fire, Gutter Ember, then eyes.
	assert_float(_cell(f, 0, 0, 2)).is_equal(t.ember_radius_u)
	assert_float(_cell(f, 0, 1, 2)).is_equal(t.beacon.radius_u)
	assert_float(_cell(f, 0, 2, 2)).is_equal(t.fire.radius_u)
	assert_float(_cell(f, 0, 3, 2)).is_equal(t.gutter_ember.radius_u)
	assert_float(_cell(f, 0, 4, 2)).is_equal(t.eye.radius_u)


func test_each_shadow_channel_goes_to_one_light() -> void:
	var f: LightField = _field()
	var t: LightingTuning = _tuning()
	f.present(0, 0.0, Vector2(500.0, 500.0))
	var c: Vector2 = f.view_rect().get_center()
	f.spawn_light(t.beacon, c)
	f.spawn_light(t.fire, c + Vector2(10.0, 0.0))
	f.spawn_light(t.fire, c + Vector2(20.0, 0.0))
	f.spawn_light(t.gutter_ember, c)
	f.spawn_light(t.eye, c)
	f.present(0, 0.0, Vector2(500.0, 500.0))
	var flags: Array[int] = []
	for i: int in range(f.lights_in_table):
		flags.append(int(_cell(f, 1, i, 3)))
	# Ember ch 0, Beacon ch 1, the first fire ch 2, the second fire casts nothing, the Gutter Ember
	# ch 3 and lights up only, the eye casts nothing.
	assert_int(flags[0]).is_equal(LightField.FLAG_SHADOW | (0 << 1))
	assert_int(flags[1]).is_equal(LightField.FLAG_SHADOW | (1 << 1))
	assert_int(flags[2]).is_equal(LightField.FLAG_SHADOW | (2 << 1))
	assert_int(flags[3]).is_equal(0)
	assert_int(flags[4]).is_equal(LightField.FLAG_SHADOW | (3 << 1) | LightField.FLAG_UP_ONLY)
	assert_int(flags[5]).is_equal(0)
	assert_int(f.casters().size()).is_equal(4)
	assert_float(f.casters()[3].z).is_equal(t.gutter_ember.radius_u)


func test_the_minimum_profile_casts_from_three_lights_and_a_smaller_buffer() -> void:
	var t: LightingTuning = _tuning()
	assert_float(t.shadow_scale(LightingTuning.PROFILE_PC)).is_equal(1.0)
	assert_float(t.shadow_scale(LightingTuning.PROFILE_DECK)).is_equal(0.75)
	assert_float(t.shadow_scale(LightingTuning.PROFILE_MIN)).is_equal(0.5)
	assert_int(t.casters(LightingTuning.PROFILE_PC)).is_equal(4)
	assert_int(t.casters(LightingTuning.PROFILE_MIN)).is_equal(3)
	var f: LightField = _field(LightingTuning.PROFILE_MIN)
	f.present(0, 0.0, Vector2(500.0, 500.0))
	var c: Vector2 = f.view_rect().get_center()
	f.spawn_light(t.gutter_ember, c)
	f.present(0, 0.0, Vector2(500.0, 500.0))
	# The Gutter Ember is on channel 3: with three casters it still lights, but casts no shadow.
	assert_int(int(_cell(f, 1, 1, 3)) & LightField.FLAG_SHADOW).is_equal(0)
	assert_int(int(_cell(f, 1, 1, 3)) & LightField.FLAG_UP_ONLY).is_equal(LightField.FLAG_UP_ONLY)


func test_ambient_is_the_zones_colour_times_the_dark() -> void:
	var f: LightField = _field()
	f.set_zone_ambient(Color(0.5, 0.4, 0.8))
	f.set_dark_level(1.0)
	f.present(0, 0.0, Vector2.ZERO)
	var a: Color = f.globals["wane_ambient"]
	assert_float(a.r).is_equal_approx(0.5, 0.001)
	f.set_dark_level(3.0)
	f.present(0, 0.0, Vector2.ZERO)
	a = f.globals["wane_ambient"]
	assert_float(a.r).is_equal_approx(0.075, 0.001)
	assert_float(a.b).is_equal_approx(0.12, 0.001)
	var dark: float = f.globals["wane_dark"]
	assert_float(dark).is_equal_approx(0.15, 0.001)


func test_the_ember_and_the_boil_are_globals_of_the_tick() -> void:
	var f: LightField = _field()
	f.present(60, 0.0, Vector2(12.0, 34.0))
	var e: Vector4 = f.globals["wane_ember"]
	assert_float(e.x).is_equal(12.0)
	assert_float(e.y).is_equal(34.0)
	assert_float(e.z).is_equal_approx(420.0, 0.0001)
	assert_float(e.w).is_equal_approx(_tuning().energy_at(1.0), 0.0001)
	# 12 reseeds a second: tick 60 is boil step 12.
	assert_float(_global_float(f, "wane_boil")).is_equal(12.0)
	assert_float(_global_float(f, "wane_time")).is_equal(1.0)
	f.present(64, 0.0, Vector2.ZERO)
	assert_float(_global_float(f, "wane_boil")).is_equal(12.0)
	f.present(65, 0.0, Vector2.ZERO)
	assert_float(_global_float(f, "wane_boil")).is_equal(13.0)


func test_every_global_the_shaders_read_is_declared_and_set() -> void:
	var inc: String = FileAccess.get_file_as_string(
		"res://shaders/lighting/light_common.gdshaderinc"
	)
	var re := RegEx.new()
	re.compile("global uniform \\w+ (wane_\\w+)")
	var names: Array[String] = []
	for m: RegExMatch in re.search_all(inc):
		names.append(m.get_string(1))
	assert_int(names.size()).is_equal(12)
	for n: String in names:
		assert_bool(ProjectSettings.has_setting("shader_globals/%s" % n)).is_true()
	var field_src: String = FileAccess.get_file_as_string("res://game/lighting/light_field.gd")
	for n: String in names:
		assert_bool(field_src.contains('"%s"' % n)).is_true()


func test_no_shader_reads_a_clock_and_none_uses_godots_lights() -> void:
	# docs/adr/0023 Decision 6.2: everything time-varying derives from the tick, so a render is
	# reproducible; Decision 3.2: the game has no Light2D, no occluder, no CanvasModulate.
	var time_re := RegEx.new()
	time_re.compile("\\bTIME\\b")
	var checked: int = 0
	for dir: String in ["res://shaders/lighting", "res://shaders/post"]:
		for file: String in DirAccess.get_files_at(dir):
			var src: String = FileAccess.get_file_as_string("%s/%s" % [dir, file])
			var code: PackedStringArray = []
			for line: String in src.split("\n"):
				code.append(line.get_slice("//", 0))
			assert_object(time_re.search("\n".join(code))).is_null()
			assert_bool(src.contains("void light()")).is_false()
			checked += 1
	assert_int(checked).is_greater_equal(6)
	for path: String in _gd_files("res://game"):
		var src: String = FileAccess.get_file_as_string(path)
		for banned: String in ["PointLight2D", "DirectionalLight2D", "LightOccluder2D", "CanvasModulate"]:
			if src.contains(banned) and not path.ends_with("light_field.gd"):
				assert_str("%s uses %s" % [path, banned]).is_empty()
	var own: String = FileAccess.get_file_as_string("res://game/lighting/light_field.gd")
	for banned: String in ["PointLight2D = ", "LightOccluder2D.new", "CanvasModulate.new"]:
		assert_bool(own.contains(banned)).is_false()


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append("%s/%s" % [dir, f])
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files("%s/%s" % [dir, d]))
	return out


# --- Rooms: built once, never on a door frame -----------------------------------------------------


func test_a_prebuilt_room_is_shown_without_building_anything() -> void:
	# A door crossing must cost no rebuild (docs/adr/0020, the door spike): the field of a room
	# prebuilt ahead of the crossing is only pointed at.
	var f: LightField = _field()
	var a: TileGrid = _grid(["....", "####"])
	var b: TileGrid = _grid(["....", "....", "#..#", "####"])
	f.prebuild("a", a)
	f.prebuild("b", b)
	var built: int = f.rooms_built
	assert_int(built).is_equal(2)
	f.show_world(CollisionWorld.new(a), "a")
	f.show_world(CollisionWorld.new(b), "b")
	f.show_world(CollisionWorld.new(a), "a")
	assert_int(f.rooms_built).is_equal(built)
	assert_object(f.shown_field()).is_same(f.field_of("a"))


func test_a_prebuilt_room_whose_grid_was_edited_is_rebuilt_not_shown_stale() -> void:
	# The field assumes the grid never changes; nothing enforces that, so an edit (the room
	# editor's, or any later runtime change) must show up in the shadows instead of casting them
	# from tiles that are gone.
	var f: LightField = _field()
	var a: TileGrid = _grid(["....", "####"])
	f.prebuild("a", a)
	var built0: int = f.rooms_built
	f.show_world(CollisionWorld.new(a), "a")
	var old_field: RoomSdf = f.shown_field()
	assert_int(f.rooms_built).is_equal(built0)
	a.set_tile(1, 0, TileGrid.SOLID)
	f.show_world(CollisionWorld.new(a), "a")
	assert_int(f.rooms_built).is_equal(built0 + 1)
	assert_object(f.shown_field()).is_not_same(old_field)
	assert_float(f.shown_field().distance(Vector2(48.0, 16.0))).is_less(0.0)
	var again: int = f.rooms_built
	f.show_world(CollisionWorld.new(a), "a")
	assert_int(f.rooms_built).is_equal(again)


func test_an_unprepared_room_is_built_once_and_kept() -> void:
	var f: LightField = _field()
	var a: TileGrid = _grid(["....", "####"])
	f.show_world(CollisionWorld.new(a), "a")
	assert_int(f.rooms_built).is_equal(1)
	f.show_world(CollisionWorld.new(_grid(["...", "###"])), "b")
	f.show_world(CollisionWorld.new(a), "a")
	assert_int(f.rooms_built).is_equal(2)


func test_a_room_without_an_id_is_built_afresh_and_not_kept() -> void:
	var f: LightField = _field()
	var a: TileGrid = _grid(["....", "####"])
	f.show_world(CollisionWorld.new(a))
	f.show_world(CollisionWorld.new(a))
	assert_int(f.rooms_built).is_equal(2)
	assert_object(f.field_of("")).is_null()


func test_solid_boxes_are_occluders_until_they_burn_away() -> void:
	var world := CollisionWorld.new(_grid(["....", "####"]))
	var box: SolidBox = SolidBox.make(32 * Fx.SUB, 0, 64 * Fx.SUB, 32 * Fx.SUB)
	world.solids.append(box)
	var f: LightField = _field()
	f.show_world(world)
	var list: Array[Vector4] = f.occluders()
	assert_int(list.size()).is_equal(1)
	assert_vector(Vector2(list[0].x, list[0].y)).is_equal(Vector2(48.0, 16.0))
	assert_vector(Vector2(list[0].z, list[0].w)).is_equal(Vector2(16.0, 16.0))
	box.enabled = false
	assert_int(f.occluders().size()).is_equal(0)
	box.enabled = true
	f.set_occluders([Vector4(0.0, 0.0, 5.0, -1.0)])
	assert_int(f.occluders().size()).is_equal(2)


func test_no_more_than_sixteen_occluders_reach_the_march_nearest_first() -> void:
	var f: LightField = _field()
	var extra: Array[Vector4] = []
	for i: int in range(24):
		extra.append(Vector4(float(i) * 100.0, 0.0, 10.0, 10.0))
	f.set_occluders(extra)
	f.present(0, 0.0, Vector2(0.0, 0.0))
	var list: Array[Vector4] = f.occluders()
	assert_int(list.size()).is_equal(ShadowBuffer.MAX_OCCLUDERS)
	for o: Vector4 in list:
		assert_float(o.x).is_less(1600.0)


func test_the_boot_scene_prebuilds_every_room_and_a_crossing_builds_nothing() -> void:
	var made: Node = auto_free(_main_scene().instantiate())
	var main: Main = made as Main
	Main.scenario_override = Scenario.make(1, "zone1/01_dash_slash")
	Main.lighting_word = "pitch"
	main.save_on_exit = false
	add_child(main)
	Main.scenario_override = null
	Main.lighting_word = ""
	var zone: ZoneDef = load("res://content/zones/zone1.tres") as ZoneDef
	assert_int(main.lighting.rooms_built).is_greater_equal(zone.rooms.size())
	var built: int = main.lighting.rooms_built
	for id: String in zone.rooms:
		main.enter_room(Simulation.new(Scenario.make(1, id)))
	assert_int(main.lighting.rooms_built).is_equal(built)


# --- The game -------------------------------------------------------------------------------------


func test_the_game_is_always_lit_and_starts_at_dusk() -> void:
	var main: Main = _lit_main("")
	await get_tree().process_frame
	assert_object(main.lighting).is_not_null()
	assert_float(main.lighting.dark_factor).is_equal(1.0)


func test_a_harness_can_hold_the_game_at_pitch_or_turn_the_lighting_off() -> void:
	var lit: Main = _lit_main("pitch")
	assert_float(lit.lighting.dark_factor).is_equal(0.15)
	var dark: Main = _lit_main("off")
	assert_object(dark.lighting).is_null()


func test_a_harness_can_start_the_stress_room_under_pitch_and_read_the_step_time() -> void:
	# What tools/bench/frame_bench.gd does: the boot scene on the stress scenario, lit.
	var run: Fixture = Fixture.parse_file("res://tests/perf/stress_run.fixture")
	Main.scenario_override = run.scenario.copy()
	Main.lighting_word = run.lighting
	var made: Node = auto_free(_main_scene().instantiate())
	var main: Main = made as Main
	main.save_on_exit = false
	add_child(main)
	Main.scenario_override = null
	Main.lighting_word = ""
	assert_object(main.lighting).is_not_null()
	assert_array(Array(main.driver.sim.load_errors)).is_empty()
	assert_int(main.driver.sim.combat.enemies.size()).is_equal(200)
	main.driver.set_process(false)
	main.driver.step_once()
	assert_int(main.driver.last_step_us).is_greater(0)
	main.lighting.present(1, 1.0, Vector2(100.0, 100.0))
	assert_int(main.lighting.rooms_built).is_greater(0)
	assert_float(main.lighting.dark_factor).is_equal(0.15)


func test_what_is_light_is_emissive_and_what_is_a_surface_is_lit() -> void:
	var emissive: Array[CanvasItem] = [VfxBudget.new(), CombatView.new()]
	for v: CanvasItem in emissive:
		add_child(v)
		auto_free(v)
		var m: ShaderMaterial = v.material as ShaderMaterial
		assert_object(m).is_not_null()
		assert_str(m.shader.resource_path).is_equal(LightField.EMISSIVE_SHADER)
	var enemies := EnemyView.new()
	add_child(enemies)
	auto_free(enemies)
	var cues: CanvasItem = enemies.get_child(0) as CanvasItem
	assert_str((cues.material as ShaderMaterial).shader.resource_path).is_equal(
		LightField.EMISSIVE_SHADER
	)
	assert_str((enemies.material as ShaderMaterial).shader.resource_path).is_equal(
		LightField.LIT_SHADER
	)
	var tiles := RoomView.new()
	add_child(tiles)
	auto_free(tiles)
	var tm: ShaderMaterial = tiles.material as ShaderMaterial
	var bevel: bool = tm.get_shader_parameter("sdf_normals")
	assert_bool(bevel).is_true()
	var player := PlayerView.new()
	add_child(player)
	auto_free(player)
	var flat: Variant = (player.material as ShaderMaterial).get_shader_parameter("sdf_normals")
	assert_bool(flat == null or flat == false).is_true()
