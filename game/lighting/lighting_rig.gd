class_name LightingRig
extends Node2D
## PHASE 1 STAND-IN, replaced by the real lighting pass in Phase 2 task 1 (normal-mapped ember
## light, emissive maps, ambient times the Wane Clock's Dark factor; BUILD.md section 10,
## Lighting). This is Godot's own 2D lighting dressed as Pitch, so that the stress room is
## measured and judged with a lit, dark world: the ember is a [PointLight2D] on the player with
## soft shadows, the room's walls are [LightOccluder2D]s built by [OccluderBuilder] from the
## collision world (merged into few polygons), and a [CanvasModulate] darkens the ambient to
## Pitch (0.15). Every number is in content/lighting.tres ([LightingTuning]).
##
## Off by default: the game builds the rig only when the scenario asks for Pitch (the fixture
## header `lighting pitch`, or `-- --lighting=pitch` on the game's command line). Emissive things
## are drawn unshaded and ignore the ambient (Godot's CanvasModulate dims lit items only): enemy
## telegraphs, the VFX budget's effects, fire and the debug overlay ([method make_emissive]); the
## HUD sits on its own canvas layers. The core knows nothing of any of it.

const PITCH: String = "pitch"
## The light texture's falloff is sampled at this many stops.
const GRADIENT_STOPS: int = 12

var tuning: LightingTuning
var occluder_count: int = 0
var polygon_count: int = 0

var _modulate: CanvasModulate
var _ember: PointLight2D
var _walls: Node2D
var _boxes: Node2D
var _solids: Array[SolidBox] = []
var _box_nodes: Array[LightOccluder2D] = []
var _seconds: float = 0.0


func _init(p_tuning: LightingTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else load(LightingTuning.PATH) as LightingTuning
	_modulate = CanvasModulate.new()
	_modulate.color = tuning.pitch_colour()
	_ember = PointLight2D.new()
	_ember.name = "Ember"
	_ember.color = tuning.ember_colour
	_ember.energy = tuning.ember_energy
	_ember.height = tuning.ember_height_px
	_ember.texture = _texture()
	_ember.texture_scale = tuning.ember_radius_u * 2.0 / float(tuning.texture_px)
	_ember.shadow_enabled = true
	_ember.shadow_filter = tuning.shadow_filter as Light2D.ShadowFilter
	_ember.shadow_filter_smooth = tuning.shadow_smooth
	_walls = Node2D.new()
	_walls.name = "Walls"
	_boxes = Node2D.new()
	_boxes.name = "Boxes"
	for n: Node in [_modulate, _walls, _boxes, _ember]:
		add_child(n)


## Whether [param word] (a fixture's `lighting` word, or the command line's) asks for Pitch.
static func asks_for_pitch(word: String) -> bool:
	return word == PITCH


## Makes [param item] emissive: drawn unshaded, so the ambient does not dim it.
static func make_emissive(item: CanvasItem) -> void:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	item.material = m


## Builds the occluders of [param world]'s room: wall tiles and slopes merged, the border, and
## one occluder per solid box.
func show_world(world: CollisionWorld) -> void:
	for parent: Node2D in [_walls, _boxes]:
		for c: Node in parent.get_children():
			parent.remove_child(c)
			c.free()
	_solids.clear()
	_box_nodes.clear()
	var polys: Array[PackedVector2Array] = OccluderBuilder.tile_polygons(world.grid)
	polys.append_array(OccluderBuilder.border_polygons(world.grid, tuning.border_u))
	for p: PackedVector2Array in polys:
		_walls.add_child(_occluder(p))
	polygon_count = polys.size()
	for s: SolidBox in world.solids:
		var o: LightOccluder2D = _occluder(OccluderBuilder.box_polygon(s))
		o.visible = s.enabled
		_boxes.add_child(o)
		_solids.append(s)
		_box_nodes.append(o)
	occluder_count = polygon_count + _solids.size()


## Moves the ember to [param at] (the player's centre, world units) and flickers it; [param delta]
## is the frame's time. A burnt-away solid box stops casting its shadow.
func follow(at: Vector2, delta: float) -> void:
	_seconds += delta
	_ember.position = at
	_ember.energy = tuning.energy_at(_seconds)
	for i: int in range(_solids.size()):
		var on: bool = _solids[i].enabled
		if _box_nodes[i].visible != on:
			_box_nodes[i].visible = on


## The ember's light node (tests, the film).
func ember() -> PointLight2D:
	return _ember


## The ambient modulate node (tests).
func ambient() -> CanvasModulate:
	return _modulate


func _occluder(poly: PackedVector2Array) -> LightOccluder2D:
	var shape := OccluderPolygon2D.new()
	shape.polygon = poly
	shape.cull_mode = OccluderPolygon2D.CULL_DISABLED
	var o := LightOccluder2D.new()
	o.occluder = shape
	return o


## The ember's texture: white in the centre, falling off to nothing at the edge of the radius.
func _texture() -> GradientTexture2D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colours := PackedColorArray()
	for k: int in range(GRADIENT_STOPS + 1):
		var d: float = float(k) / float(GRADIENT_STOPS)
		offsets.append(d)
		var v: float = pow(1.0 - d, tuning.falloff_power)
		colours.append(Color(v, v, v, 1.0))
	g.offsets = offsets
	g.colors = colours
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = tuning.texture_px
	tex.height = tuning.texture_px
	return tex
