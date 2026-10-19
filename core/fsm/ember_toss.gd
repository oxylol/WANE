class_name EmberToss
extends RefCounted
## Ash's Ember Toss (BUILD.md section 6, spells: "Throw the ember as a 600 u/s projectile that
## stops on walls; press again to teleport to it with 6 f of invulnerability", "3 f startup",
## "12 s cd"). The throw runs beside everything else: it never cancels a dash or a strike, which
## is what makes tech 11 (throw mid-dash, teleport after landing) possible.
##
## The ember is a point in sub-pixels. It spawns at the player's centre on frame
## [member KitParams.toss_startup] of the throw, flies in the stick's 8-way direction (facing when
## neutral) until it meets a wall or its flight time ends, then waits there.

## Frames left before another throw.
var cooldown: int = 0
## Frame of the throw in progress (1 on the press tick), or 0.
var startup: int = 0
var dir_x: int = 0
var dir_y: int = 0
## The ember is out (flying or waiting).
var active: bool = false
var x: int = 0
var y: int = 0
var vx: int = 0
var vy: int = 0
var flying: bool = false
## Frames of flight so far, then frames left to wait once stopped.
var flight: int = 0
var linger: int = 0


## Reads a buffered toss press: teleports to the ember if it is out, else starts a throw in the
## stick's direction when the press was made (facing when neutral; away from a wall the player
## clings to, as a dash or a side strike goes). A press during the throw's startup does nothing:
## it is used up, so it cannot teleport the moment the ember appears (docs/adr/0010).
func try_start(pl: Player, ring: InputRing) -> void:
	if not ring.has_press(InputFrame.TOSS, pl.kit.toss_buffer):
		return
	if startup > 0:
		ring.consume(InputFrame.TOSS)
		return
	if active:
		ring.consume(InputFrame.TOSS)
		_teleport(pl, ring)
		return
	if cooldown > 0:
		return
	var d: Vector2i = pl.press_dir(ring, InputFrame.TOSS, pl.kit.toss_buffer)
	ring.consume(InputFrame.TOSS)
	startup = 1
	dir_x = d.x
	dir_y = d.y
	# Thrown from a wall, or on the tick the player reaches one ([method PlayerWall.met]), a
	# throw toward the wall goes away from it.
	var thr: int = pl.p.stick_threshold
	var wall: int = (
		pl.wall_side
		if pl.loco == Player.WALL
		else PlayerWall.met(
			pl, PlayerInput.axis(ring.stick_x(), thr), PlayerInput.axis(ring.stick_y(), thr)
		)
	)
	if wall != 0 and dir_x == wall:
		dir_x = -wall
	if dir_x == 0 and dir_y == 0:
		dir_x = pl.facing
	cooldown = pl.kit.toss_cooldown
	pl.events.add(SimEvents.TOSS, pl.body.x, pl.body.y, dir_x + 3 * dir_y)


## Advances the throw and the ember by one tick (after the player has moved).
func step(pl: Player) -> void:
	cooldown = maxi(cooldown - 1, 0)
	# "3 f startup", counted as the Taper's are: frames 1 to 3 wind up and the ember is out on
	# frame 4 (the press is frame 1; movement review 4, L2).
	if startup > 0:
		if startup > pl.kit.toss_startup:
			_spawn(pl)
			startup = 0
		else:
			startup += 1
	if not active:
		return
	if flying:
		_fly(pl.world)
		flight += 1
		if flying and flight >= pl.kit.toss_flight:
			flying = false
		if not flying:
			linger = pl.kit.toss_linger
	else:
		linger -= 1
		if linger <= 0:
			active = false


func _spawn(pl: Player) -> void:
	active = true
	flying = true
	flight = 0
	linger = 0
	x = pl.body.x
	y = pl.body.y - pl.body.height / 2
	var speed: int = pl.kit.toss_speed
	if dir_x != 0 and dir_y != 0:
		speed = Fx.permille(speed, Fx.DIAGONAL_PERMILLE)
	vx = dir_x * speed
	vy = dir_y * speed


## Moves the ember point; it stops at the first wall, solid or room edge it meets.
func _fly(world: CollisionWorld) -> void:
	var steps: int = maxi(absi(vx), absi(vy)) / Fx.SUB + 1
	var px: int = x
	var py: int = y
	for i: int in range(1, steps + 1):
		var nx: int = x + Fx.div_floor(vx * i, steps)
		var ny: int = y + Fx.div_floor(vy * i, steps)
		if world.point_solid(nx, ny):
			flying = false
			x = px
			y = py
			return
		px = nx
		py = ny
	x = px
	y = py


## Moves the player so its centre is on the ember, or on the nearest spot around it where the body
## fits (within [member KitTuning.toss_fit_reach_u]: an ember resting on a wall or a floor is a
## body's half-width or half-height from the nearest fit), with the spell's invulnerability. Where
## no standing body fits, a crouched one is tried (an ember in a low gap). Nothing happens if
## neither fits within reach: the press is still used up.
func _teleport(pl: Player, ring: InputRing) -> void:
	var b: Body = pl.body
	for height: int in [pl.p.height, pl.p.crouch_height]:
		var cy: int = y + height / 2
		var at: int = _first_fit(pl, cy, b.half_w, height)
		if at < 0:
			continue
		var offsets: PackedInt32Array = pl.kit.toss_fit_offsets
		var nx: int = x + offsets[at]
		var ny: int = cy + offsets[at + 1]
		pl.events.add(SimEvents.TELEPORT, nx, ny)
		b.x = nx
		b.y = ny
		b.vx = 0
		b.vy = 0
		pl.crouching = height < pl.p.height
		b.height = height
		active = false
		pl.teleported(pl.kit.toss_invuln, ring)
		return


## Index (into the offset pairs) of the first offset from (x, [param cy]) at which a body
## [param half_w] by [param height] fits, or -1. The offsets are tried nearest first, as listed;
## those whose box a wall tile or solid box overlaps are ruled out first, from bit masks of the
## offsets each blocker covers, so a teleport that fits nowhere costs a few hundred bit tests
## rather than thousands of full queries. The rest go through [method CollisionWorld.body_fits]
## (slopes and the foot point).
func _first_fit(pl: Player, cy: int, half_w: int, height: int) -> int:
	var reach: int = pl.kit.toss_fit_reach_u
	var blocked: PackedInt64Array = _blocked_offsets(pl.world, cy, half_w, height, reach)
	var offsets: PackedInt32Array = pl.kit.toss_fit_offsets
	for i: int in range(0, offsets.size(), 2):
		var ox: int = offsets[i]
		var oy: int = offsets[i + 1]
		var row: int = oy / Fx.SUB + reach
		if (blocked[row] >> (ox / Fx.SUB + reach)) & 1 == 1:
			continue
		if pl.world.body_fits(x + ox, cy + oy, half_w, height):
			return i
	return -1


## One bit mask per vertical offset (from -[param reach] to [param reach] units): bit k set means
## the box at horizontal offset (k - reach) units overlaps a wall tile or an enabled solid box. A
## box at centre-bottom (cx, by) overlaps a blocker [l, r) x [t, b) exactly when cx is in
## (l - half_w, r + half_w) and by is in (t, b + height).
func _blocked_offsets(
	world: CollisionWorld, cy: int, half_w: int, height: int, reach: int
) -> PackedInt64Array:
	var masks := PackedInt64Array()
	masks.resize(2 * reach + 1)
	masks.fill(0)
	var span: int = reach * Fx.SUB
	var c0: int = TileGrid.cell(x - span - half_w)
	var c1: int = TileGrid.cell(x + span + half_w - 1)
	var j0: int = TileGrid.cell(cy - span - height)
	var j1: int = TileGrid.cell(cy + span - 1)
	for c: int in range(c0, c1 + 1):
		for j: int in range(j0, j1 + 1):
			if TileGrid.is_wall(world.grid.get_tile(c, j)):
				var l: int = c * TileGrid.TILE_SP
				var t: int = j * TileGrid.TILE_SP
				_block(masks, l, t, l + TileGrid.TILE_SP, t + TileGrid.TILE_SP, cy, half_w, height)
	for sb: SolidBox in world.solids:
		if sb.enabled:
			_block(masks, sb.left, sb.top, sb.right, sb.bottom, cy, half_w, height)
	return masks


func _block(
	masks: PackedInt64Array, l: int, t: int, r: int, b: int, cy: int, half_w: int, height: int
) -> void:
	var reach: int = (masks.size() - 1) / 2
	# Offsets o (units) with l - half_w < x + o * SUB < r + half_w, likewise for y.
	var ox0: int = maxi(Fx.div_floor(l - half_w - x, Fx.SUB) + 1, -reach)
	var ox1: int = mini(-Fx.div_floor(-(r + half_w - x), Fx.SUB) - 1, reach)
	var oy0: int = maxi(Fx.div_floor(t - cy, Fx.SUB) + 1, -reach)
	var oy1: int = mini(-Fx.div_floor(-(b + height - cy), Fx.SUB) - 1, reach)
	if ox0 > ox1 or oy0 > oy1:
		return
	var bits: int = ((1 << (ox1 - ox0 + 1)) - 1) << (ox0 + reach)
	for oy: int in range(oy0, oy1 + 1):
		masks[oy + reach] |= bits


func hash_into(h: StateHasher) -> void:
	for v: int in [cooldown, startup, dir_x, dir_y, x, y, vx, vy, flight, linger]:
		h.add_int(v)
	h.add_bool(active)
	h.add_bool(flying)
