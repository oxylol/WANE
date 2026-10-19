extends SceneTree
## Which first dashes carry the player across a chasm (BUILD.md section 5, tech 7; docs/adr/0010,
## Dash: a dash in the first 6 frames after walking off a ledge is a ground dash and leaves the air
## dash). A plan crosses when it stands on the far ledge (on the floor, centre at or past the given
## x) before the frame limit. Measure on the room itself: a body that moves 20 u in a tick meets
## the far face between ticks, so the reach measured as in gap_reach.gd (the farthest tick-end x on
## a chasm with no far side) understates what crosses by up to a tick's travel.
##
##   godot --headless --path . --script tools/replay/coyote_scan.gd -- <fixture> <far u> \
##       <spawn lo> <spawn hi> <spawn step> <first dash lo> <first dash hi> [up]
##
## The fixture gives the room and the spawn height; the spawns should be on the last ledge before
## the chasm, each far enough back to be running at full speed at the edge, and their different
## phases cover the sub-unit position at which the floor ends. The first dash's ticks are counted
## from the tick on which the floor ends under a run with no dash (0): the player is still on the
## floor when that tick's input is read, so a dash on it is a ground dash, the last one; 1 is the
## first tick of coyote time. Every plan holds right, presses the first dash on tick T, the second
## dash 12 to 20 ticks after it (right, and up-right too with the last argument "up") or none, and
## a jump 12 to 36 ticks after it, held to the end. The first dash is filed by the state the player
## is in when it is read: "ground" (on the floor, however close to the edge, including the tick on
## which the floor ends), "coyote" (airborne and it left the air dash alone, so it was a coyote
## dash) or "air" (the air dash). Prints, per kind, how many plans cross and the first one that
## does.

const FRAMES: int = 200
const SECOND_DASH_GAPS: Array[int] = [0, 12, 13, 14, 15, 16, 17, 18, 19, 20]
const JUMP_GAPS_LO: int = 12
const JUMP_GAPS_HI: int = 36
const KINDS: Array[String] = ["ground", "coyote", "air"]


## One way over the chasm.
class Plan:
	var x0: int = 0
	var first: int = 0
	var second: int = 0
	var up: bool = false
	var jump: int = 0

	func describe() -> String:
		return (
			"spawn %d, dash t%d, 2nd dash +%d%s, jump +%d"
			% [x0, first, second, " up-right" if up else "", jump]
		)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 7:
		printerr("usage: coyote_scan.gd -- <fixture> <far u> <spawn lo> <hi> <step> <dash lo> <hi>")
		quit(2)
		return
	var fx: Fixture = Fixture.parse_file(args[0])
	var far: int = int(args[1])
	var ups: Array[bool] = [false]
	if args.size() > 7 and args[7] == "up":
		ups.append(true)
	var first_plan: Dictionary[String, Plan] = {}
	var tried: Dictionary[String, int] = {"ground": 0, "coyote": 0, "air": 0}
	var crossed: Dictionary[String, int] = {"ground": 0, "coyote": 0, "air": 0}
	for x0: int in range(int(args[2]), int(args[3]) + 1, int(args[4])):
		var floor_ends: int = _floor_ends(fx.scenario, x0)
		for rel: int in range(int(args[5]), int(args[6]) + 1):
			var first: int = floor_ends + rel
			for second: int in SECOND_DASH_GAPS:
				for up: bool in ups:
					if second == 0 and up:
						continue
					for jump: int in range(JUMP_GAPS_LO, JUMP_GAPS_HI + 1):
						if second != 0 and jump == second:
							continue
						var p := Plan.new()
						p.x0 = x0
						p.first = first
						p.second = second
						p.up = up
						p.jump = jump
						var result: Vector2i = _run(fx.scenario, p, far)
						if result.x < 0:
							continue
						var kind: String = KINDS[result.x]
						tried[kind] += 1
						if result.y == 1:
							crossed[kind] += 1
							if not first_plan.has(kind):
								first_plan[kind] = p
	for kind: String in KINDS:
		var line: String = "%-6s %4d of %4d plans cross" % [kind, crossed[kind], tried[kind]]
		if first_plan.has(kind):
			line += ", e.g. " + first_plan[kind].describe()
		print(line)
	quit(0)


## The first tick of a run holding right from [param x0] on which the player is not on the floor.
func _floor_ends(base: Scenario, x0: int) -> int:
	var sc: Scenario = base.copy()
	sc.spawn_x = x0
	var sim := Simulation.new(sc)
	for t: int in range(FRAMES):
		sim.step(InputFrame.make(0, 0, 127, 0))
		if sim.player.loco != Player.GROUND:
			return t
	return FRAMES


## (index into KINDS, 1 if the plan crosses else 0); the kind is -1 when the first dash never fired.
func _run(base: Scenario, p: Plan, far: int) -> Vector2i:
	var sc: Scenario = base.copy()
	sc.spawn_x = p.x0
	var sim := Simulation.new(sc)
	var kind: int = -1
	var far_sub: int = Fx.units(far)
	for t: int in range(FRAMES):
		var pre_ground: bool = sim.player.loco == Player.GROUND
		sim.step(_frame(p, t))
		if t == p.first:
			if not sim.events.has(SimEvents.DASH):
				return Vector2i(-1, 0)
			if pre_ground:
				kind = 0
			elif sim.player.air_dashes_left == 1:
				kind = 1
			else:
				kind = 2
		if sim.events.has(SimEvents.HAZARD) or sim.events.has(SimEvents.ROOM):
			return Vector2i(kind, 1 if sim.events.has(SimEvents.ROOM) else 0)
		if t > p.first and sim.player.loco == Player.GROUND and sim.player.body.x >= far_sub:
			return Vector2i(kind, 1)
	return Vector2i(kind, 0)


func _frame(p: Plan, t: int) -> InputFrame:
	var held: int = 0
	var pressed: int = 0
	var stick_y: int = 0
	if t >= p.first + p.jump:
		held |= InputFrame.JUMP
	if t == p.first + p.jump:
		pressed |= InputFrame.JUMP
	if t == p.first or (p.second != 0 and t == p.first + p.second):
		pressed |= InputFrame.DASH
		if t != p.first and p.up:
			stick_y = -127
	return InputFrame.make(held, pressed, 127, stick_y)
