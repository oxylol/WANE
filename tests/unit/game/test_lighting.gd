extends GdUnitTestSuite
## The lighting pass's numbers and its seams with the game (game/lighting, shaders/lighting;
## docs/adr/0023; BUILD.md section 10, Lighting: ember radius 420 u, warm 2400 K, flicker 0.5 Hz at
## 4%, "a per-zone ambient colour multiplied by the Wane Clock's darkness factor ... At Pitch,
## ambient is 0.15 and the world is the ember"). Headless: the shapes and the table are
## test_room_sdf.gd and test_light_field.gd; the GPU half (the bake and the buffer against the
## twin, the shaders compiling) is tools/lighting/gpu_check.gd, run by ci/lighting.sh.

const STRESS_ROOM: String = "perf/stress"


func _main_scene() -> PackedScene:
	return load("res://game/main.tscn") as PackedScene


func _tuning() -> LightingTuning:
	return load(LightingTuning.PATH) as LightingTuning


func _lit_main(word: String) -> Main:
	Main.lighting_word = word
	var made: Node = auto_free(_main_scene().instantiate())
	var main: Main = made as Main
	main.save_on_exit = false
	add_child(main)
	Main.lighting_word = ""
	return main


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
	# 8 u was the ADR's start; 14 u widens the penumbra of the shadow edges (feel log, docs/adr/0026).
	assert_float(t.light_r_u).is_equal(14.0)
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
	var f := LightField.new()
	auto_free(f)
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
	assert_float(LightWord.level_for("pitch")).is_greater_equal(2.6)
	assert_float(LightWord.level_for("dusk")).is_equal(1.0)
	assert_float(LightWord.level_for("")).is_less(0.0)
	assert_float(LightWord.level_for("off")).is_less(0.0)
	assert_float(_tuning().dark_factor(LightWord.level_for("pitch"))).is_equal(0.15)
	assert_bool(LightWord.is_word("pitch")).is_true()
	assert_bool(LightWord.is_word("noon")).is_false()
	assert_float(LightWord.level_or_dusk("")).is_equal(1.0)
	assert_float(LightWord.level_or_dusk("pitch")).is_equal(3.0)


func test_a_fixture_asks_for_pitch_and_the_stress_run_does() -> void:
	var run: Fixture = Fixture.parse_file("res://tests/perf/stress_run.fixture")
	assert_array(Array(run.errors)).is_empty()
	assert_str(run.lighting).is_equal("pitch")
	var pin: Fixture = Fixture.parse_file("res://tests/replay/perf/stress_pin.fixture")
	assert_str(pin.lighting).is_equal("")


func test_every_global_the_shaders_read_is_declared_and_set() -> void:
	var inc: String = FileAccess.get_file_as_string(
		"res://shaders/lighting/light_common.gdshaderinc"
	)
	var re := RegEx.new()
	re.compile("global uniform \\w+ (wane_\\w+)")
	var names: Array[String] = []
	for m: RegExMatch in re.search_all(inc):
		names.append(m.get_string(1))
	assert_int(names.size()).is_equal(14)
	for n: String in names:
		assert_bool(ProjectSettings.has_setting("shader_globals/%s" % n)).is_true()
	var field_src: String = FileAccess.get_file_as_string("res://game/lighting/light_field.gd")
	for n: String in names:
		assert_bool(field_src.contains('"%s"' % n)).is_true()


func test_the_declared_shape_globals_equal_the_tuning() -> void:
	# The shape of the lighting (docs/adr/0026) is content, not a literal in the shader: what
	# project.godot declares is what content/lighting.tres says, so an unapplied render is the
	# tuned one.
	var t: LightingTuning = _tuning()
	assert_array(Array(t.validate())).is_empty()
	var shape: Variant = ProjectSettings.get_setting("shader_globals/wane_shape")
	var gate: Variant = ProjectSettings.get_setting("shader_globals/wane_gate")
	var want: Vector4 = t.shape_vec()
	var have: Vector4 = shape["value"]
	assert_float(have.x).is_equal_approx(want.x, 0.00001)
	assert_float(have.y).is_equal_approx(want.y, 0.00001)
	assert_float(have.z).is_equal_approx(want.z, 0.00001)
	assert_float(have.w).is_equal_approx(want.w, 0.00001)
	assert_vector(gate["value"]).is_equal(t.gate_vec())
	# The starting values (docs/adr/0026), the spec until a feel-log entry changes them.
	assert_float(t.flat_share).is_equal(0.35)
	assert_float(t.bevel_tilt).is_equal(0.95)
	assert_float(t.up_only_soft_u).is_equal(8.0)
	assert_float(t.gate_lo).is_equal(0.05)
	assert_float(t.gate_hi).is_equal(0.15)
	assert_float(t.glow_radius_share).is_equal(0.05)
	assert_float(t.glow_strength).is_equal(0.5)
	# 40 degrees above the plane: a flat surface reads sin 40 = 0.64 of any light, above lit_threshold.
	assert_float(rad_to_deg(want.z)).is_equal_approx(40.0, 0.0001)
	var ink: InkTuning = load(InkTuning.PATH) as InkTuning
	assert_float(sin(want.z)).is_greater(ink.lit_threshold + ink.terminator_soft)


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
		for banned: String in [
			"PointLight2D", "DirectionalLight2D", "LightOccluder2D", "CanvasModulate"
		]:
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
		assert_str(m.shader.resource_path).is_equal(LightSurfaces.EMISSIVE_SHADER)
	var enemies := EnemyView.new()
	add_child(enemies)
	auto_free(enemies)
	var cues: CanvasItem = enemies.get_child(0) as CanvasItem
	assert_str((cues.material as ShaderMaterial).shader.resource_path).is_equal(
		LightSurfaces.EMISSIVE_SHADER
	)
	assert_str((enemies.material as ShaderMaterial).shader.resource_path).is_equal(
		LightSurfaces.LIT_SHADER
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
