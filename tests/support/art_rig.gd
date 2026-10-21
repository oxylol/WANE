class_name ArtRig
extends RefCounted
## The review's lit test room for the render tests (docs/adr/0023 Decision 5; needs a display): the
## room of tests/screenshot/rooms/lit_test.room lit by a real [LightField] (halos and all), its
## painted backdrop (tests/art/build/lit_test_room) drawn through the background shader, and one
## sprite standing on the mark. Everything a test varies is an argument of [method shot], and a
## shot at a fixed tick and Dark is reproducible.

const ROOM_PATH: String = "res://tests/screenshot/rooms/lit_test.room"
const BACKDROP_DIR: String = "res://tests/art/build/lit_test_room"
const BACKDROP: String = "lit_test_room"
## Where the sprite stands: its feet pivot, in the room's world units.
const MARK: Vector2 = Vector2(352.0, 320.0)

var field: LightField
var sprite: InkSprite
var back: InkSprite
var tuning: LightingTuning
var _tree: SceneTree
var _camera: Camera2D
var _holder: Node2D
var _noise: Texture2D


## Builds the room under [param tree]'s root. [param p_tuning] is the lighting tuning (null for the
## project's); [param backdrop] draws the painted room, otherwise the walls are not drawn at all.
func _init(
	tree: SceneTree, noise: Texture2D, p_tuning: LightingTuning = null, backdrop: bool = true
) -> void:
	_tree = tree
	_noise = noise
	tuning = p_tuning if p_tuning != null else load(LightingTuning.PATH) as LightingTuning
	var data: RoomData = RoomData.parse(FileAccess.get_file_as_string(ROOM_PATH))
	_holder = Node2D.new()
	tree.root.add_child(_holder)
	field = LightField.new(tuning)
	_holder.add_child(field)
	field.show_world(data.build_world(), data.id)
	field.set_post_enabled(false)
	if backdrop:
		var sheet: SpriteSheet = SpriteSheet.open(BACKDROP_DIR, BACKDROP, 1, noise)
		back = InkSprite.new()
		back.background = true
		_holder.add_child(back)
		back.setup(sheet, &"idle")
	sprite = InkSprite.new()
	_holder.add_child(sprite)
	sprite.position = MARK
	_camera = Camera2D.new()
	tree.root.add_child(_camera)
	_camera.make_current()


## Draws the painted backdrop from its sheet at [param scale] (1 or 2; the 4x masters are a review
## product, not committed): a magnified shot reads the finer sheet, as the review's detail does.
func set_backdrop_scale(scale: int) -> void:
	if back != null:
		back.setup(SpriteSheet.open(BACKDROP_DIR, BACKDROP, scale, _noise), &"idle")


## Waits for the room's field to bake (a shot's shadows are right on its first frame).
func settle() -> void:
	await field.settle()


## One picture of the root viewport at [param level] of the Wane Clock (1 Dusk, 3 Pitch), tick
## [param tick], with the ember at [param ember_at], the camera centred on [param centre] at
## [param zoom]: RGBA8 as the screen shows it, or with [param hdr] the HDR picture itself (linear,
## unclamped: a value at Pitch keeps its precision).
func shot(
	tick: int, level: float, ember_at: Vector2, zoom: float, centre: Vector2, hdr: bool = false
) -> Image:
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = centre
	field.freeze(tick, tuning.dark_factor(level))
	field.present(tick, 0.0, ember_at)
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var img: Image = _tree.root.get_viewport().get_texture().get_image()
	if not hdr:
		img.convert(Image.FORMAT_RGBA8)
	return img


## The part of [param img] that is the [param size] centred on the camera's [param centre] (the
## picture is the viewport, the camera is at its middle).
static func crop(img: Image, size: Vector2i) -> Image:
	return img.get_region(Rect2i((img.get_size() - size) / 2, size))


func free_all() -> void:
	_camera.queue_free()
	_holder.queue_free()
