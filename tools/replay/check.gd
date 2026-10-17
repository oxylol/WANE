extends SceneTree
## Runs the given fixtures and prints each failing expectation (golden hashes are not checked;
## use tools/ci/run_tests.gd for the full gate).
##
##   godot --headless --path . --script tools/replay/check.gd -- <fixture path>...


func _initialize() -> void:
	var runner := FixtureRunner.new()
	var failed: int = 0
	for path: String in OS.get_cmdline_user_args():
		var result: FixtureRunner.Result = runner.run_fixture(Fixture.parse_file(path))
		if result.passed:
			print("pass %s" % result.name)
		else:
			failed += 1
			print("FAIL %s" % path)
			for m: String in result.messages:
				print("    %s" % m)
	quit(1 if failed > 0 else 0)
