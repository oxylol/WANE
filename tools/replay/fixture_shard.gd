extends SceneTree
## One process's share of the fixture suite, run by [FixtureRunner]: the fixtures whose place in
## the suite is the shard number modulo the shard count, each result printed on a line of its own
## for the runner to read (docs/adr/0006).
##
##   godot --headless --path . --script tools/replay/fixture_shard.gd -- --shard <k> --of <n>


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var shard: int = 0
	var of: int = 1
	for i: int in range(args.size() - 1):
		if args[i] == "--shard":
			shard = args[i + 1].to_int()
		elif args[i] == "--of":
			of = maxi(args[i + 1].to_int(), 1)
	var paths: Array[String] = FileWalk.find(FixtureRunner.FIXTURE_ROOT, [".fixture"])
	for result: FixtureRunner.Result in FixtureRunner.new().run_paths(paths, shard, of):
		print(FixtureRunner.RESULT_PREFIX + result.to_line())
	quit(0)
