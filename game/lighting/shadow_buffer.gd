class_name ShadowBuffer
extends Node
## The shadow buffer (docs/adr/0023 Decision 4.3): a [SubViewport] covering the view at the
## profile's scale (1.0 on PC and consoles, 0.75 on Switch 2 and the Deck, 0.5 on the minimum PC),
## RGBA8, one visibility channel per shadow-casting light (R is the ember), marched once per buffer
## texel by shaders/lighting/shadow_march.gdshader and bound as the global `wane_shadow`. Sprites
## and
## tiles read it at their screen uv, so the march costs the same whatever the overdraw. Not built
## under the dummy renderer.

const MARCH_SHADER: String = "res://shaders/lighting/shadow_march.gdshader"
const MAX_OCCLUDERS: int = 16

var viewport: SubViewport
var buffer_scale: float = 1.0
var _quad: ColorRect
var _material: ShaderMaterial
var _size_px: Vector2i = Vector2i.ZERO


func _init(tuning: LightingTuning, p_scale: float) -> void:
	buffer_scale = p_scale
	name = "ShadowBuffer"
	viewport = SubViewport.new()
	viewport.name = "Buffer"
	viewport.disable_3d = true
	# Transparent, so that the target is RGBA8: an opaque viewport's target on GL Compatibility is
	# RGB10_A2, whose alpha (the fourth caster's channel, the Gutter Ember's) has four levels.
	viewport.transparent_bg = true
	viewport.use_hdr_2d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = load(MARCH_SHADER) as Shader
	_material.set_shader_parameter("skin_u", tuning.skin_u)
	_material.set_shader_parameter("max_steps", tuning.max_steps)
	_material.set_shader_parameter("min_step_u", tuning.min_step_u)
	_material.set_shader_parameter("wall_walk_steps", tuning.wall_walk_steps)
	_quad = ColorRect.new()
	_quad.material = _material
	_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(_quad)
	add_child(viewport)
	resize(Vector2(1920, 1080))


## Sizes the buffer for a view of [param view_px] screen pixels.
func resize(view_px: Vector2) -> void:
	var s := Vector2i(
		maxi(1, roundi(view_px.x * buffer_scale)), maxi(1, roundi(view_px.y * buffer_scale))
	)
	if s == _size_px:
		return
	_size_px = s
	viewport.size = s
	_quad.size = Vector2(s)


## The buffer's size in texels.
func size_px() -> Vector2i:
	return _size_px


## The buffer as a texture, for the global `wane_shadow`.
func texture() -> ViewportTexture:
	return viewport.get_texture()


## Sets what the next march reads: the [param view] in world units, up to four [param casters] (x,
## y, reach, penumbra radius; reach 0 is not casting) and the dynamic [param occluders].
func update(view: Rect2, casters: Array[Vector4], occluders: Array[Vector4]) -> void:
	_material.set_shader_parameter(
		"view_rect", Vector4(view.position.x, view.position.y, view.size.x, view.size.y)
	)
	var cs := PackedVector4Array()
	for i: int in range(4):
		cs.append(casters[i] if i < casters.size() else Vector4(0, 0, 0, 1))
	_material.set_shader_parameter("casters", cs)
	var os := PackedVector4Array()
	var n: int = mini(occluders.size(), MAX_OCCLUDERS)
	for i: int in range(MAX_OCCLUDERS):
		os.append(occluders[i] if i < n else Vector4.ZERO)
	_material.set_shader_parameter("occluders", os)
	_material.set_shader_parameter("occluder_count", n)
