class_name UnitRunner
extends RefCounted
## The unit stage's engine (docs/adr/0006, "Unit shards"): the suites under the given paths are
## split over up to [constant MAX_PROCESSES] gdUnit4 runs, one per processor, balanced by the
## times in the timing log ([UnitShards]); each run is a Godot process of its own with its own
## report folder (reports/unit/<k>/report_1); this watches all of them at once, stops them at the
## error or time limit, and merges what they report into one answer for tools/ci/run_tests.gd.
##
## Nothing passes by omission: a process that exits non-zero, prints no summary, is killed or
## hangs fails the stage, and so does a suite handed to a process that its report does not list.

const REPORT_DIR: String = "res://reports/unit"
const GDUNIT_TOOL: String = "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"
const MAX_PROCESSES: int = 4

## Print nothing while the processes run (a quiet run); [member failures] and [member summary]
## carry what a quiet report needs.
var quiet: bool = false
## The processes are stopped once any has printed this many engine or script errors (a broken
## invariant asserting in a loop slows gdUnit4 down sharply) or the stage has run this long.
var max_errors: int = 50
var time_limit_seconds: int = 600
## How many processes to use: 0 is one per processor, at most [constant MAX_PROCESSES].
var processes: int = 0
## Where the reports go (a test points it elsewhere, so that a nested run does not delete the
## reports of the run that is running it).
var report_dir: String = REPORT_DIR
## The timing log the plan is balanced by, and the variant of its lines to prefer.
var log_path: String = ""
var variant: String = ""
## After [method run]: "N cases" and so on for the stage's line, the failures (one block of lines
## each, as [QuietReport] makes them), lines for the stage to complain of, and the suites that
## reported (path, time, cases) for the timing log.
var summary: String = ""
var failures: Array[PackedStringArray] = []
var complaints: PackedStringArray = PackedStringArray()
var reported: Array[UnitReport.Suite] = []
## The plan of the last run: the suites of each process.
var shares: Array[PackedStringArray] = []
## Seconds each process of the last run took.
var process_seconds: PackedFloat64Array = PackedFloat64Array()


## One gdUnit4 process and what it printed.
class Proc:
	var index: int = 0
	var suites: PackedStringArray = PackedStringArray()
	var pid: int = 0
	var streams: Array[FileAccess] = []
	var partial: Array[String] = ["", ""]
	var watch: UnitWatch = null
	var started_msec: int = 0
	var seconds: float = 0.0
	var done: bool = false
	var exit_code: int = 0


## Prints a process's lines and keeps what a diagnosis needs.
class UnitWatch:
	## Print nothing; the lines are kept for tools/ci/quiet_report.gd.
	var quiet: bool = false
	## Put before each printed line (which process it came from), when there are several.
	var prefix: String = ""
	## The process's stdout, one entry per line (its stderr is engine noise, kept out of it).
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
			printerr(prefix + text)
		else:
			print(prefix + text)
		var plain: String = _ansi.sub(text, "", true).strip_edges()
		if plain.contains(" > test_"):
			last_test = plain
		var is_error: bool = plain.begins_with("SCRIPT ERROR:") or plain.begins_with("ERROR:")
		# The two lines -d with --remote-debug to port 0 always prints (see _spawn).
		if is_error and not plain.contains("emote"):
			errors += 1
			if first_error == "(none)":
				first_error = plain


## How many processes a run of [param suite_count] suites uses.
func process_count(suite_count: int) -> int:
	var wanted: int = processes if processes > 0 else mini(OS.get_processor_count(), MAX_PROCESSES)
	return clampi(wanted, 1, maxi(1, suite_count))


## Runs the suites under [param targets] (suite files or folders, as res:// paths, which exist).
## Returns true if every process exited 0 within the limits and every suite handed out reported.
func run(targets: Array[String]) -> bool:
	summary = ""
	failures.clear()
	complaints.clear()
	reported.clear()
	process_seconds.clear()
	var suites: Array[String] = UnitShards.find_suites(targets)
	if suites.is_empty():
		complaints.append("  no test cases found under %s" % ", ".join(targets))
		summary = "no suites"
		return false
	shares = plan_for(suites)
	_prepare_reports()
	var procs: Array[Proc] = []
	for k: int in range(shares.size()):
		var proc: Proc = _spawn(k, shares[k])
		if proc == null:
			complaints.append("  cannot start the gdUnit4 run")
			summary = "did not start"
			_stop(procs)
			return false
		proc.watch.quiet = quiet
		proc.watch.prefix = "[%d] " % k if shares.size() > 1 else ""
		procs.append(proc)
	if not quiet:
		print("== unit: %d suites in %d processes" % [suites.size(), procs.size()])
	if not _watch(procs):
		return false
	return merge(procs, suites)


## The plan for [param suites]: costs from the timing log (or file sizes), suites that share
## files in one bundle, bundles over [method process_count] processes.
func plan_for(suites: Array[String]) -> Array[PackedStringArray]:
	var groups: Dictionary[String, String] = {}
	for path: String in suites:
		groups[path] = UnitShards.group_of(path)
	var cost: Dictionary[String, float] = UnitShards.costs(suites, log_path, variant)
	return UnitShards.plan(UnitShards.bundles(suites, cost, groups), process_count(suites.size()))


func _prepare_reports() -> void:
	# Reports live in the project folder for CI artifacts (one run's worth: reports/unit/<k>/
	# report_1); the rest of reports/ (timings.jsonl, perf.txt) is not ours to delete. .gdignore
	# keeps Godot from importing the reports' images as project assets.
	_remove_tree(ProjectSettings.globalize_path(report_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_dir))
	var ignore: FileAccess = FileAccess.open("res://reports/.gdignore", FileAccess.WRITE)
	ignore.close()


func _spawn(k: int, suites: PackedStringArray) -> Proc:
	var proc_dir: String = report_dir.path_join(str(k))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(proc_dir))
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
		GDUNIT_TOOL,
		"--ignoreHeadlessMode",
		"-c",
		"-rd",
		proc_dir,
	]
	for suite: String in suites:
		args.append_array(["-a", suite])
	var info: Dictionary[String, Variant] = {}
	info.assign(OS.execute_with_pipe(OS.get_executable_path(), args, false))
	if info.is_empty():
		return null
	var proc := Proc.new()
	proc.index = k
	proc.suites = suites
	proc.pid = info["pid"]
	var stdout: FileAccess = info["stdio"]
	var stderr: FileAccess = info["stderr"]
	proc.streams = [stdout, stderr]
	proc.watch = UnitWatch.new()
	proc.started_msec = Time.get_ticks_msec()
	return proc


## Streams the processes' output as it arrives (not at all, quiet) until every one has exited, and
## stops them all at the error or time limit. Returns false if it had to stop them.
func _watch(procs: Array[Proc]) -> bool:
	var started_msec: int = Time.get_ticks_msec()
	while true:
		var got: int = 0
		var open: int = 0
		for proc: Proc in procs:
			if proc.done:
				continue
			var running: bool = OS.is_process_running(proc.pid)
			var read: int = _read(proc)
			got += read
			if not running and read == 0:
				proc.done = true
				proc.seconds = float(Time.get_ticks_msec() - proc.started_msec) / 1000.0
				proc.exit_code = OS.get_process_exit_code(proc.pid)
				_flush(proc)
			else:
				open += 1
		var stop: String = ""
		for proc: Proc in procs:
			if proc.watch.errors >= max_errors:
				stop = "%d engine or script errors" % proc.watch.errors
		if stop == "" and Time.get_ticks_msec() - started_msec > time_limit_seconds * 1000:
			stop = "the %d s time limit" % time_limit_seconds
		if stop != "":
			_stop(procs)
			complaints.append("  unit run stopped after %s" % stop)
			for proc: Proc in procs:
				if not proc.done:
					var where: String = "process %d: " % proc.index if procs.size() > 1 else ""
					complaints.append("  %sfirst error: %s" % [where, proc.watch.first_error])
					complaints.append("  %slast test reported: %s" % [where, proc.watch.last_test])
			summary = "run stopped"
			return false
		if open == 0:
			break
		if got == 0:
			OS.delay_msec(10)
	return true


## Reads what is waiting on [param proc]'s pipes into its watch; returns how many bytes.
func _read(proc: Proc) -> int:
	var got: int = 0
	for i: int in range(2):
		var chunk: PackedByteArray = proc.streams[i].get_buffer(65536)
		got += chunk.size()
		proc.partial[i] += chunk.get_string_from_utf8()
		var lines: PackedStringArray = proc.partial[i].split("\n")
		proc.partial[i] = lines[lines.size() - 1]
		for li: int in range(lines.size() - 1):
			proc.watch.line(lines[li], i == 1)
	return got


func _flush(proc: Proc) -> void:
	for i: int in range(2):
		if proc.partial[i] != "":
			proc.watch.line(proc.partial[i], i == 1)
			proc.partial[i] = ""


func _stop(procs: Array[Proc]) -> void:
	for proc: Proc in procs:
		if not proc.done and OS.is_process_running(proc.pid):
			OS.kill(proc.pid)


## Merges the processes' answers: the case counts, the failing cases, and the checks that nothing
## went missing. Returns true if the stage passed.
func merge(procs: Array[Proc], suites: Array[String]) -> bool:
	var ok: bool = true
	var cases: int = 0
	var failed: int = 0
	var lost: int = 0
	var any_summary: bool = false
	var bases: Dictionary[String, String] = UnitShards.class_scripts()
	for proc: Proc in procs:
		var result: QuietReport.UnitResult = QuietReport.parse_unit(proc.watch.out)
		process_seconds.append(proc.seconds)
		if result.has_summary:
			any_summary = true
			cases += result.cases
		else:
			lost += 1
		var who: String = "unit run" if procs.size() == 1 else "unit process %d" % proc.index
		if proc.exit_code != 0:
			ok = false
			failed += result.failed()
			failures.append_array(result.failure_blocks(proc.exit_code, who))
			continue
		if not result.has_summary:
			ok = false
			var heading: String = "%s exited 0 but printed no summary; its last lines:" % who
			failures.append(QuietReport.failure_block(heading, result.tail))
			continue
		if not _all_reported(proc, bases):
			ok = false
	summary = "%d cases" % cases if any_summary else "no result"
	if failed > 0:
		summary += ", %d failed" % failed
	if lost > 0 and any_summary:
		summary += ", %d of %d processes without a result" % [lost, procs.size()]
	if ok and cases == 0:
		complaints.append("  no test cases found under %s" % ", ".join(suites))
		ok = false
	_print_balance(procs)
	return ok


## Reads [param proc]'s report and checks that every suite it was handed is in it.
func _all_reported(proc: Proc, bases: Dictionary[String, String]) -> bool:
	var results: String = UnitReport.newest_results(
		ProjectSettings.globalize_path(report_dir.path_join(str(proc.index)))
	)
	var suites: Array[UnitReport.Suite] = UnitReport.read(results)
	reported.append_array(suites)
	var seen: PackedStringArray = PackedStringArray()
	for suite: UnitReport.Suite in suites:
		seen.append(suite.path)
	var ok: bool = true
	for path: String in proc.suites:
		if seen.has(path.trim_prefix("res://")) or not UnitShards.has_tests(path, bases):
			continue
		ok = false
		(
			failures
			. append(
				(
					QuietReport
					. failure_block(
						"suite did not report: %s" % path,
						PackedStringArray(
							[
								(
									"it was handed to unit process %d, which exited 0, and is not in its report"
									% proc.index
								),
								"(%s)" % ("no report was written" if results == "" else results),
							]
						)
					)
				)
			)
		)
	return ok


func _print_balance(procs: Array[Proc]) -> void:
	if quiet or procs.size() < 2:
		return
	var parts: PackedStringArray = PackedStringArray()
	for proc: Proc in procs:
		parts.append("%d: %d suites %.1f s" % [proc.index, proc.suites.size(), proc.seconds])
	print("== unit processes: %s" % ", ".join(parts))


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
