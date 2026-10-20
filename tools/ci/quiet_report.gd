class_name QuietReport
extends RefCounted
## What an agent needs from a test run and nothing else (tests/README.md, "For agents: quiet
## runs"): one line per stage and, on a failure, only the failure's own words with the colour
## codes stripped and the length capped. tools/ci/run_tests.gd prints these under --quiet; the
## extraction lives here so it is tested on recorded output (tests/unit/tools/samples/).

## A failure's message is cut to this many lines.
const MAX_DETAIL_LINES: int = 15
## How a failure's detail sits under its heading line.
const DETAIL_INDENT: String = "    "
## The last lines of a unit run's output kept for a run that failed with nothing to report.
const TAIL_LINES: int = 10
## gdUnit4 prints this when a suite does not compile, then each parse error and its location.
const DISCOVERY_HEADER: String = "Script errors were detected during test discovery!"
## What gdUnit4 prints for a test case's end; only these start a failure block.
const FAILING_STATUSES: Array[String] = ["FAILED", "WARNING", "ERROR", "ABORTED"]
## The heading, and the BBCode table, of the difference gdUnit4 adds to a failed comparison.
const DIFF_HEADER: String = "Differences found:"
const DIFF_TABLE: String = "[table="
## A test location gdUnit4 glues to the end of a message line with a tab.
const LOCATION_MARK: String = "\tat "

static var _ansi: RegEx = RegEx.create_from_string("\\x1b\\[[0-9;?]*[A-Za-z]")
static var _case_line: RegEx = RegEx.create_from_string(
	"^\\s*(\\S+) > (.+?) (STARTED|PASSED|FAILED|SKIPPED|WARNING|ERROR|ABORTED|FLAKY)\\b"
)
static var _finalize_line: RegEx = RegEx.create_from_string("^\\s*(\\S+) > finalize\\(\\)\\s*$")
static var _summary_line: RegEx = RegEx.create_from_string(
	(
		"Overall Summary: (\\d+) test cases \\| (\\d+) errors \\| (\\d+) failures \\| (\\d+) flaky"
		+ " \\| (\\d+) skipped \\| (\\d+) orphans"
	)
)


## [param text] without ANSI escape sequences (colours, styles, clear-screen).
static func strip_ansi(text: String) -> String:
	return _ansi.sub(text, "", true)


## [param lines] cut to [param limit] lines: the first lines, a "... N more lines" marker, and
## the last [param keep_tail] lines (a unit failure's location is its last line).
static func clip(
	lines: PackedStringArray, limit: int = MAX_DETAIL_LINES, keep_tail: int = 0
) -> PackedStringArray:
	if lines.size() <= limit:
		return lines
	var out: PackedStringArray = lines.slice(0, limit - keep_tail)
	var hidden: int = lines.size() - limit
	out.append("... %d more line%s" % [hidden, "" if hidden == 1 else "s"])
	if keep_tail > 0:
		out.append_array(lines.slice(lines.size() - keep_tail))
	return out


## One stage's line: "compile PASS 152 scripts 4.1 s".
static func stage_line(stage: String, ok: bool, summary: String, seconds: float) -> String:
	var parts: PackedStringArray = [stage, "PASS" if ok else "FAIL"]
	if summary != "":
		parts.append(summary)
	parts.append("%s s" % seconds_text(seconds))
	return " ".join(parts)


## [param seconds] to one decimal, rounded half up, in integer arithmetic. printf rounds a tie by
## the C library it was built with and CI's Windows run printed 0.25 as "0.23" where Linux and
## macOS print "0.2"; a time in a log needs no more than the same text on every platform.
static func seconds_text(seconds: float) -> String:
	var tenths: int = maxi(roundi(seconds * 10.0), 0)
	var whole: int = floori(float(tenths) / 10.0)
	return "%d.%d" % [whole, tenths - whole * 10]


## A failure as one block of lines: [param heading], then [param detail] clipped and indented.
static func failure_block(
	heading: String, detail: PackedStringArray, keep_tail: int = 0
) -> PackedStringArray:
	var out: PackedStringArray = [heading]
	for line: String in clip(detail, MAX_DETAIL_LINES, keep_tail):
		out.append(DETAIL_INDENT + line)
	return out


## A replay fixture that failed: its name and path, then each failing expectation.
static func fixture_failure(
	name: String, path: String, messages: PackedStringArray
) -> PackedStringArray:
	return failure_block("FAIL %s (%s)" % [name, path], messages)


## A script that does not compile: its path, then the engine's errors for it (the first
## occurrence of each; the engine reports a parse error more than once).
static func compile_failure(path: String, errors: PackedStringArray) -> PackedStringArray:
	var seen: PackedStringArray = PackedStringArray()
	for error: String in errors:
		if not seen.has(error):
			seen.append(error)
	return failure_block("does not compile: %s" % path, seen)


## The outcome of one gdUnit4 run, read from its output.
class UnitResult:
	## Test cases the run reports having executed (0 until its summary line is read).
	var cases: int = 0
	var errors: int = 0
	var failures: int = 0
	## Whether the run reached its "Overall Summary" line.
	var has_summary: bool = false
	## One block per failing case: "suite > case", then its message lines (see failure_block).
	var blocks: Array[PackedStringArray] = []
	## The parse errors of a suite that does not compile.
	var discovery: PackedStringArray = PackedStringArray()
	## The last non-empty lines of the output.
	var tail: PackedStringArray = PackedStringArray()

	## Cases that did not pass, by the run's own count, or by the blocks if the run was cut off.
	func failed() -> int:
		return maxi(blocks.size(), errors + failures)

	## Everything to report under a failed unit stage's line: a block for each failing case, or
	## for why there are none (a suite that does not compile, or the run's last lines).
	func failure_blocks(exit_code: int) -> Array[PackedStringArray]:
		var out: Array[PackedStringArray] = blocks.duplicate()
		if not discovery.is_empty():
			out.append(QuietReport.failure_block("a suite does not compile", discovery))
		if out.is_empty():
			out.append(
				QuietReport.failure_block(
					"unit run exited %d with no failing case; its last lines:" % exit_code, tail
				)
			)
		return out


## Reads gdUnit4's console output ([param lines], from stdout; the engine's own error lines on
## stderr are not part of it) into a [class UnitResult].
static func parse_unit(lines: PackedStringArray) -> UnitResult:
	var result: UnitResult = UnitResult.new()
	var heading: String = ""
	var body: PackedStringArray = PackedStringArray()
	var in_discovery: bool = false
	for raw: String in lines:
		var line: String = strip_ansi(raw).strip_edges(false, true)
		if line.strip_edges() != "":
			result.tail.append(line.strip_edges())
			if result.tail.size() > TAIL_LINES:
				result.tail.remove_at(0)
		if line == DISCOVERY_HEADER:
			_end_block(result, heading, body)
			heading = ""
			in_discovery = true
			continue
		if in_discovery:
			if line.begins_with("Abnormal exit") or line.begins_with("Run dispose"):
				in_discovery = false
			elif line.strip_edges() != "":
				_append_message_line(result.discovery, line)
			continue
		var case_match: RegExMatch = _case_line.search(line)
		var finalize_match: RegExMatch = _finalize_line.search(line)
		var summary_match: RegExMatch = _summary_line.search(line)
		if case_match != null or finalize_match != null or summary_match != null:
			_end_block(result, heading, body)
			heading = ""
		elif line.begins_with("Statistics:") or line.begins_with("Run Test Suite:"):
			_end_block(result, heading, body)
			heading = ""
		if case_match != null:
			if FAILING_STATUSES.has(case_match.get_string(3)):
				heading = _heading(case_match.get_string(1), case_match.get_string(2))
		elif finalize_match != null:
			heading = _heading(finalize_match.get_string(1), "finalize()")
		elif summary_match != null:
			result.has_summary = true
			result.cases = summary_match.get_string(1).to_int()
			result.errors = summary_match.get_string(2).to_int()
			result.failures = summary_match.get_string(3).to_int()
		elif heading != "":
			_append_message_line(body, line)
		if case_match != null or finalize_match != null:
			body = PackedStringArray()
	_end_block(result, heading, body)
	return result


static func _heading(suite: String, test_case: String) -> String:
	return "%s > %s" % [suite.get_file().get_basename(), test_case]


## Adds [param line] to [param into], with a test location glued on by a tab put on its own line.
## Blank lines and gdUnit4's BBCode difference table (which repeats the two values the message
## already shows) are left out.
static func _append_message_line(into: PackedStringArray, line: String) -> void:
	var cut: int = line.find(LOCATION_MARK)
	if cut >= 0:
		_append_message_line(into, line.left(cut))
		into.append("at " + line.substr(cut + LOCATION_MARK.length()))
		return
	# gdUnit4 indents the first line of a message by two spaces and its other lines by one.
	var text: String = line.trim_prefix("  ").strip_edges(false, true)
	if text.strip_edges() == "" or text.strip_edges() == DIFF_HEADER or text.contains(DIFF_TABLE):
		return
	into.append(text)


## Files the block being read under [param heading], if there is one.
static func _end_block(result: UnitResult, heading: String, body: PackedStringArray) -> void:
	if heading == "":
		return
	var message: PackedStringArray = body.duplicate()
	if not message.is_empty() and message[0].strip_edges() == "Report:":
		message.remove_at(0)
	while not message.is_empty() and message[message.size() - 1].strip_edges() == "":
		message.remove_at(message.size() - 1)
	result.blocks.append(failure_block(heading, message, 1))
