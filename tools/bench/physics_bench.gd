extends SceneTree
## Physics cost per tick for 200 bodies (BUILD.md section 13 frame budget: input + simulation
## 3.0 ms). Each body walks the way a patrolling enemy does every tick (turning at walls), and a
## body that is not on the ground moves through the air and falls. Three grounds:
## - flat: a long floor;
## - slopes: a sawtooth of 45-degree and 1:2 slopes over a plateau;
## - ledges: platforms three tiles wide with one-tile pits, so bodies keep walking off ledges
##   (a body that falls to the floor below is put back above the platforms);
## each with no solid boxes and with 20 (doors and wax walls out of the bodies' way, which every
## query still has to look at). Bodies move as enemies do (no corner lift) and as the player does
## (the 8 u lift and 6 u slide, and in the air the far-edge landing first, which tries the plain
## step on a copy of the body: physics review 6, L3).
##
## The patrols take the far-edge landing a handful of times in 40,000 body-ticks, so its own cost
## is measured apart (physics review 7, L4): 200 bodies each put just above a platform's far edge,
## falling onto it as they move off it, every one of them landing there, timed against the plain
## air step from the same places in open air.
##
##   godot --headless --path . --script tools/bench/physics_bench.gd [-- far_edge]

const BODIES: int = 200
const TICKS: int = 200
const WIDTH: int = 118
## Repeats of the far-edge measurement's 200 steps.
const FAR_EDGE_REPS: int = 50


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("far_edge"):
		_far_edge_rows()
		quit(0)
		return
	var grounds: Dictionary[String, Array] = {
		"flat": _flat_rows(),
		"slopes": _slope_rows(),
		"ledges": _ledge_rows(),
	}
	print("ground   solids  speed  mover   ms per tick")
	for ground: String in grounds:
		var rows: Array[String] = []
		rows.assign(grounds[ground])
		for solids: int in [0, 20]:
			for speed: int in [9, 20]:
				for lift: int in [0, 8]:
					var ms: float = _run(rows, speed, solids, ground == "ledges", lift)
					var mover: String = "player" if lift > 0 else "enemy"
					print("%-8s %6d  %2d u/f  %-6s  %5.2f" % [ground, solids, speed, mover, ms])
	_far_edge_rows()
	quit(0)


func _far_edge_rows() -> void:
	print("step                 speed  landed   us per step")
	for speed: int in [9, 20]:
		var far: Vector2 = _far_edge_cost(speed, 0)
		var plain: Vector2 = _far_edge_cost(speed, 64)
		print("far-edge landing     %2d u/f  %3d/%d  %6.1f" % [speed, far.y, BODIES, far.x])
		print("plain air step       %2d u/f  %3d/%d  %6.1f" % [speed, plain.y, BODIES, plain.x])


## Microseconds per player air step (a body copy included) for bodies put 2 u above the platforms
## of the ledge ground, 8 u inside each far edge, moving off it at [param speed] u/f and falling
## 8 u/f, raised [param raise_u] above that (64 u: open air, the plain step); and how many landed
## on the edge.
func _far_edge_cost(speed: int, raise_u: int) -> Vector2:
	var w := CollisionWorld.new(TileGrid.from_rows(PackedStringArray(_ledge_rows())))
	var starts: Array[Body] = []
	for i: int in range(BODIES):
		# Platform k spans x 128 k + 32 to 128 k + 128, its top at y 192.
		var edge: int = Fx.units(128 * (i % (WIDTH / 4 - 1)) + 128)
		starts.append(
			Body.make(edge + Fx.units(2), Fx.units(190 - raise_u), Fx.units(10), Fx.units(44))
		)
	var lift: int = Fx.units(8)
	var slide: int = Fx.units(6)
	var dx: int = Fx.units(speed)
	var dy: int = Fx.units(8)
	var landed: int = 0
	var start: int = Time.get_ticks_usec()
	for rep: int in range(FAR_EDGE_REPS):
		for s: Body in starts:
			var b: Body = s.copy()
			var contact: int = w.landing_contact(b, dx, dy, lift, slide)
			if contact != CollisionQueries.NONE:
				landed += 1 if rep == 0 else 0
				w.move_x(b, contact)
				w.move_y(b, dy)
				w.walk(b, dx - contact, lift)
			else:
				w.move_x(b, dx, lift, slide)
				w.move_y(b, dy, slide)
	var us: float = float(Time.get_ticks_usec() - start) / float(FAR_EDGE_REPS * BODIES)
	return Vector2(us, landed)


func _flat_rows() -> Array[String]:
	var rows: Array[String] = []
	for j: int in range(12):
		rows.append("#" + (".".repeat(WIDTH) if j < 10 else "#".repeat(WIDTH)) + "#")
	return rows


func _slope_rows() -> Array[String]:
	var row8: String = "#"
	while row8.length() < WIDTH + 1:
		row8 += "./###\\..ab##cd."
	var rows: Array[String] = []
	for j: int in range(12):
		if j < 8:
			rows.append("#" + ".".repeat(WIDTH) + "#")
		elif j == 8:
			rows.append(row8.substr(0, WIDTH + 1) + "#")
		else:
			rows.append("#" + "#".repeat(WIDTH) + "#")
	return rows


func _ledge_rows() -> Array[String]:
	var rows: Array[String] = []
	for j: int in range(12):
		if j == 6:
			rows.append("#" + "###.".repeat(WIDTH / 4) + "##" + "#")
		elif j >= 10:
			rows.append("#".repeat(WIDTH + 2))
		else:
			rows.append("#" + ".".repeat(WIDTH) + "#")
	return rows


func _run(rows: Array[String], speed: int, solid_count: int, respawn: bool, lift_u: int) -> float:
	var grid: TileGrid = TileGrid.from_rows(PackedStringArray(rows))
	var problems: PackedStringArray = grid.validate()
	if not problems.is_empty():
		printerr(problems)
	var w := CollisionWorld.new(grid)
	for k: int in range(solid_count):
		var x: int = Fx.units(100 + k * 180)
		w.solids.append(SolidBox.make(x, Fx.units(40), x + Fx.units(20), Fx.units(60)))
	var bodies: Array[Body] = []
	for i: int in range(BODIES):
		var b := Body.make(
			Fx.units(40 + (i * 17) % 3700), Fx.units(100), Fx.units(10), Fx.units(44)
		)
		w.move_y(b, Fx.units(400))
		bodies.append(b)
	var dirs: PackedInt32Array = PackedInt32Array()
	dirs.resize(BODIES)
	dirs.fill(1)
	var floor_y: int = Fx.units(320)
	var lift: int = Fx.units(lift_u)
	var slide: int = Fx.units(6) if lift_u > 0 else 0
	var start: int = Time.get_ticks_usec()
	for _t: int in range(TICKS):
		for i: int in range(BODIES):
			var b: Body = bodies[i]
			b.clear_contacts()
			var dx: int = dirs[i] * Fx.units(speed)
			if b.on_ground:
				w.walk(b, dx, lift)
			else:
				var contact: int = CollisionQueries.NONE
				if lift > 0:
					contact = w.landing_contact(b, dx, Fx.units(8), lift, slide)
				if contact != CollisionQueries.NONE:
					w.move_x(b, contact)
					w.move_y(b, Fx.units(8))
					w.walk(b, dx - contact, lift)
				else:
					w.move_x(b, dx, lift, slide)
					w.move_y(b, Fx.units(8), slide)
			if b.hit_wall != 0:
				dirs[i] = -dirs[i]
			if respawn and b.y >= floor_y:
				b.y = Fx.units(100)
				b.on_ground = false
	return float(Time.get_ticks_usec() - start) / 1000.0 / TICKS
