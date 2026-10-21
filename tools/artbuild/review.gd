extends SceneTree
## The three-size review of one built asset (docs/adr/0023 Decision 5; BUILD.md section 10,
## Pipeline, Review), drawn by the game's own shaders and lit by the lighting pass in the lit test
## room (tests/screenshot/rooms/lit_test.room):
##   sil64.png      the silhouette at 64 px tall (shader mode 1: white on black)
##   dusk1x.png     1x (one texel per u, 1080p native) in the lit test room at Dusk, 640 x 360 u
##   pitch1x.png    the same at Pitch (ambient 0.15, the world is the ember)
##   detail4x.png   the 4x masters, camera zoom 4, at Dusk, 960 x 540 px
##   <action>.png   a contact sheet per action: every frame at 1x lit at Dusk (enlarged 2x with
##                  nearest sampling), tick and frame numbers, smear frames marked in red, the
##                  blade tip's arc over the row, and the key poses again at 4x below
## It renders, so it needs a display; tools/artbuild/review.sh builds the 4x masters first and
## runs this under a virtual one:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1920x1080 --script tools/artbuild/review.gd -- \
##     <asset> [--root res://dir] [--out dir] [--carries-ember] [--palette N] [action...]
## --root is the build root holding <asset>/ (default: assets/art/build, then tests/art/build,
## then tests/screenshot/data). --out defaults to docs/gallery/<asset>. An asset that carries its
## own ember (a Wick) is lit by it at the chest; any other is lit by an ember 120 u to its left at
## chest height, and each of its emissive regions is a light of its own kind (a flame a fire, an eye
## an eye). The tick and the Dark are frozen ([method LightField.freeze]), so a review is
## reproducible (Decision 6.3).

const ROOM_PATH: String = "res://tests/screenshot/rooms/lit_test.room"
## The room's painted shapes (tests/art/src/lit_test_room), drawn through the background shader:
## the open, broken line, the brush and the grain, so that the review judges the backdrop too.
const BACKDROP_DIR: String = "res://tests/art/build"
const BACKDROP: String = "lit_test_room"
const ROOTS: Array[String] = [
	"res://assets/art/build", "res://tests/art/build", "res://tests/screenshot/data"
]
## Where the asset stands: its feet pivot, in the room's world units.
const MARK: Vector2 = Vector2(352.0, 320.0)
## The 1x crop in u (and screen px at zoom 1), centred on the room.
const CROP_1X: Vector2i = Vector2i(640, 360)
const CROP_CENTRE: Vector2 = Vector2(320.0, 192.0)
## The 4x crop in screen px, and the view's zoom.
const CROP_4X: Vector2i = Vector2i(960, 540)
const ZOOM_DETAIL: float = 4.0
const SIL_HEIGHT_PX: float = 64.0
## The silhouette view is at least this square, and grows to hold a frame wider (a crawler) or
## deeper than that, so that no asset is clipped: the 64 px is the height, not the frame.
const SIL_VIEW_PX: int = 96
const SIL_MARGIN_PX: int = 12
## An ember not carried by the asset sits this far to its left, in u.
const EMBER_OFFSET_X: float = -120.0
## The ember's height as a share of the asset's height above its feet (chest height).
const CHEST_SHARE: float = 0.62
## The contact sheet's enlargement of the 1x row, its width and the room around a cell, in px.
const SHEET_ZOOM: int = 2
const SHEET_WIDTH_PX: int = 1900
const SHEET_PAD_PX: int = 6
const LABEL_PX: int = 14
## The sheet is at least this wide so that its title fits above a single frame.
const TITLE_WIDTH_PX: int = 560
const FRAMES_SETTLE: int = 3

var _asset: String = ""
var _dir: String = ""
var _out: String = ""
var _carries: bool = false
var _palette_row: int = 0
var _actions: Array[StringName] = []
var _meta: Dictionary[String, Variant] = {}
var _field: LightField
var _camera: Camera2D
var _sprite: InkSprite
var _back: InkSprite
var _back1: SpriteSheet
var _back4: SpriteSheet
var _prop_lights: Array[WaneLight] = []
var _tuning: LightingTuning
var _ember_at: Vector2 = Vector2.ZERO
var _asset_height_u: float = 64.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not _parse(args):
		quit(2)
		return
	var noise: Texture2D = SpriteSheet.load_noise()
	var sheet1: SpriteSheet = SpriteSheet.open(_dir, _asset, 1, noise)
	if not sheet1.is_valid():
		printerr("review: %s: %s" % [_asset, "; ".join(sheet1.errors)])
		quit(1)
		return
	var sheet4: SpriteSheet = SpriteSheet.open(_dir, _asset, 4, noise)
	if not sheet4.is_valid():
		print(
			"review: no 4x masters (build.py --masters %s): detail and key poses skipped" % _asset
		)
		sheet4 = null
	if _actions.is_empty():
		_actions = sheet1.action_names()
	_meta = SpriteSheet.json_dict(
		JSON.parse_string(FileAccess.get_file_as_string("%s/%s.sheet.json" % [_dir, _asset]))
	)
	_asset_height_u = _tallest_u(_actions)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	await _silhouette(sheet1)
	await _build_room(noise)
	_place_ember()
	_light_emissives(sheet1)
	await _shot("dusk1x", sheet1, 1, &"", 0, LightWord.DUSK_LEVEL)
	await _shot("pitch1x", sheet1, 1, &"", 0, LightWord.PITCH_LEVEL)
	if sheet4 != null:
		await _shot("detail4x", sheet4, 4, &"", 0, LightWord.DUSK_LEVEL)
	for action: StringName in _actions:
		if sheet1.has_action(action):
			await _contact_sheet(action, sheet1, sheet4)
	print("review: wrote %s" % _out)
	quit(0)


func _parse(args: PackedStringArray) -> bool:
	if args.is_empty():
		printerr(
			"usage: review.gd -- <asset> [--root dir] [--out dir] [--carries-ember] [action...]"
		)
		return false
	_asset = args[0]
	var root_arg: String = _arg(args, "--root", "")
	_carries = args.has("--carries-ember")
	_palette_row = int(_arg(args, "--palette", "0"))
	_out = _arg(args, "--out", "res://docs/gallery/%s" % _asset)
	var skip: Array[String] = ["--root", "--out", "--palette"]
	var i: int = 1
	while i < args.size():
		if skip.has(args[i]):
			i += 2
		elif args[i].begins_with("--"):
			i += 1
		else:
			_actions.append(StringName(args[i]))
			i += 1
	var candidates: Array[String] = ROOTS.duplicate()
	if root_arg != "":
		candidates = [root_arg]
	for r: String in candidates:
		var d: String = "%s/%s" % [r, _asset]
		if FileAccess.file_exists("%s/%s.sheet.json" % [d, _asset]):
			_dir = d
			break
	if _dir == "":
		printerr("review: no build of %s under %s" % [_asset, ", ".join(candidates)])
		return false
	if not (_out.begins_with("res://") or _out.begins_with("user://") or _out.begins_with("/")):
		_out = "res://" + _out
	return true


static func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i: int = args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


## The tallest the asset gets above its feet over the actions, in u (from the sheet's silhouette
## boxes, which are relative to the feet pivot).
func _tallest_u(actions: Array[StringName]) -> float:
	var tallest: float = 1.0
	for action: StringName in actions:
		for frame: Variant in _frames_of(action):
			var box: Array[Variant] = SpriteSheet.json_list(
				SpriteSheet.json_dict(frame).get("silhouette_box", null)
			)
			if box.size() == 4:
				tallest = maxf(tallest, -SpriteSheet.json_num(box[1], 0.0))
	return tallest


## The sheet.json frames of [param action] (empty if it has none).
func _frames_of(action: StringName) -> Array[Variant]:
	var table: Dictionary[String, Variant] = SpriteSheet.json_dict(_meta.get("actions", null))
	var body: Dictionary[String, Variant] = SpriteSheet.json_dict(table.get(String(action), null))
	return SpriteSheet.json_list(body.get("frames", null))


## A [x0, y0, x1, y1] box of frame metadata, or a zero box.
func _box_of(v: Variant) -> Rect2:
	var b: Array[Variant] = SpriteSheet.json_list(v)
	if b.size() != 4:
		return Rect2()
	var x0: float = SpriteSheet.json_num(b[0], 0.0)
	var y0: float = SpriteSheet.json_num(b[1], 0.0)
	return Rect2(x0, y0, SpriteSheet.json_num(b[2], 0.0) - x0, SpriteSheet.json_num(b[3], 0.0) - y0)


# --- the silhouette -------------------------------------------------------------------------


## sil64.png: the first action's first frame in shader mode 1, scaled so the tallest frame of the
## asset is 64 px, white on black, in a viewport of its own (no lighting, no post pass). The view
## is 96 px square, or larger on the side where the frame would not fit with a margin: an asset
## that is wider than it is tall (the Soot-tick, the Gnawer) is drawn whole at the same scale.
func _silhouette(sheet: SpriteSheet) -> void:
	var action: StringName = (
		_actions[0] if sheet.has_action(_actions[0]) else sheet.action_names()[0]
	)
	var k: float = SIL_HEIGHT_PX / _asset_height_u
	var box: Rect2 = _box_of(
		SpriteSheet.json_dict(_frames_of(action)[0]).get("silhouette_box", null)
	)
	var above: float = maxf(-box.position.y, 0.0) * k
	var below: float = maxf(box.end.y, 0.0) * k
	var size := Vector2i(
		maxi(SIL_VIEW_PX, ceili(box.size.x * k) + 2 * SIL_MARGIN_PX),
		maxi(SIL_VIEW_PX, ceili(above) + ceili(below) + 2 * SIL_MARGIN_PX)
	)
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(size)
	vp.add_child(bg)
	var sil := InkSprite.new()
	vp.add_child(sil)
	sil.mode = InkSprite.Mode.SILHOUETTE
	sil.setup(sheet, action)
	sil.scale *= k
	# Feet a margin above the bottom (more if the frame hangs below them), centred on the
	# silhouette's horizontal middle.
	var feet_y: float = float(size.y - SIL_MARGIN_PX - ceili(below))
	sil.position = Vector2(float(size.x) * 0.5 - box.get_center().x * k, feet_y)
	root.add_child(vp)
	await _frames(2)
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_save(img, "sil64")
	vp.queue_free()


# --- the lit test room ----------------------------------------------------------------------


func _build_room(noise: Texture2D) -> void:
	var data: RoomData = RoomData.parse(FileAccess.get_file_as_string(ROOM_PATH))
	for e: String in data.errors:
		printerr("%s: %s" % [ROOM_PATH, e])
	var world: CollisionWorld = data.build_world()
	_tuning = load(LightingTuning.PATH) as LightingTuning
	var holder := Node2D.new()
	holder.name = "World"
	root.add_child(holder)
	_field = LightField.new()
	holder.add_child(_field)
	_field.show_world(world, data.id)
	_back1 = SpriteSheet.open("%s/%s" % [BACKDROP_DIR, BACKDROP], BACKDROP, 1, noise)
	_back4 = SpriteSheet.open("%s/%s" % [BACKDROP_DIR, BACKDROP], BACKDROP, 4, noise)
	if _back1.is_valid():
		_back = InkSprite.new()
		_back.background = true
		holder.add_child(_back)
		_back.setup(_back1, &"idle")
	else:
		printerr("review: no painted backdrop: %s" % "; ".join(_back1.errors))
		var view := RoomView.new()
		holder.add_child(view)
		view.show_world(world, data.doors)
	_sprite = InkSprite.new()
	_sprite.carries_ember = _carries
	_sprite.palette_row = _palette_row
	holder.add_child(_sprite)
	_sprite.position = MARK
	_camera = Camera2D.new()
	_camera.position = CROP_CENTRE
	root.add_child(_camera)
	_camera.make_current()
	await _field.settle()


## The ember: at the asset's chest if it carries one, else 120 u to its left at chest height.
func _place_ember() -> void:
	var chest: Vector2 = MARK + Vector2(0.0, -_asset_height_u * CHEST_SHARE)
	_ember_at = chest if _carries else chest + Vector2(EMBER_OFFSET_X, 0.0)


## The light an emissive region of [param kind] (sheet.json `kind`) is. An enemy's eye is the tiny,
## steady point of BUILD.md section 10 (Lighting, "enemy eyes (point lights, tiny)"); every other
## emissive part (a flame, a hot blade) is a fire.
func _light_kind(kind: String) -> LightKind:
	return _tuning.eye if kind == "eye" else _tuning.fire


## A prop's emissive parts are lights: one light of the region's kind (see [method _light_kind]) at
## each emissive region of the asset's first frame. A Wick's emissive is its ember, light 0.
func _light_emissives(sheet: SpriteSheet) -> void:
	if _carries:
		return
	var act: StringName = _actions[0] if sheet.has_action(_actions[0]) else sheet.action_names()[0]
	var frames: Array[Variant] = _frames_of(act)
	if frames.is_empty():
		return
	var regions: Array[Variant] = SpriteSheet.json_list(
		SpriteSheet.json_dict(frames[0]).get("emissive_regions", null)
	)
	for r_v: Variant in regions:
		var c: Array[Variant] = SpriteSheet.json_list(
			SpriteSheet.json_dict(r_v).get("centre", null)
		)
		if c.size() != 2:
			continue
		var at: Vector2 = (
			MARK + Vector2(SpriteSheet.json_num(c[0], 0.0), SpriteSheet.json_num(c[1], 0.0))
		)
		var kind: String = str(SpriteSheet.json_dict(r_v).get("kind", "ember"))
		_prop_lights.append(_field.spawn_light(_light_kind(kind), at))


## Draws the backdrop from the sheet at the picture's scale.
func _bind_backdrop(detail: bool) -> void:
	if _back == null:
		return
	var sheet: SpriteSheet = _back4 if detail and _back4.is_valid() else _back1
	if _back.sheet != sheet:
		_back.setup(sheet, &"idle")


## The sheet.json frames of [param action] as dictionaries.
func _frame_meta(action: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Variant in _frames_of(action):
		out.append(SpriteSheet.json_dict(f))
	return out


func _frames(n: int) -> void:
	for _i: int in range(n):
		await RenderingServer.frame_post_draw


## Lights the room at [param level] on [param tick] and returns the root viewport's picture.
func _grab(tick: int, level: float, zoom: float, centre: Vector2) -> Image:
	_bind_backdrop(zoom > 1.0)
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = centre
	_field.freeze(tick, _tuning.dark_factor(level))
	_field.present(tick, 0.0, _ember_at)
	await _frames(FRAMES_SETTLE)
	return root.get_viewport().get_texture().get_image()


## One lit picture of the asset's first frame (or [param action]'s frame [param index]).
func _shot(
	file: String, sheet: SpriteSheet, scale: int, action: StringName, index: int, level: float
) -> void:
	var act: StringName = action if action != &"" else _actions[0]
	if not sheet.has_action(act):
		act = sheet.action_names()[0]
	_sprite.setup(sheet, act)
	_sprite.show_frame(act, index)
	var detail: bool = scale > 1
	var centre: Vector2 = CROP_CENTRE
	var size: Vector2i = CROP_1X
	if detail:
		# Centre on the asset's body: halfway up, so the head and the feet are both in.
		centre = MARK + Vector2(0.0, -_asset_height_u * 0.5)
		size = CROP_4X
	var full: Image = await _grab(0, level, ZOOM_DETAIL if detail else 1.0, centre)
	var origin: Vector2i = (full.get_size() - size) / 2
	var crop: Image = full.get_region(Rect2i(origin, size))
	crop.convert(Image.FORMAT_RGBA8)
	_save(crop, file)


# --- the contact sheet ----------------------------------------------------------------------


## <action>.png: every frame lit at Dusk at 1x and enlarged, labelled; the key poses at 4x below.
func _contact_sheet(action: StringName, sheet1: SpriteSheet, sheet4: SpriteSheet) -> void:
	var count: int = sheet1.frame_count(action)
	var cell: Vector2 = sheet1.cell_of(action)
	var origin: Vector2 = sheet1.origin_of(action)
	var frames_meta: Array[Dictionary] = _frame_meta(action)
	var tick: int = 0
	var pics: Array[Image] = []
	var starts: Array[int] = []
	_sprite.setup(sheet1, action)
	for i: int in range(count):
		_sprite.show_frame(action, i)
		var full: Image = await _grab(tick, LightWord.DUSK_LEVEL, 1.0, CROP_CENTRE)
		# The cell in screen px: the view is centred on CROP_CENTRE at zoom 1.
		var top_left: Vector2 = MARK - origin - CROP_CENTRE + Vector2(full.get_size()) * 0.5
		var pic: Image = full.get_region(Rect2i(Vector2i(top_left), Vector2i(cell)))
		pic.convert(Image.FORMAT_RGBA8)
		pic.resize(int(cell.x) * SHEET_ZOOM, int(cell.y) * SHEET_ZOOM, Image.INTERPOLATE_NEAREST)
		pics.append(pic)
		starts.append(tick)
		tick += sheet1.frame_ticks(action, i)
	var keys: Array[int] = []
	var key_pics: Array[Image] = []
	if sheet4 != null and sheet4.has_action(action):
		_sprite.setup(sheet4, action)
		for i: int in range(count):
			if frames_meta[i].get("key", false) != true:
				continue
			_sprite.show_frame(action, i)
			var centre: Vector2 = MARK - origin + cell * 0.5
			var full4: Image = await _grab(starts[i], LightWord.DUSK_LEVEL, ZOOM_DETAIL, centre)
			var tl: Vector2 = (Vector2(full4.get_size()) - cell * ZOOM_DETAIL) * 0.5
			var p4: Image = full4.get_region(Rect2i(Vector2i(tl), Vector2i(cell * ZOOM_DETAIL)))
			p4.convert(Image.FORMAT_RGBA8)
			key_pics.append(p4)
			keys.append(i)
	await _compose(action, cell, origin, frames_meta, pics, starts, keys, key_pics, sheet1)


## Lays the pictures out in a SubViewport with labels and the arc, and saves it.
func _compose(
	action: StringName,
	cell: Vector2,
	origin: Vector2,
	frames_meta: Array[Dictionary],
	pics: Array[Image],
	starts: Array[int],
	keys: Array[int],
	key_pics: Array[Image],
	sheet1: SpriteSheet
) -> void:
	var cw: int = int(cell.x) * SHEET_ZOOM + SHEET_PAD_PX
	var ch: int = int(cell.y) * SHEET_ZOOM + SHEET_PAD_PX + LABEL_PX + 2
	var per_row: int = maxi(1, SHEET_WIDTH_PX / cw)
	var rows: int = (pics.size() + per_row - 1) / per_row
	var width: int = mini(pics.size(), per_row) * cw
	var key_w: int = 0
	var key_h: int = 0
	if not key_pics.is_empty():
		key_w = key_pics[0].get_width() + SHEET_PAD_PX
		key_h = key_pics[0].get_height() + LABEL_PX + SHEET_PAD_PX
	var key_per_row: int = maxi(1, SHEET_WIDTH_PX / maxi(key_w, 1)) if key_w > 0 else 1
	var key_rows: int = (key_pics.size() + key_per_row - 1) / key_per_row if key_w > 0 else 0
	width = maxi(width, mini(key_pics.size(), key_per_row) * key_w)
	var height: int = LABEL_PX + 4 + rows * ch + key_rows * key_h + SHEET_PAD_PX
	var vp := SubViewport.new()
	vp.size = Vector2i(maxi(width, TITLE_WIDTH_PX), height)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.06)
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	_label(
		vp,
		(
			"%s  %s  %d frames  %d fps  1x lit at Dusk, enlarged %dx"
			% [_asset, action, pics.size(), sheet1.fps_of(action), SHEET_ZOOM]
		),
		Vector2(SHEET_PAD_PX, 0.0),
		Color(0.9, 0.85, 0.7)
	)
	var tips: Array[Vector2] = _blade_tips(frames_meta, origin)
	for i: int in range(pics.size()):
		var cx: int = (i % per_row) * cw
		var cy: int = LABEL_PX + 4 + (i / per_row) * ch
		var tex := TextureRect.new()
		tex.texture = ImageTexture.create_from_image(pics[i])
		tex.position = Vector2(cx, cy + LABEL_PX)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		vp.add_child(tex)
		var smear: bool = SpriteSheet.json_dict(frames_meta[i].get("smear", null)).values().has(
			true
		)
		var key: bool = frames_meta[i].get("key", false) == true
		var text: String = (
			"%d t%d%s%s" % [i, starts[i], " K" if key else "", " SMEAR" if smear else ""]
		)
		_label(
			vp, text, Vector2(cx + 2, cy), Color(1.0, 0.4, 0.35) if smear else Color(0.8, 0.8, 0.85)
		)
		if smear:
			var bar := ColorRect.new()
			bar.color = Color(1.0, 0.3, 0.25)
			bar.position = Vector2(cx, cy + LABEL_PX - 2)
			bar.size = Vector2(pics[i].get_width(), 2)
			vp.add_child(bar)
		if not tips.is_empty():
			_arc(vp, tips, i, Vector2(cx, cy + LABEL_PX))
	for j: int in range(key_pics.size()):
		var kx: int = (j % key_per_row) * key_w
		var ky: int = LABEL_PX + 4 + rows * ch + (j / key_per_row) * key_h
		_label(vp, "key pose %d at 4x" % keys[j], Vector2(kx + 2, ky), Color(0.8, 0.8, 0.85))
		var kt := TextureRect.new()
		kt.texture = ImageTexture.create_from_image(key_pics[j])
		kt.position = Vector2(kx, ky + LABEL_PX)
		kt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		vp.add_child(kt)
	await _frames(3)
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_save(img, String(action))
	vp.queue_free()


func _label(parent: Node, text: String, at: Vector2, colour: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override(&"font_size", LABEL_PX - 3)
	l.add_theme_color_override(&"font_color", colour)
	parent.add_child(l)


## The blade tip of each frame (sheet.json `tip` of the part tagged `blade`), in u from the cell's
## top-left. Empty if some frame has none.
func _blade_tips(frames_meta: Array[Dictionary], origin: Vector2) -> Array[Vector2]:
	var tips: Array[Vector2] = []
	for frame_v: Variant in frames_meta:
		var f: Dictionary[String, Variant] = SpriteSheet.json_dict(frame_v)
		var found: bool = false
		for pb: Variant in SpriteSheet.json_list(f.get("part_boxes", null)):
			var part_box: Dictionary[String, Variant] = SpriteSheet.json_dict(pb)
			var tip: Array[Variant] = SpriteSheet.json_list(part_box.get("tip", null))
			if tip.size() == 2:
				tips.append(
					(
						Vector2(
							SpriteSheet.json_num(tip[0], 0.0), SpriteSheet.json_num(tip[1], 0.0)
						)
						+ origin
					)
				)
				found = true
				break
		if not found:
			return []
	return tips


## The tips up to frame [param upto], joined, drawn in the cell at [param cell_at].
func _arc(vp: SubViewport, tips: Array[Vector2], upto: int, cell_at: Vector2) -> void:
	var line := Line2D.new()
	line.width = 1.0
	line.default_color = Color(0.4, 0.9, 1.0, 0.8)
	for k: int in range(upto + 1):
		line.add_point(cell_at + tips[k] * float(SHEET_ZOOM))
	vp.add_child(line)
	var dot := ColorRect.new()
	dot.color = Color(1.0, 1.0, 0.4)
	dot.size = Vector2(3, 3)
	dot.position = cell_at + tips[upto] * float(SHEET_ZOOM) - Vector2(1, 1)
	vp.add_child(dot)


func _save(img: Image, file: String) -> void:
	var path: String = ProjectSettings.globalize_path("%s/%s.png" % [_out, file])
	var err: Error = img.save_png(path)
	print("review: %s (%dx%d): %s" % [path, img.get_width(), img.get_height(), error_string(err)])
