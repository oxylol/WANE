extends SceneTree
## How far past a ledge's edge each way of crossing a gap carries the player (BUILD.md section 5,
## tech 2: "a gap exactly one dash-jump wide"; docs/adr/0010). The reach is the farthest x of the
## player's centre with the feet at or above the ledge's height, on a room with no far side; a gap
## of width W is crossable when the reach is more than W minus half the body's width.
##
##   godot --headless --path . --script tools/replay/gap_reach.gd -- [route]...
##
## Routes (all of them by default):
##   plain       a dash-jump (the jump on dash frames 5 to 9) and nothing else
##   dash_air    a dash-jump and its air jump, no air dash
##   dash_jump   a dash-jump, its air jump, and the air dash right or up-right, before or after it
##   carry       no dash-jump of any kind (no jump on any dash's frames 5 to 9, the air dash's
##               included): a ground dash, a jump on a later frame (its carry-over frames in
##               coyote time), the air jump and the air dash, in either order
##   run         no dash-jump either: a running jump up to the last coyote frame, the air jump and
##               the air dash
##   carry_toss  carry with one Ember Toss: a throw (right or up-right) and the teleport to it
##   run_toss    run with one Ember Toss
## Each route is searched on a coarse grid of ticks and spawn points, then every tick around the
## best plan; a toss route starts from its route's best plan and searches the throw, the teleport
## and the air jump and air dash around them in turn until nothing improves. Hold right
## throughout; a jump is held until two ticks before the air jump, which is then held to the end.
## Takes a few minutes per route.

const ROOM: String = "test/longchasm"
const EDGE_U: int = 480
const LEDGE_U: int = 384
const FRAMES: int = 330
## Ticks 4 to 8 are dash frames 5 to 9 (the dash is pressed on tick 0).
const DASH_JUMP_TICKS: Array[int] = [4, 5, 6, 7, 8]
const NEVER: int = 100000


## One way through the gap: the spawn x, the jump, air jump and air dash ticks (NEVER for none),
## whether the air dash goes up-right, whether a ground dash starts on tick 0, and the Ember
## Toss's throw (up-right if [member toss_up]) and teleport ticks.
class Plan:
	var x0: int = 0
	var jump: int = 0
	var air: int = NEVER
	var dash: int = NEVER
	var up: bool = false
	var ground_dash: bool = true
	var toss: int = NEVER
	var toss_up: bool = false
	var port: int = NEVER

	func copy() -> Plan:
		var p := Plan.new()
		p.x0 = x0
		p.jump = jump
		p.air = air
		p.dash = dash
		p.up = up
		p.ground_dash = ground_dash
		p.toss = toss
		p.toss_up = toss_up
		p.port = port
		return p

	## Two presses never share a tick (each would read the other's stick).
	func clashes() -> bool:
		var ticks: Array[int] = [jump, air, dash, toss, port]
		for i: int in range(ticks.size()):
			for j: int in range(i + 1, ticks.size()):
				if ticks[i] != NEVER and ticks[i] == ticks[j]:
					return true
		return false

	func describe() -> String:
		var parts: PackedStringArray = ["spawn %d" % x0]
		if ground_dash:
			parts.append("ground dash t0")
		parts.append("jump t%d" % jump)
		if dash < air:
			parts.append("air dash%s t%d" % [" up-right" if up else "", dash])
		if air != NEVER:
			parts.append("air jump t%d" % air)
		if dash > air and dash != NEVER:
			parts.append("air dash%s t%d" % [" up-right" if up else "", dash])
		if toss != NEVER:
			parts.append("toss%s t%d, teleport t%d" % [" up-right" if toss_up else "", toss, port])
		return ", ".join(parts)


func _initialize() -> void:
	var routes: PackedStringArray = OS.get_cmdline_user_args()
	if routes.is_empty():
		routes = ["plain", "dash_air", "dash_jump", "carry", "run", "carry_toss", "run_toss"]
	for route: String in routes:
		var base: String = route.trim_suffix("_toss")
		var plans: Array[Plan] = _coarse(base)
		if plans.is_empty():
			printerr("unknown route '%s'" % route)
			quit(2)
			return
		var best: Plan = _best(plans, base)
		best = _best(_around(best, base), base)
		if route != base:
			best = _with_toss(best, route)
		print(
			"%-9s %5d u past the edge: %s" % [route, _reach(best, route) - EDGE_U, best.describe()]
		)
	quit(0)


func _coarse(route: String) -> Array[Plan]:
	var plans: Array[Plan] = []
	var dash_jump: bool = route == "plain" or route == "dash_air" or route == "dash_jump"
	var spawns: Array[int] = []
	var jumps: Array[int] = []
	if dash_jump:
		spawns.assign(range(300, EDGE_U + 1, 12))
		jumps.assign(DASH_JUMP_TICKS)
	elif route == "carry":
		spawns.assign(range(330, EDGE_U, 12))
		jumps.assign([9, 10, 11, 12, 14, 16])
	elif route == "run":
		spawns.assign(range(60, 330, 30))
		jumps.assign(range(10, 50, 4))
	else:
		return plans
	for x0: int in spawns:
		for jump: int in jumps:
			var base := Plan.new()
			base.x0 = x0
			base.jump = jump
			base.ground_dash = route != "run"
			if route == "plain":
				plans.append(base)
				continue
			if route == "dash_air":
				for air: int in range(jump + 8, jump + 64, 2):
					var p: Plan = base.copy()
					p.air = air
					plans.append(p)
				continue
			for air: int in range(jump + 8, jump + 64, 4):
				for dash: int in range(jump + 4, jump + 100, 8):
					for up: bool in [false, true]:
						var p: Plan = base.copy()
						p.air = air
						p.dash = dash if dash != air else dash + 1
						p.up = up
						plans.append(p)
	return plans


## [param p] with one Ember Toss: the throw and the teleport on a grid, then the air jump and air
## dash on a grid around them, then every tick around the four, until a pass improves nothing.
func _with_toss(p: Plan, route: String) -> Plan:
	var best: Plan = p
	var reach: int = _reach(p, route)
	var improved: bool = true
	while improved:
		improved = false
		var plans: Array[Plan] = []
		for toss: int in range(best.jump, best.jump + 150, 3):
			for toss_up: bool in [false, true]:
				for port: int in range(toss + 6, toss + 175, 4):
					var q: Plan = best.copy()
					q.toss = toss
					q.toss_up = toss_up
					q.port = port
					plans.append(q)
		var last: int = best.port if best.port != NEVER else best.jump + 60
		for air: int in range(best.jump + 8, last + 80, 4):
			for dash: int in range(best.jump + 4, last + 100, 6):
				for up: bool in [false, true]:
					var q: Plan = best.copy()
					q.air = air
					q.dash = dash
					q.up = up
					plans.append(q)
		for dt: int in range(-3, 4):
			for dp: int in range(-3, 4):
				for da: int in range(-2, 3):
					for dd: int in range(-2, 3):
						var q: Plan = best.copy()
						q.toss += dt
						q.port += dp
						q.air += da
						q.dash += dd
						plans.append(q)
		var found: Plan = _best(plans, route)
		var r: int = _reach(found, route)
		if r > reach:
			reach = r
			best = found
			improved = true
	return best


## Every plan within a few ticks (and spawn units) of [param p].
func _around(p: Plan, route: String) -> Array[Plan]:
	var plans: Array[Plan] = []
	var air_steps: Array[int] = [0]
	if p.air != NEVER:
		air_steps.assign(range(-4, 5))
	var dash_steps: Array[int] = [0]
	if p.dash != NEVER:
		dash_steps.assign(range(-6, 7))
	for dx: int in range(-12, 13):
		for dj: int in range(-2, 3):
			var jump: int = p.jump + dj
			if route == "plain" or route == "dash_air" or route == "dash_jump":
				if not DASH_JUMP_TICKS.has(jump):
					continue
			for da: int in air_steps:
				for dd: int in dash_steps:
					var q: Plan = p.copy()
					q.x0 = p.x0 + dx
					q.jump = jump
					q.air = p.air + da if p.air != NEVER else NEVER
					q.dash = p.dash + dd if p.dash != NEVER else NEVER
					if q.dash == q.air and q.dash != NEVER:
						continue
					plans.append(q)
	return plans


func _best(plans: Array[Plan], route: String) -> Plan:
	var best: Plan = plans[0]
	var best_reach: int = -1
	for p: Plan in plans:
		if p.clashes():
			continue
		var r: int = _reach(p, route)
		if r > best_reach:
			best_reach = r
			best = p
	return best


## The farthest x (units) with the feet at or above the ledge, or -1 if the plan is not the route
## it claims to be (a jump fired during any dash in a route without a dash-jump).
func _reach(p: Plan, route: String) -> int:
	var sc: Scenario = Scenario.make(1, ROOM)
	sc.spawn_x = p.x0
	sc.spawn_y = LEDGE_U
	var sim := Simulation.new(sc)
	var ledge: int = Fx.units(LEDGE_U)
	var best: int = 0
	var no_dash_jump: bool = route.begins_with("carry") or route.begins_with("run")
	for t: int in range(FRAMES):
		var dashing: bool = sim.player.loco == Player.DASH
		sim.step(_frame(p, t))
		var jumped: bool = sim.events.has(SimEvents.JUMP) or sim.events.has(SimEvents.AIR_JUMP)
		if no_dash_jump and dashing and jumped:
			return -1
		if sim.events.has(SimEvents.HAZARD):
			break
		var b: Body = sim.player.body
		if b.y <= ledge:
			best = maxi(best, b.x)
		elif b.y > ledge + Fx.units(64) and (p.port == NEVER or t >= p.port):
			# Fallen well below the ledge with no teleport still to come (one can bring the player
			# back up to an ember thrown high).
			break
	return Fx.div_floor(best, Fx.SUB)


func _frame(p: Plan, t: int) -> InputFrame:
	var held: int = 0
	var pressed: int = 0
	if (t >= p.jump and t <= p.air - 2) or t >= p.air:
		held |= InputFrame.JUMP
	if t == p.jump or t == p.air:
		pressed |= InputFrame.JUMP
	var stick_y: int = 0
	if (p.ground_dash and t == 0) or t == p.dash:
		pressed |= InputFrame.DASH
		if t == p.dash and p.up:
			stick_y = -127
	if t == p.toss or t == p.port:
		pressed |= InputFrame.TOSS
		if t == p.toss and p.toss_up:
			stick_y = -127
	return InputFrame.make(held, pressed, 127, stick_y)
