class_name UnitReport
extends RefCounted
## What gdUnit4's JUnit report (<report dir>/report_N/results.xml) says about a unit run: each
## suite that reported, with its path, its time and its cases' names and times. The timing log
## (tools/ci/timing_log.gd) takes its suite and case lines from it, and the parallel unit stage
## (tools/ci/unit_shards.gd, docs/adr/0006) checks that every suite it handed out reported.

const RESULTS_FILE: String = "results.xml"
const REPORT_PREFIX: String = "report_"


## One suite as the report lists it.
class Suite:
	## The suite's file, from the project root: "tests/unit/core/test_rng.gd".
	var path: String = ""
	var seconds: float = 0.0
	## Case names and times, in the order the report lists them.
	var case_names: PackedStringArray = PackedStringArray()
	var case_seconds: PackedFloat64Array = PackedFloat64Array()


## The results.xml of the newest report_N folder under [param report_dir], or "" if there is none.
static func newest_results(report_dir: String) -> String:
	var dir: DirAccess = DirAccess.open(report_dir)
	if dir == null:
		return ""
	var best: int = -1
	for sub: String in dir.get_directories():
		if not sub.begins_with(REPORT_PREFIX):
			continue
		var number: String = sub.trim_prefix(REPORT_PREFIX)
		if number.is_valid_int() and number.to_int() > best:
			if FileAccess.file_exists(report_dir.path_join(sub).path_join(RESULTS_FILE)):
				best = number.to_int()
	if best < 0:
		return ""
	return report_dir.path_join(REPORT_PREFIX + str(best)).path_join(RESULTS_FILE)


## The suites in the report at [param results_path], in its order; empty if it cannot be read.
static func read(results_path: String) -> Array[Suite]:
	var suites: Array[Suite] = []
	var parser := XMLParser.new()
	if not FileAccess.file_exists(results_path) or parser.open(results_path) != OK:
		return suites
	var current: Suite = null
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var element: String = parser.get_node_name()
		if element == "testsuite":
			current = Suite.new()
			var package: String = _attribute(parser, "package")
			var file: String = _attribute(parser, "name") + ".gd"
			current.path = package.path_join(file) if package != "" else file
			current.seconds = _attribute(parser, "time").to_float()
			suites.append(current)
		elif element == "testcase" and current != null:
			current.case_names.append(_attribute(parser, "name"))
			current.case_seconds.append(_attribute(parser, "time").to_float())
	return suites


static func _attribute(parser: XMLParser, name: String) -> String:
	return parser.get_named_attribute_value_safe(name)
