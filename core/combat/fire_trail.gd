class_name FireTrail
extends RefCounted
## A stretch of fire a strike leaves at Kindling Blaze and above (BUILD.md section 6, Kindling:
## "attacks leave a 10 f fire trail that damages"). Each tick a strike's box is live it leaves its
## box behind as a trail for [member left] ticks; the trails of one strike burn each enemy once
## (by the strike's serial), so the trail adds one small hit to a strike, never a stream of them.

var box: Rect2i = Rect2i()
var left: int = 0
## The serial of the strike that left it.
var serial: int = 0


func _init(p_box: Rect2i, p_left: int, p_serial: int) -> void:
	box = p_box
	left = p_left
	serial = p_serial


func hash_into(h: StateHasher) -> void:
	h.add_int(box.position.x)
	h.add_int(box.position.y)
	h.add_int(box.size.x)
	h.add_int(box.size.y)
	h.add_int(left)
	h.add_int(serial)
