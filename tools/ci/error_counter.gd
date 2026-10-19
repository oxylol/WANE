class_name ErrorCounter
extends Logger
## Counts engine and script errors (a failed assert, a push_error, a runtime script error) so
## tools/ci/run_tests.gd can fail a stage that printed one. A failed assert in GDScript prints an
## error and carries on, which would otherwise let a broken invariant pass CI.

var errors: int = 0
var first: String = ""
## Each error that names a project file, by that file: "line 5: Parse Error: ..." (how a script
## that does not compile says why).
var by_file: Dictionary[String, PackedStringArray] = {}
var _lock: Mutex = Mutex.new()


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_lock.lock()
	errors += 1
	if first == "":
		first = "%s:%d in %s(): %s %s" % [file, line, function, code, rationale]
	if file.begins_with("res://"):
		var lines: PackedStringArray = by_file.get(file, PackedStringArray())
		lines.append("line %d: %s" % [line, rationale if rationale != "" else code])
		by_file[file] = lines
	_lock.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
