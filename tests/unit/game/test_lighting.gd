extends GdUnitTestSuite
## The Phase 1 stand-in lighting (game/lighting; BUILD.md section 10, Lighting: ember radius 420 u,
## warm, flicker 0.5 Hz at 4%, soft shadows against the collision layer, Pitch ambient 0.15).

const STRESS_ROOM: String = "perf/stress"


func _grid(rows: Array[String]) -> TileGrid:
	return TileGrid.from_rows(PackedStringArray(rows))


## Twice the signed area of [param p].
func _area2(p: PackedVector2Array) -> float:
	var a: float = 0.0
	for i: int in range(p.size()):
		var q: Vector2 = p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a)


func test_the_numbers_are_the_sections_and_validate() -> void:
	var t: LightingTuning = load(LightingTuning.PATH) as LightingTuning
	assert_array(Array(t.validate())).is_empty()
	assert_float(t.ember_radius_u).is_equal(420.0)
	assert_float(t.pitch_ambient).is_equal(0.15)
	assert_float(t.flicker_hz).is_equal(0.5)
	assert_float(t.flicker_amplitude).is_equal(0.04)
	assert_float(t.pitch_colour().g).is_equal_approx(0.15 * t.ambient_tint.g, 0.0001)


func test_the_flicker_swings_four_percent_at_half_a_hertz() -> void:
	var t: LightingTuning = load(LightingTuning.PATH) as LightingTuning
	assert_float(t.energy_at(0.0)).is_equal_approx(t.ember_energy, 0.0001)
	# A quarter of the 2 s period is the crest, three quarters the trough.
	assert_float(t.energy_at(0.5)).is_equal_approx(t.ember_energy * 1.04, 0.0001)
	assert_float(t.energy_at(1.5)).is_equal_approx(t.ember_energy * 0.96, 0.0001)
	assert_float(t.energy_at(2.0)).is_equal_approx(t.ember_energy, 0.0001)


func test_a_bad_tuning_is_reported() -> void:
	var t := LightingTuning.new()
	t.pitch_ambient = 1.5
	t.ember_radius_u = 0.0
	t.texture_px = 8
	assert_int(t.validate().size()).is_equal(3)


func test_wall_tiles_merge_into_the_fewest_rectangles() -> void:
	var g: TileGrid = _grid(["........", "..##....", "..##....", "########", "########"])
	var polys: Array[PackedVector2Array] = OccluderBuilder.tile_polygons(g)
	# The two-by-two block is one rectangle, the floor another; the block and floor differ in width.
	assert_int(polys.size()).is_equal(2)
	var area: float = 0.0
	for p: PackedVector2Array in polys:
		area += _area2(p) / 2.0
	assert_float(area).is_equal(float(4 + 16) * 32.0 * 32.0)


func test_smooth_tiles_cast_and_one_ways_spikes_and_pits_do_not() -> void:
	var g: TileGrid = _grid(["S==^~", ".....", "#####"])
	var polys: Array[PackedVector2Array] = OccluderBuilder.tile_polygons(g)
	assert_int(polys.size()).is_equal(2)


func test_a_run_of_slope_tiles_is_one_polygon_along_its_top() -> void:
	# The 1:2 ramp's low and high halves meet at 16 u: one polygon of five points, the shared top
	# point once, covering 256 + 768 square units.
	var g: TileGrid = _grid(["......", "..ab..", ".####.", "######"])
	var polys: Array[PackedVector2Array] = OccluderBuilder.tile_polygons(g)
	var found: Array[PackedVector2Array] = []
	for p: PackedVector2Array in polys:
		if p.size() == 5:
			found.append(p)
	assert_int(found.size()).is_equal(1)
	assert_float(_area2(found[0]) / 2.0).is_equal_approx(1024.0, 0.01)


func test_the_border_is_four_bands_outside_the_room() -> void:
	var g: TileGrid = _grid(["....", "...."])
	var bands: Array[PackedVector2Array] = OccluderBuilder.border_polygons(g, 64.0)
	assert_int(bands.size()).is_equal(4)
	var inside := Rect2(Vector2.ZERO, Vector2(4, 2) * 32.0)
	for b: PackedVector2Array in bands:
		for pt: Vector2 in b:
			assert_bool(inside.grow(-0.5).has_point(pt)).is_false()


func test_the_stress_room_is_a_few_polygons() -> void:
	var room: RoomData = RoomData.load_id(STRESS_ROOM)
	var world: CollisionWorld = room.build_world()
	var rig := LightingRig.new()
	auto_free(rig)
	add_child(rig)
	rig.show_world(world)
	# 128 x 30 tiles, ramps, tiers and ten hung boxes: merged, not one occluder a tile.
	assert_int(rig.polygon_count).is_less(200)
	assert_int(rig.occluder_count).is_equal(rig.polygon_count + world.solids.size())


func test_the_rig_lights_the_player_with_a_soft_shadowed_ember_at_pitch() -> void:
	var rig := LightingRig.new()
	auto_free(rig)
	add_child(rig)
	var t: LightingTuning = rig.tuning
	var ember: PointLight2D = rig.ember()
	assert_bool(ember.shadow_enabled).is_true()
	assert_int(ember.shadow_filter).is_not_equal(Light2D.SHADOW_FILTER_NONE)
	# The light texture spans the radius: its half side is 420 u on screen.
	assert_float(ember.texture_scale * float(ember.texture.get_width()) * 0.5).is_equal_approx(
		t.ember_radius_u, 0.01
	)
	assert_object(rig.ambient().color).is_equal(t.pitch_colour())
	rig.follow(Vector2(100.0, 50.0), 0.5)
	assert_vector(ember.position).is_equal(Vector2(100.0, 50.0))
	assert_float(ember.energy).is_equal_approx(t.ember_energy * 1.04, 0.0001)


func test_a_burnt_solid_box_stops_casting() -> void:
	var world := CollisionWorld.new(_grid(["....", "####"]))
	var box: SolidBox = SolidBox.make(0, 0, 32 * Fx.SUB, 32 * Fx.SUB)
	world.solids.append(box)
	var rig := LightingRig.new()
	auto_free(rig)
	add_child(rig)
	rig.show_world(world)
	var node: LightOccluder2D = rig.find_children("*", "LightOccluder2D", true, false).back()
	assert_bool(node.visible).is_true()
	box.enabled = false
	rig.follow(Vector2.ZERO, 0.016)
	assert_bool(node.visible).is_false()
	box.enabled = true
	rig.follow(Vector2.ZERO, 0.016)
	assert_bool(node.visible).is_true()


func test_a_new_room_replaces_the_occluders() -> void:
	var rig := LightingRig.new()
	auto_free(rig)
	add_child(rig)
	rig.show_world(CollisionWorld.new(_grid(["....", "####"])))
	var first: int = rig.occluder_count
	rig.show_world(CollisionWorld.new(_grid(["....", "....", "####"])))
	assert_int(rig.occluder_count).is_equal(first)
	assert_int(rig.find_children("*", "LightOccluder2D", true, false).size()).is_equal(first)


func test_emissive_things_are_drawn_unshaded() -> void:
	var views: Array[CanvasItem] = [VfxBudget.new(), CombatView.new(), DebugOverlay.new()]
	for v: CanvasItem in views:
		add_child(v)
		auto_free(v)
		var m: CanvasItemMaterial = v.material as CanvasItemMaterial
		assert_object(m).is_not_null()
		assert_int(m.light_mode).is_equal(CanvasItemMaterial.LIGHT_MODE_UNSHADED)
	var enemies := EnemyView.new()
	add_child(enemies)
	auto_free(enemies)
	var cues: CanvasItem = enemies.get_child(0) as CanvasItem
	assert_int((cues.material as CanvasItemMaterial).light_mode).is_equal(
		CanvasItemMaterial.LIGHT_MODE_UNSHADED
	)


func test_a_fixture_asks_for_pitch_and_the_stress_run_does() -> void:
	var run: Fixture = Fixture.parse_file("res://tests/perf/stress_run.fixture")
	assert_array(Array(run.errors)).is_empty()
	assert_str(run.lighting).is_equal("pitch")
	var pin: Fixture = Fixture.parse_file("res://tests/replay/perf/stress_pin.fixture")
	assert_str(pin.lighting).is_equal("")
	assert_bool(LightingRig.asks_for_pitch("pitch")).is_true()
	assert_bool(LightingRig.asks_for_pitch("dusk")).is_false()


func test_the_game_is_unlit_unless_it_is_asked() -> void:
	var main: Node = auto_free((load("res://game/main.tscn") as PackedScene).instantiate())
	add_child(main)
	await get_tree().process_frame
	assert_object(main.get("lighting")).is_null()
