extends GdUnitTestSuite
## The ink and gouache shaders (BUILD.md section 10, Style; ADR-0023 Decision 2 and 7.2), headless:
## they compile, every global they read is declared, the numbers validate and reach the shaders,
## nothing in them reads the clock, and the sheet and sprite classes lay a frame out as the ADR
## says. What they draw is tested under a display by tests/screenshot/run_ink_render_tests.gd.

const SPRITE: String = "res://shaders/ink/ink_sprite.gdshader"
const BACKGROUND: String = "res://shaders/ink/ink_background.gdshader"
const COMMON: String = "res://shaders/ink/ink_common.gdshaderinc"
const LIGHT: String = "res://shaders/lighting/light_common.gdshaderinc"
## The material uniforms ADR-0023 Decision 7.2 fixes, plus texel_u (u per texel at the bound scale).
const UNIFORMS: Array[String] = [
	"shape_tex",
	"normal_tex",
	"parts_tex",
	"palette_tex",
	"noise_tex",
	"frame_u",
	"texel_u",
	"carries_ember",
	"palette_row",
	"mode",
]


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _uniform_names(path: String) -> Array[String]:
	var shader: Shader = load(path) as Shader
	var names: Array[String] = []
	for u: Variant in shader.get_shader_uniform_list():
		names.append(str(u["name"]))
	return names


## Names of the `global uniform` declarations in [param text].
func _globals_in(text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("global\\s+uniform\\s+\\w+\\s+(\\w+)")
	for m: RegExMatch in re.search_all(text):
		out.append(m.get_string(1))
	return out


func test_both_shaders_compile_with_the_adr_uniforms() -> void:
	for path: String in [SPRITE, BACKGROUND]:
		var names: Array[String] = _uniform_names(path)
		for u: String in UNIFORMS:
			(
				assert_bool(names.has(u))
				. override_failure_message("%s lacks uniform %s" % [path, u])
				. is_true()
			)
		# A shader that fails to compile lists no uniforms at all, so this is the compile test.
		assert_int(names.size()).is_equal(UNIFORMS.size())


func test_every_global_the_shaders_read_is_declared_in_the_project() -> void:
	var all: Array[String] = []
	for path: String in [COMMON, LIGHT]:
		all.append_array(_globals_in(_text(path)))
	assert_int(all.size()).is_greater(10)
	for g: String in all:
		(
			assert_bool(ProjectSettings.has_setting("shader_globals/%s" % g))
			. override_failure_message(
				(
					"global %s is read by a shader but not declared in project.godot [shader_globals]"
					% g
				)
			)
			. is_true()
		)


func test_the_shaders_are_unshaded_and_have_no_clock() -> void:
	for path: String in [SPRITE, BACKGROUND]:
		assert_bool(_text(path).contains("render_mode unshaded")).is_true()
	for path: String in [SPRITE, BACKGROUND, COMMON, LIGHT]:
		var text: String = _text(path)
		var re := RegEx.new()
		re.compile("\\bTIME\\b")
		(
			assert_object(re.search(text))
			. override_failure_message(
				(
					"%s reads TIME: every time-varying value comes from the tick (ADR-0023 Decision 6.2)"
					% path
				)
			)
			. is_null()
		)


func test_the_decode_constants_are_the_adrs() -> void:
	var text: String = _text(COMMON)
	assert_bool(text.contains("const float INK_S_ZERO = 128.0;")).is_true()
	assert_bool(text.contains("const float INK_S_STEPS_PER_U = 16.0;")).is_true()
	assert_bool(text.contains("const float INK_U_STEPS_PER_U = 16.0;")).is_true()
	assert_bool(text.contains("const float INK_WOBBLE1_CELLS = 16.0;")).is_true()
	assert_bool(text.contains("const float INK_WOBBLE2_CELLS = 32.0;")).is_true()


func test_the_tuning_validates_and_matches_the_sections_numbers() -> void:
	var t: InkTuning = load(InkTuning.PATH) as InkTuning
	assert_array(Array(t.validate())).is_empty()
	# ADR-0023 Decisions 2.1, 2.2, 2.4 and 3: the starting values.
	assert_vector(Vector2(t.line_lit_u, t.line_shadow_u)).is_equal(Vector2(0.3, 1.3))
	assert_float(t.line_min_px).is_equal(0.8)
	assert_float(t.wobble_u).is_equal(0.22)
	assert_vector(Vector2(t.wave1_u, t.wave2_u)).is_equal(Vector2(10.0, 4.0))
	assert_float(t.boil_hz).is_equal(12.0)
	assert_float(t.lit_threshold).is_equal(0.20)
	assert_float(t.edge_dark).is_equal(0.22)
	assert_float(t.grain_strength).is_equal(0.07)
	assert_float(t.rim_u).is_equal(1.2)
	assert_float(t.brush_stretch).is_equal(14.0)
	assert_float(t.bg_thin).is_equal(0.35)
	assert_vector(Vector2(t.bg_break_lo, t.bg_break_hi)).is_equal(Vector2(0.42, 0.5))
	assert_vector(Vector2(t.bg_drop_lo, t.bg_drop_hi)).is_equal(Vector2(0.15, 0.55))


func test_a_bad_tuning_is_refused() -> void:
	var t: InkTuning = InkTuning.new()
	t.line_shadow_u = 0.1
	t.terminator_soft = 0.5
	t.boil_hz = 0.0
	assert_int(t.validate().size()).is_equal(3)


func test_the_declared_globals_equal_the_tuning_so_an_unapplied_render_is_the_tuned_one() -> void:
	var t: InkTuning = load(InkTuning.PATH) as InkTuning
	for global_name: StringName in InkGlobals.PACKED:
		var declared: Variant = ProjectSettings.get_setting("shader_globals/%s" % global_name)
		assert_bool(declared is Dictionary).is_true()
		var have: Vector4 = declared["value"]
		var want: Vector4 = t.call(InkGlobals.PACKED[global_name])
		(
			assert_vector(have)
			. override_failure_message(
				"%s in project.godot differs from content/art/ink.tres" % global_name
			)
			. is_equal(want)
		)


func test_every_packed_global_has_a_packing_and_apply_writes_them() -> void:
	# The dummy renderer keeps no global values, so what apply writes is read back under a display
	# (tests/screenshot/run_ink_render_tests.gd); here every global is declared and packed.
	var t: InkTuning = load(InkTuning.PATH) as InkTuning
	assert_int(InkGlobals.PACKED.size()).is_equal(7)
	for global_name: StringName in InkGlobals.PACKED:
		assert_bool(t.has_method(InkGlobals.PACKED[global_name])).is_true()
		assert_int(typeof(t.call(InkGlobals.PACKED[global_name]))).is_equal(TYPE_VECTOR4)
	InkGlobals.apply(t)


func test_the_boil_step_is_the_tick_over_the_boil_rate() -> void:
	# 12 Hz at 60 ticks a second: a new wobble every fifth tick.
	assert_float(InkGlobals.boil_step(0, 12.0)).is_equal(0.0)
	assert_float(InkGlobals.boil_step(4, 12.0)).is_equal(0.0)
	assert_float(InkGlobals.boil_step(5, 12.0)).is_equal(1.0)
	assert_float(InkGlobals.boil_step(60, 12.0)).is_equal(12.0)
	assert_float(InkGlobals.boil_step(3600, 12.0)).is_equal(720.0)
	InkGlobals.set_tick(65, 12.0)


func test_the_probe_bakes_the_channel_layout() -> void:
	var images: Dictionary[StringName, Image] = InkProbe.bake(
		InkProbe.figure_prims(), InkProbe.FIGURE_CELL_U, 1
	)
	var shape: Image = images[&"shape"]
	var o: Vector2i = Vector2i(InkProbe.FIGURE_ORIGIN_U)
	# Inside the head: S negative, so its byte is below 128; the front-side flag is set only on the
	# pixels of the part that owns the nearest visible edge.
	var head: Color = shape.get_pixel(o.x, o.y - 54)
	assert_float(head.r * 255.0).is_less(128.0)
	# Far from everything: S positive at its range, U saturated.
	var far: Color = shape.get_pixel(2, 2)
	assert_float(far.r * 255.0).is_greater(200.0)
	assert_float(far.g * 255.0).is_greater(200.0)
	# The ember is the only emissive part.
	var ember: Color = shape.get_pixel(o.x, o.y - 30)
	assert_float(ember.a).is_greater(0.9)
	assert_float(shape.get_pixel(o.x, o.y - 54).a).is_equal(0.0)
	# The parts image names the ember's palette column and the blade's flag.
	var parts: Image = images[&"parts"]
	assert_int(roundi(parts.get_pixel(o.x, o.y - 30).r * 255.0)).is_equal(8)
	assert_int(roundi(parts.get_pixel(o.x + 25, o.y - 42).a * 255.0) & 2).is_equal(2)
	# The normal map faces the viewer in the middle of a part and tilts outward at its edge.
	var normal: Image = images[&"normal"]
	var mid: Color = normal.get_pixel(o.x, o.y - 54)
	var rim: Color = normal.get_pixel(o.x + 10, o.y - 54)
	assert_float(mid.b).is_greater(0.95)
	assert_float(rim.r).is_greater(0.6)


func test_the_probe_noise_is_tileable_and_deterministic() -> void:
	for cells: int in [16, 32, 64, 128]:
		# The texel just past the last one is the first again, so the edge has no seam.
		var step: float = absf(
			InkProbe.value_noise(255, 17, cells, 3) - InkProbe.value_noise(0, 17, cells, 3)
		)
		var inside: float = absf(
			InkProbe.value_noise(100, 17, cells, 3) - InkProbe.value_noise(101, 17, cells, 3)
		)
		assert_float(step).is_less(maxf(inside, 0.1) * 3.0)
	assert_float(InkProbe.value_noise(10, 20, 32, 4)).is_equal(InkProbe.value_noise(10, 20, 32, 4))
	assert_float(InkProbe.value_noise(10, 20, 32, 4)).is_not_equal(
		InkProbe.value_noise(10, 20, 32, 5)
	)


func test_a_sheet_lays_out_a_frame_at_its_scale() -> void:
	var noise: ImageTexture = InkProbe.noise_texture()
	var sheet: SpriteSheet = InkProbe.figure_sheet(2, noise)
	assert_bool(sheet.is_valid()).is_true()
	assert_vector(sheet.cell_u).is_equal(InkProbe.FIGURE_CELL_U)
	assert_int(sheet.frame_count(&"idle")).is_equal(1)
	assert_that(sheet.frame_rect(&"idle", 0)).is_equal(Rect2i(0, 0, 192, 256))
	var sprite := InkSprite.new()
	sprite.setup(sheet, &"idle")
	# The node stands at the feet pivot and is scaled back to u: 2 texels a u becomes 0.5.
	assert_vector(sprite.scale).is_equal(Vector2(0.5, 0.5))
	assert_vector(sprite.offset).is_equal(-InkProbe.FIGURE_ORIGIN_U * 2.0)
	sprite.facing = -1
	assert_vector(sprite.scale).is_equal(Vector2(-0.5, 0.5))
	sprite.free()


func test_sprites_of_one_family_share_a_material_and_instance_values_ride_on_the_colour() -> void:
	var noise: ImageTexture = InkProbe.noise_texture()
	var sheet: SpriteSheet = InkProbe.figure_sheet(1, noise)
	var a := InkSprite.new()
	var b := InkSprite.new()
	a.setup(sheet, &"idle")
	b.setup(sheet, &"idle")
	assert_object(a.material).is_same(b.material)
	b.carries_ember = true
	assert_object(a.material).is_not_same(b.material)
	b.palette_row = 1
	var row: int = (b.material as ShaderMaterial).get_shader_parameter(&"palette_row")
	assert_int(row).is_equal(1)
	# Neutral instance values: no flash, full emissive, no dissolve, opaque.
	assert_that(a.self_modulate).is_equal(Color(0.0, 1.0, 0.0, 1.0))
	a.flash = 0.5
	a.dissolve = 0.25
	a.opacity = 0.75
	assert_that(a.self_modulate).is_equal(Color(0.5, 1.0, 0.25, 0.75))
	a.free()
	b.free()


func test_a_sheet_reads_the_json_of_adr_1_6() -> void:
	var dir: String = "user://ink_sheet_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var meta: Dictionary[String, Variant] = {
		"version": 1,
		"asset": "t",
		"cell_u": [96, 128],
		"origin_u": [48, 112],
		"actions":
		{
			"run":
			{
				"fps": 24,
				"loop": true,
				"frames":
				[
					{"rect": {"1": [0, 0, 96, 128], "2": [0, 0, 192, 256]}, "ticks": 3},
					{"rect": {"1": [96, 0, 96, 128], "2": [192, 0, 192, 256]}, "ticks": 2},
				],
			}
		},
	}
	var f: FileAccess = FileAccess.open("%s/t.sheet.json" % dir, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	var sheet: SpriteSheet = SpriteSheet.open(dir, "t", 2, null)
	# The textures are not there (nothing was built), which is reported, not crashed on.
	assert_bool(sheet.is_valid()).is_false()
	assert_bool(sheet.has_action(&"run")).is_true()
	assert_int(sheet.frame_count(&"run")).is_equal(2)
	assert_that(sheet.frame_rect(&"run", 1)).is_equal(Rect2i(192, 0, 192, 256))
	assert_int(sheet.frame_ticks(&"run", 0)).is_equal(3)
	assert_bool(sheet.action_loops(&"run")).is_true()
	assert_vector(sheet.origin_u).is_equal(Vector2(48, 112))
	var missing: PackedStringArray = sheet.errors
	assert_bool(missing.size() > 0).is_true()
	assert_bool(SpriteSheet.open(dir, "nothing", 1, null).is_valid()).is_false()


func test_the_project_imports_channel_textures_as_data() -> void:
	# Godot's default import would overwrite the RGB next to every alpha pixel (measured), so the
	# project sets its importer defaults for every texture (ADR-0023 Decision 1.3).
	var defaults: Variant = ProjectSettings.get_setting("importer_defaults/texture")
	assert_bool(defaults is Dictionary).is_true()
	assert_bool(defaults["process/fix_alpha_border"] == false).is_true()
	assert_bool(defaults["process/premult_alpha"] == false).is_true()
	assert_int(defaults["compress/mode"]).is_equal(0)
	assert_bool(defaults["mipmaps/generate"] == false).is_true()


func test_a_channel_texture_that_overrides_the_import_defaults_is_reported() -> void:
	var good: String = (
		"[params]\n\ncompress/mode=0\nmipmaps/generate=false\n"
		+ "process/fix_alpha_border=false\nprocess/premult_alpha=false\n"
	)
	assert_int(SpriteSheet.import_problems(good).size()).is_equal(0)
	var godot_default: String = good.replace("fix_alpha_border=false", "fix_alpha_border=true")
	var problems: PackedStringArray = SpriteSheet.import_problems(godot_default)
	assert_int(problems.size()).is_equal(1)
	assert_bool(problems[0].contains("fix_alpha_border")).is_true()
	var lossy: String = good.replace("compress/mode=0", "compress/mode=2")
	assert_int(SpriteSheet.import_problems(lossy).size()).is_equal(1)
	assert_int(SpriteSheet.import_problems("").size()).is_equal(0)
