class_name FixtureRunner
extends RefCounted
## Runs replay fixtures headless (BUILD.md section 13: "All 12 tech interactions and every boss
## phase are replay fixtures in tests/replay/ ... They run headless in under 10 seconds total").
##
## For each fixture: step the simulation through the input script, check every expectation, then
## prove determinism twice: the recorded replay must survive encoding exactly (its inputs,
## scenario, version, content and every recorded state hash), and the hashes must match the
## committed golden values in [constant GOLDEN_PATH], which CI checks on Linux, Windows and macOS
## (ADR-0006). The replay system's own fixtures (under tests/replay/core/) and every
## [constant PLAYBACK_EVERY]th fixture in path order are also played back in full through
## [ReplayPlayer] in a fresh simulation.
##
## An expectation that cannot be evaluated (a value reference outside the run, a word compared
## with a number, a word the key never takes) fails; nothing passes vacuously.
##
## The suite runs in several processes at once ([member shards]): each runs an interleaved share
## of the fixtures ([code]tools/replay/fixture_shard.gd[/code]) and reports every result on its
## output; this process checks them against the golden file, blesses, and keeps the time
## (ADR-0006).

const FIXTURE_ROOT: String = "res://tests/replay"
const GOLDEN_PATH: String = "res://tests/replay/golden_hashes.txt"
const CORE_FIXTURES: String = "res://tests/replay/core/"
## One fixture in this many (in path order) is played back in full through [ReplayPlayer]. Every
## fixture's replay is checked to decode exactly, and its hashes against the golden file: with the
## same inputs a deterministic simulation reproduces them, so a full playback of each adds
## nothing but its cost (half the suite's time). The sample still catches anything the run does
## that its replay cannot reproduce, such as a probe with a side effect.
const PLAYBACK_EVERY: int = 4
const VERSION_PREFIX: String = "# sim_version "
## BUILD.md section 13 budget for the whole fixture suite.
const SUITE_BUDGET_MSEC: int = 10000
## The most processes the suite runs in, and the script each runs.
const MAX_SHARDS: int = 4
const SHARD_SCRIPT: String = "res://tools/replay/fixture_shard.gd"
## A shard's output line carrying one fixture's result.
const RESULT_PREFIX: String = "fixture-result "

var results: Array[Result] = []
## The suite's time limit in milliseconds; 0 for none (an instrumented coverage run).
var budget_msec: int = SUITE_BUDGET_MSEC
## Processes to run the suite in: 1 runs every fixture in this one (an instrumented coverage run
## must); 0 runs one per processor, up to [constant MAX_SHARDS].
var shards: int = 0
## The script each shard runs (a test points it elsewhere to see a shard die).
var shard_script: String = SHARD_SCRIPT


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

	## The result as one line of tab-separated fields, each escaped as a C string (a shard reports
	## its results this way; [method from_line] reads it back exactly).
	func to_line() -> String:
		var fields: PackedStringArray = [
			name, path, "1" if passed else "0", str(frames), str(msec), hash_line
		]
		fields.append_array(messages)
		var escaped: PackedStringArray = []
		for field: String in fields:
			escaped.append(field.c_escape())
		return "\t".join(escaped)

	static func from_line(line: String) -> Result:
		var fields: PackedStringArray = line.split("\t")
		var r := Result.new()
		if fields.size() < 6:
			r.fail("unreadable shard result: %s" % line)
			return r
		for i: int in range(fields.size()):
			fields[i] = fields[i].c_unescape()
		r.name = fields[0]
		r.path = fields[1]
		r.passed = fields[2] == "1"
		r.frames = fields[3].to_int()
		r.msec = fields[4].to_float()
		r.hash_line = fields[5]
		r.messages = fields.slice(6)
		return r


## Runs every fixture under [constant FIXTURE_ROOT]. With [param bless] the golden file is
## rewritten from this run instead of checked. Returns true if everything passed.
func run_all(bless: bool = false) -> bool:
	results.clear()
	var started: int = Time.get_ticks_msec()
	var golden: Dictionary[String, String] = load_golden()
	var golden_version: int = load_golden_version()
	var names: Dictionary[String, String] = {}
	var failed: int = 0
	var paths: Array[String] = FileWalk.find(FIXTURE_ROOT, [".fixture"])
	var count: int = shards if shards > 0 else mini(OS.get_processor_count(), MAX_SHARDS)
	if count > 1:
		results = run_sharded(paths, count)
	else:
		results = run_paths(paths)
	for result: Result in results:
		if names.has(result.name):
			result.fail("duplicate fixture name (also %s)" % names[result.name])
		names[result.name] = result.path
		if not bless and result.passed:
			_check_golden(result, golden, golden_version)
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
	var busy: float = 0.0
	for r: Result in results:
		busy += r.msec
	print(
		(
			"%d fixtures, %d failed, %d ms (%d ms of fixture time in %d processes)"
			% [results.size(), failed, elapsed, roundi(busy), count]
		)
	)
	if budget_msec > 0 and elapsed > budget_msec:
		printerr("FAIL fixture suite took %d ms, budget %d ms" % [elapsed, budget_msec])
		failed += 1
	if bless and failed == 0:
		return _bless(golden, golden_version)
	return failed == 0


## Runs the fixtures at [param paths] (the whole suite's, in path order) whose place in it is
## [param shard] modulo [param of], in this process: one shard's share, or all of them.
func run_paths(paths: Array[String], shard: int = 0, of: int = 1) -> Array[Result]:
	var out: Array[Result] = []
	for i: int in range(shard, paths.size(), of):
		var path: String = paths[i]
		var play_back: bool = path.begins_with(CORE_FIXTURES) or i % PLAYBACK_EVERY == 0
		out.append(run_fixture(Fixture.parse_file(path), play_back))
	return out


## Runs [param paths] in [param count] processes at once, each [constant SHARD_SCRIPT] with its
## share, and returns their results in path order. A fixture whose result never came back (its
## process died) fails with what that process printed last.
func run_sharded(paths: Array[String], count: int) -> Array[Result]:
	var outputs: Array[Array] = []
	var codes: Array[int] = []
	var threads: Array[Thread] = []
	outputs.resize(count)
	codes.resize(count)
	for k: int in range(count):
		var output: Array[String] = []
		outputs[k] = output
		var thread := Thread.new()
		thread.start(_run_shard.bind(k, count, output, codes))
		threads.append(thread)
	for thread: Thread in threads:
		thread.wait_to_finish()
	var by_path: Dictionary[String, Result] = {}
	for k: int in range(count):
		for chunk: Variant in outputs[k]:
			for line: String in str(chunk).split("\n"):
				if line.begins_with(RESULT_PREFIX):
					# Windows ends the lines with "\r\n".
					var fields: String = line.trim_prefix(RESULT_PREFIX).trim_suffix("\r")
					var result: Result = Result.from_line(fields)
					by_path[result.path] = result
	var out: Array[Result] = []
	for i: int in range(paths.size()):
		if by_path.has(paths[i]):
			out.append(by_path[paths[i]])
			continue
		var lost := Result.new()
		lost.name = paths[i].get_file().get_basename()
		lost.path = paths[i]
		var k: int = i % count
		var tail: String = str(outputs[k][0]).right(400) if not outputs[k].is_empty() else ""
		lost.fail("shard %d of %d (exit %d) returned no result: %s" % [k, count, codes[k], tail])
		out.append(lost)
	return out


func _run_shard(k: int, count: int, output: Array[String], codes: Array[int]) -> void:
	var args: PackedStringArray = [
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		shard_script,
		"--",
		"--shard",
		str(k),
		"--of",
		str(count),
	]
	codes[k] = OS.execute(OS.get_executable_path(), args, output, true)


## Runs one parsed fixture and checks its expectations and replay round-trip; with
## [param play_back] the replay is also played back in full.
func run_fixture(fx: Fixture, play_back: bool = true) -> Result:
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
	_check_round_trip(replay, result, play_back)
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


func _check_round_trip(replay: Replay, result: Result, play_back: bool) -> void:
	var decoded: Replay = Replay.decode(replay.encode())
	if decoded == null:
		result.fail("replay did not decode")
		return
	if (
		decoded.frames != replay.frames
		or not decoded.scenario.equals(replay.scenario)
		or decoded.sim_version != replay.sim_version
		or decoded.content_hash != replay.content_hash
		or decoded.hash_ticks != replay.hash_ticks
		or decoded.hash_values != replay.hash_values
	):
		result.fail("replay round trip changed the recording")
		return
	if not play_back:
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
