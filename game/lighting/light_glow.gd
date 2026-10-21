class_name LightGlow
extends Node2D
## The soft halos of the lights (docs/adr/0025; BUILD.md section 10, The ember): one additive quad
## per light in the table, drawn over the sprites and under the post pass, sized in world units. It
## owns nothing but what to draw: [LightField] hands it the halos each frame.

const SHADER: String = "res://shaders/lighting/glow.gdshader"

var _centres: Array[Vector2] = []
var _radii: Array[float] = []
var _colours: Array[Color] = []


func _init(falloff: float = 2.0) -> void:
	name = "Glow"
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	var m := ShaderMaterial.new()
	m.shader = load(SHADER) as Shader
	m.set_shader_parameter("falloff", falloff)
	material = m


## Replaces the halos: one entry a light, its centre, radius (u) and colour (rgb already times the
## energy and the strength).
func set_halos(centres: Array[Vector2], radii: Array[float], colours: Array[Color]) -> void:
	_centres = centres
	_radii = radii
	_colours = colours
	queue_redraw()


## How many halos are drawn.
func count() -> int:
	return _centres.size()


func _draw() -> void:
	for i: int in range(_centres.size()):
		var r: float = _radii[i]
		draw_rect(Rect2(_centres[i] - Vector2(r, r), Vector2(r, r) * 2.0), _colours[i])
