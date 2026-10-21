class_name TimingLog
extends RefCounted
## The timing log (BUILD.md section 13, "Testing and CI"; docs/adr/0025): what the test run, the
## fixture runner and the film tool measure, as one JSON object per line appended to
## reports/timings.jsonl (git-ignored). tools/ci/timing_report.py reads it; its module docstring and
## tests/README.md ("Timing log") describe the fields. ci/timing.sh writes the same lines from
## the shell scripts and tools/ci/timing_report.py from Python.
##
## One [TimingLog] is one invocation: every line it writes carries the same time stamp, run id,
## commit, processor count and load average (the 1-minute average when the invocation started, so
## the run's own work does not count). Lines are kept until [method flush], so a run that dies
## leaves no half-measured log.
##
## WANE_TIMING_LOG=<path> writes there instead; WANE_TIMING_LOG=off writes nothing (the
## instrumented coverage run, whose times are not the project's). WANE_TIMING_TOOL names the
## script that started the run (ci/test.sh and ci/unit.sh set it) and WANE_TIMING_RUN is the
## run id they share with the lines the shell writes (ci/timing.sh).

const ENV_PATH: String = "WANE_TIMING_LOG"
const ENV_TOOL: String = "WANE_TIMING_TOOL"
const ENV_RUN: String = "WANE_TIMING_RUN"
const OFF: String = "off"
const DEFAULT_PATH: String = "res://reports/timings.jsonl"
## The log is moved to <path>.1 (replacing the older one) once it passes this size; the report
## reads both.
const MAX_BYTES: int = 8388608
## A case or fixture faster than this is not worth a line (the suite or stage line holds its
## time); a case that gets slower than this shows up as a new item.
const FLOORS: Dictionary[String, float] = {"case": 0.05, "fixture": 0.02}

var tool: String = ""
var variant: String = ""
## The absolute path written to, or "" when nothing is written.
var path: String = ""
var _lines: PackedStringArray = PackedStringArray()
var _stamp: String = ""
var _run: String = ""
var _commit: String = ""
var _processors: int = 1
var _load: float = -1.0


## [param default_tool] names the script when WANE_TIMING_TOOL is not set; [param variant_text]
## separates series that must not be compared (the native path on or off).
func _init(default_tool: String, variant_text: String = "") -> void:
	var tool_env: String = OS.get_environment(ENV_TOOL)
	tool = tool_env if tool_env != "" else default_tool
	variant = variant_text
	var path_env: String = OS.get_environment(ENV_PATH)
	if path_env == OFF:
		return
	path = history_path()
	_stamp = Time.get_datetime_string_from_system(true) + "Z"
	_run = OS.get_environment(ENV_RUN)
	if _run == "":
		var compact: String = _stamp.replace("-", "").replace(":", "").replace("Z", "")
		_run = "%s-%d" % [compact, OS.get_process_id()]
	_commit = _git_commit()
	_processors = OS.get_processor_count()
	_load = load_average()


func enabled() -> bool:
	return path != ""


## The log to read history from (the unit stage balances its processes by it): the one written to,
## or the default one when writing is switched off.
static func history_path() -> String:
	var path_env: String = OS.get_environment(ENV_PATH)
	if path_env == "" or path_env == OFF:
		path_env = DEFAULT_PATH
	return ProjectSettings.globalize_path(path_env)


## Notes one measured item; the line is written by [method flush]. Cases and fixtures under their
## [constant FLOORS] entry are left out. [param item_variant] replaces the log's variant when not
## empty.
func add(
	stage: String, kind: String, item: String, seconds: float, item_variant: String = ""
) -> void:
	if not enabled():
		return
	if FLOORS.has(kind) and seconds < FLOORS[kind]:
		return
	var entry: Dictionary[String, Variant] = {
		"ts": _stamp,
		"run": _run,
		"commit": _commit,
		"tool": tool,
		"stage": stage,
		"kind": kind,
		"item": item,
		"variant": item_variant if item_variant != "" else variant,
		"seconds": seconds,
		"processors": _processors,
		"load": _load,
	}
	_lines.append(format(entry))


## How many lines wait for [method flush].
func pending() -> int:
	return _lines.size()


## Appends the noted lines to the log (rotating it first if it is over [constant MAX_BYTES]) and
## forgets them. A log that cannot be written is not a failure of the run: false is returned.
func flush() -> bool:
	if not enabled() or _lines.is_empty():
		_lines.clear()
		return true
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if FileAccess.file_exists(path):
		var size: int = _file_size(path)
		if size > MAX_BYTES:
			DirAccess.rename_absolute(path, path + ".1")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_lines.clear()
		return false
	file.seek_end()
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	_lines.clear()
	return true


## One entry as a line of JSON, the fields in a fixed order. Seconds have three decimals and the
## load two; an unknown load (below 0) is null.
static func format(entry: Dictionary[String, Variant]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in entry.keys():
		var value: Variant = entry[key]
		var text: String
		if key == "seconds":
			var seconds: float = value
			text = "%.3f" % seconds
		elif key == "load":
			var load_avg: float = value
			text = "%.2f" % load_avg if load_avg >= 0.0 else "null"
		elif value is int:
			text = str(value)
		else:
			text = JSON.stringify(str(value))
		parts.append('"%s":%s' % [key, text])
	return "{" + ",".join(parts) + "}"


## The 1-minute load average, or -1.0 where the system does not say (Linux: /proc/loadavg; macOS:
## sysctl).
static func load_average() -> float:
	if FileAccess.file_exists("/proc/loadavg"):
		# A file in /proc reports a length of 0, so it is read by line, not as a string.
		var file: FileAccess = FileAccess.open("/proc/loadavg", FileAccess.READ)
		if file == null:
			return -1.0
		var words: PackedStringArray = file.get_line().split(" ")
		return words[0].to_float() if words.size() > 0 and words[0].is_valid_float() else -1.0
	if OS.get_name() == "macOS":
		var output: Array[String] = []
		if OS.execute("sysctl", ["-n", "vm.loadavg"], output) == 0 and output.size() > 0:
			# "{ 1.23 4.56 7.89 }"
			var words: PackedStringArray = output[0].replace("{", "").strip_edges().split(" ")
			return words[0].to_float() if words.size() > 0 and words[0].is_valid_float() else -1.0
	return -1.0


static func _git_commit() -> String:
	var output: Array[String] = []
	var root: String = ProjectSettings.globalize_path("res://")
	if OS.execute("git", ["-C", root, "rev-parse", "--short", "HEAD"], output) != 0:
		return "unknown"
	return (
		output[0].strip_edges()
		if output.size() > 0 and output[0].strip_edges() != ""
		else "unknown"
	)


static func _file_size(file_path: String) -> int:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return 0
	var size: int = file.get_length()
	file.close()
	return size
