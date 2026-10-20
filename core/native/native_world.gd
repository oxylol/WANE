class_name NativeWorld
extends RefCounted
## The native physics sweep behind a [CollisionWorld] (docs/adr/0022): the C++ class WaneSweep
## (native/src/sweep.cpp) holds a copy of the world's tile grid, solid boxes and spike inset, and
## answers the world's moves and queries from the bodies' fields. The GDScript sweep stays the
## reference and the specification; the two give identical bodies after every move
## (tests/unit/core/physics/test_native_sweep.gd).
##
## What is mirrored, and when. The grid is sent again when it is another grid or its revision has
## moved; the spike inset when it differs. The solid boxes are sent whole when the world's list is
## another list or has another length; otherwise, when [member SolidBox.edits] has moved since the
## last look (some box somewhere was changed) or [method recheck] was called, every box is compared
## with what was sent and the ones that differ are sent again. Boxes hold no link to a mirror, so a
## box may be in several worlds, and a box taken out of a list leaves nothing behind. The one
## change the mirror cannot see by itself is a box put in place of another, or two swapped, in a
## list that keeps its length: the simulation calls [method CollisionWorld.begin_tick], which
## calls [method recheck], at the start of every tick, and [method invalidate] forgets the mirror
## for any caller that must be seen at once.
##
## Nothing here is state: never hashed, rebuilt from the world at any time.

const SWEEP_CLASS: StringName = &"WaneSweep"
const FLAG_ENABLED: int = 1
const FLAG_CLINGABLE: int = 2
## The answer of a move: distance moved, x, y, on_ground, ground_tile, on_slope, hit_ceiling,
## hit_wall, nudge_x, nudge_y (native/src/wane_sweep.h).
const R_MOVED: int = 0
const R_X: int = 1
const R_Y: int = 2
const R_GROUND: int = 3
const R_TILE: int = 4
const R_SLOPE: int = 5
const R_CEILING: int = 6
const R_WALL: int = 7
const R_NUDGE_X: int = 8
const R_NUDGE_Y: int = 9

var _sweep: Object = null
var _grid: TileGrid = null
var _grid_rev: int = -1
var _spike: int = -1
var _list: Array[SolidBox] = []
var _count: int = -1
## What was sent for the boxes: six integers each (left, top, right, bottom, flags, spare).
var _sent: PackedInt64Array = PackedInt64Array()
var _edits: int = -1
var _recheck: bool = true


## A link to a fresh native sweep, or null when the native path is not in use (the switch is off,
## or the library is absent or stale: [method NativeBackend.use_native]). [param force] ignores the
## switch and asks only that the library is there (a test playing both paths side by side).
static func create(force: bool = false) -> NativeWorld:
	if not (NativeBackend.available() if force else NativeBackend.use_native()):
		return null
	var link := NativeWorld.new()
	link._sweep = ClassDB.instantiate(SWEEP_CLASS)
	return link


## Forgets everything mirrored: the next call sends the grid and every box again.
func invalidate() -> void:
	_grid = null
	_list = []
	_count = -1


## Makes the next call compare every box with what was sent (see the class comment).
func recheck() -> void:
	_recheck = true


# --- moves ---------------------------------------------------------------------------------


## A walk sends the box and nudge_y and gets back the position, the nudge, and the ground contact
## and hit_wall in one integer (native/src/wane_sweep.h): it is the commonest move and the cheapest
## to call.
func walk(w: CollisionQueries, b: Body, dx: int, lift_sp: int) -> int:
	_sync(w)
	var r: PackedInt64Array = _sweep.call(
		&"walk", b.x, b.y, b.half_w, b.height, b.nudge_y, dx, lift_sp
	)
	b.x = r[1]
	b.y = r[2]
	b.nudge_y = r[3]
	var contact: int = r[4]
	b.on_ground = (contact & 1) != 0
	b.on_slope = (contact & 2) != 0
	b.ground_tile = (contact >> 3) - 1
	if (contact & 4) != 0:
		b.hit_wall = 1 if dx > 0 else -1
	return r[0]


func move_x(w: CollisionQueries, b: Body, dx: int, lift_sp: int, duck_sp: int) -> int:
	_sync(w)
	var r: PackedInt64Array = _sweep.call(
		&"move_x",
		b.x,
		b.y,
		b.half_w,
		b.height,
		b.on_ground,
		b.ground_tile,
		b.on_slope,
		b.hit_ceiling,
		b.hit_wall,
		b.nudge_x,
		b.nudge_y,
		dx,
		lift_sp,
		duck_sp
	)
	return _apply(b, r)


func move_y(w: CollisionQueries, b: Body, dy: int, corner_sp: int) -> int:
	_sync(w)
	var r: PackedInt64Array = _sweep.call(
		&"move_y",
		b.x,
		b.y,
		b.half_w,
		b.height,
		b.on_ground,
		b.ground_tile,
		b.on_slope,
		b.hit_ceiling,
		b.hit_wall,
		b.nudge_x,
		b.nudge_y,
		dy,
		corner_sp
	)
	return _apply(b, r)


func refresh_ground(w: CollisionQueries, b: Body) -> void:
	_sync(w)
	var r: int = _sweep.call(&"refresh_ground", b.x, b.y, b.half_w)
	b.on_ground = (r & 1) != 0
	b.on_slope = (r & 2) != 0
	b.ground_tile = (r >> 2) - 1


## A walker's step in one call (docs/adr/0020): the ledge test, the turn and the walk. Sets the
## body's position and ground contact and clears its other contacts, as the reference does.
func patrol_walk(
	w: CollisionQueries, b: Body, dir: int, step: int, drop: int, falls: bool
) -> int:
	_sync(w)
	var r: PackedInt64Array = _sweep.call(
		&"patrol_walk", b.x, b.y, b.half_w, b.height, dir, step, drop, falls
	)
	b.x = r[1]
	b.y = r[2]
	var contact: int = r[3]
	b.on_ground = (contact & 1) != 0
	b.on_slope = (contact & 2) != 0
	b.ground_tile = (contact >> 2) - 1
	b.clear_contacts()
	return r[0]


## Many bodies in one call (see [method CollisionWorld.patrol_many]).
func patrol_many(w: CollisionQueries, ops: PackedInt64Array, count: int) -> PackedInt64Array:
	_sync(w)
	return _sweep.call(&"patrol_many", ops, count)


func landing_contact(
	w: CollisionQueries, b: Body, dx: int, dy: int, lift_sp: int, slide_sp: int
) -> int:
	_sync(w)
	return _sweep.call(
		&"landing_contact", b.x, b.y, b.half_w, b.height, b.on_ground, dx, dy, lift_sp, slide_sp
	)


# --- queries -------------------------------------------------------------------------------


func can_drop_through(w: CollisionQueries, b: Body) -> bool:
	_sync(w)
	return _sweep.call(&"can_drop_through", b.x, b.y, b.half_w, b.on_ground, b.on_slope)


func wall_near(w: CollisionQueries, b: Body, dir: int, reach: int, include_smooth: bool) -> bool:
	_sync(w)
	return _sweep.call(&"wall_near", b.x, b.y, b.half_w, b.height, dir, reach, include_smooth)


func touches_spikes(w: CollisionQueries, l: int, r: int, t: int, b: int) -> bool:
	_sync(w)
	return _sweep.call(&"touches_spikes", l, r, t, b)


func touches_hazard(w: CollisionQueries, l: int, r: int, t: int, b: int) -> bool:
	_sync(w)
	return _sweep.call(&"touches_hazard", l, r, t, b)


func region_blocked(w: CollisionQueries, l: int, r: int, t: int, b: int) -> bool:
	_sync(w)
	return _sweep.call(&"region_blocked", l, r, t, b)


func body_fits(w: CollisionQueries, cx: int, bottom: int, half_w: int, height: int) -> bool:
	_sync(w)
	return _sweep.call(&"body_fits", cx, bottom, half_w, height)


func point_solid(w: CollisionQueries, x: int, y: int) -> bool:
	_sync(w)
	return _sweep.call(&"point_solid", x, y)


func floor_top_in(w: CollisionQueries, l: int, r: int, y0: int, y1: int) -> int:
	_sync(w)
	return _sweep.call(&"floor_top_in", l, r, y0, y1)


func headroom(w: CollisionQueries, b: Body, new_height: int) -> bool:
	_sync(w)
	return _sweep.call(&"headroom", b.x, b.y, b.half_w, b.height, new_height)


# --- the mirror ----------------------------------------------------------------------------


func _apply(b: Body, r: PackedInt64Array) -> int:
	b.x = r[R_X]
	b.y = r[R_Y]
	b.on_ground = r[R_GROUND] != 0
	b.ground_tile = r[R_TILE]
	b.on_slope = r[R_SLOPE] != 0
	b.hit_ceiling = r[R_CEILING] != 0
	b.hit_wall = r[R_WALL]
	b.nudge_x = r[R_NUDGE_X]
	b.nudge_y = r[R_NUDGE_Y]
	return r[R_MOVED]


## Brings the native copy up to the world as it is now.
func _sync(w: CollisionQueries) -> void:
	var g: TileGrid = w.grid
	if g != _grid or g.revision != _grid_rev:
		_send_grid(g)
	if w.spike_inset_sp != _spike:
		_spike = w.spike_inset_sp
		_sweep.call(&"set_spike_inset", _spike)
	var list: Array[SolidBox] = w.solids
	if list.size() != _count or not is_same(list, _list):
		_send_boxes(list)
	elif _recheck or SolidBox.edits != _edits:
		_resend_changed_boxes(list)


func _send_grid(g: TileGrid) -> void:
	_grid = g
	_grid_rev = g.revision
	_sweep.call(&"set_grid", g.width, g.height, g.raw())


func _send_boxes(list: Array[SolidBox]) -> void:
	_list = list
	_count = list.size()
	_edits = SolidBox.edits
	_recheck = false
	_sent.resize(6 * _count)
	for i: int in range(_count):
		_write(list[i], 6 * i)
	_sweep.call(&"set_boxes", _sent)


## Sends the boxes that are not as they were sent.
func _resend_changed_boxes(list: Array[SolidBox]) -> void:
	_edits = SolidBox.edits
	_recheck = false
	for i: int in range(_count):
		var sb: SolidBox = list[i]
		var at: int = 6 * i
		var flags: int = _flags(sb)
		if (
			_sent[at] != sb.left
			or _sent[at + 1] != sb.top
			or _sent[at + 2] != sb.right
			or _sent[at + 3] != sb.bottom
			or _sent[at + 4] != flags
		):
			_write(sb, at)
			_sweep.call(&"set_box", i, sb.left, sb.top, sb.right, sb.bottom, flags)


func _write(sb: SolidBox, at: int) -> void:
	_sent[at] = sb.left
	_sent[at + 1] = sb.top
	_sent[at + 2] = sb.right
	_sent[at + 3] = sb.bottom
	_sent[at + 4] = _flags(sb)
	_sent[at + 5] = 0


func _flags(sb: SolidBox) -> int:
	return (FLAG_ENABLED if sb.enabled else 0) | (FLAG_CLINGABLE if sb.clingable else 0)
