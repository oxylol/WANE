extends SceneTree
## A shard that ignores the mode it was given and runs the reference: what the runner must catch
## (tests/unit/tools/test_fixture_shards.gd). It runs only the fixtures of [constant SOME].

const SOME: Array[String] = [
	"res://tests/replay/movement/jump_full.fixture",
	"res://tests/replay/combat/side1_hits_dummy_once.fixture",
	"res://tests/replay/tech/tech02_dash_jump_frame5.fixture",
	"res://tests/replay/core/input_buffer_latest_press.fixture",
	"res://tests/replay/camera/cam_teleport.fixture",
]


func _initialize() -> void:
	NativeBackend.configure(NativeBackend.Mode.OFF)
	print(FixtureRunner.MODE_PREFIX + FixtureRunner.mode_line())
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var shard: int = args[args.find("--shard") + 1].to_int()
	var of: int = args[args.find("--of") + 1].to_int()
	for result: FixtureRunner.Result in FixtureRunner.new().run_paths(SOME, shard, of):
		print(FixtureRunner.RESULT_PREFIX + result.to_line())
	quit(0)
