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
## replaces its default limit; ci/unit.sh uses both. The unit stage runs its suites in up to four
## gdUnit4 processes at once, one per processor (tools/ci/unit_runner.gd, docs/adr/0006);
## --unit-processes <n> sets how many (1: one process, as before).

const SKIP_DIRS: Array[String] = ["res://.godot", "res://addons/gdUnit4", "res://reports"]
const CONTENT_ROOT: String = "res://content"
const UNIT_ROOT: String = "res://tests/unit"
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
## 0: one gdUnit4 process per processor, at most four (tools/ci/unit_runner.gd).
var _unit_processes: int = 0
## What this run measured (tools/ci/timing_log.gd): written when the run ends.
var _timing: TimingLog = null
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
	_timing = TimingLog.new("run_tests.gd", "native=" + NativeBackend.mode_name())
	if not _time_budget:
		# A run that is slow on purpose (the instrumented coverage copy) measures nothing.
		_timing.path = ""
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
		var stage_seconds: float = float(Time.get_ticks_usec() - stage_usec) / 1000000.0
		_report_stage(stage, ok, stage_seconds)
		# A failed stage is not timed: it stops early or runs on error paths. A unit run of a few
		# suites is not the stage (the suites and cases it ran are logged).
		if ok and (stage != "unit" or _unit_paths.is_empty()):
			_timing.add(stage, "stage", stage, stage_seconds)
		if not ok:
			failed.append(stage)
			if _fail_fast:
				break
	var seconds: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	OS.remove_logger(_errors)
	_timing.flush()
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
		if args[i] == "--unit-processes" and i + 1 < args.size() and args[i + 1].is_valid_int():
			_unit_processes = maxi(args[i + 1].to_int(), 1)
			i += 2
			continue
		if args[i] != "--stage" or i + 1 >= args.size():
			printerr(
				(
					(
						"usage: run_tests.gd [-- [--quiet] [--fail-fast] [--no-time-budget]"
						+ " [--unit <res:// path>]... [--unit-time-limit <seconds>]"
						+ " [--unit-processes <n>]"
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
	if ok:
		var times: Dictionary[String, float] = runner.call("timings")
		for fixture_name: String in times:
			_timing.add("fixtures", "fixture", fixture_name, times[fixture_name])
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
	var runner := UnitRunner.new()
	runner.quiet = _quiet
	runner.processes = _unit_processes
	runner.max_errors = UNIT_MAX_ERRORS
	runner.time_limit_seconds = _unit_time_limit
	if not _time_budget:
		runner.time_limit_seconds = maxi(_unit_time_limit, SLOW_UNIT_TIME_LIMIT_SECONDS)
	runner.log_path = TimingLog.history_path()
	runner.variant = _timing.variant
	var ok: bool = runner.run(targets)
	for line: String in runner.complaints:
		_complain(line)
	_failures.append_array(runner.failures)
	_summary = runner.summary
	if ok:
		_log_unit_times(runner.reported)
		_log_unit_processes(runner.process_seconds)
	return ok


## Notes each suite's and case's time from the reports of the run that just passed.
func _log_unit_times(suites: Array[UnitReport.Suite]) -> void:
	for suite: UnitReport.Suite in suites:
		_timing.add("unit", "suite", suite.path, suite.seconds)
		for i: int in range(suite.case_names.size()):
			var item: String = "%s::%s" % [suite.path, suite.case_names[i]]
			_timing.add("unit", "case", item, suite.case_seconds[i])


## Notes how long each of the unit stage's processes ran, so that the report can show how well the
## plan balanced them (tools/ci/timing_report.py, "unit processes").
func _log_unit_processes(seconds: PackedFloat64Array) -> void:
	if _unit_paths.is_empty():
		for k: int in range(seconds.size()):
			_timing.add(
				"unit", "process", "unit process %d of %d" % [k, seconds.size()], seconds[k]
			)
