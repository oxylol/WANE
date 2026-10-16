class_name FixtureRunner
extends RefCounted
## Runs replay fixtures headless (BUILD.md section 13: "All 12 tech interactions and every boss
## phase are replay fixtures in tests/replay/ ... They run headless in under 10 seconds total").
##
## For each fixture: step the simulation through the input script, check every expectation, then
## prove determinism twice: the recorded replay must encode, decode and reproduce every state hash
## bit-for-bit, and the hashes must match the committed golden values in [constant GOLDEN_PATH],
## which CI checks on Linux, Windows and macOS (ADR-0006).
##
## An expectation that cannot be evaluated (a value reference outside the run, a word compared
## with a number, a word the key never takes) fails; nothing passes vacuously.

const FIXTURE_ROOT: String = "res://tests/replay"
const GOLDEN_PATH: String = "res://tests/replay/golden_hashes.txt"
const VERSION_PREFIX: String = "# sim_version "
## BUILD.md section 13 budget for the whole fixture suite.
const SUITE_BUDGET_MSEC: int = 10000

var results: Array[Result] = []


## Outcome of one fixture.
class Result:
	var name: String = ""
	var path: String = ""
	var passed: bool = true
	var messages: PackedStringArray = PackedStringArray()
	var frames: int = 0
	## "in:<input hash> content:<content hash> <end tick>:<end hash> <tick>:<hash> ..." as stored in
	## the golden file.
	var hash_line: String = ""
	var msec: float = 0.0

	func fail(message: String) -> void:
		passed = false
		messages.append(message)


## Runs every fixture under [constant FIXTURE_ROOT]. With [param bless] the golden file is
## rewritten from this run instead of checked. Returns true if everything passed.
func run_all(bless: bool = false) -> bool:
	results.clear()
	var started: int = Time.get_ticks_msec()
	var golden: Dictionary[String, String] = load_golden()
	var golden_version: int = load_golden_version()
	var names: Dictionary[String, String] = {}
	var failed: int = 0
	for path: String in FileWalk.find(FIXTURE_ROOT, [".fixture"]):
		var fx: Fixture = Fixture.parse_file(path)
		var result: Result = run_fixture(fx)
		if names.has(result.name):
			result.fail("duplicate fixture name (also %s)" % names[result.name])
		names[result.name] = path
		if not bless and result.passed:
			_check_golden(result, golden, golden_version)
		results.append(result)
	for r: Result in results:
		if not r.passed:
			failed += 1
			printerr("FAIL %s (%s)" % [r.name, r.path])
			for m: String in r.messages:
				printerr("    %s" % m)
		else:
			print("pass %-44s %5d frames %7.1f ms" % [r.name, r.frames, r.msec])
	if not bless:
		for stale: String in golden.keys():
			if not names.has(stale):
				printerr("FAIL golden entry '%s' has no fixture; re-bless" % stale)
				failed += 1
	var elapsed: int = Time.get_ticks_msec() - started
	print("%d fixtures, %d failed, %d ms" % [results.size(), failed, elapsed])
	if elapsed > SUITE_BUDGET_MSEC:
		printerr("FAIL fixture suite took %d ms, budget %d ms" % [elapsed, SUITE_BUDGET_MSEC])
		failed += 1
	if bless and failed == 0:
		return _bless(golden, golden_version)
	return failed == 0


## Runs one parsed fixture and checks its expectations and replay round-trip.
func run_fixture(fx: Fixture) -> Result:
	var result := Result.new()
	result.name = fx.name
	result.path = fx.path
	result.frames = fx.frame_total
	for e: String in fx.errors:
		result.fail("parse: %s" % e)
	if not result.passed:
		return result
	var started: int = Time.get_ticks_usec()
	var sim := Simulation.new(fx.scenario)
	var recorder := ReplayRecorder.new(fx.scenario)
	var keys: Array[String] = fx.probe_keys()
	var snaps: Array[Dictionary] = []
	for i: int in range(fx.frame_total):
		var frame: InputFrame = fx.input_frame(i)
		sim.step(frame)
		recorder.record(frame)
		var snap: Dictionary[String, Variant] = {}
		for key: String in keys:
			snap[key] = sim.probe(key)
		snaps.append(snap)
	for key: String in keys:
		if snaps[0][key] == null:
			result.fail("unknown probe key '%s'" % key)
	if result.passed:
		_evaluate(fx, snaps, sim, result)
	var replay: Replay = recorder.finish(sim)
	_check_round_trip(replay, result)
	for e: String in sim.load_errors:
		result.fail("load: %s" % e)
	result.hash_line = _hash_line(replay, sim)
	result.msec = float(Time.get_ticks_usec() - started) / 1000.0
	return result


static func load_golden() -> Dictionary[String, String]:
	var golden: Dictionary[String, String] = {}
	if not FileAccess.file_exists(GOLDEN_PATH):
		return golden
	for line: String in FileAccess.get_file_as_string(GOLDEN_PATH).split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue
		var space: int = trimmed.find(" ")
		if space > 0:
			golden[trimmed.substr(0, space)] = trimmed.substr(space + 1)
	return golden


## The simulation version the golden file was blessed with, or -1.
static func load_golden_version() -> int:
	if not FileAccess.file_exists(GOLDEN_PATH):
		return -1
	for line: String in FileAccess.get_file_as_string(GOLDEN_PATH).split("\n"):
		if line.begins_with(VERSION_PREFIX) and line.substr(VERSION_PREFIX.length()).is_valid_int():
			return line.substr(VERSION_PREFIX.length()).to_int()
	return -1


func _evaluate(fx: Fixture, snaps: Array[Dictionary], sim: Simulation, result: Result) -> void:
	var marks: Dictionary[String, int] = {}
	for e: Fixture.Expectation in fx.expectations:
		var where: String = "line %d: %s" % [e.line, e.text]
		var a: int = _resolve(e.from, marks, fx.frame_total)
		var b: int = _resolve(e.to, marks, fx.frame_total)
		if a < 0 or b < 0 or b < a:
			result.fail("%s: frame range unresolved or out of 0..%d" % [where, fx.frame_total - 1])
			continue
		var expected: Array[Variant] = []
		var problem: String = _expected_values(e, snaps, marks, sim, expected)
		if problem != "":
			result.fail("%s: %s" % [where, problem])
			continue
		match e.kind:
			"at", "during":
				for f: int in range(a, b + 1):
					var why: String = _first_failure(e, f, snaps, expected)
					if why != "":
						result.fail("%s: frame %d: %s" % [where, f, why])
						break
			"never":
				for f: int in range(a, b + 1):
					if _first_failure(e, f, snaps, expected) == "":
						result.fail("%s: all conditions held at frame %d" % [where, f])
						break
			"mark":
				for f: int in range(a, b + 1):
					if _first_failure(e, f, snaps, expected) == "":
						marks[e.mark_name] = f
						break
				if not marks.has(e.mark_name):
					result.fail("%s: no frame in %d..%d satisfied it" % [where, a, b])


## Fills [param out] with each condition's expected value (int or String); returns "" or why the
## expectation cannot be evaluated.
func _expected_values(
	e: Fixture.Expectation,
	snaps: Array[Dictionary],
	marks: Dictionary[String, int],
	sim: Simulation,
	out: Array[Variant]
) -> String:
	for c: Fixture.Condition in e.conditions:
		var sample: Variant = snaps[0][c.key]
		if c.is_word():
			var word: String = c.terms[0].literal_word
			var vocabulary: PackedStringArray = sim.probe_words(c.key)
			if typeof(sample) != TYPE_STRING or not vocabulary.has(word):
				return (
					"'%s': key '%s' never takes the value '%s' (values: %s)"
					% [
						c.text,
						c.key,
						word,
						", ".join(vocabulary) if not vocabulary.is_empty() else "integers"
					]
				)
			out.append(word)
			continue
		if typeof(sample) != TYPE_INT:
			return "'%s': key '%s' holds names, not numbers" % [c.text, c.key]
		var total: int = 0
		for t: Fixture.Term in c.terms:
			var v: int = t.literal_int
			if t.key != "":
				var at: int = _resolve(t.at, marks, snaps.size())
				if at < 0:
					return "'%s': %s@%s is outside the run" % [c.text, t.key, t.at.describe()]
				if typeof(snaps[at][t.key]) != TYPE_INT:
					return "'%s': key '%s' holds names, not numbers" % [c.text, t.key]
				v = snaps[at][t.key]
			total += t.polarity * v
		out.append(total)
	return ""


func _resolve(ref: Fixture.FrameRef, marks: Dictionary[String, int], total: int) -> int:
	if ref == null:
		return -1
	var base: int = ref.frame
	if ref.mark != "":
		if not marks.has(ref.mark):
			return -1
		base = marks[ref.mark]
	var f: int = base + ref.offset
	return f if f >= 0 and f < total else -1


## "" if every condition of [param e] holds at frame [param f], else what failed.
func _first_failure(
	e: Fixture.Expectation, f: int, snaps: Array[Dictionary], expected: Array[Variant]
) -> String:
	for i: int in range(e.conditions.size()):
		var c: Fixture.Condition = e.conditions[i]
		var actual: Variant = snaps[f][c.key]
		if not _compare(actual, c.op, expected[i]):
			return "%s (actual %s=%s, expected %s %s)" % [c.text, c.key, actual, c.op, expected[i]]
	return ""


func _compare(actual: Variant, op: String, expected: Variant) -> bool:
	if typeof(expected) == TYPE_STRING:
		var same: bool = typeof(actual) == TYPE_STRING and str(actual) == str(expected)
		return same if op == "=" else not same
	if typeof(actual) != TYPE_INT:
		return false
	var a: int = actual
	var e: int = expected
	var result: bool = false
	match op:
		"=":
			result = a == e
		"!=":
			result = a != e
		"<":
			result = a < e
		"<=":
			result = a <= e
		">":
			result = a > e
		">=":
			result = a >= e
	return result


func _check_round_trip(replay: Replay, result: Result) -> void:
	var decoded: Replay = Replay.decode(replay.encode())
	if decoded == null:
		result.fail("replay did not decode")
		return
	if decoded.frames != replay.frames or not decoded.scenario.equals(replay.scenario):
		result.fail("replay round trip changed the recording")
		return
	var player := ReplayPlayer.new(decoded)
	if not player.run_to_end():
		result.fail("replay: %s" % player.describe())


func _hash_line(replay: Replay, sim: Simulation) -> String:
	var inputs := StateHasher.new()
	replay.scenario.hash_into(inputs)
	for packed: int in replay.frames:
		inputs.add_int(packed)
	var parts: PackedStringArray = [
		"in:%08x" % inputs.value(),
		"content:%08x" % sim.content_hash,
		"%d:%08x" % [sim.tick, sim.state_hash()],
	]
	for i: int in range(sim.hash_ticks.size()):
		parts.append("%d:%08x" % [sim.hash_ticks[i], sim.hash_values[i]])
	return " ".join(parts)


## Fixtures whose state hashes moved although their inputs and content did not: only a code
## change does that.
func code_changed(old: Dictionary[String, String]) -> Array[String]:
	var changed: Array[String] = []
	for r: Result in results:
		if not old.has(r.name) or old[r.name] == r.hash_line:
			continue
		if _inputs_of(old[r.name]) == _inputs_of(r.hash_line):
			changed.append(r.name)
	return changed


## The "in:" and "content:" tokens of a golden line: what the fixture fed and loaded.
static func _inputs_of(line: String) -> String:
	var words: PackedStringArray = line.split(" ")
	return " ".join(words.slice(0, 2))


func _check_golden(result: Result, golden: Dictionary[String, String], version: int) -> void:
	if version != Simulation.VERSION:
		result.fail(
			(
				"golden hashes were blessed for simulation version %d; this build is version %d"
				% [version, Simulation.VERSION]
			)
		)
		return
	if not golden.has(result.name):
		result.fail("no golden hashes; run tools/replay/bless.gd and commit the result")
		return
	if golden[result.name] != result.hash_line:
		result.fail(
			(
				(
					"state hashes differ from golden (a desync across platforms, or the simulation"
					+ " changed and the fixture needs re-blessing with a Simulation.VERSION bump):"
					+ "\n      golden %s\n      actual %s"
				)
				% [golden[result.name], result.hash_line]
			)
		)


## Writes the golden file, refusing if behaviour changed with the same inputs and the same content
## (which only a code change can do) unless Simulation.VERSION was bumped, so old replays say
## "older build" instead of "desync". A changed fixture or changed content needs no bump: the
## replay's content hash already tells those apart.
func _bless(old: Dictionary[String, String], old_version: int) -> bool:
	var changed: Array[String] = code_changed(old)
	if not changed.is_empty() and old_version == Simulation.VERSION:
		printerr(
			(
				(
					"refusing to bless: %d fixture(s) changed behaviour with the same inputs and"
					+ " content (%s), so the code changed; bump Simulation.VERSION"
					+ " in core/sim/simulation.gd"
				)
				% [changed.size(), ", ".join(changed)]
			)
		)
		return false
	var lines: PackedStringArray = [
		(
			"# Golden hashes per replay fixture: <name> in:<inputs> content:<content>"
			+ " <end tick>:<hash> <tick>:<hash> ..."
		),
		"# Regenerate with: godot --headless --path . --script tools/replay/bless.gd",
		VERSION_PREFIX + str(Simulation.VERSION),
	]
	var sorted: Array[Result] = results.duplicate()
	sorted.sort_custom(func(x: Result, y: Result) -> bool: return x.name < y.name)
	for r: Result in sorted:
		lines.append("%s %s" % [r.name, r.hash_line])
	var f: FileAccess = FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("blessed %d fixtures into %s" % [sorted.size(), GOLDEN_PATH])
	return true
