extends GdUnitTestSuite
## The light field: the table, the ranking and culling, the Dark, the globals, and the rooms it
## builds once and never on a door frame (game/lighting/light_field.gd; docs/adr/0023 Decision 3;
## docs/adr/0020 Decision 19: a door crossing costs no spike). Headless: the script work; the dummy
## renderer draws nothing, so the bake and the buffer are tools/lighting/gpu_check.gd.


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


## The table's value at [param row] and [param col], component [param k] (0 to 3).
func _global_float(f: LightField, global_name: String) -> float:
	var v: float = f.globals[global_name]
	return v


func _cell(f: LightField, row: int, col: int, k: int) -> float:
	return f.table[(row * LightField.TABLE_COLUMNS + col) * 4 + k]


## Twice the signed area of the shape [param i] of [param s], as an absolute area in u squared.

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
	assert_array(Array(a.table)).is_equal(Array(b.table))
	# A later tick flickers differently.
	b.present(78, 0.25, Vector2(10.0, 20.0))
	assert_float(_cell(b, 1, 0, 0)).is_not_equal(_cell(a, 1, 0, 0))


func test_a_frozen_field_ignores_the_tick_it_is_given() -> void:
	var f: LightField = _field()
	f.freeze(30, 0.15)
	f.present(5, 0.5, Vector2.ZERO)
	var first: PackedFloat32Array = f.table.duplicate()
	f.present(900, 0.9, Vector2.ZERO)
	assert_array(Array(f.table)).is_equal(Array(first))
	assert_float(f.dark_factor).is_equal(0.15)
	f.thaw()
	f.present(900, 0.9, Vector2.ZERO)
	assert_array(Array(f.table)).is_not_equal(Array(first))


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
	assert_int(f.casters.size()).is_equal(4)
	assert_float(f.casters[3].z).is_equal(t.gutter_ember.radius_u)


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
	f.ambient_colour = Color(0.5, 0.4, 0.8)
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


func test_the_fields_of_rooms_used_longest_ago_are_let_go_but_never_the_one_on_show() -> void:
	# docs/review F5: the cache of distance fields has an eviction (LightingTuning.fields_kept).
	var f: LightField = _field()
	var kept: int = _tuning().fields_kept
	var grid: TileGrid = _grid(["....", "####"])
	f.show_world(CollisionWorld.new(grid), "room_0")
	for i: int in range(1, kept + 6):
		var g: TileGrid = _grid(["....", "####"])
		f.prebuild("room_%d" % i, g)
	assert_object(f.field_of("room_0")).is_not_null()
	assert_object(f.field_of("room_%d" % (kept + 5))).is_not_null()
	var held: int = 0
	for i: int in range(0, kept + 6):
		if f.field_of("room_%d" % i) != null:
			held += 1
	assert_int(held).is_equal(kept)
	# The oldest of the others went first.
	assert_object(f.field_of("room_1")).is_null()
