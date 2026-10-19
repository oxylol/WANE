class_name CorePurity
extends RefCounted
## Mechanical check of CLAUDE.md's architecture rules for core/ (rules 1 and 2; Prohibited list):
## no floats, no float maths, no Node or engine singletons, no frame callbacks, no unseeded
## randomness, no file writes (the core may read content, never write). Comments and string
## literals are ignored. Run by tools/ci/run_tests.gd.
##
## Votive listener scripts (content/votives/, tests/votives/) run inside the core, so they obey the
## same rules, and the API boundary besides (docs/adr/0015): a listener extends VotiveListener and
## names no class but the API's; it keeps no state of its own (no member or static variables, no
## class_name, inner class, signal or annotation); it reaches nothing around the API (no member
## whose name starts with an underscore, no reflection, no loading, no self); and it holds no
## number of its own (CLAUDE.md rule 6: integer literals other than 0 and 1 belong in its
## resource).

const PATTERNS: Array[String] = [
	"\\bfloat\\b",
	"(?<![\\w.])\\d+\\.\\d*(?![\\w.])|(?<![\\w.])\\.\\d+\\b",
	"(?<![\\w.])\\d+[eE][+-]?\\d+\\b",
	"\\b(Vector2|Vector3|Rect2|Transform2D|Color|Basis|Quaternion)\\b",
	(
		"\\b(sin|cos|tan|asin|acos|atan|atan2|sqrt|pow|exp|log|lerp|lerpf|lerp_angle|smoothstep"
		+ "|snapped|snappedf|floor|ceil|round|floorf|ceilf|roundf|absf|minf|maxf|clampf|signf"
		+ "|fmod|fposmod|deg_to_rad|rad_to_deg|ease|move_toward|is_equal_approx)\\s*\\("
	),
	"\\b(randf|randi|randf_range|randi_range|randfn|randomize|seed|RandomNumberGenerator)\\b",
	(
		"\\b(Node|Node2D|Control|CanvasItem|SceneTree|Input|Time|OS|DisplayServer"
		+ "|RenderingServer|PhysicsServer2D|AudioServer|Engine)\\b"
	),
	"\\b(_process|_physics_process|_ready|_input|_unhandled_input|get_tree|await)\\b",
	"\\b(PI|TAU|INF|NAN)\\b",
	(
		"FileAccess\\.(WRITE|READ_WRITE|WRITE_READ)"
		+ "|FileAccess\\.open\\([^,]*,(?!\\s*FileAccess\\.READ\\b)"
		+ "|\\bDirAccess\\b|\\.store_\\w+\\s*\\(|\\bResourceSaver\\b|\\bConfigFile\\b"
	),
]
const LABELS: Array[String] = [
	"float type",
	"float literal",
	"float literal",
	"float vector type",
	"float maths",
	"unseeded randomness",
	"Node or engine singleton",
	"frame callback",
	"float constant",
	"file write (I/O belongs to services in game/)",
]

## The roots holding Votive listener scripts.
const LISTENER_ROOTS: Array[String] = ["res://content/votives", "res://tests/votives"]
## The only classes a listener may name: the API it is handed, the base it extends, the event
## sources it may compare, and the value types the API returns.
const LISTENER_CLASSES: Array[String] = [
	"VotiveListener",
	"VotiveApi",
	"ProcApi",
	"BladeHitApi",
	"BounceApi",
	"RunApi",
	"ProcSource",
	"PackedStringArray",
	"String",
]
const LISTENER_PATTERNS: Array[String] = [
	"^(static\\s+)?var\\b",
	"^(class_name|class|signal|@\\w+)\\b",
	"\\.[\\s\\\\]*_",
	(
		"\\b(get|set|call|callv|call_deferred|set_deferred|get_meta|set_meta|has_meta"
		+ "|get_script|set_script"
		+ "|connect|emit_signal|get_indexed|set_indexed|get_property_list|has_method|free"
		+ "|notification|load|preload|instance_from_id|get_node|str_to_var|bytes_to_var"
		+ "|Callable|Expression|ClassDB)[\\s\\\\]*\\("
	),
	"\\bself\\b",
	"(?<![\\w.])([2-9][\\d_]*|1[\\d_]+|0[\\d_]*[1-9][\\d_]*|0[xXbB][0-9a-fA-F_]+)(?![\\w.])",
]
const LISTENER_LABELS: Array[String] = [
	"listener state (a member or static variable; the counter is the API's)",
	"a class_name, inner class, signal or annotation on a listener",
	"reaching around the API (an underscore member)",
	"reflection or loading",
	"self",
	"a number of its own (CLAUDE.md rule 6: it belongs in the Votive's resource)",
]

var _compiled: Array[RegEx] = []
var _labels: Array[String] = []
var _listener_rules: Array[RegEx] = []
var _class_word: RegEx = RegEx.create_from_string("\\b[A-Z][a-z0-9]+[A-Za-z0-9]*\\b")


func _init() -> void:
	for i: int in range(PATTERNS.size()):
		var re := RegEx.new()
		re.compile(PATTERNS[i])
		_compiled.append(re)
		_labels.append(LABELS[i])
	for pattern: String in LISTENER_PATTERNS:
		_listener_rules.append(RegEx.create_from_string("(?m)" + pattern))


## Violations in [param source] as "line N: <label>: <code>" strings.
func check_source(source: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	var line_number: int = 0
	for line: String in source.split("\n"):
		line_number += 1
		var code: String = strip_line(line)
		if code.strip_edges() == "":
			continue
		for i: int in range(_compiled.size()):
			if _compiled[i].search(code) != null:
				problems.append("line %d: %s: %s" % [line_number, _labels[i], line.strip_edges()])
	return problems


## Every violation under res://core, and in every Votive listener ([method check_votives]).
func check_core() -> PackedStringArray:
	var problems: PackedStringArray = []
	for path: String in FileWalk.find("res://core", [".gd"]):
		for p: String in check_source(FileAccess.get_file_as_string(path)):
			problems.append("%s %s" % [path, p])
	problems.append_array(check_votives())
	return problems


## Every violation in the Votive listener scripts under [constant LISTENER_ROOTS].
func check_votives() -> PackedStringArray:
	var problems: PackedStringArray = []
	for root: String in LISTENER_ROOTS:
		for path: String in FileWalk.find(root, [".gd"]):
			for p: String in check_listener(FileAccess.get_file_as_string(path)):
				problems.append("%s %s" % [path, p])
	return problems


## The core's rules and the listener's API boundary on [param source], a Votive listener script.
func check_listener(source: String) -> PackedStringArray:
	var problems: PackedStringArray = check_source(source)
	var extends_base: bool = false
	var line_number: int = 0
	for line: String in source.split("\n"):
		line_number += 1
		var code: String = strip_line(line)
		if code.strip_edges() == "":
			continue
		if code.strip_edges() == "extends VotiveListener":
			extends_base = true
			continue
		if code.strip_edges().begins_with("extends"):
			problems.append("line %d: a listener extends VotiveListener: %s" % [line_number, line])
			continue
		for m: RegExMatch in _class_word.search_all(code):
			if not LISTENER_CLASSES.has(m.get_string()):
				problems.append(
					(
						"line %d: names %s, which is not the listener API: %s"
						% [line_number, m.get_string(), line.strip_edges()]
					)
				)
	problems.append_array(_check_listener_rules(source))
	if not extends_base:
		problems.append("line 1: a listener extends VotiveListener")
	return problems


## The listener rules over the whole of [param source], so that a member written across a space or
## a line continuation ("api. _bus", or "api.\\" then "_bus") is seen as the one token it is.
func _check_listener_rules(source: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	var lines: PackedStringArray = source.split("\n")
	var code_lines: PackedStringArray = []
	for line: String in lines:
		code_lines.append(strip_line(line))
	var text: String = "\n".join(code_lines)
	var reported: Dictionary[String, bool] = {}
	for i: int in range(_listener_rules.size()):
		for m: RegExMatch in _listener_rules[i].search_all(text):
			var line_number: int = text.substr(0, m.get_start()).count("\n") + 1
			var key: String = "%d:%d" % [i, line_number]
			if reported.has(key):
				continue
			reported[key] = true
			var shown: String = lines[line_number - 1].strip_edges()
			problems.append("line %d: %s: %s" % [line_number, LISTENER_LABELS[i], shown])
	return problems


## [param line] with string literals blanked and any comment removed.
static func strip_line(line: String) -> String:
	var out: String = ""
	var quote: String = ""
	var i: int = 0
	while i < line.length():
		var c: String = line[i]
		if quote != "":
			if c == "\\":
				i += 2
				continue
			if c == quote:
				quote = ""
				out += c
			i += 1
			continue
		if c == "#":
			break
		if c == '"' or c == "'":
			quote = c
			out += c
		else:
			out += c
		i += 1
	return out
