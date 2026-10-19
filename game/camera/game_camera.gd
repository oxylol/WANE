class_name GameCamera
extends Camera2D
## The camera node: steps a [CameraRig] once per simulation tick and places the view between the
## last two ticks at the driver's interpolation factor, so it is as smooth at 144 Hz as at 60.
## Godot's own smoothing and limits stay off: the rig does all of it.

var rig: CameraRig = CameraRig.new()
var _room: Rect2 = Rect2()


func _ready() -> void:
	position_smoothing_enabled = false
	ignore_rotation = true
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER


## Cuts to [param sim]'s player (a new session or room).
func begin(sim: Simulation) -> void:
	_room = _room_of(sim)
	_fit_zoom()
	if sim.player != null:
		rig.reset(_subject(sim), _room)
	show_at(1.0)


## Follows [param sim]'s player through one tick; through a door, the view cuts to the new room.
func step(sim: Simulation) -> void:
	if sim.events.has(SimEvents.ROOM):
		_room = _room_of(sim)
	if sim.player != null:
		rig.step(_subject(sim), _room)


static func _room_of(sim: Simulation) -> Rect2:
	var grid: TileGrid = sim.world.grid
	return Rect2(0, 0, grid.width * TileGrid.TILE, grid.height * TileGrid.TILE)


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
