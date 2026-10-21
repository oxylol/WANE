extends GdUnitTestSuite
## The art build's data textures reach the GPU unaltered (ADR-0023 Decision 1.3): Godot's import
## must be lossless, with no mipmaps and no alpha-border fix (which rewrites the colour of the
## zero-alpha texels that carry most of the distance data).

const SHEET_DIR: String = "res://tests/art/build/candle_stump/"
const SCALES: Array[int] = [1, 2]
const KINDS: Array[String] = ["shape", "normal", "parts"]


func _png_path(scale: int, kind: String) -> String:
	return "%scandle_stump@%dx.%s.png" % [SHEET_DIR, scale, kind]


func test_imported_textures_equal_their_png_files() -> void:
	for scale: int in SCALES:
		for kind: String in KINDS:
			var path: String = _png_path(scale, kind)
			var texture: Texture2D = load(path) as Texture2D
			assert_object(texture).override_failure_message("not imported: " + path).is_not_null()
			var imported: Image = texture.get_image()
			var raw: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
			imported.convert(Image.FORMAT_RGBA8)
			raw.convert(Image.FORMAT_RGBA8)
			assert_vector(Vector2(imported.get_size())).is_equal(Vector2(raw.get_size()))
			(
				assert_bool(imported.get_data() == raw.get_data())
				. override_failure_message("%s changed by the import" % path)
				. is_true()
			)


func test_a_zero_alpha_texel_keeps_its_data() -> void:
	## shape.png's alpha is the emissive coverage, zero on most of the sheet, while R and G hold
	## S and U: a texel far from any silhouette must still read S saturated (255).
	var texture: Texture2D = load(_png_path(1, "shape")) as Texture2D
	var image: Image = texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	var corner: Color = image.get_pixel(0, 0)
	assert_int(corner.a8).is_equal(0)
	assert_int(corner.r8).is_equal(255)
	assert_int(corner.g8).is_equal(255)
