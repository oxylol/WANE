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
## The suite runs in several shards at once ([member shards]), each a share of the fixtures that
## [method plan_shards] balances: shard 0 in this process, the others in processes of their own
## ([code]tools/replay/fixture_shard.gd[/code]) that report every result on their output. This
## process checks the results against the golden file, blesses, and keeps the time (ADR-0006).
##
## What makes it fast is work not done, never a check not made (ADR-0006, Shards): the fixtures of
## a shard share what their simulations read ([SimCache]), a fixture reads only the probe keys at
## the frames its expectations look at ([method Fixture.probe_plan]), and no shard waits for the
## others' playbacks.

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
## A shard's last output line: the milliseconds of CPU time the process used ([method
## process_cpu_msec]).
const CPU_PREFIX: String = "fixture-cpu "
## /proc/<pid>/stat counts CPU time in clock ticks; Linux's are 100 a second.
const CLOCK_TICKS_PER_SECOND: int = 100
## A shard's output line naming the native mode it ran in ([method mode_line]).
const MODE_PREFIX: String = "fixture-mode "
## The ticks of simulation one fixture's own work is taken to cost when the shards are balanced
## ([method shard_weight]).
const FIXTURE_OVERHEAD_TICKS: int = 20
## What a shard in a process of its own spends before its first fixture, in the same ticks: the
## process starts, loads the project and compiles the simulation (about a second; a tick of the
## suite's average fixture costs about a ninth of a millisecond). Shard 0 runs in the process that
## started the others, has all of that done, and takes that much more of the suite.
const CHILD_START_TICKS: int = 9000

## The snapshot of a frame no expectation looks at ([method Fixture.probe_plan]).
const NOT_PROBED: Dictionary[String, Variant] = {}
## What [method _first_failure] says when an expectation reads a value the plan did not probe: a
## fault in the plan or the evaluation, never a verdict on the simulation.
const PLAN_MISS: String = "internal error: not probed"

var results: Array[Result] = []
## The suite's time limit in milliseconds; 0 for none (an instrumented coverage run).
var budget_msec: int = SUITE_BUDGET_MSEC
## Processes to run the suite in: 1 runs every fixture in this one (an instrumented coverage run
## must); 0 runs one per processor, up to [constant MAX_SHARDS].
var shards: int = 0
## The script each shard in a process of its own runs (a test points it elsewhere to see a shard
## die).
var shard_script: String = SHARD_SCRIPT
## What starting a shard's process costs, in ticks of simulation, when the shards are planned
## ([constant CHILD_START_TICKS]); a test sets 0 to put fixtures in every process.
var child_start_ticks: int = CHILD_START_TICKS
## The mode line each shard of the last [method run_sharded] reported, by shard (empty: none).
var shard_modes: Array[String] = []
## The CPU time each shard of the last [method run_sharded] used, in milliseconds (-1: not
## known on this platform), and the wall time that call took.
var shard_cpu_msec: Array[int] = []
var sharded_msec: int = 0
## Quiet (tools/ci/run_tests.gd --quiet): [method run_all] prints nothing and leaves each failure
## in [member failure_blocks] instead, as lines for tools/ci/quiet_report.gd.
var quiet: bool = false
var failure_blocks: Array[PackedStringArray] = []


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


## How many fixtures the last [method run_all] ran.
func result_count() -> int:
	return results.size()


## One failure that is not one fixture's: on stderr, or, quiet, a block of its own.
func _fail_line(text: String) -> void:
	if quiet:
		failure_blocks.append(PackedStringArray([text]))
	else:
		printerr(text)


## Runs every fixture under [constant FIXTURE_ROOT]. With [param bless] the golden file is
## rewritten from this run instead of checked. Returns true if everything passed.
func run_all(bless: bool = false) -> bool:
	results.clear()
	failure_blocks.clear()
	var started: int = Time.get_ticks_msec()
	var cpu_started: int = process_cpu_msec()
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
			if quiet:
				failure_blocks.append(QuietReport.fixture_failure(r.name, r.path, r.messages))
				continue
			printerr("FAIL %s (%s)" % [r.name, r.path])
			for m: String in r.messages:
				printerr("    %s" % m)
		elif not quiet:
			print("pass %-44s %5d frames %7.1f ms" % [r.name, r.frames, r.msec])
	if not bless:
		for stale: String in golden.keys():
			if not names.has(stale):
				_fail_line("FAIL golden entry '%s' has no fixture; re-bless" % stale)
				failed += 1
	var elapsed: int = Time.get_ticks_msec() - started
	var busy: float = 0.0
	for r: Result in results:
		busy += r.msec
	if not quiet:
		print(
			(
				"%d fixtures, %d failed, %d ms (%d ms of fixture time in %d processes)"
				% [results.size(), failed, elapsed, roundi(busy), count]
			)
		)
	# CPU time is information: it never decides the budget (ADR-0006, Budget).
	var cpu: int = _cpu_equivalent_msec(count, elapsed, cpu_started)
	if cpu >= 0 and not quiet:
		print("CPU time of the slowest process and the runner: %d ms (information only)" % cpu)
	var native: bool = NativeBackend.use_native()
	if over_budget(elapsed, budget_msec, native):
		_fail_line("FAIL fixture suite took %d ms, budget %d ms" % [elapsed, budget_msec])
		failed += 1
	elif budget_msec > 0 and not native and not quiet:
		print("budget not applied: the GDScript reference path (ADR-0006, Budget)")
	if bless and failed == 0:
		return _bless(golden, golden_version)
	return failed == 0


## Whether a suite that took [param elapsed_msec] fails [param limit_msec] (0: none). The budget is
## the shipped configuration's, the native path's ([param native]); the GDScript reference run
## proves the same hashes and is not timed against it (ADR-0006, Budget; the director's decision).
static func over_budget(elapsed_msec: int, limit_msec: int, native: bool) -> bool:
	return native and limit_msec > 0 and elapsed_msec > limit_msec


## The milliseconds of CPU time (user and system, every thread) this process has used, or -1 where
## /proc is not there (not Linux).
static func process_cpu_msec() -> int:
	if not FileAccess.file_exists("/proc/self/stat"):
		return -1
	# A /proc file reports length 0, so it is read line by line, not whole.
	var file: FileAccess = FileAccess.open("/proc/self/stat", FileAccess.READ)
	return cpu_msec_from_stat(file.get_line()) if file != null else -1


## The CPU time in a /proc/<pid>/stat line: utime and stime, fields 14 and 15. The command name
## (field 2) may hold spaces and brackets, so the fields are counted from the last ")". -1 if the
## line is too short.
static func cpu_msec_from_stat(text: String) -> int:
	var close: int = text.rfind(")")
	if close < 0:
		return -1
	# From field 3 (the state): utime is the 12th of these, stime the 13th.
	var fields: PackedStringArray = text.substr(close + 1).strip_edges().split(" ", false)
	if fields.size() < 13:
		return -1
	return (fields[11].to_int() + fields[12].to_int()) * 1000 / CLOCK_TICKS_PER_SECOND


## What the suite cost in CPU time as one process at a time would see it: the slowest shard's CPU
## time plus the runner's own work around the shards (all of its wall time but theirs). -1 if
## any of it is unknown.
func _cpu_equivalent_msec(count: int, elapsed: int, cpu_started: int) -> int:
	if count <= 1:
		var now: int = process_cpu_msec()
		return now - cpu_started if now >= 0 and cpu_started >= 0 else -1
	var slowest: int = -1
	for ms: int in shard_cpu_msec:
		if ms < 0:
			return -1
		slowest = maxi(slowest, ms)
	return slowest + maxi(0, elapsed - sharded_msec) if slowest >= 0 else -1


## Runs the fixtures at [param paths] (the whole suite's, in path order) whose place in it is
## [param shard] modulo [param of], in this process: one shard's share, or all of them.
func run_paths(paths: Array[String], shard: int = 0, of: int = 1) -> Array[Result]:
	var places: PackedInt32Array = PackedInt32Array()
	for i: int in range(shard, paths.size(), of):
		places.append(i)
	return run_places(paths, places)


## Runs the fixtures at [param places] in [param paths] (the whole suite's, in path order), in this
## process and in that order. The fixtures share what their simulations read ([SimCache]).
func run_places(paths: Array[String], places: PackedInt32Array) -> Array[Result]:
	var cache := SimCache.new()
	var out: Array[Result] = []
	for i: int in places:
		out.append(run_fixture(Fixture.parse_file(paths[i]), plays_back(paths[i], i), cache))
	return out


## The native mode and whether the native path is in use, as a shard reports it and the runner
## expects it.
static func mode_line() -> String:
	return "%s native=%s" % [NativeBackend.mode_name(), NativeBackend.use_native()]


## Runs [param paths] in [param count] shards at once and returns their results in path order:
## shard 0 in this process, which has its simulations compiled already, and each of the others in a
## process of its own running [constant SHARD_SCRIPT], which spends [constant CHILD_START_TICKS]
## of simulation starting up. Each has the share [method plan_shards] gave it. A fixture whose
## result never came back (its process died) fails with what that process printed last.
func run_sharded(paths: Array[String], count: int) -> Array[Result]:
	var began: int = Time.get_ticks_msec()
	# A shard finds its fixtures by their place in the suite, which it walks as this process does.
	var suite: Array[String] = FileWalk.find(FIXTURE_ROOT, [".fixture"])
	var place_of: Dictionary[String, int] = {}
	for i: int in range(suite.size()):
		place_of[suite[i]] = i
	var wanted: PackedInt32Array = PackedInt32Array()
	var weights: PackedInt64Array = PackedInt64Array()
	for path: String in paths:
		if place_of.has(path):
			var place: int = place_of[path]
			wanted.append(place)
			weights.append(shard_weight(path, place))
	var shares: Array[PackedInt32Array] = plan_shards(wanted, weights, count, child_start_ticks)
	var shard_of: Dictionary[int, int] = {}
	var outputs: Array[Array] = []
	var codes: Array[int] = []
	var threads: Array[Thread] = []
	outputs.resize(count)
	codes.resize(count)
	for k: int in range(count):
		var output: Array[String] = []
		outputs[k] = output
		for place: int in shares[k]:
			shard_of[place] = k
		if k == 0 or shares[k].is_empty():
			continue
		var thread := Thread.new()
		thread.start(_run_shard.bind(k, count, shares[k], output, codes))
		threads.append(thread)
	var local: Array[Result] = []
	var local_cpu: int = -1
	if not shares[0].is_empty():
		var cpu_began: int = process_cpu_msec()
		local = run_places(suite, shares[0])
		var cpu_ended: int = process_cpu_msec()
		local_cpu = cpu_ended - cpu_began if cpu_began >= 0 and cpu_ended >= 0 else -1
	for thread: Thread in threads:
		thread.wait_to_finish()
	sharded_msec = Time.get_ticks_msec() - began
	var by_path: Dictionary[String, Result] = {}
	shard_modes.clear()
	shard_modes.resize(count)
	shard_cpu_msec.clear()
	shard_cpu_msec.resize(count)
	shard_cpu_msec.fill(-1)
	shard_modes[0] = mode_line()
	shard_cpu_msec[0] = local_cpu
	for result: Result in local:
		by_path[result.path] = result
	for k: int in range(1, count):
		var found: Array[Result] = []
		for chunk: Variant in outputs[k]:
			for line: String in str(chunk).split("\n"):
				# Windows ends the lines with "\r\n".
				line = line.trim_suffix("\r")
				if line.begins_with(MODE_PREFIX):
					shard_modes[k] = line.trim_prefix(MODE_PREFIX)
				elif line.begins_with(CPU_PREFIX):
					shard_cpu_msec[k] = line.trim_prefix(CPU_PREFIX).to_int()
				elif line.begins_with(RESULT_PREFIX):
					found.append(Result.from_line(line.trim_prefix(RESULT_PREFIX)))
		# A shard that ran on another path than this process proves nothing about this one.
		if not found.is_empty() and shard_modes[k] != mode_line():
			for result: Result in found:
				result.fail(
					(
						"shard %d ran native '%s', this process runs '%s' (ADR-0021)"
						% [k, shard_modes[k], mode_line()]
					)
				)
		for result: Result in found:
			by_path[result.path] = result
	var out: Array[Result] = []
	for path: String in paths:
		if by_path.has(path):
			out.append(by_path[path])
			continue
		var lost := Result.new()
		lost.name = path.get_file().get_basename()
		lost.path = path
		if not place_of.has(path):
			lost.fail("not a fixture of the suite under %s" % FIXTURE_ROOT)
			out.append(lost)
			continue
		var k: int = shard_of[place_of[path]]
		var tail: String = str(outputs[k][0]).right(400) if not outputs[k].is_empty() else ""
		lost.fail("shard %d of %d (exit %d) returned no result: %s" % [k, count, codes[k], tail])
		out.append(lost)
	return out


## What the fixture at [param path], [param place] in the suite, costs the shard that runs it, in
## ticks of simulation: its frames (read from its header, not parsed) for the run, and again for
## the playback if it is played back, and the ticks one fixture's own work comes to
## ([constant FIXTURE_OVERHEAD_TICKS]: parsing it, recording and checking its replay, building its
## simulations). A guess, good enough to balance the shards; a poor one costs time, never a result.
static func shard_weight(path: String, place: int) -> int:
	var ticks: int = Fixture.peek_frames(path) + FIXTURE_OVERHEAD_TICKS
	return ticks * (2 if plays_back(path, place) else 1)


## Whether the fixture at [param path], [param place] in the suite, is also played back in full.
static func plays_back(path: String, place: int) -> bool:
	return path.begins_with(CORE_FIXTURES) or place % PLAYBACK_EVERY == 0


## Splits the fixtures at [param places] over [param count] shards so that each has about the same
## [param weights]: the heaviest fixture not yet placed goes to the shard with the least so far
## (ties to the lower shard), and each shard runs its fixtures in suite order. Every shard but
## the first starts with [param late_weight] already counted against it. The plan is a
## function of its arguments alone. It replaces the interleave (shard k ran every n-th fixture),
## which put every playback (every fourth fixture) on the same shard whenever n was 2 or 4, and
## left the slowest shard a third over the mean.
static func plan_shards(
	places: PackedInt32Array, weights: PackedInt64Array, count: int, late_weight: int = 0
) -> Array[PackedInt32Array]:
	var order: Array[int] = []
	for i: int in range(places.size()):
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			return weights[a] > weights[b] or (weights[a] == weights[b] and places[a] < places[b])
	)
	var shares: Array[PackedInt32Array] = []
	var loads: PackedInt64Array = PackedInt64Array()
	for k: int in range(count):
		shares.append(PackedInt32Array())
		loads.append(0 if k == 0 else late_weight)
	for i: int in order:
		var lightest: int = 0
		for k: int in range(1, count):
			if loads[k] < loads[lightest]:
				lightest = k
		shares[lightest].append(places[i])
		loads[lightest] += weights[i]
	for share: PackedInt32Array in shares:
		share.sort()
	return shares


func _run_shard(
	k: int, count: int, places: PackedInt32Array, output: Array[String], codes: Array[int]
) -> void:
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
		"--places",
		_join_places(places),
		"--native",
		NativeBackend.mode_name(),
	]
	codes[k] = OS.execute(OS.get_executable_path(), args, output, true)


static func _join_places(places: PackedInt32Array) -> String:
	var words: PackedStringArray = PackedStringArray()
	for place: int in places:
		words.append(str(place))
	return ",".join(words)


## Runs one parsed fixture and checks its expectations and replay round-trip; with
## [param play_back] the replay is also played back in full. Builds its simulations with
## [param cache] if given ([SimCache]); the result is the same without.
func run_fixture(fx: Fixture, play_back: bool = true, cache: SimCache = null) -> Result:
	var result := Result.new()
	result.name = fx.name
	result.path = fx.path
	result.frames = fx.frame_total
	for e: String in fx.errors:
		result.fail("parse: %s" % e)
	if not result.passed:
		return result
	var started: int = Time.get_ticks_usec()
	var sim := Simulation.new(fx.scenario, cache)
	var recorder := ReplayRecorder.new(fx.scenario)
	var keys: Array[String] = fx.probe_keys()
	var plan: Dictionary[int, PackedStringArray] = fx.probe_plan()
	var inputs: Array[InputFrame] = fx.input_frames()
	var snaps: Array[Dictionary] = []
	for i: int in range(fx.frame_total):
		var frame: InputFrame = inputs[i]
		sim.step(frame)
		recorder.record(frame)
		if not plan.has(i):
			snaps.append(NOT_PROBED)
			continue
		var snap: Dictionary[String, Variant] = {}
		for key: String in plan[i]:
			snap[key] = sim.probe(key)
		snaps.append(snap)
	for key: String in keys:
		if snaps[0][key] == null:
			result.fail("unknown probe key '%s'" % key)
	if result.passed:
		_evaluate(fx, snaps, sim, result)
	var replay: Replay = recorder.finish(sim)
	_check_round_trip(replay, result, play_back, cache)
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
					var why: String = _first_failure(e, f, snaps, expected)
					if why == "":
						result.fail("%s: all conditions held at frame %d" % [where, f])
						break
					if why.begins_with(PLAN_MISS):
						result.fail("%s: frame %d: %s" % [where, f, why])
						break
			"mark":
				for f: int in range(a, b + 1):
					var why: String = _first_failure(e, f, snaps, expected)
					if why == "":
						marks[e.mark_name] = f
						break
					if why.begins_with(PLAN_MISS):
						result.fail("%s: frame %d: %s" % [where, f, why])
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
				if not snaps[at].has(t.key):
					return "%s: '%s' at frame %d" % [PLAN_MISS, t.key, at]
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
		if not snaps[f].has(c.key):
			return "%s: '%s' at frame %d" % [PLAN_MISS, c.key, f]
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


func _check_round_trip(
	replay: Replay, result: Result, play_back: bool, cache: SimCache = null
) -> void:
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
	var player := ReplayPlayer.new(decoded, cache)
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
