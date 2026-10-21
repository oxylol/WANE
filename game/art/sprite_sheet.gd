class_name SpriteSheet
extends RefCounted
## One asset's baked sheet at one scale (ADR-0023 Decision 1, written by tools/artbuild/): the
## three channel textures, the palette, the frame rectangles and ticks from `<asset>.sheet.json`,
## and the shared ink materials. It draws nothing; InkSprite does.

const SHEET_VERSION: int = 1
const SPRITE_SHADER: String = "res://shaders/ink/ink_sprite.gdshader"
const BACKGROUND_SHADER: String = "res://shaders/ink/ink_background.gdshader"
const NOISE_PATH: String = "res://assets/art/build/noise/noise.png"
## Palette variants a sheet's palette image may hold: four rows each (lit, shadow, rim, emissive).
const PALETTE_ROWS: int = 4


## The frames of one action: the rectangle of each in texels at this scale, the page of the atlas
## it is on and its length in 60 Hz ticks. A cell is per action (the artbuild packs each action's
## frames in a cell of the size that action needs), so the cell and the feet pivot inside it are
## too (sheet.json `cell_u` and `cell_origin_u` of the action).
class ActionFrames:
	extends RefCounted
	var fps: int = 24
	var loop: bool = true
	var rects: Array[Rect2i] = []
	var pages: Array[int] = []
	var ticks: Array[int] = []
	var cell_u: Vector2 = Vector2.ZERO
	var origin_u: Vector2 = Vector2.ZERO


var asset: String = ""
## Texels per u: 1 for the 1080p set, 2 for the 2160p set, 4 for the review masters.
var texels_per_u: int = 1
## Page 0 of the atlas (the whole of it for an asset that fits one page).
var shape: Texture2D
var normal: Texture2D
var parts: Texture2D
var palette: Texture2D
var noise: Texture2D
## Pages beyond the first (`<asset>.p<N>@<s>x.*.png`), index 0 being page 1.
var more_shape: Array[Texture2D] = []
var more_normal: Array[Texture2D] = []
var more_parts: Array[Texture2D] = []
## The largest frame cell in u, and the feet pivot of the asset's source, in u. Each action has its
## own cell and pivot inside it ([method cell_of], [method origin_of]).
var cell_u: Vector2 = Vector2.ZERO
var origin_u: Vector2 = Vector2.ZERO
var page_count: int = 1
var errors: PackedStringArray = []
var _actions: Dictionary[StringName, ActionFrames] = {}
var _materials: Dictionary[int, ShaderMaterial] = {}


## Reads `<dir>/<asset>.sheet.json` and `<asset>@<scale>x.{shape,normal,parts}.png` and
## `<asset>.palette.png` from [param dir] (a res:// folder). Problems go to [member errors].
static func open(dir: String, asset_id: String, scale: int, noise_tex: Texture2D) -> SpriteSheet:
	var sheet := SpriteSheet.new()
	sheet.asset = asset_id
	sheet.texels_per_u = scale
	sheet.noise = noise_tex
	var json_path: String = "%s/%s.sheet.json" % [dir, asset_id]
	var text: String = FileAccess.get_file_as_string(json_path)
	if text.is_empty():
		sheet.errors.append("%s: not found or empty" % json_path)
		return sheet
	var meta: Dictionary[String, Variant] = json_dict(JSON.parse_string(text))
	if meta.is_empty():
		sheet.errors.append("%s: not a JSON object" % json_path)
		return sheet
	sheet._read_meta(meta, scale)
	var stem: String = "%s/%s@%dx" % [dir, asset_id, scale]
	sheet.shape = sheet._texture("%s.shape.png" % stem)
	sheet.normal = sheet._texture("%s.normal.png" % stem)
	sheet.parts = sheet._texture("%s.parts.png" % stem)
	sheet.palette = sheet._texture("%s/%s.palette.png" % [dir, asset_id])
	for page: int in range(1, sheet.page_count):
		var tail: String = ".p%d@%dx" % [page, scale]
		var base: String = "%s/%s%s" % [dir, asset_id, tail]
		sheet.more_shape.append(sheet._texture("%s.shape.png" % base))
		sheet.more_normal.append(sheet._texture("%s.normal.png" % base))
		sheet.more_parts.append(sheet._texture("%s.parts.png" % base))
	return sheet


## A sheet of one frame from images already in memory (tests and tools): the frame is the whole
## texture, in one action called [param action].
static func from_images(
	images: Dictionary[StringName, Image], scale: int, origin: Vector2, noise_tex: Texture2D
) -> SpriteSheet:
	var sheet := SpriteSheet.new()
	sheet.texels_per_u = scale
	sheet.noise = noise_tex
	sheet.shape = ImageTexture.create_from_image(images[&"shape"])
	sheet.normal = ImageTexture.create_from_image(images[&"normal"])
	sheet.parts = ImageTexture.create_from_image(images[&"parts"])
	sheet.palette = ImageTexture.create_from_image(images[&"palette"])
	var size: Vector2i = images[&"shape"].get_size()
	sheet.cell_u = Vector2(size) / float(scale)
	sheet.origin_u = origin
	var frames := ActionFrames.new()
	frames.rects.append(Rect2i(Vector2i.ZERO, size))
	frames.pages.append(0)
	frames.ticks.append(1)
	frames.cell_u = sheet.cell_u
	frames.origin_u = origin
	sheet._actions[&"idle"] = frames
	return sheet


func is_valid() -> bool:
	return (
		errors.is_empty() and shape != null and normal != null and parts != null and palette != null
	)


func has_action(action: StringName) -> bool:
	return _actions.has(action)


func action_names() -> Array[StringName]:
	return _actions.keys()


func frame_count(action: StringName) -> int:
	return _actions[action].rects.size()


func frame_rect(action: StringName, index: int) -> Rect2i:
	return _actions[action].rects[index]


## The atlas page frame [param index] of [param action] is on.
func frame_page(action: StringName, index: int) -> int:
	return _actions[action].pages[index]


## The frame cell of [param action] in u.
func cell_of(action: StringName) -> Vector2:
	return _actions[action].cell_u


## The feet pivot inside [param action]'s cell, measured from the cell's top-left, in u.
func origin_of(action: StringName) -> Vector2:
	return _actions[action].origin_u


func shape_page(page: int) -> Texture2D:
	return shape if page == 0 else more_shape[page - 1]


func normal_page(page: int) -> Texture2D:
	return normal if page == 0 else more_normal[page - 1]


func parts_page(page: int) -> Texture2D:
	return parts if page == 0 else more_parts[page - 1]


## How long a frame is held, in 60 Hz ticks (from the pose timing).
func frame_ticks(action: StringName, index: int) -> int:
	return _actions[action].ticks[index]


## The action's baked frame rate.
func fps_of(action: StringName) -> int:
	return _actions[action].fps


func action_loops(action: StringName) -> bool:
	return _actions[action].loop


## The shared material for a family of sprites: one material per (kind, carrier, palette row,
## mode, atlas page) so every sprite of a sheet in the same family batches. The per-instance values
## (flash, emissive boost, dissolve, alpha) ride on self_modulate, not on the material.
func material(
	background: bool, carrier: bool, palette_row: int, mode: int, page: int = 0
) -> ShaderMaterial:
	var key: int = (
		int(background) | (int(carrier) << 1) | (palette_row << 2) | (mode << 12) | (page << 16)
	)
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = load(BACKGROUND_SHADER if background else SPRITE_SHADER) as Shader
	mat.set_shader_parameter(&"shape_tex", shape_page(page))
	mat.set_shader_parameter(&"normal_tex", normal_page(page))
	mat.set_shader_parameter(&"parts_tex", parts_page(page))
	mat.set_shader_parameter(&"palette_tex", palette)
	mat.set_shader_parameter(&"noise_tex", noise)
	mat.set_shader_parameter(&"frame_u", cell_u)
	mat.set_shader_parameter(&"texel_u", 1.0 / float(texels_per_u))
	mat.set_shader_parameter(&"carries_ember", carrier)
	mat.set_shader_parameter(&"palette_row", palette_row)
	mat.set_shader_parameter(&"mode", mode)
	_materials[key] = mat
	return mat


func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		errors.append("%s: not imported or missing" % path)
		return null
	var sidecar: String = FileAccess.get_file_as_string("%s.import" % path)
	for problem: String in import_problems(sidecar):
		errors.append("%s: %s" % [path, problem])
	return load(path) as Texture2D


## What is wrong with a channel texture's import settings (the text of its .import file). The
## channels are data, not pictures: Godot's default import bleeds the colour of opaque pixels into
## the RGB of transparent neighbours (fix_alpha_border), which here overwrites the palette index,
## the brush angle and the taper next to every pixel that has an alpha (a measured corruption), and
## lossy compression or premultiplication would change them too. project.godot [importer_defaults]
## sets all of this for every texture; this catches an asset that overrides it.
static func import_problems(import_text: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	if import_text.is_empty():
		return problems
	var wanted: Dictionary[String, String] = {
		"process/fix_alpha_border": "false",
		"process/premult_alpha": "false",
		"compress/mode": "0",
		"mipmaps/generate": "false",
	}
	var lines: PackedStringArray = import_text.split("\n")
	for key: String in wanted:
		var want: String = "%s=%s" % [key, wanted[key]]
		var found: bool = false
		for line: String in lines:
			if line.strip_edges() == want:
				found = true
		if not found:
			problems.append("import setting %s must be %s (channel data)" % [key, wanted[key]])
	return problems


## The shared noise (assets/art/build/noise/noise.png), with mipmaps whatever its import says: the
## brush streaks and the paper grain are minified at 1x, and without mipmaps they alias.
static func load_noise() -> Texture2D:
	if not ResourceLoader.exists(NOISE_PATH):
		return null
	var img: Image = (load(NOISE_PATH) as Texture2D).get_image()
	if not img.has_mipmaps():
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _read_meta(meta: Dictionary[String, Variant], scale: int) -> void:
	if int(json_num(meta.get("version", 0), 0.0)) != SHEET_VERSION:
		errors.append("%s: sheet.json version must be %d" % [asset, SHEET_VERSION])
	var cell: Array[Variant] = json_list(meta.get("cell_u", null))
	var origin: Array[Variant] = json_list(meta.get("origin_u", null))
	if cell.size() == 2:
		cell_u = Vector2(json_num(cell[0], 0.0), json_num(cell[1], 0.0))
	else:
		errors.append("%s: cell_u must be [w, h]" % asset)
	if origin.size() == 2:
		origin_u = Vector2(json_num(origin[0], 0.0), json_num(origin[1], 0.0))
	else:
		errors.append("%s: origin_u must be [x, y]" % asset)
	var pages: Array[Variant] = json_list(meta.get("pages", null))
	page_count = maxi(1, pages.size())
	var actions: Dictionary[String, Variant] = json_dict(meta.get("actions", null))
	if actions.is_empty():
		errors.append("%s: actions must be a non-empty object" % asset)
	for action_name: String in actions:
		_read_action(StringName(action_name), json_dict(actions[action_name]), scale)


func _read_action(action: StringName, body: Dictionary[String, Variant], scale: int) -> void:
	var frames := ActionFrames.new()
	frames.fps = int(json_num(body.get("fps", 24), 24.0))
	if frames.fps <= 0:
		errors.append("%s: action %s has an fps of %d" % [asset, action, frames.fps])
	var loop_v: Variant = body.get("loop", true)
	var loop_ok: bool = typeof(loop_v) == TYPE_BOOL
	if not loop_ok:
		errors.append("%s: action %s: loop must be true or false" % [asset, action])
	frames.loop = not loop_ok or loop_v == true
	var cell: Array[Variant] = json_list(body.get("cell_u", null))
	var origin: Array[Variant] = json_list(body.get("cell_origin_u", null))
	frames.cell_u = (
		Vector2(json_num(cell[0], 0.0), json_num(cell[1], 0.0)) if cell.size() == 2 else cell_u
	)
	frames.origin_u = (
		Vector2(json_num(origin[0], 0.0), json_num(origin[1], 0.0))
		if origin.size() == 2
		else origin_u
	)
	var list: Array[Variant] = json_list(body.get("frames", null))
	if list.is_empty():
		errors.append("%s: action %s has no frames" % [asset, action])
		return
	for frame_v: Variant in list:
		var frame: Dictionary[String, Variant] = json_dict(frame_v)
		var r: Array[Variant] = json_list(json_dict(frame.get("rect", null)).get(str(scale), null))
		if r.size() != 4:
			# The sheet is invalid from here (errors is not empty), so the frames after this one
			# shifting their indices is moot.
			errors.append("%s: a frame of %s has no rect for scale %d" % [asset, action, scale])
			continue
		var x: int = int(json_num(r[0], 0.0))
		var y: int = int(json_num(r[1], 0.0))
		var w: int = int(json_num(r[2], 0.0))
		var h: int = int(json_num(r[3], 0.0))
		var page: int = int(json_num(frame.get("page", 0), 0.0))
		var ticks: int = int(json_num(frame.get("ticks", 1), 1.0))
		if w <= 0 or h <= 0:
			errors.append("%s: a frame of %s has an empty rect" % [asset, action])
		if page < 0 or page >= page_count:
			errors.append(
				"%s: a frame of %s is on page %d of %d" % [asset, action, page, page_count]
			)
			page = 0
		if ticks <= 0:
			errors.append("%s: a frame of %s is held for %d ticks" % [asset, action, ticks])
			ticks = 1
		frames.rects.append(Rect2i(x, y, w, h))
		frames.pages.append(page)
		frames.ticks.append(ticks)
	_actions[action] = frames


## JSON reading helpers (a value of the wrong type reads as the fallback or an empty container).
static func json_num(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		var f: float = v
		return f
	return fallback


static func json_list(v: Variant) -> Array[Variant]:
	var out: Array[Variant] = []
	if typeof(v) == TYPE_ARRAY:
		for item: Variant in v:
			out.append(item)
	return out


static func json_dict(v: Variant) -> Dictionary[String, Variant]:
	var out: Dictionary[String, Variant] = {}
	if typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v:
			out[str(k)] = v[k]
	return out
