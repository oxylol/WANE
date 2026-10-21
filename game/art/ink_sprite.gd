class_name InkSprite
extends Sprite2D
## One frame of a SpriteSheet drawn through the ink and gouache shader (ADR-0023 Decision 7.2).
## The node is at the feet pivot, in world units: it scales itself by 1 / texels per u, so a node's
## position and a core position are the same thing at every texture scale. Every InkSprite of a
## sheet in the same family shares one material and batches; what differs per sprite (flash,
## emissive boost, dissolve, opacity) rides on self_modulate (ADR-0023 Decision 2.5).

## Shader mode: 0 lit, 1 silhouette (white on the alpha), 2 visibility, 3 channel debug, 4 the
## wobble field (the line's noise, as a grey), 5 the two-value choice (0 the shadow value, 1 the
## lit value, as a grey).
enum Mode { LIT = 0, SILHOUETTE = 1, VISIBILITY = 2, CHANNELS = 3, WOBBLE = 4, VALUE = 5 }

var sheet: SpriteSheet
## True for a sprite that has its own ember (the Wicks): its line is weighted by the room's key
## light, not by its own ember (ADR-0023 Decision 3.3).
var carries_ember: bool = false:
	set(value):
		carries_ember = value
		_bind_material()
## Palette variant (zone, hurt, Kindling tier): a row group of the palette image.
var palette_row: int = 0:
	set(value):
		palette_row = value
		_bind_material()
var mode: Mode = Mode.LIT:
	set(value):
		mode = value
		_bind_material()
## True draws the open, broken line of a background layer instead of the closed line.
var background: bool = false:
	set(value):
		background = value
		_bind_material()
## 1 faces right (as authored), -1 mirrors: the shader carries the flip into the normals.
var facing: int = 1:
	set(value):
		facing = 1 if value >= 0 else -1
		_apply_scale()
## Hit or parry flash, 0 to 1.
var flash: float = 0.0:
	set(value):
		flash = value
		_modulate()
## Emissive boost (Kindling tiers, wax softening), 0 to 1, 1 at rest.
var emissive_boost: float = 1.0:
	set(value):
		emissive_boost = value
		_modulate()
## Dissolve (death), 0 whole to 1 gone.
var dissolve: float = 0.0:
	set(value):
		dissolve = value
		_modulate()
## Opacity, 0 to 1.
var opacity: float = 1.0:
	set(value):
		opacity = value
		_modulate()

## The atlas page of the frame shown.
var _page: int = 0


func _init() -> void:
	centered = false
	region_enabled = true
	_modulate()


## Binds [param s] and shows its first frame of [param action] (a sheet's frames are in texels at
## its scale; the node is scaled back to u).
func setup(s: SpriteSheet, action: StringName) -> void:
	sheet = s
	_page = -1
	_apply_scale()
	show_frame(action, 0)


## Shows frame [param index] of [param action].
func show_frame(action: StringName, index: int) -> void:
	var page: int = sheet.frame_page(action, index)
	if page != _page:
		_page = page
		texture = sheet.shape_page(page)
		_bind_material()
	offset = -sheet.origin_of(action) * float(sheet.texels_per_u)
	region_rect = Rect2(sheet.frame_rect(action, index))


func _apply_scale() -> void:
	if sheet == null:
		return
	scale = Vector2(float(facing), 1.0) / float(sheet.texels_per_u)


func _bind_material() -> void:
	if sheet == null:
		return
	material = sheet.material(background, carries_ember, palette_row, int(mode), _page)


## The per-instance values on the vertex colour: r flash, g emissive boost, b dissolve, a opacity.
func _modulate() -> void:
	self_modulate = Color(flash, emissive_boost, dissolve, opacity)
