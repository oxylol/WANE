class_name CorePurity
extends RefCounted
## Mechanical check of CLAUDE.md's architecture rules for core/ (rules 1 and 2; Prohibited list):
## no floats, no float maths, no Node or engine singletons, no frame callbacks, no unseeded
## randomness. Comments and string literals are ignored. Run by tools/ci/run_tests.gd.

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
]

var _compiled: Array[RegEx] = []
var _labels: Array[String] = []


func _init() -> void:
	for i: int in range(PATTERNS.size()):
		var re := RegEx.new()
		re.compile(PATTERNS[i])
		_compiled.append(re)
		_labels.append(LABELS[i])


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


## Every violation under res://core.
func check_core() -> PackedStringArray:
	var problems: PackedStringArray = []
	for path: String in FileWalk.find("res://core", [".gd"]):
		for p: String in check_source(FileAccess.get_file_as_string(path)):
			problems.append("%s %s" % [path, p])
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
