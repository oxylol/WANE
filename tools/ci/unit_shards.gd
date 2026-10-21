class_name UnitShards
extends RefCounted
## How the unit stage splits its suites over processes (docs/adr/0006, "Unit shards"): which files
## are suites, which suites must share a process, what each costs, and the plan that gives every
## process about the same cost. All of it is a function of the files and the timing log, so the
## same tree and log give the same plan. tools/ci/unit_runner.gd runs the plan.

## A suite that writes files other suites read, or reads files they write, says so with a line
## "# unit-group: <name>" and then runs in one process with the suites of the same name.
const GROUP_MARK: String = "# unit-group:"
## What gdUnit4's suites extend; a file is a suite when its chain of base scripts ends here
## (GdUnitTestSuiteScanner.is_test_suite, read from the text instead of by loading the script).
const SUITE_BASE: String = "GdUnitTestSuite"
const CLASS_ROOT: String = "res://tests"
## The number of timing-log samples whose median is a suite's cost.
const SAMPLES: int = 3
const MAX_BASE_DEPTH: int = 16

static var _class_name: RegEx = RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
static var _extends: RegEx = RegEx.create_from_string(
	'(?m)^(?:class_name\\s+\\w+\\s+)?extends\\s+("[^"]+"|\\w+)'
)
static var _test_func: RegEx = RegEx.create_from_string("(?m)^(?:static\\s+)?func\\s+test")
## The fields of a timing-log line that [method logged_seconds] reads: item, variant, seconds (the
## lines are written compactly in this order by tools/ci/timing_log.gd, ci/timing.sh and
## tools/ci/timing_report.py).
static var _suite_line: RegEx = RegEx.create_from_string(
	'"item":"([^"]*)","variant":"([^"]*)","seconds":([0-9.]+)'
)
static var _group: RegEx = RegEx.create_from_string("(?m)^" + GROUP_MARK + "\\s*(\\S+)\\s*$")


## One indivisible piece of the plan: suites that run in one process, and what they cost.
class Bundle:
	var paths: PackedStringArray = PackedStringArray()
	var cost: float = 0.0
	## The first path in path order: what ties are broken by.
	var key: String = ""


## The suites with tests under [param targets] (a suite file or a folder, as res:// paths), sorted.
## A file named as a target is returned as it is, so that gdUnit4 itself says what is wrong with
## it; in a folder, a file is a suite when it extends gdUnit4's, directly or through other
## scripts, and runs a test (a base class holding only helpers has nothing to report).
static func find_suites(targets: Array[String]) -> Array[String]:
	var bases: Dictionary[String, String] = class_scripts()
	var found: Array[String] = []
	for target: String in targets:
		if FileAccess.file_exists(target):
			if not found.has(target):
				found.append(target)
			continue
		for path: String in FileWalk.find(target, [".gd"]):
			if not found.has(path) and has_tests(path, bases):
				found.append(path)
	found.sort()
	return found


## Whether the script at [param path] is a gdUnit4 suite that runs at least one test, itself or
## through a base script. [param bases] is the project's class-name-to-script map ([method _bases]).
static func has_tests(path: String, bases: Dictionary[String, String]) -> bool:
	var chain: Array[String] = _chain(path, bases)
	if chain.is_empty():
		return false
	for script: String in chain:
		if _test_func.search(FileAccess.get_file_as_string(script)) != null:
			return true
	return false


## The scripts from [param path] up to (not including) gdUnit4's own base, or empty if the script
## does not extend it.
static func _chain(path: String, bases: Dictionary[String, String]) -> Array[String]:
	var chain: Array[String] = []
	var current: String = path
	for _depth: int in range(MAX_BASE_DEPTH):
		chain.append(current)
		var parent: RegExMatch = _extends.search(FileAccess.get_file_as_string(current))
		if parent == null:
			return []
		var base: String = parent.get_string(1)
		if base == SUITE_BASE:
			return chain
		if base.begins_with('"'):
			current = base.trim_prefix('"').trim_suffix('"')
		elif bases.has(base):
			current = bases[base]
		else:
			return []
	return []


## Every script under [constant CLASS_ROOT] that names a class, by class name.
static func class_scripts() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for path: String in FileWalk.find(CLASS_ROOT, [".gd"]):
		var named: RegExMatch = _class_name.search(FileAccess.get_file_as_string(path))
		if named != null:
			out[named.get_string(1)] = path
	return out


## The group named by [param path]'s "# unit-group:" line, or "" if it has none.
static func group_of(path: String) -> String:
	var found: RegExMatch = _group.search(FileAccess.get_file_as_string(path))
	return found.get_string(1) if found != null else ""


## What each of [param suites] costs, in seconds where the timing log at [param log_path] has them
## (the median of the last [constant SAMPLES] times of the unit stage; those of [param variant]
## if there are any, else any) and, for a suite it has never seen, its file size times what a byte
## of the suites it has seen costs. With no log at all the cost is the file size.
static func costs(
	suites: Array[String], log_path: String, variant: String
) -> Dictionary[String, float]:
	var seen: Dictionary[String, float] = logged_seconds(log_path, variant)
	var rates: Array[float] = []
	for path: String in suites:
		if seen.has(path.trim_prefix("res://")) and file_size(path) > 0:
			rates.append(seen[path.trim_prefix("res://")] / float(file_size(path)))
	rates.sort()
	var rate: float = rates[rates.size() / 2] if not rates.is_empty() else 1.0
	var out: Dictionary[String, float] = {}
	for path: String in suites:
		var key: String = path.trim_prefix("res://")
		out[path] = seen[key] if seen.has(key) else float(file_size(path)) * rate
	return out


## Each suite's recent time in the log, by path from the project root ("tests/unit/core/x.gd").
static func logged_seconds(log_path: String, variant: String) -> Dictionary[String, float]:
	var same: Dictionary[String, PackedFloat64Array] = {}
	var any: Dictionary[String, PackedFloat64Array] = {}
	for part: String in [log_path + ".1", log_path]:
		if not FileAccess.file_exists(part):
			continue
		for line: String in FileAccess.get_file_as_string(part).split("\n", false):
			if not line.contains('"kind":"suite"') or not line.contains('"stage":"unit"'):
				continue
			var fields: RegExMatch = _suite_line.search(line)
			if fields == null:
				continue
			var item: String = fields.get_string(1)
			var seconds: float = fields.get_string(3).to_float()
			if not any.has(item):
				any[item] = PackedFloat64Array()
			any[item].append(seconds)
			if fields.get_string(2) == variant:
				if not same.has(item):
					same[item] = PackedFloat64Array()
				same[item].append(seconds)
	var out: Dictionary[String, float] = {}
	for item: String in any:
		var samples: PackedFloat64Array = same[item] if same.has(item) else any[item]
		out[item] = median(samples.slice(maxi(0, samples.size() - SAMPLES)))
	return out


static func median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var middle: int = sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) / 2.0


static func file_size(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size: int = file.get_length()
	file.close()
	return size


## Suites of one group share a bundle; every other suite is a bundle of its own.
## [param groups] maps a suite to its group name ("" for none).
static func bundles(
	suites: Array[String], cost: Dictionary[String, float], groups: Dictionary[String, String]
) -> Array[Bundle]:
	var out: Array[Bundle] = []
	var by_group: Dictionary[String, Bundle] = {}
	for path: String in suites:
		var group: String = groups.get(path, "")
		var bundle: Bundle = by_group.get(group) if group != "" else null
		if bundle == null:
			bundle = Bundle.new()
			bundle.key = path
			out.append(bundle)
			if group != "":
				by_group[group] = bundle
		bundle.paths.append(path)
		bundle.cost += cost.get(path, 0.0)
	return out


## Splits [param bundles] over at most [param count] processes: the costliest bundle not yet
## placed goes to the process with the least so far (ties to the lower one, and to the earlier
## path among equal costs), and each process runs its suites in path order. Processes that get
## nothing are left out, so the result has between 1 and [param count] shares.
static func plan(bundle_list: Array[Bundle], count: int) -> Array[PackedStringArray]:
	var order: Array[Bundle] = bundle_list.duplicate()
	order.sort_custom(
		func(a: Bundle, b: Bundle) -> bool:
			return a.cost > b.cost or (a.cost == b.cost and a.key < b.key)
	)
	var processes: int = clampi(count, 1, maxi(1, order.size()))
	var shares: Array[PackedStringArray] = []
	var loads: PackedFloat64Array = PackedFloat64Array()
	for _k: int in range(processes):
		shares.append(PackedStringArray())
		loads.append(0.0)
	for bundle: Bundle in order:
		var lightest: int = 0
		for k: int in range(1, processes):
			if loads[k] < loads[lightest]:
				lightest = k
		shares[lightest].append_array(bundle.paths)
		loads[lightest] += bundle.cost
	for share: PackedStringArray in shares:
		share.sort()
	var used: Array[PackedStringArray] = []
	for share: PackedStringArray in shares:
		if not share.is_empty():
			used.append(share)
	return used
