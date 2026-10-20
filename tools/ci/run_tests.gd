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
##
## --quiet prints one line per stage ("compile PASS 152 scripts 4.1 s") and, for a stage that
## fails, only what failed (tools/ci/quiet_report.gd), all on stdout; the closing marker is the
## same. --fail-fast stops after the first failing stage. --unit <res:// path> (repeatable) runs
## only those gdUnit4 suites or folders in the unit stage, and --unit-time-limit <seconds>
## replaces its default limit; ci/unit.sh uses both.

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
## A quiet run shows at most this many failures per stage and says how many it left out.
const MAX_FAILURES_SHOWN: int = 12
## The unit stage's limit in a run that is slow on purpose (--no-time-budget: the instrumented copy
## runs several times slower, and the camera suites alone take over ten minutes in it).
const SLOW_UNIT_TIME_LIMIT_SECONDS: int = 2400

var _errors: ErrorCounter = ErrorCounter.new()
var _time_budget: bool = true
var _quiet: bool = false
var _fail_fast: bool = false
var _unit_paths: Array[String] = []
var _unit_time_limit: int = UNIT_TIME_LIMIT_SECONDS
## A quiet run's report on the stage that is running: the summary after PASS or FAIL, and each
## failure as a block of lines.
var _summary: String = ""
var _failures: Array[PackedStringArray] = []


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
		if not _quiet:
			print("== stage: %s" % stage)
		var errors_before: int = _errors.errors
		var stage_usec: int = Time.get_ticks_usec()
		_summary = ""
		_failures.clear()
		var ok: bool = _run_stage(stage)
		if _errors.errors > errors_before and stage != "compile":
			_complain(
				(
					"  %d engine or script error(s) during the stage; first: %s"
					% [_errors.errors - errors_before, _errors.first]
				)
			)
			ok = false
		_report_stage(stage, ok, float(Time.get_ticks_usec() - stage_usec) / 1000000.0)
		if not ok:
			failed.append(stage)
			if _fail_fast:
				break
	var seconds: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	OS.remove_logger(_errors)
	if failed.is_empty():
		print("ALL STAGES PASSED (%s s)" % QuietReport.seconds_text(seconds))
		quit(0)
	else:
		var marker: String = (
			"FAILED STAGES: %s (%s s)" % [", ".join(failed), QuietReport.seconds_text(seconds)]
		)
		if _quiet:
			print(marker)
		else:
			printerr(marker)
		quit(1)


## Progress a quiet run leaves out.
func _say(text: String) -> void:
	if not _quiet:
		print(text)


## One line of a stage's failure: on stderr at once, or, quiet, under the stage's line.
func _complain(text: String) -> void:
	if _quiet:
		_failures.append(PackedStringArray([text]))
	else:
		printerr(text)


## A stage's closing report: the PASS or FAIL line and, quiet, the failures under it.
func _report_stage(stage: String, ok: bool, seconds: float) -> void:
	if not _quiet:
		print("== stage %s: %s" % [stage, "PASS" if ok else "FAIL"])
		return
	print(QuietReport.stage_line(stage, ok, _summary, seconds))
	for i: int in range(mini(_failures.size(), MAX_FAILURES_SHOWN)):
		for line: String in _failures[i]:
			print(line)
	if _failures.size() > MAX_FAILURES_SHOWN:
		print("  ... %d more failures not shown" % (_failures.size() - MAX_FAILURES_SHOWN))


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
		if args[i] == "--quiet":
			_quiet = true
			i += 1
			continue
		if args[i] == "--fail-fast":
			_fail_fast = true
			i += 1
			continue
		if args[i] == "--unit" and i + 1 < args.size() and args[i + 1].begins_with("res://"):
			_unit_paths.append(args[i + 1])
			i += 2
			continue
		if args[i] == "--unit-time-limit" and i + 1 < args.size() and args[i + 1].is_valid_int():
			_unit_time_limit = args[i + 1].to_int()
			i += 2
			continue
		if args[i] != "--stage" or i + 1 >= args.size():
			printerr(
				(
					(
						"usage: run_tests.gd [-- [--quiet] [--fail-fast] [--no-time-budget]"
						+ " [--unit <res:// path>]... [--unit-time-limit <seconds>]"
						+ " --stage <%s>...]"
					)
					% "|".join(ALL_STAGES)
				)
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
	_say("compiled %d scripts, %d failed" % [paths.size(), bad.size()])
	for path: String in bad:
		if _quiet:
			var why: PackedStringArray = PackedStringArray(["(no engine error seen)"])
			if _errors.by_file.has(path):
				why = _errors.by_file[path]
			_failures.append(QuietReport.compile_failure(path, why))
		else:
			printerr("  does not compile: %s" % path)
	var impure: PackedStringArray = CorePurity.new().check_core()
	for problem: String in impure:
		_complain("  core rule broken: %s" % problem)
	_say("core purity: %d problems" % impure.size())
	_summary = "%d scripts" % paths.size()
	if not bad.is_empty():
		_summary += ", %d failed" % bad.size()
	if not impure.is_empty():
		_summary += ", %d core rule problems" % impure.size()
	return bad.is_empty() and impure.is_empty()


func _stage_content() -> bool:
	var paths: Array[String] = FileWalk.find(CONTENT_ROOT, [".tres", ".res"])
	var problems: int = 0
	for path: String in paths:
		var res: Resource = load(path)
		if res == null:
			_complain("  cannot load: %s" % path)
			problems += 1
			continue
		if not res.has_method("validate"):
			_complain("  %s: no schema (its script has no validate())" % path)
			problems += 1
			continue
		var errors: PackedStringArray = res.call("validate")
		for message: String in errors:
			_complain("  %s: %s" % [path, message])
		problems += errors.size()
	# Rooms are text, not resources: their schema is the room parser and the geometry rules
	# (docs/adr/0009).
	var rooms: Array[String] = FileWalk.find(RoomData.CONTENT_ROOT, [".room"])
	for path: String in rooms:
		var room_id: String = path.trim_prefix(RoomData.CONTENT_ROOT).trim_suffix(".room")
		var room: RoomData = RoomData.load_id(room_id)
		for message: String in room.errors:
			_complain("  %s: %s" % [path, message])
		problems += room.errors.size()
	_say(
		(
			"validated %d content resources and %d rooms, %d problems"
			% [paths.size(), rooms.size(), problems]
		)
	)
	_summary = "%d resources, %d rooms" % [paths.size(), rooms.size()]
	if problems > 0:
		_summary += ", %d problems" % problems
	return problems == 0


func _stage_fixtures() -> bool:
	var runner_path: String = "res://tools/replay/fixture_runner.gd"
	if not ResourceLoader.exists(runner_path):
		_say("no fixture runner yet (Phase 1 task 1 adds it)")
		_summary = "no fixture runner"
		return true
	var runner_script: GDScript = load(runner_path) as GDScript
	var runner: Object = runner_script.new()
	if not _time_budget:
		# An instrumented coverage run: one process, so the instrumentation sees every fixture.
		runner.set("budget_msec", 0)
		runner.set("shards", 1)
	runner.set("quiet", _quiet)
	var ok: bool = runner.call("run_all")
	var count: int = runner.call("result_count")
	var failures: Array[PackedStringArray] = runner.get("failure_blocks")
	_failures.append_array(failures)
	_summary = "%d fixtures" % count
	if not ok:
		_summary += ", %d failed" % maxi(failures.size(), 1)
	return ok


func _stage_unit() -> bool:
	var targets: Array[String] = [UNIT_ROOT]
	if not _unit_paths.is_empty():
		targets = _unit_paths
	for target: String in targets:
		if not FileAccess.file_exists(target) and not DirAccess.dir_exists_absolute(target):
			_complain("  no such unit suite or folder: %s" % target)
			_summary = "no such path"
			return false
	if _unit_paths.is_empty() and FileWalk.find(UNIT_ROOT, [".gd"]).is_empty():
		_say("no unit suites")
		_summary = "no suites"
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
	]
	for target: String in targets:
		args.append_array(["-a", target])
	var info: Dictionary[String, Variant] = {}
	info.assign(OS.execute_with_pipe(OS.get_executable_path(), args, false))
	if info.is_empty():
		_complain("  cannot start the gdUnit4 run")
		_summary = "did not start"
		return false
	var pid: int = info["pid"]
	var stdout: FileAccess = info["stdio"]
	var stderr: FileAccess = info["stderr"]
	return _watch_unit_run(pid, stdout, stderr)


## Streams the unit run's output as it arrives (not at all, quiet) and stops it at the error or
## time limit. Returns true if the run exited 0 within the limits.
func _watch_unit_run(pid: int, stdout: FileAccess, stderr: FileAccess) -> bool:
	var streams: Array[FileAccess] = [stdout, stderr]
	var partial: Array[String] = ["", ""]
	var watch := UnitWatch.new()
	watch.quiet = _quiet
	var started_msec: int = Time.get_ticks_msec()
	var unit_limit: int = _unit_time_limit
	if not _time_budget:
		unit_limit = maxi(unit_limit, SLOW_UNIT_TIME_LIMIT_SECONDS)
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
			_complain("  unit run stopped after %s" % stop)
			_complain("  first error: %s" % watch.first_error)
			_complain("  last test reported: %s" % watch.last_test)
			_summary = "run stopped"
			return false
		if not running and got == 0:
			break
		if got == 0:
			OS.delay_msec(10)
	for i: int in range(2):
		if partial[i] != "":
			watch.line(partial[i], i == 1)
	var exit_code: int = OS.get_process_exit_code(pid)
	var result: QuietReport.UnitResult = QuietReport.parse_unit(watch.out)
	_summary = "%d cases" % result.cases if result.has_summary else "no result"
	if exit_code != 0 and result.failed() > 0:
		_summary += ", %d failed" % result.failed()
	if exit_code != 0 and _quiet:
		_failures.append_array(result.failure_blocks(exit_code))
	if exit_code == 0 and not _unit_paths.is_empty() and result.cases == 0:
		_complain("  no test cases found under %s" % ", ".join(_unit_paths))
		return false
	return exit_code == 0


## Prints the child's lines and keeps what a diagnosis needs.
class UnitWatch:
	## Print nothing; the lines are kept for tools/ci/quiet_report.gd.
	var quiet: bool = false
	## The child's stdout, one entry per line (its stderr is engine noise, kept out of it).
	var out: PackedStringArray = PackedStringArray()
	var errors: int = 0
	var first_error: String = "(none)"
	var last_test: String = "(none yet)"
	var _ansi: RegEx = RegEx.create_from_string("\\x1b\\[[0-9;]*m")

	func line(text: String, is_stderr: bool) -> void:
		if not is_stderr:
			out.append(text)
		if quiet:
			pass
		elif is_stderr:
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
