#!/usr/bin/env bash
# Headless test gate: import the project, then run tools/ci/run_tests.gd (script compile check,
# content schemas, replay fixtures, gdUnit4 unit suites). Extra arguments go to run_tests.gd,
# e.g. `ci/test.sh --stage compile --stage fixtures`.
#
# The run must exit 0 AND print the pass marker: if run_tests.gd itself fails to compile, Godot
# idles instead of exiting, so a time limit and the marker are what keep that from looking green.
#
# --quiet is for agents, who run this dozens of times and read every line: one line per stage
# ("compile PASS 155 scripts 4.1 s"), and for a stage that fails only what failed (the script and
# its error, the content problem, the fixture's failing expectations, the unit case's message),
# then the same closing marker. The engine's own stderr noise is dropped; it is shown (last 20
# lines) only if the run died without reaching the marker. CI runs without it and keeps its full
# logs. To run a few unit suites only, see ci/unit.sh.
# Usage: GODOT=/path/to/godot ci/test.sh [--quiet] [--stage <name>]...
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT:-godot}"
limit="${TEST_TIME_LIMIT:-900}"
log="$(mktemp)"
err="$(mktemp)"
trap 'rm -f "$log" "$err"' EXIT
quiet=0
for arg in "$@"; do
	if [ "$arg" = "--quiet" ]; then quiet=1; fi
done
# Godot colours its console output even when it is not a terminal.
strip_ansi() { sed $'s/\x1b\\[[0-9;?]*[A-Za-z]//g'; }
if ! "$godot" --headless --path . --import > "$log" 2>&1; then
	if [ "$quiet" -eq 1 ]; then strip_ansi < "$log" | tail -n 30 >&2; else cat "$log" >&2; fi
	echo "test: project import failed" >&2
	exit 1
fi
# GNU timeout where it exists (Linux, Git Bash), gtimeout from Homebrew coreutils, otherwise
# perl's alarm (macOS ships perl but not timeout). All three exit 124 or 142 on the limit.
with_limit() {
	if command -v timeout > /dev/null 2>&1; then
		timeout "$limit" "$@"
	elif command -v gtimeout > /dev/null 2>&1; then
		gtimeout "$limit" "$@"
	else
		perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$limit" "$@"
	fi
}
status=0
if [ "$quiet" -eq 1 ]; then
	with_limit "$godot" --headless --path . --script tools/ci/run_tests.gd -- "$@" > "$log" 2> "$err" || status=$?
	grep -v -e '^Godot Engine v' -e '^$' "$log" || true
else
	with_limit "$godot" --headless --path . --script tools/ci/run_tests.gd -- "$@" 2>&1 | tee "$log" || status=$?
fi
if [ "$status" -ne 0 ] || ! grep -q "^ALL STAGES PASSED" "$log"; then
	if [ "$quiet" -eq 1 ] && grep -q "^FAILED STAGES" "$log"; then
		echo "test: FAILED (exit $status)" >&2
		exit 1
	fi
	if [ "$quiet" -eq 1 ]; then strip_ansi < "$err" | tail -n 20 >&2; fi
	echo "test: FAILED (exit $status, or no pass marker; 124 or 142 means the ${limit}s limit was hit)" >&2
	exit 1
fi
