extends SceneTree
## One process's share of the fixture suite, run by [FixtureRunner]: the fixtures whose place in
## the suite is the shard number modulo the shard count, each result printed on a line of its own
## for the runner to read (docs/adr/0006).
##
##   godot --headless --path . --script tools/replay/fixture_shard.gd -- --shard <k> --of <n>
##       [--places <i>,<j>,...] [--native off|auto|on]
##
## With --places the shard runs the fixtures at those places in the suite (the order of the
## sorted paths under tests/replay), the share the runner planned for it
## ([method FixtureRunner.plan_shards]); without, the places whose number is the shard modulo the
## shard count.
##
## The work is in _initialize(), not _init(): the NativeBoot autoload (which reads WANE_NATIVE)
## exists only from there on, and a shard must run on the path the suite was asked to prove
## (ADR-0021). The runner also passes its own mode as --native, and a shard prints the mode it ran
## on before its first result, so the runner can see that the A/B of native off and on was real.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var shard: int = 0
	var of: int = 1
	var places: PackedInt32Array = PackedInt32Array()
	var planned: bool = false
	for i: int in range(args.size() - 1):
		if args[i] == "--shard":
			shard = args[i + 1].to_int()
		elif args[i] == "--of":
			of = maxi(args[i + 1].to_int(), 1)
		elif args[i] == "--places":
			planned = true
			for place: String in args[i + 1].split(",", false):
				places.append(place.to_int())
		elif args[i] == "--native":
			var parsed: int = NativeBackend.parse_mode(args[i + 1])
			if parsed < 0:
				printerr("shard: --native is '%s'; expected off, auto or on" % args[i + 1])
				quit(1)
				return
			NativeBackend.configure(parsed as NativeBackend.Mode)
	if NativeBackend.mode() == NativeBackend.Mode.ON and not NativeBackend.available():
		printerr("shard: native mode on but %s" % NativeBackend.problem())
		quit(1)
		return
	print(FixtureRunner.MODE_PREFIX + FixtureRunner.mode_line())
	var paths: Array[String] = FileWalk.find(FixtureRunner.FIXTURE_ROOT, [".fixture"])
	var runner := FixtureRunner.new()
	var results: Array[FixtureRunner.Result] = (
		runner.run_places(paths, places) if planned else runner.run_paths(paths, shard, of)
	)
	for result: FixtureRunner.Result in results:
		print(FixtureRunner.RESULT_PREFIX + result.to_line())
	print(FixtureRunner.CPU_PREFIX + str(FixtureRunner.process_cpu_msec()))
	quit(0)
