class_name SolidBox
extends RefCounted
## A rectangular solid that is not part of the tile grid: a door, a breakable wax wall, a
## platform that can be switched off. Edges are in sub-pixels; the box covers [left, right) x
## [top, bottom). A disabled box is ignored by every query.

## Tags of boxes the game can take away during a run: wax burns (BUILD.md s5 tech 12).
const FRAGILE_TAGS: Array[String] = ["wax"]

## Counts every move of any box's edges, for what is cached from where the boxes stand
## ([FlatWalk]). Switching a box on or off does not count: the cache holds the places of all of
## them.
static var revision: int = 0

## Counts every change to any box's edges or flags (and so every box made), for the native
## mirrors ([NativeWorld]): a mirror looks through its boxes only when this has moved since it
## last did. A box holds no link to a mirror, so a box may be in any number of worlds, in any
## list, and be dropped from one, with nothing to forget.
static var edits: int = 0

var left: int = 0:
	set(v):
		if v != left:
			left = v
			revision += 1
			edits += 1
var top: int = 0:
	set(v):
		if v != top:
			top = v
			revision += 1
			edits += 1
var right: int = 0:
	set(v):
		if v != right:
			right = v
			revision += 1
			edits += 1
var bottom: int = 0:
	set(v):
		if v != bottom:
			bottom = v
			revision += 1
			edits += 1
var enabled: bool = true:
	set(v):
		if v != enabled:
			enabled = v
			edits += 1
## Whether the wall-cling verb works on its sides (textured, not smooth or wet).
var clingable: bool = true:
	set(v):
		if v != clingable:
			clingable = v
			edits += 1
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
