extends SceneTree
## Renders the ink shaders' test figure and stage through the game's own shaders: the 64 px
## silhouette, 1x at Dusk and at Pitch, and the 4x detail at Dusk and at Pitch (the three-size
## review of BUILD.md section 10, Pipeline, on the probe). Needs a display:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 --script tests/screenshot/render_ink.gd -- \
##     <out dir> [tick] [--channels]
## --channels also writes the channel debug view (mode 3) of the figure at 4x.

const SIL_HEIGHT_PX: float = 64.0
## The tallest the figure gets, in u (wick tip to feet), for the 64 px silhouette.
const FIGURE_HEIGHT_U: float = 78.0


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: render_ink.gd -- <out dir> [tick] [--channels]")
		quit(2)
		return
	var out_dir: String = args[0]
	var tick: int = args[1].to_int() if args.size() > 1 and args[1].is_valid_int() else 0
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tuning: InkTuning = load(InkTuning.PATH) as InkTuning
	var noise: ImageTexture = InkProbe.noise_texture()
	var stage: SpriteSheet = InkProbe.stage_sheet(noise)
	var fig1: SpriteSheet = InkProbe.figure_sheet(1, noise)
	var fig4: SpriteSheet = InkProbe.figure_sheet(4, noise)
	var ember: Vector2 = InkRender.ember_world()
	var names: Array[String] = ["dusk", "pitch"]
	var factors: Array[float] = [InkRender.DUSK, InkRender.PITCH]
	for k: int in range(2):
		InkRender.set_globals(tuning, tick, ember, factors[k])
		var vp1: SubViewport = InkRender.viewport(
			root, InkRender.VIEW_1X, 1.0, Vector2(InkRender.VIEW_1X) * 0.5
		)
		InkRender.add_stage_and_figure(vp1, stage, fig1, true)
		var img1: Image = await InkRender.capture(self, vp1)
		img1.save_png("%s/%s1x.png" % [out_dir, names[k]])
		vp1.queue_free()
		var vp4: SubViewport = InkRender.viewport(
			root, InkRender.VIEW_4X, 4.0, InkProbe.STAGE_MARK_U + Vector2(10.0, -38.0)
		)
		InkRender.add_stage_and_figure(vp4, stage, fig4, false)
		var img4: Image = await InkRender.capture(self, vp4)
		img4.save_png("%s/%s4x.png" % [out_dir, names[k]])
		vp4.queue_free()
	InkRender.set_globals(tuning, tick, ember, InkRender.DUSK)
	var vps: SubViewport = InkRender.viewport(
		root,
		Vector2i(96, 96),
		1.0,
		Vector2(InkProbe.STAGE_MARK_U.x, InkProbe.STAGE_MARK_U.y - 36.0)
	)
	var fig: InkSprite = InkRender.add_stage_and_figure(vps, stage, fig1, false)
	fig.mode = InkSprite.Mode.SILHOUETTE
	fig.scale *= SIL_HEIGHT_PX / FIGURE_HEIGHT_U
	var sil: Image = await InkRender.capture(self, vps)
	sil.save_png("%s/sil64.png" % out_dir)
	vps.queue_free()
	if args.has("--channels"):
		var vpc: SubViewport = InkRender.viewport(
			root, InkRender.VIEW_4X, 4.0, InkProbe.STAGE_MARK_U + Vector2(10.0, -38.0)
		)
		var figc: InkSprite = InkRender.add_stage_and_figure(vpc, stage, fig4, false)
		figc.mode = InkSprite.Mode.CHANNELS
		var ch: Image = await InkRender.capture(self, vpc)
		ch.save_png("%s/channels4x.png" % out_dir)
		vpc.queue_free()
	print("rendered to ", out_dir)
	quit()
