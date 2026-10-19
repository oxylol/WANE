extends SceneTree
## Runs the given fixtures and prints each failing expectation (golden hashes are not checked;
## use tools/ci/run_tests.gd for the full gate). A directory runs every fixture under it.
##
##   godot --headless --path . --script tools/replay/check.gd -- <fixture path or dir>...


func _initialize() -> void:
	var runner := FixtureRunner.new()
	var failed: int = 0
	var paths: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if DirAccess.dir_exists_absolute(arg):
			paths.append_array(FileWalk.find(arg, [".fixture"]))
		else:
			paths.append(arg)
	for path: String in paths:
		var result: FixtureRunner.Result = runner.run_fixture(Fixture.parse_file(path))
		if result.passed:
			print("pass %s" % result.name)
		else:
			failed += 1
			print("FAIL %s" % path)
			for m: String in result.messages:
				print("    %s" % m)
	quit(1 if failed > 0 else 0)
