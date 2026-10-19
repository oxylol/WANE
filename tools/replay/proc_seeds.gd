extends SceneTree
## Finds run seeds whose PROCS stream rolls a given way, for proc fixtures (docs/adr/0015): a
## fixture that shows a chance working picks a seed whose rolls land where it needs them, and its
## doc line says so.
##
##   godot --headless --path . --script tools/replay/proc_seeds.gd -- <lo> <hi> [<lo> <hi>...]
##
## Prints the first seeds from 1 up (at most 8) whose first PROCS rolls (each [method Rng.below]
## of a million, as [ProcBus] rolls a chance) fall in [lo, hi), [lo, hi), ... in turn, and each
## seed's rolls.

const LIMIT: int = 8
const SEARCH: int = 100000


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() % 2 != 0:
		printerr("usage: proc_seeds.gd -- <lo> <hi> [<lo> <hi>...]")
		quit(2)
		return
	var found: int = 0
	for seed_value: int in range(1, SEARCH):
		var r: Rng = RngStreams.new(seed_value).procs()
		var rolls: PackedInt32Array = []
		var ok: bool = true
		for k: int in range(0, args.size(), 2):
			var roll: int = r.below(ProcBus.PPM)
			rolls.append(roll)
			if roll < args[k].to_int() or roll >= args[k + 1].to_int():
				ok = false
				break
		if ok:
			print("seed %d: rolls %s" % [seed_value, str(rolls)])
			found += 1
			if found >= LIMIT:
				break
	quit(0 if found > 0 else 1)
