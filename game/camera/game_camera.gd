class_name GameCamera
extends Camera2D
## The camera node: steps a [CameraRig] once per simulation tick and places the view between the
## last two ticks at the driver's interpolation factor, so it is as smooth at 144 Hz as at 60.
## Godot's own smoothing and limits stay off: the rig does all of it.

var rig: CameraRig = CameraRig.new()
var _room: Rect2 = Rect2()
## The player's box after the latest tick (units), for [method apply_shake].
var _box: Rect2 = Rect2()


func _ready() -> void:
	position_smoothing_enabled = false
	ignore_rotation = true
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER


## Cuts to [param sim]'s player (a new session or room).
func begin(sim: Simulation) -> void:
	_room = _room_of(sim)
	_fit_zoom()
	if sim.player != null:
		var s: CameraSubject = _subject(sim)
		_box = s.box
		rig.reset(s, _room)
	show_at(1.0)


## Follows [param sim]'s player through one tick; through a door, the view cuts to the new room.
func step(sim: Simulation) -> void:
	if sim.events.has(SimEvents.ROOM):
		_room = _room_of(sim)
	if sim.player != null:
		var s: CameraSubject = _subject(sim)
		_box = s.box
		rig.step(s, _room)


static func _room_of(sim: Simulation) -> Rect2:
	var grid: TileGrid = sim.world.grid
	return Rect2(0, 0, grid.width * TileGrid.TILE, grid.height * TileGrid.TILE)


## Offsets the drawn view by [param shake] (screen shake: the drawn view only, never the rig),
## but never so far that the player is drawn nearer than [member CameraTuning.edge_margin_u] to the
## view's edge: where the follow holds the player on the margin (a room edge with no border tile),
## a shake toward the player is cut short on that axis (camera review 7, M1).
func apply_shake(shake: Vector2) -> void:
	offset = shake_within_margin(
		rig.center, shake, _box, rig.half_view(), float(rig.tuning.edge_margin_u)
	)


## [param shake] cut on each axis to what keeps [param player] at least [param margin] from the
## edge of a view of half-size [param half] centred on [param center] plus the shake. Where the
## view is already nearer than that (it never is, in play) the shake may not take it nearer.
static func shake_within_margin(
	center: Vector2, shake: Vector2, player: Rect2, half: Vector2, margin: float
) -> Vector2:
	var room: Vector2 = half - Vector2(margin, margin)
	var lo: Vector2 = Vector2(
		minf(player.end.x - room.x, center.x), minf(player.end.y - room.y, center.y)
	)
	var hi: Vector2 = Vector2(
		maxf(player.position.x + room.x, center.x), maxf(player.position.y + room.y, center.y)
	)
	var drawn: Vector2 = center + shake
	return Vector2(clampf(drawn.x, lo.x, hi.x), clampf(drawn.y, lo.y, hi.y)) - center


## Places the view at [param alpha] (0..1) between the last two ticks.
func show_at(alpha: float) -> void:
	_fit_zoom()
	position = rig.view_rect(alpha).get_center()


func _subject(sim: Simulation) -> CameraSubject:
	return CameraSubject.of(sim, rig.tuning.fall_lead_frames)


## Zooms so the planned view (1920 x 1080 units) fits the screen; a screen of another shape sees
## more in one direction, and the rig is told the size it really shows.
func _fit_zoom() -> void:
	var screen: Vector2 = get_viewport_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var planned := Vector2(rig.tuning.view_w_u, rig.tuning.view_h_u)
	var fit: float = minf(screen.x / planned.x, screen.y / planned.y)
	zoom = Vector2(fit, fit)
	rig.view_size = screen / fit
