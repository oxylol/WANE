extends SceneTree
## The door crossing's presentation cost (BUILD.md section 13, Testing and CI: no frame-time spike
## above 20 ms; docs/adr/0020). A door is crossed on one tick: [method Main._on_ticked] then shows
## the new room (the room view's tiles and, under Pitch, the lighting's occluders). That must cost
## no more than any other tick, so this plays it for every room of zone 1: the boot scene at Pitch
## (the stress room's lighting), then for each room a fresh [Simulation] on it and the time of
## [method Main.enter_room], the call the room event makes. The first crossing into each room is
## what is timed (a second would find anything cached), the least over [member PerfBudget.repeats]
## fresh boots; the worst room is gated against [member PerfBudget.door_max_us]. Headless (the
## dummy renderer) this is the script and scene-tree cost, as in frame_bench.gd.
##
##   godot --headless --path . --script tools/bench/door_bench.gd [-- --quiet --report <path>]

const SCENE: String = "res://game/main.tscn"
## Frames a boot is given before the crossings are timed.
const SETTLE_FRAMES: int = 3

var _quiet: bool = false
var _report: String = ""
var _lines: PackedStringArray = PackedStringArray()
var _budget: PerfBudget
var _rooms: PackedStringArray = PackedStringArray()
var _best: PackedInt32Array = PackedInt32Array()
var _boot_us: int = 0
var _pass: int = 0
var _frame: int = 0
var _main: Main
var _done: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_quiet = args.has("--quiet")
	var at: int = args.find("--report")
	_report = args[at + 1] if at >= 0 and at + 1 < args.size() else ""
	_budget = load(PerfBudget.PATH) as PerfBudget
	var zone: ZoneDef = load("res://content/zones/zone1.tres") as ZoneDef
	_rooms = PackedStringArray(zone.rooms)
	_best.resize(_rooms.size())
	_best.fill(1 << 30)
	_boot()


func _boot() -> void:
	# The boot scene reads these when it enters the tree, which is after this call.
	Main.lighting_word = LightingRig.PITCH
	Main.scenario_override = Scenario.make(1, _rooms[0])
	var started: int = Time.get_ticks_usec()
	_main = (load(SCENE) as PackedScene).instantiate() as Main
	_main.save_on_exit = false
	root.add_child(_main)
	_boot_us = Time.get_ticks_usec() - started
	_frame = 0


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return false
	if _main.lighting == null:
		printerr("the boot scene built no lighting")
		quit(1)
		return true
	for i: int in range(_rooms.size()):
		var sim := Simulation.new(Scenario.make(1, _rooms[i]))
		var t: int = Time.get_ticks_usec()
		_main.enter_room(sim)
		_best[i] = mini(_best[i], Time.get_ticks_usec() - t)
	_pass += 1
	_main.free()
	if _pass < _budget.repeats:
		_boot()
		return false
	_finish()
	return true


func _finish() -> void:
	_done = true
	Main.lighting_word = ""
	Main.scenario_override = null
	var worst: int = 0
	var failures: PackedStringArray = PackedStringArray()
	_say(
		(
			"door crossings, zone 1 at Pitch, %d rooms, least of %d boots (boot %.1f ms):"
			% [_rooms.size(), _budget.repeats, float(_boot_us) / 1000.0]
		),
		false
	)
	for i: int in range(_rooms.size()):
		worst = maxi(worst, _best[i])
		_say("  %-28s %6.2f ms" % [_rooms[i], float(_best[i]) / 1000.0], false)
	var line: String = (
		"door crossing worst %.2f ms (gate %.2f ms)"
		% [float(worst) / 1000.0, float(_budget.door_max_us) / 1000.0]
	)
	_say(line, true)
	if worst > _budget.door_max_us:
		failures.append(line)
	if _report != "":
		DirAccess.make_dir_recursive_absolute(_report.get_base_dir())
		var f: FileAccess = FileAccess.open(_report, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_lines) + "\n")
			f.close()
	if failures.is_empty():
		print("DOOR GATE PASSED")
		quit(0)
	else:
		print("DOOR GATE FAILED")
		quit(1)


func _say(line: String, gate: bool) -> void:
	_lines.append(line)
	if gate or not _quiet:
		print(line)
