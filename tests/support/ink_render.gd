class_name InkRender
extends RefCounted
## Renders the ink shaders for tests and review (needs a display: xvfb, GL Compatibility). A
## render is a SubViewport of a fixed size, so it does not depend on the window, drawing the
## probe's stage and figure at a given Dark factor and boil tick. Everything that varies in time
## comes from the tick, so the same arguments give the same bytes (ADR-0023 Decision 6.2).

## Zone 1's ambient (bruise violet) at Dusk, times the Dark factor (BUILD.md section 10, Lighting).
const AMBIENT: Color = Color(0.20, 0.12, 0.28, 1.0)
const DUSK: float = 1.0
const PITCH: float = 0.15
const VIEW_1X: Vector2i = Vector2i(480, 270)
const VIEW_4X: Vector2i = Vector2i(640, 360)
## The figure's ember is at its chest, in the figure's own coordinates.
const CHEST: Vector2 = Vector2(0.0, -30.0)
## The room's key light, toward the upper left (ADR-0023 Decision 3.3), at full strength.
const KEY: Vector4 = Vector4(-0.7071, -0.7071, 1.0, 0.0)


## Pushes the tuning, the boil step of [param tick] and the light for [param ember] at
## [param dark_factor] (1.0 Dusk, 0.15 Pitch) to the global shader parameters.
static func set_globals(tuning: InkTuning, tick: int, ember: Vector2, dark_factor: float) -> void:
	InkGlobals.apply(tuning)
	InkGlobals.set_tick(tick, tuning.boil_hz)
	RenderingServer.global_shader_parameter_set(&"wane_ambient", AMBIENT * dark_factor)
	RenderingServer.global_shader_parameter_set(
		&"wane_ember", Vector4(ember.x, ember.y, 420.0, 1.6)
	)
	RenderingServer.global_shader_parameter_set(&"wane_key", KEY)


## A SubViewport of [param size] in HDR 2D, [param zoom] times magnified around [param centre].
static func viewport(parent: Node, size: Vector2i, zoom: float, centre: Vector2) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.use_hdr_2d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera2D.new()
	cam.position = centre
	cam.zoom = Vector2(zoom, zoom)
	vp.add_child(cam)
	parent.add_child(vp)
	return vp


## The stage (a background layer) and the figure standing on its mark, in [param vp].
## Returns the figure.
static func add_stage_and_figure(
	vp: SubViewport, stage: SpriteSheet, figure: SpriteSheet, with_stage: bool
) -> InkSprite:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.03)
	bg.position = Vector2(-2000, -2000)
	bg.size = Vector2(4000, 4000)
	vp.add_child(bg)
	if with_stage:
		var st := InkSprite.new()
		st.background = true
		st.palette_row = 2
		vp.add_child(st)
		st.setup(stage, &"idle")
		st.position = InkProbe.STAGE_MARK_U
	var fig := InkSprite.new()
	fig.carries_ember = true
	vp.add_child(fig)
	fig.setup(figure, &"idle")
	fig.position = InkProbe.STAGE_MARK_U
	return fig


## Waits for [param vp] to draw with the current globals and returns its picture as RGBA8, or as
## the half-float HDR image when [param hdr] (values above 1 and below 1/255 survive).
static func capture(tree: SceneTree, vp: SubViewport, hdr: bool = false) -> Image:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	if not hdr:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Where the figure's ember is on the stage, in world units.
static func ember_world() -> Vector2:
	return InkProbe.STAGE_MARK_U + CHEST
