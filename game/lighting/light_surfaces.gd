class_name LightSurfaces
extends RefCounted
## The materials that put a surface in the lighting pass (docs/adr/0023 Decisions 3.2 and 3.4): lit
## grey boxes, until their art and normal maps arrive, and emissives (fire, sparks, procs, the
## telegraphs, the blade's heat). Each is one shared [ShaderMaterial], so everything that uses it
## batches. Nothing here is lit by Godot's own lights.

const LIT_SHADER: String = "res://shaders/lighting/lit_flat.gdshader"
const EMISSIVE_SHADER: String = "res://shaders/lighting/emissive.gdshader"

static var _lit_material: ShaderMaterial
static var _bevel_material: ShaderMaterial
static var _emissive_material: ShaderMaterial


## Makes [param item] emissive: unaffected by the ambient, brighter than 1.0 so the post pass blooms
## it.
static func make_emissive(item: CanvasItem) -> void:
	if _emissive_material == null:
		var t := load(LightingTuning.PATH) as LightingTuning
		_emissive_material = ShaderMaterial.new()
		_emissive_material.shader = load(EMISSIVE_SHADER) as Shader
		_emissive_material.set_shader_parameter("boost", t.emissive_boost)
	item.material = _emissive_material


## Makes [param item] a lit grey-box surface (Phase 1's stand-in for sprites with normal maps).
## [param bevel] gives it a normal from the room's distance field (tiles); otherwise it is flat.
static func make_lit(item: CanvasItem, bevel: bool = false) -> void:
	if _lit_material == null:
		_lit_material = ShaderMaterial.new()
		_lit_material.shader = load(LIT_SHADER) as Shader
		_bevel_material = ShaderMaterial.new()
		_bevel_material.shader = _lit_material.shader
		_bevel_material.set_shader_parameter("sdf_normals", true)
	item.material = _bevel_material if bevel else _lit_material
