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
## --no-time-budget lifts the fixture suite's 10 s budget, for runs that are slow on purpose (the
## instrumented copy tools/ci/gd_coverage.py runs). The process exits 1 if any stage fails and 2
## on a bad command line.

const SKIP_DIRS: Array[String] = ["res://.godot", "res://addons/gdUnit4", "res://reports"]
const CONTENT_ROOT: String = "res://content"
const UNIT_ROOT: String = "res://tests/unit"
const REPORT_DIR: String = "res://reports"
const ALL_STAGES: Array[String] = ["compile", "content", "fixtures", "unit"]
## The unit run is stopped, with a diagnosis, once it has printed this many engine or script
## errors (a broken invariant asserting in a loop) or run this long; gdUnit4 slows down sharply
## as errors pile up, and without these limits CI would only time out, with nothing to read.
const UNIT_MAX_ERRORS: int = 50
const UNIT_TIME_LIMIT_SECONDS: int = 600
## The unit stage's limit in a run that is slow on purpose (--no-time-budget: the instrumented copy
## runs several times slower, and the camera suites alone take over ten minutes in it).
const SLOW_UNIT_TIME_LIMIT_SECONDS: int = 2400

var _errors: ErrorCounter = ErrorCounter.new()
var _time_budget: bool = true


# The stages run from _initialize(), not _init(): only then is this script the engine's main
# loop, which the coverage probe (tools/ci/gd_coverage.py) needs to dump its hits at exit.
func _initialize() -> void:
	var stages: Array[String] = _requested_stages()
	if stages.is_empty():
		quit(2)
		return
	var failed: Array[String] = []
	var started_usec: int = Time.get_ticks_usec()
	OS.add_logger(_errors)
	for stage: String in stages:
		print("== stage: %s" % stage)
		var errors_before: int = _errors.errors
		var ok: bool = _run_stage(stage)
		if _errors.errors > errors_before and stage != "compile":
			printerr(
				(
					"  %d engine or script error(s) during the stage; first: %s"
					% [_errors.errors - errors_before, _errors.first]
				)
			)
			ok = false
		print("== stage %s: %s" % [stage, "PASS" if ok else "FAIL"])
		if not ok:
			failed.append(stage)
	var seconds: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	OS.remove_logger(_errors)
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
		if args[i] == "--no-time-budget":
			_time_budget = false
			i += 1
			continue
		if args[i] != "--stage" or i + 1 >= args.size():
			printerr(
				"usage: run_tests.gd [-- [--no-time-budget] --stage <%s>...]" % "|".join(ALL_STAGES)
			)
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
	# Rooms are text, not resources: their schema is the room parser and the geometry rules
	# (docs/adr/0009).
	var rooms: Array[String] = FileWalk.find(RoomData.CONTENT_ROOT, [".room"])
	for path: String in rooms:
		var room_id: String = path.trim_prefix(RoomData.CONTENT_ROOT).trim_suffix(".room")
		var room: RoomData = RoomData.load_id(room_id)
		for message: String in room.errors:
			printerr("  %s: %s" % [path, message])
		problems += room.errors.size()
	print(
		(
			"validated %d content resources and %d rooms, %d problems"
			% [paths.size(), rooms.size(), problems]
		)
	)
	return problems == 0


func _stage_fixtures() -> bool:
	var runner_path: String = "res://tools/replay/fixture_runner.gd"
	if not ResourceLoader.exists(runner_path):
		print("no fixture runner yet (Phase 1 task 1 adds it)")
		return true
	var runner_script: GDScript = load(runner_path) as GDScript
	var runner: Object = runner_script.new()
	if not _time_budget:
		# An instrumented coverage run: one process, so the instrumentation sees every fixture.
		runner.set("budget_msec", 0)
		runner.set("shards", 1)
	var ok: bool = runner.call("run_all")
	return ok


func _stage_unit() -> bool:
	if FileWalk.find(UNIT_ROOT, [".gd"]).is_empty():
		print("no unit suites")
		return true
	# Reports live in the project folder for CI artifacts (one run's worth: reports/report_1);
	# .gdignore keeps Godot from importing the report's images as project assets.
	_remove_tree(ProjectSettings.globalize_path(REPORT_DIR))
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
	var info: Dictionary[String, Variant] = {}
	info.assign(OS.execute_with_pipe(OS.get_executable_path(), args, false))
	if info.is_empty():
		printerr("  cannot start the gdUnit4 run")
		return false
	var pid: int = info["pid"]
	var stdout: FileAccess = info["stdio"]
	var stderr: FileAccess = info["stderr"]
	return _watch_unit_run(pid, stdout, stderr)


## Streams the unit run's output as it arrives and stops it at the error or time limit. Returns
## true if the run exited 0 within the limits.
func _watch_unit_run(pid: int, stdout: FileAccess, stderr: FileAccess) -> bool:
	var streams: Array[FileAccess] = [stdout, stderr]
	var partial: Array[String] = ["", ""]
	var watch := UnitWatch.new()
	var started_msec: int = Time.get_ticks_msec()
	var unit_limit: int = UNIT_TIME_LIMIT_SECONDS if _time_budget else SLOW_UNIT_TIME_LIMIT_SECONDS
	while true:
		var running: bool = OS.is_process_running(pid)
		var got: int = 0
		for i: int in range(2):
			var chunk: PackedByteArray = streams[i].get_buffer(65536)
			got += chunk.size()
			partial[i] += chunk.get_string_from_utf8()
			var lines: PackedStringArray = partial[i].split("\n")
			partial[i] = lines[lines.size() - 1]
			for li: int in range(lines.size() - 1):
				watch.line(lines[li], i == 1)
		var stop: String = ""
		if watch.errors >= UNIT_MAX_ERRORS:
			stop = "%d engine or script errors" % watch.errors
		elif Time.get_ticks_msec() - started_msec > unit_limit * 1000:
			stop = "the %d s time limit" % unit_limit
		if stop != "":
			OS.kill(pid)
			printerr("  unit run stopped after %s" % stop)
			printerr("  first error: %s" % watch.first_error)
			printerr("  last test reported: %s" % watch.last_test)
			return false
		if not running and got == 0:
			break
		if got == 0:
			OS.delay_msec(10)
	for i: int in range(2):
		if partial[i] != "":
			watch.line(partial[i], i == 1)
	return OS.get_process_exit_code(pid) == 0


## Prints the child's lines and keeps what a diagnosis needs.
class UnitWatch:
	var errors: int = 0
	var first_error: String = "(none)"
	var last_test: String = "(none yet)"
	var _ansi: RegEx = RegEx.create_from_string("\\x1b\\[[0-9;]*m")

	func line(text: String, is_stderr: bool) -> void:
		if is_stderr:
			printerr(text)
		else:
			print(text)
		var plain: String = _ansi.sub(text, "", true).strip_edges()
		if plain.contains(" > test_"):
			last_test = plain
		var is_error: bool = plain.begins_with("SCRIPT ERROR:") or plain.begins_with("ERROR:")
		# The two lines -d with --remote-debug to port 0 always prints (see _stage_unit).
		if is_error and not plain.contains("emote"):
			errors += 1
			if first_error == "(none)":
				first_error = plain


static func _remove_tree(absolute: String) -> void:
	var dir: DirAccess = DirAccess.open(absolute)
	if dir == null:
		return
	dir.include_hidden = true
	for sub: String in dir.get_directories():
		_remove_tree(absolute.path_join(sub))
	for file: String in dir.get_files():
		DirAccess.remove_absolute(absolute.path_join(file))
	DirAccess.remove_absolute(absolute)
