extends SceneTree
## A shard that ignores the mode it was given and runs the reference: what the runner must catch
## (tests/unit/tools/test_fixture_shards.gd). It runs the fixtures it is handed, as a real shard
## does ([code]tools/replay/fixture_shard.gd[/code]), but on the GDScript path.


func _initialize() -> void:
	NativeBackend.configure(NativeBackend.Mode.OFF)
	print(FixtureRunner.MODE_PREFIX + FixtureRunner.mode_line())
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var places: PackedInt32Array = PackedInt32Array()
	for place: String in args[args.find("--places") + 1].split(",", false):
		places.append(place.to_int())
	var paths: Array[String] = FileWalk.find(FixtureRunner.FIXTURE_ROOT, [".fixture"])
	for result: FixtureRunner.Result in FixtureRunner.new().run_places(paths, places):
		print(FixtureRunner.RESULT_PREFIX + result.to_line())
	quit(0)
