class_name EnemyCells
extends RefCounted
## The room's enemies bucketed by where their centres stand, for the procs' "within a radius" and
## "nearest" questions (docs/adr/0015: a Bell's ring, a chain's arc), so a question reads the few
## cells its radius reaches rather than every enemy in the room. Built once a tick by [Combat],
## after everything has moved (nothing moves an enemy again until its next step: a hit's knockback
## is a speed). Plain integer arrays, a linked list per cell: building it for 200 enemies is a few
## array writes each. Not state: rebuilt from the enemies, it holds nothing they do not.

## The side of a cell, in sub-pixels: at least as wide as the radii asked about, so a question
## reads three or four cells a side.
const CELL: int = 128 * Fx.SUB

## Each enemy's centre, x then y, in sub-pixels.
var centres: PackedInt32Array = PackedInt32Array()
## The widest half-width and the tallest height among the enemies: how far a collider can reach
## from its centre.
var reach_x: int = 0
var reach_y: int = 0
var _x0: int = 0
var _y0: int = 0
var _cols: int = 0
var _rows: int = 0
## The first enemy in each cell (-1 for none), and the next enemy in the same cell after each.
var _heads: PackedInt32Array = PackedInt32Array()
var _next: PackedInt32Array = PackedInt32Array()


## Buckets [param enemies] by their centres.
func build(enemies: Array[Enemy]) -> void:
	var n: int = enemies.size()
	centres.resize(2 * n)
	_next.resize(n)
	if n == 0:
		_cols = 0
		_rows = 0
		return
	var lo_x: int = 0x7FFFFFFF
	var lo_y: int = 0x7FFFFFFF
	var hi_x: int = -0x7FFFFFFF
	var hi_y: int = -0x7FFFFFFF
	reach_x = 0
	reach_y = 0
	for k: int in range(n):
		var c: Vector2i = enemies[k].centre()
		reach_x = maxi(reach_x, enemies[k].body.half_w)
		reach_y = maxi(reach_y, enemies[k].body.height)
		centres[2 * k] = c.x
		centres[2 * k + 1] = c.y
		if c.x < lo_x:
			lo_x = c.x
		if c.x > hi_x:
			hi_x = c.x
		if c.y < lo_y:
			lo_y = c.y
		if c.y > hi_y:
			hi_y = c.y
	_x0 = Fx.div_floor(lo_x, CELL)
	_y0 = Fx.div_floor(lo_y, CELL)
	_cols = Fx.div_floor(hi_x, CELL) - _x0 + 1
	_rows = Fx.div_floor(hi_y, CELL) - _y0 + 1
	_heads.resize(_cols * _rows)
	_heads.fill(-1)
	# Every centre is at or past the first cell's corner, so a plain division is the floor.
	var ox: int = _x0 * CELL
	var oy: int = _y0 * CELL
	for k: int in range(n):
		var cell: int = (centres[2 * k] - ox) / CELL * _rows + (centres[2 * k + 1] - oy) / CELL
		_next[k] = _heads[cell]
		_heads[cell] = k


## The enemies of [param enemies] (the list built from), other than [param skip] and the dead,
## whose centres are within [param radius] sub-pixels of [param at], in no particular order.
func within(enemies: Array[Enemy], at: Vector2i, radius: int, skip: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _cols == 0:
		return out
	var r2: int = radius * radius
	var cx0: int = maxi(Fx.div_floor(at.x - radius, CELL) - _x0, 0)
	var cx1: int = mini(Fx.div_floor(at.x + radius, CELL) - _x0, _cols - 1)
	var cy0: int = maxi(Fx.div_floor(at.y - radius, CELL) - _y0, 0)
	var cy1: int = mini(Fx.div_floor(at.y + radius, CELL) - _y0, _rows - 1)
	var cx: int = cx0
	while cx <= cx1:
		var cy: int = cy0
		while cy <= cy1:
			var k: int = _heads[cx * _rows + cy]
			while k >= 0:
				var dx: int = centres[2 * k] - at.x
				var dy: int = centres[2 * k + 1] - at.y
				if dx * dx + dy * dy <= r2 and k != skip and enemies[k].state != Enemy.DEAD:
					out.append(k)
				k = _next[k]
			cy += 1
		cx += 1
	return out


## The enemies whose colliders could meet [param box]: every one (the dead too) whose centre lies
## within the box grown by the colliders' reach, in no particular order. A superset of the ones
## whose hurtboxes meet it; the caller does the exact test.
func touching(box: Rect2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _cols == 0:
		return out
	var l: int = box.position.x - reach_x
	var r: int = box.end.x + reach_x
	var t: int = box.position.y - reach_y
	var b: int = box.end.y + reach_y
	var cx0: int = maxi(Fx.div_floor(l, CELL) - _x0, 0)
	var cx1: int = mini(Fx.div_floor(r, CELL) - _x0, _cols - 1)
	var cy0: int = maxi(Fx.div_floor(t, CELL) - _y0, 0)
	var cy1: int = mini(Fx.div_floor(b, CELL) - _y0, _rows - 1)
	var cx: int = cx0
	while cx <= cx1:
		var cy: int = cy0
		while cy <= cy1:
			var k: int = _heads[cx * _rows + cy]
			while k >= 0:
				var x: int = centres[2 * k]
				var y: int = centres[2 * k + 1]
				if x >= l and x <= r and y >= t and y <= b:
					out.append(k)
				k = _next[k]
			cy += 1
		cx += 1
	return out
