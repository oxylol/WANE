class_name PlayerInput
extends RefCounted
## How a Wick reads the stick (BUILD.md section 5): each axis on its own for running, crouching and
## the wall (past [member MovementParams.stick_threshold]), an 8-way direction in equal sectors for
## what goes somewhere (a dash, the toss), and a 4-way direction in equal sectors for a strike (the
## Taper is 4-directional), each taken from the frame its buffered press was made.

## tan(22.5 degrees) in thousandths: the edge between a straight and a diagonal 8-way sector.
const TAN_22_5_PERMILLE: int = 414


## -1, 0 or 1: [param v] past [param threshold] either way.
static func axis(v: int, threshold: int) -> int:
	return 1 if v >= threshold else (-1 if v <= -threshold else 0)


## The stick's 8-way direction on the frame the buffered press of [param bit] (no older than
## [param max_age]) was made. A buffered strike, dash or toss goes the way the stick pointed when
## it was pressed, not wherever it points when the press fires: tapping down and attack together
## and letting go of the stick is still a down-strike when it fires after the pogo's chain window.
static func press_dir(ring: InputRing, bit: int, max_age: int, threshold: int) -> Vector2i:
	var f: InputFrame = ring.frame_at(maxi(ring.press_age(bit, max_age), 0))
	return dir8(f.stick_x, f.stick_y, threshold)


## The stick's 4-way direction ([method dir4]) on the frame the buffered press of [param bit] was
## made, as [method press_dir] reads the 8-way one.
static func press_dir4(ring: InputRing, bit: int, max_age: int, threshold: int) -> Vector2i:
	var f: InputFrame = ring.frame_at(maxi(ring.press_age(bit, max_age), 0))
	return dir4(f.stick_x, f.stick_y, threshold)


## The 4-way direction of stick ([param x], [param y]) in equal 90-degree sectors, past
## [param threshold] on its longer axis: vertical when the vertical axis is at least as long, so a
## d-pad diagonal (both axes full) is up or down. The 8 equal sectors would give up and down 135
## degrees each and the side 45: a stick 23 degrees above level would be an up-strike.
static func dir4(x: int, y: int, threshold: int) -> Vector2i:
	var ax: int = absi(x)
	var ay: int = absi(y)
	if maxi(ax, ay) < threshold:
		return Vector2i.ZERO
	return Vector2i(0, signi(y)) if ay >= ax else Vector2i(signi(x), 0)


## The 8-way direction of stick ([param x], [param y]) in equal 45-degree sectors: past
## [param threshold] on its longer axis, and diagonal when the shorter axis is at least
## tan(22.5 degrees) of the longer. (Each axis held to the threshold on its own, the running and
## crouch rule, would leave the diagonals 29.5 degrees of the circle against 60.5 for the straight
## directions.)
static func dir8(x: int, y: int, threshold: int) -> Vector2i:
	var ax: int = absi(x)
	var ay: int = absi(y)
	var major: int = maxi(ax, ay)
	if major < threshold:
		return Vector2i.ZERO
	var dir := Vector2i(signi(x), signi(y))
	if mini(ax, ay) * 1000 < major * TAN_22_5_PERMILLE:
		if ax >= ay:
			dir.y = 0
		else:
			dir.x = 0
	return dir
