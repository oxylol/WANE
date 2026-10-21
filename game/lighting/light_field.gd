class_name LightField
extends Node2D
## The lighting pass (docs/adr/0023 Decision 3; BUILD.md section 10, Lighting). It replaces the
## Phase 1 stand-in. It owns the light table (at most 16 lights, culled to the view and ranked
## ember, Beacons, fire, Gutter Ember, eyes), the room distance fields baked at prebuild, the shadow
## buffer that marches the ember's soft shadows through them, and the post pass; every frame it
## writes the `wane_*` global shader parameters that the lit shaders read (shaders/lighting/
## light_common.gdshaderinc). Nothing is lit by Godot's own lights; nothing is drawn lit except
## through those shaders.
##
## Everything time-varying derives from the tick and the interpolation fraction handed to
## [method present], never from a clock: the ember's flicker, the fire, the boil that reseeds the
## ink's wobble. [method freeze] pins the tick and the Dark so a render is reproducible.
##
## A room's field is built and baked once, at [method prebuild], cached by room id and grid stamp
## (docs/adr/0020 Decision 19: a door frame is no spike); [method show_world] only points the
## globals at a field already made. Under the dummy renderer (--headless) the script work still
## runs, which is what the frame bench gates, but the bake, the buffer and the post pass are not
## built. The core knows nothing of any of it.

## Columns and rows of the light table, and the shader's cap.
const TABLE_COLUMNS: int = 16
const TABLE_ROWS: int = 4
const FLAG_SHADOW: int = 1
const FLAG_UP_ONLY: int = 8
## Frames the bake queue waits for a bake before [method settle] gives up on it.
const SETTLE_FRAMES: int = 600

const POST_SHADER: String = "res://shaders/post/post.gdshader"

var tuning: LightingTuning
var profile: int = LightingTuning.PROFILE_PC
## The ember: light 0 of the table. [method present] moves it.
var ember: WaneLight
## The ambient colour before the Dark: the zone's, or the tuning's. Assign the zone's on entering
## it.
var ambient_colour: Color
## The Dark factor now (1 at Dusk, 0.15 at Pitch).
var dark_factor: float = 1.0
## The key light of the room: x and y toward it, z its strength at Dusk. Assign the room's own. The
## shaders get it with w the share the Dark leaves of it ([method LightingTuning.key_share]).
var key: Vector4
## How many rooms' fields were built, how many are baked, how many lights the table holds now,
## and how many dynamic occluders the shadow march got.
var rooms_built: int = 0
var lights_in_table: int = 0
var occluders_in_march: int = 0

## The light table as written this frame (RGBA32F, 16 x 4, row by row).
var table: PackedFloat32Array = PackedFloat32Array()
## The shadow-casting lights of the frame by channel: x, y, reach, penumbra radius.
var casters: Array[Vector4] = []
## The globals as last written, by name (the dummy renderer cannot be asked), for tests and the
## debug overlay.
var globals: Dictionary[String, Variant] = {}

var _lights: Array[WaneLight] = []
var _table_image: Image
var _table_texture: ImageTexture
var _fields: Dictionary[String, RoomSdf] = {}
var _stamps: Dictionary[String, Vector3i] = {}
var _shown: RoomSdf = null
var _bound: RoomSdf = null
var _none_texture: ImageTexture = null
var _recent: Array[String] = []
var _queue: Array[RoomSdf] = []
var _baking: int = 0
var _world: CollisionWorld = null
var _extra_occluders: Array[Vector4] = []
var _frozen: bool = false
var _frozen_tick: int = 0
var _buffer: ShadowBuffer = null
var _glow: LightGlow = null
var _post_layer: CanvasLayer = null
var _post_material: ShaderMaterial = null
var _tick: int = 0
var _alpha: float = 1.0
var _view: Rect2 = Rect2(0, 0, 1920, 1080)


func _init(p_tuning: LightingTuning = null, p_profile: int = LightingTuning.PROFILE_PC) -> void:
	tuning = p_tuning if p_tuning != null else load(LightingTuning.PATH) as LightingTuning
	profile = p_profile
	name = "LightField"
	ambient_colour = tuning.ambient_colour
	key = Vector4(tuning.key_dir.x, tuning.key_dir.y, tuning.key_strength, 0.0)
	ember = _make_ember()
	_lights.append(ember)
	table.resize(TABLE_COLUMNS * TABLE_ROWS * 4)
	_table_image = Image.create_from_data(
		TABLE_COLUMNS, TABLE_ROWS, false, Image.FORMAT_RGBAF, table.to_byte_array()
	)
	_table_texture = ImageTexture.create_from_image(_table_image)
	_set_global("wane_light_table", _table_texture)
	# A world with no walls until a room is shown: a far-away distance and a unit rectangle.
	var none: Image = Image.create_from_data(
		1, 1, false, Image.FORMAT_RF, PackedFloat32Array([100000.0]).to_byte_array()
	)
	none.convert(Image.FORMAT_RH)
	_none_texture = ImageTexture.create_from_image(none)
	_set_global("wane_room_sdf", _none_texture)
	_set_global("wane_room_rect", Vector4(0, 0, 1, 1))
	_write_globals(0.0)


func _enter_tree() -> void:
	if not RoomSdf.can_render():
		return
	if _buffer == null:
		_buffer = ShadowBuffer.new(tuning, tuning.shadow_scale(profile))
		add_child(_buffer)
		_set_global("wane_shadow", _buffer.texture())
	if _glow == null:
		_glow = LightGlow.new(tuning.glow_falloff)
		add_child(_glow)
	if _post_layer == null:
		_build_post()


# --- The Dark and the zone ----------------------------------------------------------------------


## Sets the Dark by Wane Clock level [param d]; the factor is [method LightingTuning.dark_factor].
func set_dark_level(d: float) -> void:
	dark_factor = tuning.dark_factor(d)


## Sets the Dark factor directly (a render at a chosen Dark).
func set_dark_factor(f: float) -> void:
	dark_factor = clampf(f, 0.0, 1.0)


## Pins the tick and the Dark: [method present] then ignores its tick and fraction, so a render is
## reproducible (docs/adr/0023 Decision 6.3).
func freeze(tick: int, p_dark_factor: float) -> void:
	_frozen = true
	_frozen_tick = tick
	set_dark_factor(p_dark_factor)


## Turns the post pass (bloom, shoulder, vignette, grain) on or off: a test that measures what the
## surfaces and the halos draw wants the HDR picture as it is, before the screen's own tone.
func set_post_enabled(on: bool) -> void:
	if _post_layer != null:
		_post_layer.visible = on


## Lets time run again after [method freeze].
func thaw() -> void:
	_frozen = false


# --- Lights ---------------------------------------------------------------------------------------


## Adds a light (a Beacon, a fire, a Gutter Ember, an eye).
func add_light(l: WaneLight) -> void:
	if not _lights.has(l):
		_lights.append(l)


func remove_light(l: WaneLight) -> void:
	if l != ember:
		_lights.erase(l)


## Makes a light of [param kind] at [param at] and adds it.
func spawn_light(kind: LightKind, at: Vector2) -> WaneLight:
	var l := WaneLight.new(kind, at)
	l.phase = at.x * tuning.flicker_phase_per_u.x + at.y * tuning.flicker_phase_per_u.y
	add_light(l)
	return l


## Sets dynamic occluders beyond the room's solid boxes (enemies that cast shadows): boxes
## (centre x, centre y, half width, half height) or circles (centre x, centre y, radius, -1).
func set_occluders(list: Array[Vector4]) -> void:
	_extra_occluders = list


func _make_ember() -> WaneLight:
	var k := LightKind.new()
	k.id = &"ember"
	k.radius_u = tuning.ember_radius_u
	k.kelvin = tuning.ember_kelvin
	k.energy = tuning.ember_energy
	k.flicker = LightKind.SINE
	k.flicker_hz = tuning.flicker_hz
	k.flicker_amplitude = tuning.flicker_amplitude
	k.shadow_channel = 0
	k.falloff_power = tuning.falloff_power
	k.priority = 0
	return WaneLight.new(k)


# --- Rooms ------------------------------------------------------------------------------------


## Builds the distance field of room [param room_id] ahead of its being shown and queues its bake,
## so that crossing into it builds nothing (docs/adr/0020 Decision 19). A room already built from
## this [param grid] as it is costs nothing; a grid edited since (its [member TileGrid.revision], or
## its size, changed) is built afresh, so a cached field never shadows a tile that is gone.
func prebuild(room_id: String, grid: TileGrid) -> void:
	var stamp := Vector3i(grid.revision, grid.width, grid.height)
	if _fields.has(room_id) and _stamps[room_id] == stamp:
		return
	var was_shown: bool = _fields.has(room_id) and _fields[room_id] == _shown
	var field: RoomSdf = _build(grid)
	if _fields.has(room_id):
		# The field it replaces is not baked for nothing.
		_queue.erase(_fields[room_id])
	_fields[room_id] = field
	_stamps[room_id] = stamp
	if was_shown:
		_shown = field
	_enqueue(field)
	_touch(room_id)


## Shows [param world]'s room: points the lighting at the field kept under [param room_id] (built
## now if it was not; an empty id builds an uncached one) and reads the room's solid boxes as
## dynamic occluders.
func show_world(world: CollisionWorld, room_id: String = "") -> void:
	_world = world
	if room_id != "":
		prebuild(room_id, world.grid)
		_shown = _fields[room_id]
		_touch(room_id)
	else:
		_shown = _build(world.grid)
		_enqueue(_shown)
	if RoomSdf.can_render() and not _shown.baked and _queue.has(_shown):
		# The room on show bakes first.
		_queue.erase(_shown)
		_queue.push_front(_shown)
	_bind_room()


## Remembers that [param room_id] was used now and lets the fields of the rooms used longest ago go
## beyond [member LightingTuning.fields_kept] (never the one on show, the one bound or one queued).
func _touch(room_id: String) -> void:
	_recent.erase(room_id)
	_recent.append(room_id)
	var i: int = 0
	while _fields.size() > tuning.fields_kept and i < _recent.size():
		var old: String = _recent[i]
		var f: RoomSdf = _fields.get(old)
		if old == room_id or f == _shown or f == _bound or _queue.has(f):
			i += 1
			continue
		_fields.erase(old)
		_stamps.erase(old)
		_recent.remove_at(i)


func _build(grid: TileGrid) -> RoomSdf:
	rooms_built += 1
	return RoomSdf.from_grid(grid, tuning.border_u, tuning.sdf_texel_u)


func _enqueue(field: RoomSdf) -> void:
	if RoomSdf.can_render() and not field.baked and not _queue.has(field):
		_queue.append(field)


## The shadow buffer, or null under the dummy renderer.
func shadow_buffer() -> ShadowBuffer:
	return _buffer


## The distance field of the room on show (tests, the twin).
func shown_field() -> RoomSdf:
	return _shown


## The field kept under [param room_id], or null.
func field_of(room_id: String) -> RoomSdf:
	return _fields.get(room_id)


## How many fields are waiting for the GPU or being baked.
func bakes_pending() -> int:
	return _queue.size() + _baking


func _process(_delta: float) -> void:
	if _baking == 0 and not _queue.is_empty() and is_inside_tree():
		var f: RoomSdf = _queue.pop_front()
		_baking += 1
		f.finished.connect(_on_baked, CONNECT_ONE_SHOT)
		f.begin_bake(self)
	if _shown != null and _shown != _bound and _shown.baked:
		_bind_room()
	# The camera moves after the game's own _process: place the light against the view as drawn.
	if is_inside_tree() and view_rect() != _view:
		_refresh()


func _on_baked() -> void:
	_baking -= 1


## Waits until every queued bake is done (a render or a test needs the shadows right on its first
## frame). A no-op headless.
func settle() -> void:
	if not RoomSdf.can_render():
		return
	var frames: int = 0
	while bakes_pending() > 0 and frames < SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
		frames += 1
	_bind_room()


func _bind_room() -> void:
	if _shown == null or _bound == _shown:
		return
	if not _shown.baked:
		# Until the new room's field is baked the walls of the last one must not light or shadow it:
		# the field of no walls stands in.
		if _bound != null:
			_bound = null
			_set_global("wane_room_sdf", _none_texture)
			_set_global("wane_room_rect", Vector4(0, 0, 1, 1))
		return
	_bound = _shown
	_set_global("wane_room_sdf", _shown.texture)
	var r: Rect2 = _shown.rect
	_set_global("wane_room_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))


# --- The frame ----------------------------------------------------------------------------------


## Writes this frame's lights and globals: [param tick] and [param alpha] are the simulation's tick
## and the interpolation fraction, [param ember_at] the ember's place in world units. Moves the
## ember, ranks and culls the lights into the table, and sets what the shadow march reads.
func present(tick: int, alpha: float, ember_at: Vector2) -> void:
	if _frozen:
		_tick = _frozen_tick
		_alpha = 0.0
	else:
		_tick = tick
		_alpha = alpha
	ember.position = ember_at
	_refresh()


## Writes the table, the globals and the march's inputs from the last [method present] and the view
## as it is now.
func _refresh() -> void:
	var seconds: float = (float(_tick) + _alpha) / 60.0
	_view = view_rect()
	_fill_table(seconds)
	_write_globals(seconds)
	if _buffer != null:
		var vp: Viewport = get_viewport()
		if vp != null:
			_buffer.resize(vp.get_visible_rect().size)
		_buffer.update(_view, casters, occluders())


## The rect of the world on screen.
func view_rect() -> Rect2:
	if not is_inside_tree():
		return _view
	var vp: Viewport = get_viewport()
	var vr: Rect2 = vp.get_visible_rect()
	return vp.get_canvas_transform().affine_inverse() * vr


func _fill_table(seconds: float) -> void:
	# Candidates: enabled lights whose reach touches the view, ranked by priority then distance to
	# the ember, the first max_lights kept.
	var inflated: Rect2 = _view
	var cand: Array[WaneLight] = []
	for l: WaneLight in _lights:
		if not l.enabled:
			continue
		var reach: float = l.radius_u
		if l != ember and not inflated.grow(reach).has_point(l.position):
			continue
		cand.append(l)
	var e: Vector2 = ember.position
	if cand.size() > tuning.max_lights:
		cand.sort_custom(
			func(a: WaneLight, b: WaneLight) -> bool:
				if a.kind.priority != b.kind.priority:
					return a.kind.priority < b.kind.priority
				return a.position.distance_squared_to(e) < b.position.distance_squared_to(e)
		)
		cand.resize(tuning.max_lights)
	else:
		# The ember stays first whatever the others' priorities.
		cand.sort_custom(
			func(a: WaneLight, b: WaneLight) -> bool: return a.kind.priority < b.kind.priority
		)
	var casters_n: int = tuning.casters(profile)
	casters.clear()
	for k: int in range(4):
		casters.append(Vector4(0, 0, 0, tuning.light_r_u))
	var taken: Array[bool] = [false, false, false, false]
	var n: int = 0
	for l: WaneLight in cand:
		var kind: LightKind = l.kind
		var c: Color = l.colour()
		var en: float = l.energy_at(seconds)
		var flags: int = 0
		var ch: int = kind.shadow_channel
		if ch >= 0 and ch < casters_n and not taken[ch]:
			taken[ch] = true
			flags |= FLAG_SHADOW | (ch << 1)
			casters[ch] = Vector4(l.position.x, l.position.y, l.radius_u, tuning.light_r_u)
		if kind.up_only:
			flags |= FLAG_UP_ONLY
		var h: float = kind.height_u if kind.height_u > 0.0 else tuning.light_height_u
		_put(0, n, l.position.x, l.position.y, l.radius_u, h)
		_put(1, n, c.r * en, c.g * en, c.b * en, float(flags))
		_put(2, n, kind.falloff_power, tuning.light_r_u, 0.0, 0.0)
		n += 1
	lights_in_table = n
	_set_halos(cand, seconds)
	_table_image.set_data(
		TABLE_COLUMNS, TABLE_ROWS, false, Image.FORMAT_RGBAF, table.to_byte_array()
	)
	_table_texture.update(_table_image)
	_set_global("wane_light_count", n)


## The halos of the lights in the table: radius the share of the light's reach (not under the
## minimum), colour its own times its energy times the strength.
func _set_halos(lit: Array[WaneLight], seconds: float) -> void:
	if _glow == null:
		return
	var centres: Array[Vector2] = []
	var radii: Array[float] = []
	var colours: Array[Color] = []
	for l: WaneLight in lit:
		var k: float = l.energy_at(seconds) * tuning.glow_strength
		var c: Color = l.colour()
		centres.append(l.position)
		radii.append(maxf(l.radius_u * tuning.glow_radius_share, tuning.glow_min_u))
		colours.append(Color(c.r * k, c.g * k, c.b * k, 1.0))
	_glow.set_halos(centres, radii, colours)


func _put(row: int, col: int, a: float, b: float, c: float, d: float) -> void:
	var o: int = (row * TABLE_COLUMNS + col) * 4
	table[o] = a
	table[o + 1] = b
	table[o + 2] = c
	table[o + 3] = d


## The dynamic occluders: the room's solid boxes that stand, then the extra ones, nearest the
## ember first, at most sixteen.
func occluders() -> Array[Vector4]:
	var out: Array[Vector4] = []
	if _world != null:
		for s: SolidBox in _world.solids:
			if not s.enabled:
				continue
			var x0: float = float(s.left) / Fx.SUB
			var y0: float = float(s.top) / Fx.SUB
			var x1: float = float(s.right) / Fx.SUB
			var y1: float = float(s.bottom) / Fx.SUB
			out.append(Vector4((x0 + x1) * 0.5, (y0 + y1) * 0.5, (x1 - x0) * 0.5, (y1 - y0) * 0.5))
	out.append_array(_extra_occluders)
	if out.size() > ShadowBuffer.MAX_OCCLUDERS:
		var e: Vector2 = ember.position
		out.sort_custom(
			func(a: Vector4, b: Vector4) -> bool:
				return (
					Vector2(a.x, a.y).distance_squared_to(e)
					< Vector2(b.x, b.y).distance_squared_to(e)
				)
		)
		out.resize(ShadowBuffer.MAX_OCCLUDERS)
	occluders_in_march = out.size()
	return out


func _set_global(global_name: String, value: Variant) -> void:
	globals[global_name] = value
	RenderingServer.global_shader_parameter_set(global_name, value)


func _write_globals(seconds: float) -> void:
	var amb: Color = ambient_colour * dark_factor
	_set_global("wane_ambient", Color(amb.r, amb.g, amb.b, 1.0))
	_set_global("wane_dark", dark_factor)
	# The key's direction and strength, and in w the share of it the Dark leaves (0 at Pitch).
	_set_global("wane_key", Vector4(key.x, key.y, key.z, tuning.key_share(dark_factor)))
	_set_global("wane_shape", tuning.shape_vec())
	_set_global("wane_gate", tuning.gate_vec())
	_set_global(
		"wane_ember",
		Vector4(ember.position.x, ember.position.y, ember.radius_u, ember.energy_at(seconds))
	)
	# The view's top left and its size, in world units: what a shader needs for a reach in u (the
	# post's bloom) at any output size, since the screen's pixels are not the world's.
	_set_global(
		"wane_view", Vector4(_view.position.x, _view.position.y, _view.size.x, _view.size.y)
	)
	_set_global("wane_boil", floorf(seconds * tuning.boil_hz))
	_set_global("wane_time", seconds)


func _build_post() -> void:
	_post_layer = CanvasLayer.new()
	_post_layer.name = "Post"
	_post_layer.layer = 1
	_post_material = ShaderMaterial.new()
	_post_material.shader = load(POST_SHADER) as Shader
	_post_material.set_shader_parameter("bloom_threshold", tuning.bloom_threshold)
	_post_material.set_shader_parameter("bloom_strength", tuning.bloom_strength)
	_post_material.set_shader_parameter("bloom_radius_u", tuning.bloom_radius_u)
	_post_material.set_shader_parameter("bloom_core", tuning.bloom_core)
	_post_material.set_shader_parameter("bloom_ring", tuning.bloom_ring)
	_post_material.set_shader_parameter("shoulder_knee", tuning.shoulder_knee)
	_post_material.set_shader_parameter("vignette_start", tuning.vignette_start)
	_post_material.set_shader_parameter("vignette_end", tuning.vignette_end)
	_post_material.set_shader_parameter("vignette_squash", tuning.vignette_squash)
	_post_material.set_shader_parameter("grain", tuning.grain)
	_post_material.set_shader_parameter("vignette", tuning.vignette)
	var quad := ColorRect.new()
	quad.name = "Quad"
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quad.set_anchors_preset(Control.PRESET_FULL_RECT)
	quad.material = _post_material
	_post_layer.add_child(quad)
	add_child(_post_layer)
