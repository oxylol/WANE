extends SceneTree
## Headless test entry point (CLAUDE.md, "Engine and environment").
##
##   godot --headless --path . --script tools/ci/run_tests.gd [-- --stage <name>...]
##
## Stages, in order:
##   compile   every first-party script compiles under the warnings-as-errors policy (ADR-0002),
##             and core/ obeys CLAUDE.md rules 1 and 2 (tools/ci/core_purity.gd)
##   content   every resource under content/ loads and passes its schema's validate()
##   fixtures  every replay fixture under tests/replay/ passes (BUILD.md section 13)
##   unit      every gdUnit4 suite under tests/unit/ passes
## The process exits 1 if any stage fails and 2 on a bad command line.

const SKIP_DIRS: Array[String] = ["res://.godot", "res://addons/gdUnit4", "res://reports"]
const CONTENT_ROOT: String = "res://content"
const UNIT_ROOT: String = "res://tests/unit"
const REPORT_DIR: String = "res://reports"
const ALL_STAGES: Array[String] = ["compile", "content", "fixtures", "unit"]


func _init() -> void:
	var stages: Array[String] = _requested_stages()
	if stages.is_empty():
		quit(2)
		return
	var failed: Array[String] = []
	var started_usec: int = Time.get_ticks_usec()
	for stage: String in stages:
		print("== stage: %s" % stage)
		var ok: bool = _run_stage(stage)
		print("== stage %s: %s" % [stage, "PASS" if ok else "FAIL"])
		if not ok:
			failed.append(stage)
	var seconds: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	if failed.is_empty():
		print("ALL STAGES PASSED (%.1f s)" % seconds)
		quit(0)
	else:
		printerr("FAILED STAGES: %s (%.1f s)" % [", ".join(failed), seconds])
		quit(1)


func _run_stage(stage: String) -> bool:
	match stage:
		"compile":
			return _stage_compile()
		"content":
			return _stage_content()
		"fixtures":
			return _stage_fixtures()
		"unit":
			return _stage_unit()
	return false


## Stages named with --stage (all of them if none); empty on an unknown name.
func _requested_stages() -> Array[String]:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var picked: Array[String] = []
	var i: int = 0
	while i < args.size():
		if args[i] != "--stage" or i + 1 >= args.size():
			printerr("usage: run_tests.gd [-- --stage <%s>]..." % "|".join(ALL_STAGES))
			return []
		var stage: String = args[i + 1]
		if not ALL_STAGES.has(stage):
			printerr("unknown stage '%s' (stages: %s)" % [stage, ", ".join(ALL_STAGES)])
			return []
		if not picked.has(stage):
			picked.append(stage)
		i += 2
	if picked.is_empty():
		return ALL_STAGES.duplicate()
	var ordered: Array[String] = []
	for stage: String in ALL_STAGES:
		if picked.has(stage):
			ordered.append(stage)
	return ordered


## Every first-party file under res:// with one of [param suffixes].
static func project_files(suffixes: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for path: String in FileWalk.find("res://", suffixes):
		var skip: bool = false
		for dir: String in SKIP_DIRS:
			if path.begins_with(dir + "/"):
				skip = true
				break
		if not skip:
			out.append(path)
	return out


func _stage_compile() -> bool:
	var paths: Array[String] = project_files([".gd"])
	var bad: Array[String] = []
	for path: String in paths:
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			bad.append(path)
	print("compiled %d scripts, %d failed" % [paths.size(), bad.size()])
	for path: String in bad:
		printerr("  does not compile: %s" % path)
	var impure: PackedStringArray = CorePurity.new().check_core()
	for problem: String in impure:
		printerr("  core rule broken: %s" % problem)
	print("core purity: %d problems" % impure.size())
	return bad.is_empty() and impure.is_empty()


func _stage_content() -> bool:
	var paths: Array[String] = FileWalk.find(CONTENT_ROOT, [".tres", ".res"])
	var problems: int = 0
	for path: String in paths:
		var res: Resource = load(path)
		if res == null:
			printerr("  cannot load: %s" % path)
			problems += 1
			continue
		if not res.has_method("validate"):
			printerr("  %s: no schema (its script has no validate())" % path)
			problems += 1
			continue
		var errors: PackedStringArray = res.call("validate")
		for message: String in errors:
			printerr("  %s: %s" % [path, message])
		problems += errors.size()
	print("validated %d content resources, %d problems" % [paths.size(), problems])
	return problems == 0


func _stage_fixtures() -> bool:
	var runner_path: String = "res://tools/replay/fixture_runner.gd"
	if not ResourceLoader.exists(runner_path):
		print("no fixture runner yet (Phase 1 task 1 adds it)")
		return true
	var runner_script: GDScript = load(runner_path) as GDScript
	var runner: Object = runner_script.new()
	var ok: bool = runner.call("run_all")
	return ok


func _stage_unit() -> bool:
	if FileWalk.find(UNIT_ROOT, [".gd"]).is_empty():
		print("no unit suites")
		return true
	# Reports live in the project folder for CI artifacts; .gdignore keeps Godot from importing
	# the report's images as project assets.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	var ignore: FileAccess = FileAccess.open(REPORT_DIR.path_join(".gdignore"), FileAccess.WRITE)
	ignore.close()
	var args: PackedStringArray = [
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"-s",
		"-d",
		# Needed with -d: without a remote debugger, a script error drops the child process into
		# Godot's interactive command-line debugger and the run hangs. Port 0 is never bound, so
		# the connection is refused at once (Godot prints two harmless ERROR lines for it).
		"--remote-debug",
		"tcp://127.0.0.1:0",
		"res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
		"--ignoreHeadlessMode",
		"-c",
		"-rd",
		REPORT_DIR,
		"-a",
		UNIT_ROOT,
	]
	var output: Array[String] = []
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	for chunk: String in output:
		print(chunk)
	return code == 0
