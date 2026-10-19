class_name SolidBox
extends RefCounted
## A rectangular solid that is not part of the tile grid: a door, a breakable wax wall, a
## platform that can be switched off. Edges are in sub-pixels; the box covers [left, right) x
## [top, bottom). A disabled box is ignored by every query.

## Tags of boxes the game can take away during a run: wax burns (BUILD.md s5 tech 12).
const FRAGILE_TAGS: Array[String] = ["wax"]

var left: int = 0
var top: int = 0
var right: int = 0
var bottom: int = 0
var enabled: bool = true
## Whether the wall-cling verb works on its sides (textured, not smooth or wet).
var clingable: bool = true
## Free-form tag for gameplay (for example "wax" for walls a kindle-dash breaks).
var tag: String = ""


static func make(l: int, t: int, r: int, b: int) -> SolidBox:
	var s := SolidBox.new()
	s.left = l
	s.top = t
	s.right = r
	s.bottom = b
	return s


## True if the game can take this box away during a run (it is never safe ground).
func fragile() -> bool:
	return FRAGILE_TAGS.has(tag)


## True if this box overlaps [l, r) x [t, b).
func overlaps(l: int, r: int, t: int, b: int) -> bool:
	return left < r and right > l and top < b and bottom > t


func hash_into(h: StateHasher) -> void:
	h.add_int(left)
	h.add_int(top)
	h.add_int(right)
	h.add_int(bottom)
	h.add_bool(enabled)
	h.add_bool(clingable)
	h.add_string(tag)
