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


## The frames of one action: the rectangle of each in texels at this scale and its length in
## 60 Hz ticks.
class ActionFrames:
	extends RefCounted
	var fps: int = 24
	var loop: bool = true
	var rects: Array[Rect2i] = []
	var ticks: Array[int] = []


var asset: String = ""
## Texels per u: 1 for the 1080p set, 2 for the 2160p set, 4 for the review masters.
var texels_per_u: int = 1
var shape: Texture2D
var normal: Texture2D
var parts: Texture2D
var palette: Texture2D
var noise: Texture2D
## The frame cell in u, and the feet pivot inside it measured from the cell's top-left, in u.
var cell_u: Vector2 = Vector2.ZERO
var origin_u: Vector2 = Vector2.ZERO
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
	var meta: Dictionary[String, Variant] = _dict(JSON.parse_string(text))
	if meta.is_empty():
		sheet.errors.append("%s: not a JSON object" % json_path)
		return sheet
	sheet._read_meta(meta, scale)
	var stem: String = "%s/%s@%dx" % [dir, asset_id, scale]
	sheet.shape = sheet._texture("%s.shape.png" % stem)
	sheet.normal = sheet._texture("%s.normal.png" % stem)
	sheet.parts = sheet._texture("%s.parts.png" % stem)
	sheet.palette = sheet._texture("%s/%s.palette.png" % [dir, asset_id])
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
	frames.ticks.append(1)
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


## How long a frame is held, in 60 Hz ticks (from the pose timing).
func frame_ticks(action: StringName, index: int) -> int:
	return _actions[action].ticks[index]


func action_loops(action: StringName) -> bool:
	return _actions[action].loop


## The shared material for a family of sprites: one material per (kind, carrier, palette row,
## mode) so every sprite of a sheet in the same family batches. The per-instance values (flash,
## emissive boost, dissolve, alpha) ride on self_modulate, not on the material.
func material(background: bool, carrier: bool, palette_row: int, mode: int) -> ShaderMaterial:
	var key: int = int(background) | (int(carrier) << 1) | (palette_row << 2) | (mode << 12)
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = load(BACKGROUND_SHADER if background else SPRITE_SHADER) as Shader
	mat.set_shader_parameter(&"shape_tex", shape)
	mat.set_shader_parameter(&"normal_tex", normal)
	mat.set_shader_parameter(&"parts_tex", parts)
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
	return load(path) as Texture2D


func _read_meta(meta: Dictionary[String, Variant], scale: int) -> void:
	if int(_num(meta.get("version", 0), 0.0)) != SHEET_VERSION:
		errors.append("%s: sheet.json version must be %d" % [asset, SHEET_VERSION])
	var cell: Array[Variant] = _list(meta.get("cell_u", null))
	var origin: Array[Variant] = _list(meta.get("origin_u", null))
	if cell.size() == 2:
		cell_u = Vector2(_num(cell[0], 0.0), _num(cell[1], 0.0))
	else:
		errors.append("%s: cell_u must be [w, h]" % asset)
	if origin.size() == 2:
		origin_u = Vector2(_num(origin[0], 0.0), _num(origin[1], 0.0))
	else:
		errors.append("%s: origin_u must be [x, y]" % asset)
	var actions: Dictionary[String, Variant] = _dict(meta.get("actions", null))
	if actions.is_empty():
		errors.append("%s: actions must be a non-empty object" % asset)
	for action_name: String in actions:
		_read_action(StringName(action_name), _dict(actions[action_name]), scale)


func _read_action(action: StringName, body: Dictionary[String, Variant], scale: int) -> void:
	var frames := ActionFrames.new()
	frames.fps = int(_num(body.get("fps", 24), 24.0))
	var loops: bool = body.get("loop", true)
	frames.loop = loops
	var list: Array[Variant] = _list(body.get("frames", null))
	if list.is_empty():
		errors.append("%s: action %s has no frames" % [asset, action])
		return
	for frame_v: Variant in list:
		var frame: Dictionary[String, Variant] = _dict(frame_v)
		var r: Array[Variant] = _list(_dict(frame.get("rect", null)).get(str(scale), null))
		if r.size() != 4:
			errors.append("%s: a frame of %s has no rect for scale %d" % [asset, action, scale])
			continue
		var x: int = int(_num(r[0], 0.0))
		var y: int = int(_num(r[1], 0.0))
		var w: int = int(_num(r[2], 0.0))
		var h: int = int(_num(r[3], 0.0))
		frames.rects.append(Rect2i(x, y, w, h))
		frames.ticks.append(int(_num(frame.get("ticks", 1), 1.0)))
	_actions[action] = frames


static func _num(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		var f: float = v
		return f
	return fallback


static func _list(v: Variant) -> Array[Variant]:
	var out: Array[Variant] = []
	if typeof(v) == TYPE_ARRAY:
		for item: Variant in v:
			out.append(item)
	return out


static func _dict(v: Variant) -> Dictionary[String, Variant]:
	var out: Dictionary[String, Variant] = {}
	if typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v:
			out[str(k)] = v[k]
	return out
