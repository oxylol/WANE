extends GdUnitTestSuite
## Randomised invariants (docs/adr/0008). Two kinds of room:
## - "soup": random tiles, 1:2 slopes and solid boxes included, with any slope that breaks
##   [method TileGrid.validate] cleared, the way the room editor refuses it;
## - "terrain": a continuous ground of flats, 45-degree and 1:2 slopes (ramps often several tile
##   rows tall), crests, peaks and valleys.
## The invariants: no move ever leaves a box's upper body in anything solid or its foot point
## inside anything; a fall never passes a floor and never comes to rest hovering on a crest; a walk
## stopped by a "wall" always has something solid within a unit of it, and one that is not stopped
## and stays on the ground moves exactly as far as asked; walking a continuous ground never
## leaves it, keeps its speed and walks back to exactly where it started; a walk ends where the
## same walk in pieces ends; a sideways move on the ground (an air dash that has touched down)
## goes wherever walking goes level or uphill; air steps with sideways speed land cleanly on
## ramps. Falls run one tick at a time under Ash's gravity, as the player falls. Each test stops
## at the first violation and says how to reproduce it.

const U: int = PhysicsKit.U


func test_airborne_moves_never_embed_or_tunnel() -> void:
	var rng: Rng = Rng.seeded(20261016, 0)
	for room: int in range(80):
		var w: CollisionWorld = _soup_world(rng)
		for _b: int in range(5):
			var b: Body = _free_body(w, rng)
			if b == null:
				continue
			for move: int in range(40):
				var problem: String = _random_air_move(w, b, rng)
				if problem != "":
					fail("soup room %d, move %d: %s" % [room, move, problem])
					return


func test_falls_under_per_tick_gravity_land_cleanly() -> void:
	# The player's air step: move_x with the corner corrections, then move_y by a velocity that
	# gravity grows each tick. Wherever it lands: not embedded, not hovering on a crest, and
	# grounded exactly when re-reading the ground says so.
	var rng: Rng = Rng.seeded(3, 4)
	var g: int = PhysicsKit.fall_gravity()
	var terminal: int = PhysicsKit.terminal()
	for room: int in range(120):
		var w: CollisionWorld = _soup_world(rng)
		for _b: int in range(4):
			var b: Body = _free_body(w, rng)
			if b == null:
				continue
			var vx: int = rng.between(-20, 20) * U + rng.between(-255, 255)
			var vy: int = rng.between(-17, 4) * U
			for tick: int in range(90):
				b.clear_contacts()
				var from := Vector2i(b.x, b.y)
				w.move_x(b, vx, 8 * U, 6 * U)
				if not b.on_ground:
					vy = mini(vy + g, terminal)
					w.move_y(b, vy, 6 * U)
					if b.hit_ceiling:
						vy = 0
				var problem: String = _landing_problem(w, b)
				if problem != "":
					fail(
						(
							"soup room %d, fall tick %d from %s (vx %d, vy %d): %s"
							% [room, tick, from, vx, vy, problem]
						)
					)
					return
				if b.on_ground:
					break


func test_walking_never_embeds_and_never_stops_for_nothing() -> void:
	var rng: Rng = Rng.seeded(7, 1)
	for room: int in range(120):
		var w: CollisionWorld = _soup_world(rng)
		var b: Body = _free_body(w, rng)
		if b == null:
			continue
		PhysicsKit.fall(w, b)
		for move: int in range(80):
			if not b.on_ground:
				PhysicsKit.fall(w, b)
				continue
			var from := Vector2i(b.x, b.y)
			var d: int = rng.between(-25, 25) * U + rng.between(-255, 255)
			var moved: int = PhysicsKit.walk(w, b, d)
			var problem: String = _walk_problem(w, b, d, moved)
			if problem != "":
				fail("soup room %d, walk %d from %s by %d: %s" % [room, move, from, d, problem])
				return


func test_walking_a_continuous_ground_never_leaves_it_and_reverses_exactly() -> void:
	var rng: Rng = Rng.seeded(99, 2)
	for room: int in range(40):
		var w: CollisionWorld = _terrain_world(rng)
		var b: Body = PhysicsKit.body(rng.between(60, 1800), 64)
		PhysicsKit.fall(w, b)
		if not b.on_ground:
			fail("terrain room %d: the drop did not land" % room)
			return
		for move: int in range(60):
			var start := Vector2i(b.x, b.y)
			var d: int = rng.between(-25, 25) * U + rng.between(-255, 255)
			var moved: int = PhysicsKit.walk(w, b, d)
			if not b.on_ground or PhysicsKit.embedded(w, b):
				fail(
					(
						"terrain room %d, walk %d from %s by %d: grounded %s at (%d, %d)"
						% [room, move, start, d, b.on_ground, b.x, b.y]
					)
				)
				return
			if b.hit_wall != 0:
				continue
			if moved != d:
				fail(
					(
						"terrain room %d, walk %d from %s: moved %d of %d"
						% [room, move, start, moved, d]
					)
				)
				return
			PhysicsKit.walk(w, b, -d)
			if b.x != start.x or b.y != start.y:
				fail(
					(
						"terrain room %d, walk %d: %d and back from %s ended at (%d, %d)"
						% [room, move, d, start, b.x, b.y]
					)
				)
				return


func test_landing_anywhere_across_crests_and_walking_off_stays_grounded() -> void:
	# A continuous ground with a crest of each slope kind onto a raised plateau, a peak and a
	# valley. Drop the box at every 2 units across it, from three heights, falling a tick at a
	# time; then walk away both ways at 3 u a tick: grounded every tick, never embedded.
	var w: CollisionWorld = (
		PhysicsKit
		. world(
			[
				"##############################",
				"#............................#",
				"#............................#",
				"#............................#",
				"#............................#",
				"#............................#",
				"#..../###\\...ab##cd../\\......#",
				"#########################\\/###",
				"##############################",
			]
		)
	)
	for x_u: int in range(42, 919, 2):
		for drop_y: int in [100, 160, 186]:
			for dir: int in [-1, 1]:
				var b: Body = PhysicsKit.body(x_u, drop_y)
				if not w.body_fits(b.x, b.y, b.half_w, b.height):
					continue
				PhysicsKit.fall(w, b)
				var problem: String = _landing_problem(w, b)
				if problem != "" or not b.on_ground:
					fail(
						(
							"drop at x=%d from %d: %s (grounded %s)"
							% [x_u, drop_y, problem, b.on_ground]
						)
					)
					return
				for step: int in range(15):
					PhysicsKit.walk(w, b, dir * 3 * U)
					if not b.on_ground or PhysicsKit.embedded(w, b):
						fail(
							(
								"drop at x=%d from %d, walking %d, step %d: grounded %s at (%d, %d)"
								% [x_u, drop_y, dir, step, b.on_ground, b.x, b.y]
							)
						)
						return


func test_a_walk_ends_where_the_same_walk_in_pieces_ends() -> void:
	# Step-size invariance (physics review round 3, M3): one walk and the same distance walked in
	# random pieces, both on the ground throughout, end in the same place. Within a sub-pixel: on
	# a 1:2 slope under a ceiling the swept contact of a stepped surface can round either way.
	var rng: Rng = Rng.seeded(13, 7)
	for room: int in range(120):
		var w: CollisionWorld = _soup_world(rng) if room % 2 == 0 else _terrain_world(rng)
		var b: Body = _free_body(w, rng)
		if b == null:
			continue
		PhysicsKit.fall(w, b)
		for move: int in range(30):
			if not b.on_ground:
				PhysicsKit.fall(w, b)
				continue
			var start := Vector2i(b.x, b.y)
			var d: int = rng.between(-25, 25) * U + rng.between(-255, 255)
			var pieces: Body = _copy(b)
			var left: int = d
			var grounded: bool = true
			while left != 0 and grounded:
				var piece: int = signi(left) * mini(absi(left), rng.between(1, 6 * U))
				PhysicsKit.walk(w, pieces, piece)
				left -= piece
				grounded = pieces.on_ground
			PhysicsKit.walk(w, b, d)
			if not (grounded and b.on_ground):
				continue
			if absi(b.x - pieces.x) > 1 or absi(b.y - pieces.y) > 1:
				fail(
					(
						"room %d, walk %d from %s by %d: one walk to (%d, %d), in pieces to (%d, %d)"
						% [room, move, start, d, b.x, b.y, pieces.x, pieces.y]
					)
				)
				return


func test_a_sideways_move_on_the_ground_goes_where_walking_goes() -> void:
	# What an air dash does once it has touched down (physics review round 3, H1): move_x on a
	# grounded box, then move_y(0). It never embeds or hovers and keeps the ground flag right, and
	# where a walk of the same distance goes level or uphill without stopping, it does not stop
	# either: the crest a ramp leads to, and the wall under a ramp's next row, stop only the upper
	# body. (Downhill a level move may meet what a descending walk passes under.)
	var rng: Rng = Rng.seeded(41, 6)
	for room: int in range(120):
		var w: CollisionWorld = _soup_world(rng) if room % 2 == 0 else _terrain_world(rng)
		var b: Body = _free_body(w, rng)
		if b == null:
			continue
		PhysicsKit.fall(w, b)
		for move: int in range(40):
			if not b.on_ground:
				PhysicsKit.fall(w, b)
				continue
			var start := Vector2i(b.x, b.y)
			var d: int = rng.between(-25, 25) * U + rng.between(-255, 255)
			var walker: Body = _copy(b)
			PhysicsKit.walk(w, walker, d)
			b.clear_contacts()
			w.move_x(b, d, 8 * U, 6 * U)
			var stopped: bool = b.hit_wall != 0
			w.move_y(b, 0)
			var problem: String = _landing_problem(w, b)
			if (
				problem == ""
				and stopped
				and walker.hit_wall == 0
				and walker.on_ground
				and walker.y <= start.y
				and absi(b.x - start.x) < absi(walker.x - start.x)
			):
				problem = (
					"stopped at (%d, %d); a walk goes to (%d, %d)" % [b.x, b.y, walker.x, walker.y]
				)
			if problem != "":
				fail("room %d, move %d from %s by %d: %s" % [room, move, start, d, problem])
				return


func test_air_steps_with_sideways_speed_land_cleanly_on_ramps_and_walk_on() -> void:
	# The player's air step, x then y under per-tick gravity, with a sideways speed, over ground
	# whose ramps span several tile rows (physics review round 3, H2: a landing that rode up across
	# a row boundary ended inside the slope above and was stuck). Wherever it lands it is clean,
	# and walking on either way is never stopped by nothing.
	var rng: Rng = Rng.seeded(5, 8)
	var g: int = PhysicsKit.fall_gravity()
	var terminal: int = PhysicsKit.terminal()
	for room: int in range(60):
		var w: CollisionWorld = _terrain_world(rng)
		for _drop: int in range(12):
			var b: Body = PhysicsKit.body(rng.between(60, 1800), rng.between(40, 200))
			b.x += rng.between(0, 255)
			if not w.body_fits(b.x, b.y, b.half_w, b.height):
				continue
			var vx: int = rng.between(-20, 20) * U + rng.between(-255, 255)
			var vy: int = rng.between(-15, 0) * U
			var from := Vector2i(b.x, b.y)
			for _tick: int in range(120):
				b.clear_contacts()
				w.move_x(b, vx, 8 * U, 6 * U)
				vy = mini(vy + g, terminal)
				w.move_y(b, vy, 6 * U)
				if b.hit_ceiling:
					vy = 0
				var problem: String = _landing_problem(w, b)
				if problem != "":
					fail("room %d, drop from %s (vx %d): %s" % [room, from, vx, problem])
					return
				if b.on_ground:
					break
			if not b.on_ground:
				continue
			var dir: int = 1 if rng.below(2) == 0 else -1
			for step: int in range(12):
				var moved: int = PhysicsKit.walk(w, b, dir * 9 * U)
				var problem: String = _walk_problem(w, b, dir * 9 * U, moved)
				if problem == "" and not b.on_ground:
					problem = "left the ground at (%d, %d)" % [b.x, b.y]
				if problem != "":
					fail(
						(
							"room %d, drop from %s (vx %d), walking %d, step %d: %s"
							% [room, from, vx, dir, step, problem]
						)
					)
					return


func test_edge_run_matches_a_unit_by_unit_walk() -> void:
	# _edge_run jumps between the ranges each flat span holds; it must give exactly what checking
	# every sub-pixel would.
	var rng: Rng = Rng.seeded(11, 5)
	for room: int in range(30):
		var grid := TileGrid.new(12, 4)
		for i: int in range(12):
			grid.set_tile(i, 3, TileGrid.SOLID)
			var r: int = rng.below(4)
			grid.set_tile(i, 2, TileGrid.SOLID if r == 0 else (TileGrid.ONE_WAY if r == 1 else 0))
		var w := CollisionWorld.new(grid)
		for _s: int in range(rng.below(3)):
			var l: int = rng.between(0, 360) * U + rng.between(0, 255)
			w.solids.append(SolidBox.make(l, 64 * U, l + rng.between(1, 40) * U, 80 * U))
		for _t: int in range(20):
			var hw: int = rng.between(1, 20) * U
			var b := Body.make(rng.between(40, 340) * U + rng.between(0, 255), 64 * U, hw, 44 * U)
			var dir: int = 1 if rng.below(2) == 0 else -1
			var seg: int = rng.between(1, 32 * U)
			var expected: int = _edge_run_by_units(w, b, dir, seg)
			var got: int = w._edge_run(b, dir, seg)
			if got != expected:
				fail(
					(
						"room %d: _edge_run(x=%d, half_w=%d, dir %d, seg %d) = %d, expected %d"
						% [room, b.x, hw, dir, seg, got, expected]
					)
				)
				return


## The reference for _edge_run: the first sub-pixel step at which no flat floor at the body's
## height is under any part of it, or seg + 1.
func _edge_run_by_units(w: CollisionWorld, b: Body, dir: int, seg: int) -> int:
	var j: int = Fx.div_floor(b.y, TileGrid.TILE_SP)
	for i: int in range(1, seg + 1):
		var p: int = b.x + dir * i
		var held: bool = false
		for c: int in range(TileGrid.cell(p - b.half_w), TileGrid.cell(p + b.half_w - 1) + 1):
			var t: int = w.grid.get_tile(c, j)
			if TileGrid.is_wall(t) or t == TileGrid.ONE_WAY:
				held = true
		for s: SolidBox in w.solids:
			if s.top == b.y and s.left < p + b.half_w and s.right > p - b.half_w:
				held = true
		if not held:
			return i
	return seg + 1


## What is wrong with where a falling body has got to, or "".
func _landing_problem(w: CollisionWorld, b: Body) -> String:
	if PhysicsKit.embedded(w, b):
		return "embedded at (%d, %d)" % [b.x, b.y]
	if PhysicsKit.hovering(w, b):
		return "hovering on a crest at (%d, %d)" % [b.x, b.y]
	var on: bool = b.on_ground
	var probe: Body = Body.make(b.x, b.y, b.half_w, b.height)
	w.refresh_ground(probe)
	if probe.on_ground != on:
		return "grounded %s, but %s on re-reading at (%d, %d)" % [on, probe.on_ground, b.x, b.y]
	return ""


## What is wrong with a walk by [param d] that moved [param moved], or "".
func _walk_problem(w: CollisionWorld, b: Body, d: int, moved: int) -> String:
	if PhysicsKit.embedded(w, b):
		return "embedded at (%d, %d)" % [b.x, b.y]
	var on: bool = b.on_ground
	var probe: Body = Body.make(b.x, b.y, b.half_w, b.height)
	w.refresh_ground(probe)
	if probe.on_ground != on:
		return "grounded %s, but %s on re-reading" % [on, probe.on_ground]
	if b.hit_wall != 0 and on and not PhysicsKit.blocked_for_a_reason(w, b, b.hit_wall):
		return "stopped by nothing at (%d, %d) after %d" % [b.x, b.y, moved]
	if b.hit_wall == 0 and on and moved != d:
		return "moved %d of %d with nothing in the way, at (%d, %d)" % [moved, d, b.x, b.y]
	return ""


## One random airborne move; "" if every invariant held, else what broke.
func _random_air_move(w: CollisionWorld, b: Body, rng: Rng) -> String:
	b.clear_contacts()
	b.on_ground = false
	var from := Vector2i(b.x, b.y)
	var d: int = rng.between(-30, 30) * U + rng.between(-255, 255)
	var op: String = ""
	if rng.below(2) == 0:
		op = "move_x(%d)" % d
		w.move_x(b, d, 8 * U, 6 * U)
	else:
		op = "move_y(%d)" % d
		w.move_y(b, d, 6 * U)
	if PhysicsKit.embedded(w, b):
		return "%s from %s embedded at (%d, %d)" % [op, from, b.x, b.y]
	if op.begins_with("move_y") and d > 0 and b.x == from.x:
		# The foot point's path down must not have crossed anything solid above where it ended.
		var y: int = from.y + U
		while y < b.y:
			if w.point_solid(b.x, y - 1):
				return "%s from %s passed solid at y=%d and ended at %d" % [op, from, y, b.y]
			y += U
		if _crossed_one_way(w, b, from.y):
			return "%s from %s fell through a one-way platform" % [op, from]
	return ""


## Random tiles and solid boxes; slopes that break the geometry rules are cleared. Half of the
## slopes are given a wall to rest on first, so that many survive.
func _soup_world(rng: Rng) -> CollisionWorld:
	var chars: String = "......#S=/\\abcd"
	var grid := TileGrid.new(18, 14)
	for j: int in range(14):
		for i: int in range(18):
			var t: int = TileGrid.SOLID
			if j < 13:
				t = TileGrid.CHARS.find(chars[rng.below(chars.length())])
			grid.set_tile(i, j, t)
	for j: int in range(13):
		for i: int in range(18):
			if TileGrid.is_slope(grid.get_tile(i, j)) and rng.below(2) == 0:
				grid.set_tile(i, j + 1, TileGrid.SOLID)
	for _pass: int in range(30):
		var bad: Array[Vector2i] = _bad_slopes(grid)
		if bad.is_empty():
			break
		for cell: Vector2i in bad:
			grid.set_tile(cell.x, cell.y, TileGrid.EMPTY)
	assert_array(Array(grid.validate())).is_empty()
	var w := CollisionWorld.new(grid)
	(load(WorldTuning.PATH) as WorldTuning).apply(w)
	for _s: int in range(rng.below(4)):
		var l: int = rng.between(0, 520) * U + rng.between(0, 255)
		var t2: int = rng.between(0, 380) * U + rng.between(0, 255)
		w.solids.append(
			SolidBox.make(l, t2, l + rng.between(8, 80) * U, t2 + rng.between(8, 80) * U)
		)
	return w


## Cells of the slopes [method TileGrid.validate] complains about.
func _bad_slopes(grid: TileGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var re: RegEx = RegEx.create_from_string("column (\\d+), row (\\d+)")
	for problem: String in grid.validate():
		var m: RegExMatch = re.search(problem)
		if m != null:
			out.append(Vector2i(m.get_string(1).to_int(), m.get_string(2).to_int()))
	return out


## A continuous ground across the room: flats, 45-degree and 1:2 slopes up and down, ramps often
## running over several tile rows.
func _terrain_world(rng: Rng) -> CollisionWorld:
	var width: int = 60
	var height: int = 14
	var grid := TileGrid.new(width, height)
	var level: int = 9
	var c: int = 0
	# A ramp kind (1 to 4) repeats for a run of up to four steps, so ramps span several tile rows
	# and their row boundaries (a slope over the wall that carries the next row's slope) are
	# common.
	var run_kind: int = 0
	var run_left: int = 0
	while c < width:
		var kind: int = rng.below(6)
		if run_left > 0:
			kind = run_kind
			run_left -= 1
		elif kind >= 1 and kind <= 4 and rng.below(2) == 0:
			run_kind = kind
			run_left = rng.between(1, 3)
		if c == 0 or c >= width - 2:
			kind = 0
		if (kind == 1 or kind == 3) and level <= 4:
			kind = 0
		if (kind == 2 or kind == 4) and level >= height - 3:
			kind = 0
		match kind:
			1:
				_ground(grid, c, level)
				grid.set_tile(c, level - 1, TileGrid.SLOPE_R)
				level -= 1
				c += 1
			2:
				_ground(grid, c, level + 1)
				grid.set_tile(c, level, TileGrid.SLOPE_L)
				level += 1
				c += 1
			3:
				_ground(grid, c, level)
				_ground(grid, c + 1, level)
				grid.set_tile(c, level - 1, TileGrid.SLOPE_R_LO)
				grid.set_tile(c + 1, level - 1, TileGrid.SLOPE_R_HI)
				level -= 1
				c += 2
			4:
				_ground(grid, c, level + 1)
				_ground(grid, c + 1, level + 1)
				grid.set_tile(c, level, TileGrid.SLOPE_L_HI)
				grid.set_tile(c + 1, level, TileGrid.SLOPE_L_LO)
				level += 1
				c += 2
			_:
				_ground(grid, c, level)
				c += 1
	assert_array(Array(grid.validate())).is_empty()
	var w := CollisionWorld.new(grid)
	(load(WorldTuning.PATH) as WorldTuning).apply(w)
	return w


func _ground(grid: TileGrid, c: int, from_row: int) -> void:
	for j: int in range(from_row, grid.height):
		grid.set_tile(c, j, TileGrid.SOLID)


func _copy(b: Body) -> Body:
	var c := Body.make(b.x, b.y, b.half_w, b.height)
	c.on_ground = b.on_ground
	c.ground_tile = b.ground_tile
	c.on_slope = b.on_slope
	return c


func _free_body(w: CollisionWorld, rng: Rng) -> Body:
	for _try: int in range(50):
		var b: Body = PhysicsKit.body(rng.between(20, 556), rng.between(50, 400))
		b.x += rng.between(0, 255)
		if w.body_fits(b.x, b.y, b.half_w, b.height):
			return b
	return null


func _crossed_one_way(w: CollisionWorld, b: Body, from_bottom: int) -> bool:
	for c: int in range(TileGrid.cell(b.left()), TileGrid.cell(b.right() - 1) + 1):
		for j: int in range(TileGrid.cell(from_bottom), TileGrid.cell(b.y) + 1):
			var top: int = j * TileGrid.TILE_SP
			if w.grid.get_tile(c, j) == TileGrid.ONE_WAY and from_bottom <= top and b.y > top:
				return true
	return false
