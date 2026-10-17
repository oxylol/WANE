class_name ShaftJumps
extends RefCounted
## Writes a fixture that wall-jumps up a shaft, jumping off each wall the tick Ash clings to it:
## a closed-loop policy played through a simulation once and recorded as a plain input script, so
## the camera tests can sweep shaft widths without storing one generated fixture per width.


## The fixture text for [param frames] ticks in [param room] from ([param x], [param y]): the
## first jump is held 15 ticks, each wall jump 11, and Ash jumps off a wall [param delay] ticks
## after clinging to it.
static func fixture_text(room: String, x: int, y: int, frames: int, delay: int = 0) -> String:
	var head: String = (
		"fixture shaft_jumps\ndoc wall-jumps up a shaft (generated)\nroom %s\nspawn %d %d\nframes %d\n"
		% [room, x, y, frames]
	)
	var fx: Fixture = Fixture.parse_text(head + "input\nend\nexpect\nend\n")
	var sim := Simulation.new(fx.scenario)
	var lines: PackedStringArray = []
	var dir: int = -1
	var cling_ticks: int = 0
	var hold_left: int = 15
	var was_held: bool = false
	for f: int in range(frames):
		var jump: bool = hold_left > 0
		hold_left -= 1
		if sim.player.loco == Player.WALL:
			cling_ticks += 1
			if cling_ticks > delay and not was_held:
				dir = -sim.player.wall_side
				jump = true
				hold_left = 11
				cling_ticks = 0
			elif was_held:
				jump = false
				hold_left = 0
		else:
			cling_ticks = 0
		var held: int = InputFrame.JUMP if jump else 0
		var pressed: int = held if not was_held else 0
		was_held = jump
		sim.step(InputFrame.make(held, pressed, dir * InputFrame.STICK_MAX, 0))
		lines.append("  %d %s%s" % [f, "L" if dir < 0 else "R", " jump" if jump else ""])
	return head + "input\n" + "\n".join(lines) + "\nend\nexpect\nend\n"
