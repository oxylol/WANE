class_name Fixture
extends RefCounted
## A replay fixture: an input script and the expected state at named frames (BUILD.md section
## 13; CLAUDE.md working method step 2). Parsed from a `.fixture` text file. The grammar is
## specified in docs/adr/0006-replays-and-fixtures.md and summarised in tests/replay/README.md.
## Anything the grammar does not define is a parse error, never silently ignored.
##
## Frame numbering: "frame F" is the state after the simulation has consumed input frame F, so
## frame 0 is the state after the first step.

const OPS: Array[String] = ["<=", ">=", "!=", "=", "<", ">"]
const DIRECTION_TOKENS: Dictionary[String, Vector2i] = {
	"L": Vector2i(-1, 0), "R": Vector2i(1, 0), "U": Vector2i(0, -1), "D": Vector2i(0, 1)
}
const BUTTON_TOKENS: Dictionary[String, int] = {
	"jump": InputFrame.JUMP,
	"attack": InputFrame.ATTACK,
	"atk": InputFrame.ATTACK,
	"dash": InputFrame.DASH,
	"spell": InputFrame.SPELL,
	"mend": InputFrame.MEND,
	"vessel": InputFrame.VESSEL,
	"toss": InputFrame.TOSS,
}
## Directive -> exact word count (including the directive); -1 means "at least 2".
const HEADER_WORDS: Dictionary[String, int] = {
	"fixture": 2,
	"doc": -1,
	"seed": 2,
	"room": 2,
	"wick": 2,
	"spawn": 3,
	"option": 3,
	"frames": 2,
	"lighting": 2,
}

var path: String = ""
var name: String = ""
var doc: String = ""
var scenario: Scenario = Scenario.new()
## How the fixture is to be drawn: "" (the game as it is, at Dusk) or "pitch" or "dusk" (the Dark
## factor the lighting pass is held at, game/lighting). Presentation only: not part of the
## scenario, so no hash moves.
var lighting: String = ""
var frame_total: int = 0
## Held bits, tap (press-without-hold) bits and stick per frame, length [member frame_total].
var held: PackedInt32Array = PackedInt32Array()
var taps: PackedInt32Array = PackedInt32Array()
var stick_x: PackedInt32Array = PackedInt32Array()
var stick_y: PackedInt32Array = PackedInt32Array()
var expectations: Array[Expectation] = []
var errors: PackedStringArray = PackedStringArray()

var _input_lines: Array[PackedStringArray] = []
var _input_line_numbers: PackedInt32Array = PackedInt32Array()
var _seen: Array[String] = []


## A frame reference: a literal frame or a mark name, plus an offset.
class FrameRef:
	var mark: String = ""
	var frame: int = 0
	var offset: int = 0

	func describe() -> String:
		var base: String = mark if mark != "" else str(frame)
		if offset > 0:
			return "%s+%d" % [base, offset]
		if offset < 0:
			return "%s%d" % [base, offset]
		return base


## One term of a value expression: an integer literal, a word, or a probe key read at a frame.
class Term:
	var polarity: int = 1
	var literal_int: int = 0
	var literal_word: String = ""
	var is_word: bool = false
	var key: String = ""
	var at: FrameRef = null


## key op value-expression.
class Condition:
	var key: String = ""
	var op: String = "="
	var terms: Array[Term] = []
	var text: String = ""

	func is_word() -> bool:
		return terms.size() == 1 and terms[0].is_word


## One expectation line.
class Expectation:
	## "at", "during", "mark" or "never".
	var kind: String = ""
	var line: int = 0
	var text: String = ""
	var from: FrameRef = null
	var to: FrameRef = null
	var mark_name: String = ""
	var conditions: Array[Condition] = []


static func parse_file(file_path: String) -> Fixture:
	var fx := Fixture.new()
	fx.path = file_path
	if not FileAccess.file_exists(file_path):
		fx.errors.append("file not found")
		return fx
	fx._parse(FileAccess.get_file_as_string(file_path))
	return fx


## The 'frames <N>' of the fixture file at [param file_path], read from its header without parsing
## the rest; 0 if the file has none or cannot be read.
static func peek_frames(file_path: String) -> int:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return 0
	while not file.eof_reached():
		var words: PackedStringArray = file.get_line().strip_edges().split(" ", false)
		if words.size() >= 2 and words[0] == "frames":
			return words[1].to_int()
	return 0


static func parse_text(text: String, label: String = "<text>") -> Fixture:
	var fx := Fixture.new()
	fx.path = label
	fx._parse(text)
	return fx


## One "parse: ..." line per parse error: what `check.gd` reports for a fixture it refuses and what
## `trace.gd` prints before it refuses the same fixture (empty when the fixture parsed cleanly).
func refusals() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for e: String in errors:
		lines.append("parse: %s" % e)
	return lines


## The input frame the fixture feeds at [param i].
func input_frame(i: int) -> InputFrame:
	var prev_held: int = held[i - 1] if i > 0 else 0
	var pressed: int = (held[i] & ~prev_held) | taps[i]
	return InputFrame.make(held[i], pressed, stick_x[i], stick_y[i])


## [method input_frame] of every tick, in order. Ticks with the same input share one frame object:
## nothing changes an [InputFrame] once it is made, and a held button or a stick left alone is most
## of a fixture.
func input_frames() -> Array[InputFrame]:
	var out: Array[InputFrame] = []
	out.resize(frame_total)
	var frame: InputFrame = null
	var prev_held: int = 0
	for i: int in range(frame_total):
		var pressed: int = (held[i] & ~prev_held) | taps[i]
		if (
			frame == null
			or frame.held != held[i]
			or frame.pressed != pressed
			or frame.stick_x != stick_x[i]
			or frame.stick_y != stick_y[i]
		):
			frame = InputFrame.make(held[i], pressed, stick_x[i], stick_y[i])
		out[i] = frame
		prev_held = held[i]
	return out


## The input of tick [param i] of the fixture played over and over: the input starts again at its
## first frame every [member frame_total] ticks, and the first frame of a pass sees the last frame
## of the pass before as its previous one (so a key held across the seam is not pressed again).
func looped_input_frame(i: int) -> InputFrame:
	var at: int = i % frame_total
	if at != 0 or i == 0:
		return input_frame(at)
	var last: int = frame_total - 1
	var pressed: int = (held[0] & ~held[last]) | taps[0]
	return InputFrame.make(held[0], pressed, stick_x[0], stick_y[0])


## Every probe key the expectations read.
func probe_keys() -> Array[String]:
	var keys: Array[String] = []
	for e: Expectation in expectations:
		for c: Condition in e.conditions:
			if not keys.has(c.key):
				keys.append(c.key)
			for t: Term in c.terms:
				if t.key != "" and not keys.has(t.key):
					keys.append(t.key)
	return keys


## The probe keys to read after each frame, so that every expectation finds what it looks at and
## nothing else is read: a key is read at the frames an expectation can look at it, and at frame 0,
## where the runner learns whether a key exists and what kind of value it takes. A frame an
## expectation reaches through a mark is any frame the mark can be at, so a mark's reach is the
## range of the line that sets it, and the plan is a superset of what is evaluated; the runner
## fails a fixture whose expectation reads a value the plan left out. The plan maps a frame to the
## keys to read after it; a frame it does not name reads none.
func probe_plan() -> Dictionary[int, PackedStringArray]:
	var last: int = frame_total - 1
	# Each key's frame ranges as pairs (first, last, first, last ...), ends included.
	var wanted: Dictionary[String, PackedInt32Array] = {}
	var marks: Dictionary[String, Vector2i] = {}
	for e: Expectation in expectations:
		var from: Vector2i = _reach(e.from, marks, last)
		var to: Vector2i = _reach(e.to, marks, last)
		if from.x > from.y or to.x > to.y or from.x > to.y:
			continue
		var span := Vector2i(from.x, to.y)
		if e.kind == "mark":
			marks[e.mark_name] = span
		for c: Condition in e.conditions:
			_want(wanted, c.key, span)
			for t: Term in c.terms:
				if t.key == "":
					continue
				var at: Vector2i = _reach(t.at, marks, last)
				if at.x <= at.y:
					_want(wanted, t.key, at)
	var plan: Dictionary[int, PackedStringArray] = {}
	if frame_total == 0:
		return plan
	for key: String in probe_keys():
		_plan_key(plan, 0, key)
		var seen: PackedByteArray = PackedByteArray()
		seen.resize(frame_total)
		seen[0] = 1
		var ranges: PackedInt32Array = wanted.get(key, PackedInt32Array())
		for k: int in range(0, ranges.size(), 2):
			for f: int in range(ranges[k], ranges[k + 1] + 1):
				if seen[f] == 0:
					seen[f] = 1
					_plan_key(plan, f, key)
	return plan


func _plan_key(plan: Dictionary[int, PackedStringArray], frame: int, key: String) -> void:
	if not plan.has(frame):
		plan[frame] = PackedStringArray()
	plan[frame].append(key)


## The frames a reference can resolve to: its literal frame, or the span of its mark, shifted by its
## offset, within the run. Empty (x > y) if none is in the run.
func _reach(ref: FrameRef, marks: Dictionary[String, Vector2i], last: int) -> Vector2i:
	if ref == null:
		return Vector2i(1, 0)
	var base := Vector2i(ref.frame, ref.frame)
	if ref.mark != "":
		base = marks.get(ref.mark, Vector2i(0, last))
	return Vector2i(maxi(base.x + ref.offset, 0), mini(base.y + ref.offset, last))


func _want(wanted: Dictionary[String, PackedInt32Array], key: String, span: Vector2i) -> void:
	if not wanted.has(key):
		wanted[key] = PackedInt32Array()
	wanted[key].append(span.x)
	wanted[key].append(span.y)


func _parse(text: String) -> void:
	var block: String = ""
	var line_number: int = 0
	for raw: String in text.split("\n"):
		line_number += 1
		var stripped_raw: String = raw.strip_edges()
		if block == "" and (stripped_raw.begins_with("doc ") or stripped_raw == "doc"):
			_header(PackedStringArray(["doc", stripped_raw.substr(3).strip_edges()]), line_number)
			continue
		var hash_at: int = raw.find("#")
		var line: String = (raw.substr(0, hash_at) if hash_at >= 0 else raw).strip_edges()
		if line == "":
			continue
		var words: PackedStringArray = line.split(" ", false)
		if words[0] == "end":
			if block == "":
				errors.append("line %d: 'end' outside a block" % line_number)
			elif words.size() > 1:
				errors.append("line %d: 'end' takes no words" % line_number)
			block = ""
			continue
		match block:
			"input":
				_input_lines.append(words)
				_input_line_numbers.append(line_number)
			"expect":
				_parse_expectation(words, line_number, line)
			_:
				if words[0] == "input" or words[0] == "expect":
					if words.size() > 1:
						errors.append("line %d: '%s' takes no words" % [line_number, words[0]])
					block = words[0]
				else:
					_header(words, line_number)
	if block != "":
		errors.append("unterminated '%s' block" % block)
	if name == "":
		errors.append("missing 'fixture <name>'")
	if doc == "":
		errors.append("missing 'doc <BUILD.md reference>'")
	if frame_total <= 0:
		errors.append("missing or non-positive 'frames <N>'")
		return
	_build_inputs()
	_check_marks()


func _header(words: PackedStringArray, line_number: int) -> void:
	var directive: String = words[0]
	if not HEADER_WORDS.has(directive):
		errors.append("line %d: unknown directive '%s'" % [line_number, directive])
		return
	var want: int = HEADER_WORDS[directive]
	if (want < 0 and (words.size() < 2 or words[1] == "")) or (want > 0 and words.size() != want):
		errors.append("line %d: '%s' has the wrong number of words" % [line_number, directive])
		return
	if directive != "option" and _seen.has(directive):
		errors.append("line %d: '%s' given twice" % [line_number, directive])
		return
	_seen.append(directive)
	match directive:
		"fixture":
			name = words[1]
		"doc":
			doc = words[1]
		"seed":
			scenario.seed_value = _int_word(words, 1, line_number)
		"room":
			scenario.room = words[1]
		"wick":
			# "wick none": no player, for fixtures about the core alone.
			scenario.wick = "" if words[1] == "none" else words[1]
		"spawn":
			scenario.spawn_x = _int_word(words, 1, line_number)
			scenario.spawn_y = _int_word(words, 2, line_number)
		"option":
			# Option names are identifiers: "votive_<id>" names a Votive file (docs/adr/0015).
			if not words[1].is_valid_identifier():
				errors.append("line %d: option '%s' is not an identifier" % [line_number, words[1]])
			if scenario.options.has(words[1]):
				errors.append("line %d: option '%s' given twice" % [line_number, words[1]])
			scenario.options[words[1]] = _int_word(words, 2, line_number)
		"frames":
			frame_total = _int_word(words, 1, line_number)
		"lighting":
			if LightWord.is_word(words[1]):
				lighting = words[1]
			else:
				errors.append(
					"line %d: lighting is 'pitch' or 'dusk', not '%s'" % [line_number, words[1]]
				)


func _int_word(words: PackedStringArray, i: int, line_number: int) -> int:
	if i >= words.size() or not words[i].is_valid_int():
		errors.append("line %d: expected an integer at word %d" % [line_number, i + 1])
		return 0
	return words[i].to_int()


func _build_inputs() -> void:
	held.resize(frame_total)
	taps.resize(frame_total)
	stick_x.resize(frame_total)
	stick_y.resize(frame_total)
	held.fill(0)
	taps.fill(0)
	stick_x.fill(0)
	stick_y.fill(0)
	var owner_line: PackedInt32Array = PackedInt32Array()
	owner_line.resize(frame_total)
	owner_line.fill(0)
	for li: int in range(_input_lines.size()):
		var words: PackedStringArray = _input_lines[li]
		var line_number: int = _input_line_numbers[li]
		var bounds: Vector2i = _parse_range(words[0], line_number)
		if bounds.x < 0:
			continue
		var frame := _parse_input_tokens(words, line_number)
		for f: int in range(bounds.x, bounds.y + 1):
			if owner_line[f] != 0:
				errors.append(
					"line %d: frame %d is already set on line %d" % [line_number, f, owner_line[f]]
				)
				break
			owner_line[f] = line_number
			held[f] = frame.held
			taps[f] = frame.pressed
			stick_x[f] = frame.stick_x
			stick_y[f] = frame.stick_y


## The tokens of one input line as an InputFrame (held, taps in [member InputFrame.pressed]). Each
## stick axis and each button may be given once per line.
func _parse_input_tokens(words: PackedStringArray, line_number: int) -> InputFrame:
	var out := InputFrame.new()
	var x_set: bool = false
	var y_set: bool = false
	for wi: int in range(1, words.size()):
		var w: String = words[wi]
		if w == "-":
			continue
		var axis_x: int = 0
		var axis_y: int = 0
		var has_x: bool = false
		var has_y: bool = false
		if DIRECTION_TOKENS.has(w):
			var d: Vector2i = DIRECTION_TOKENS[w]
			axis_x = d.x * InputFrame.STICK_MAX
			axis_y = d.y * InputFrame.STICK_MAX
			has_x = d.x != 0
			has_y = d.y != 0
		elif (w.begins_with("x=") or w.begins_with("y=")) and w.substr(2).is_valid_int():
			var v: int = w.substr(2).to_int()
			if absi(v) > InputFrame.STICK_MAX:
				errors.append("line %d: '%s' is outside the stick range" % [line_number, w])
			has_x = w[0] == "x"
			has_y = w[0] == "y"
			axis_x = v
			axis_y = v
		else:
			var bit: int = _button_token(w, line_number)
			if bit == 0:
				continue
			# "jump" holds, "!jump" taps; both on one line is a re-press while held (released
			# and pressed again between two ticks), which the input layer can produce too.
			var tap: bool = w.begins_with("!")
			if ((out.pressed if tap else out.held) & bit) != 0:
				errors.append("line %d: button '%s' given twice" % [line_number, w])
			if tap:
				out.pressed |= bit
			else:
				out.held |= bit
			continue
		if (has_x and x_set) or (has_y and y_set):
			errors.append(
				"line %d: '%s' sets a stick axis already set on this line" % [line_number, w]
			)
		if has_x:
			out.stick_x = axis_x
			x_set = true
		if has_y:
			out.stick_y = axis_y
			y_set = true
	return out


func _button_token(w: String, line_number: int) -> int:
	var token: String = w.substr(1) if w.begins_with("!") else w
	if BUTTON_TOKENS.has(token.to_lower()):
		return BUTTON_TOKENS[token.to_lower()]
	errors.append("line %d: unknown input token '%s'" % [line_number, w])
	return 0


## "N" or "N..M" (inclusive) to (N, M); (-1, -1) on error.
func _parse_range(word: String, line_number: int) -> Vector2i:
	var parts: PackedStringArray = word.split("..")
	var a: int = -1
	var b: int = -1
	if parts.size() == 1 and parts[0].is_valid_int():
		a = parts[0].to_int()
		b = a
	elif parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		a = parts[0].to_int()
		b = parts[1].to_int()
	if a < 0 or b < a or b >= frame_total:
		errors.append(
			"line %d: bad frame range '%s' (frames 0..%d)" % [line_number, word, frame_total - 1]
		)
		return Vector2i(-1, -1)
	return Vector2i(a, b)


func _parse_expectation(words: PackedStringArray, line_number: int, line: String) -> void:
	var e := Expectation.new()
	e.kind = words[0]
	e.line = line_number
	e.text = line
	var first_condition: int = 2
	match e.kind:
		"at":
			if words.size() < 3:
				errors.append("line %d: 'at <frame> <condition>...'" % line_number)
				return
			e.from = _parse_ref(words[1], line_number)
			e.to = e.from
		"during", "never":
			if words.size() < 3 or words[1].split("..").size() != 2:
				errors.append("line %d: '%s <a>..<b> <condition>...'" % [line_number, e.kind])
				return
			var ends: PackedStringArray = words[1].split("..")
			e.from = _parse_ref(ends[0], line_number)
			e.to = _parse_ref(ends[1], line_number)
		"mark":
			if words.size() < 4 or words[2].split("..").size() != 2:
				errors.append("line %d: 'mark <name> <a>..<b> <condition>...'" % line_number)
				return
			e.mark_name = words[1]
			if not e.mark_name.is_valid_identifier():
				errors.append("line %d: mark name must be an identifier" % line_number)
			var span: PackedStringArray = words[2].split("..")
			e.from = _parse_ref(span[0], line_number)
			e.to = _parse_ref(span[1], line_number)
			first_condition = 3
		_:
			errors.append("line %d: unknown expectation '%s'" % [line_number, e.kind])
			return
	for wi: int in range(first_condition, words.size()):
		var c: Condition = _parse_condition(words[wi], line_number)
		if c != null:
			e.conditions.append(c)
	expectations.append(e)


## "12", "name", "name+3", "name-2".
func _parse_ref(word: String, line_number: int) -> FrameRef:
	var r := FrameRef.new()
	var base: String = word
	var sign_at: int = maxi(word.rfind("+"), word.rfind("-"))
	if sign_at > 0:
		var off: String = word.substr(sign_at)
		if off.substr(1).is_valid_int():
			r.offset = off.to_int()
			base = word.substr(0, sign_at)
	if base.is_valid_int() and base.to_int() >= 0:
		r.frame = base.to_int()
	elif base.is_valid_identifier():
		r.mark = base
	else:
		errors.append("line %d: bad frame reference '%s'" % [line_number, word])
	return r


func _parse_condition(word: String, line_number: int) -> Condition:
	for op: String in OPS:
		var at: int = word.find(op)
		if at <= 0:
			continue
		var c := Condition.new()
		c.text = word
		c.key = word.substr(0, at)
		c.op = op
		c.terms = _parse_terms(word.substr(at + op.length()), line_number)
		if c.terms.is_empty():
			return null
		if c.is_word() and op != "=" and op != "!=":
			errors.append(
				"line %d: '%s' orders a word; only = and != compare words" % [line_number, word]
			)
			return null
		for t: Term in c.terms:
			if t.is_word and c.terms.size() > 1:
				errors.append("line %d: '%s' mixes a word into arithmetic" % [line_number, word])
				return null
		return c
	errors.append("line %d: bad condition '%s'" % [line_number, word])
	return null


## value-expression: term (("+" | "-") term)*. A term is an integer, an integer with a "u"
## suffix (units: times 256 sub-pixels), a word, or key@ref where ref is a frame or mark, or
## key@(ref+n) / key@(ref-n) for an offset. A bare "+" or "-" straight after key@ref is an error,
## because "x@m+5" would read as either "x at m, plus 5" or "x at m+5": write 5+x@m or x@(m+5).
func _parse_terms(text: String, line_number: int) -> Array[Term]:
	var terms: Array[Term] = []
	var pieces: PackedStringArray = []
	var signs: PackedInt32Array = []
	var depth: int = 0
	var start: int = 0
	var polarity: int = 1
	if text.begins_with("-") and text.length() > 1 and text.substr(1, 1).is_valid_int():
		polarity = -1
		start = 1
	for i: int in range(start, text.length()):
		var c: String = text[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
		elif (c == "+" or c == "-") and depth == 0 and i > start:
			pieces.append(text.substr(start, i - start))
			signs.append(polarity)
			polarity = 1 if c == "+" else -1
			start = i + 1
	pieces.append(text.substr(start))
	signs.append(polarity)
	for k: int in range(pieces.size()):
		var term: Term = _parse_term(pieces[k], signs[k], line_number)
		if term == null:
			return []
		if term.key != "" and k < pieces.size() - 1 and not pieces[k].ends_with(")"):
			errors.append(
				(
					(
						"line %d: '%s' is ambiguous: write x@(m+n) for an offset frame or put"
						+ " literals before x@m"
					)
					% [line_number, text]
				)
			)
			return []
		terms.append(term)
	return terms


func _parse_term(word: String, polarity: int, line_number: int) -> Term:
	var t := Term.new()
	t.polarity = polarity
	if word.is_valid_int():
		t.literal_int = word.to_int()
	elif word.ends_with("u") and word.substr(0, word.length() - 1).is_valid_int():
		t.literal_int = word.substr(0, word.length() - 1).to_int() * Fx.SUB
	elif word.contains("@"):
		var parts: PackedStringArray = word.split("@")
		var ref_text: String = parts[1]
		if ref_text.begins_with("(") and ref_text.ends_with(")"):
			ref_text = ref_text.substr(1, ref_text.length() - 2)
		elif ref_text.contains("(") or ref_text.contains(")"):
			errors.append("line %d: unbalanced parentheses in '%s'" % [line_number, word])
			return null
		if parts.size() != 2 or parts[0] == "":
			errors.append("line %d: bad value reference '%s'" % [line_number, word])
			return null
		t.key = parts[0]
		t.at = _parse_ref(ref_text, line_number)
	elif word.is_valid_identifier():
		t.literal_word = word
		t.is_word = true
	else:
		errors.append("line %d: bad value '%s'" % [line_number, word])
		return null
	return t


func _check_marks() -> void:
	var defined: Array[String] = []
	for e: Expectation in expectations:
		for r: FrameRef in [e.from, e.to]:
			if r != null and r.mark != "" and not defined.has(r.mark):
				errors.append("line %d: mark '%s' used before it is defined" % [e.line, r.mark])
		for c: Condition in e.conditions:
			for t: Term in c.terms:
				if t.at != null and t.at.mark != "" and not defined.has(t.at.mark):
					errors.append(
						"line %d: mark '%s' used before it is defined" % [e.line, t.at.mark]
					)
		if e.kind == "mark":
			if defined.has(e.mark_name):
				errors.append("line %d: mark '%s' defined twice" % [e.line, e.mark_name])
			defined.append(e.mark_name)
