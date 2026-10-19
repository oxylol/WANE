class_name Body
extends RefCounted
## An axis-aligned box moved through a [CollisionWorld]. Position is the bottom-centre of the box
## in sub-pixels: the box covers x in [x - half_w, x + half_w) and y in [y - height, y).
## Velocities are owned by whatever drives the body (the player state machine); the world only
## moves the box and reports contacts.

var x: int = 0
var y: int = 0
var half_w: int = 0
var height: int = 0
var vx: int = 0
var vy: int = 0

## Ground contact, refreshed by every move and by [method CollisionWorld.refresh_ground].
var on_ground: bool = false
## Tile type the body stands on (TileGrid ids), or -1 when airborne.
var ground_tile: int = -1
var on_slope: bool = false
## Contacts and corrections from the moves since the last [method clear_contacts] (the player
## clears them at the start of every tick and reads them only within it, which is why they are not
## part of the state hash).
## Set by a move that was stopped by a ceiling.
var hit_ceiling: bool = false
## -1 or 1 when a horizontal move was stopped by a wall, else 0.
var hit_wall: int = 0
## Corner-correction nudge applied, in sub-pixels (for the F3 overlay, the view's easing and
## tests). Riding up a slope is not a nudge.
var nudge_x: int = 0
var nudge_y: int = 0


static func make(cx: int, bottom: int, p_half_w: int, p_height: int) -> Body:
	var b := Body.new()
	b.x = cx
	b.y = bottom
	b.half_w = p_half_w
	b.height = p_height
	return b


## A copy of the box, its velocity and its ground contact (for trying a move without making it).
func copy() -> Body:
	var b := Body.make(x, y, half_w, height)
	b.vx = vx
	b.vy = vy
	b.on_ground = on_ground
	b.ground_tile = ground_tile
	b.on_slope = on_slope
	return b


func left() -> int:
	return x - half_w


func right() -> int:
	return x + half_w


func top() -> int:
	return y - height


func clear_contacts() -> void:
	hit_ceiling = false
	hit_wall = 0
	nudge_x = 0
	nudge_y = 0


func hash_into(h: StateHasher) -> void:
	h.add_int(x)
	h.add_int(y)
	h.add_int(half_w)
	h.add_int(height)
	h.add_int(vx)
	h.add_int(vy)
	h.add_bool(on_ground)
	h.add_int(ground_tile)
	h.add_bool(on_slope)
