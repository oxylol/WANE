#!/usr/bin/env bash
# Headless test gate: import the project, then run tools/ci/run_tests.gd (script compile check,
# content schemas, replay fixtures, gdUnit4 unit suites). Extra arguments go to run_tests.gd,
# e.g. `ci/test.sh --stage compile --stage fixtures`.
#
# The run must exit 0 AND print the pass marker: if run_tests.gd itself fails to compile, Godot
# idles instead of exiting, so a time limit and the marker are what keep that from looking green.
# Usage: GODOT=/path/to/godot ci/test.sh [--stage <name>]...
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT:-godot}"
limit="${TEST_TIME_LIMIT:-900}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if ! "$godot" --headless --path . --import > "$log" 2>&1; then
	cat "$log" >&2
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
with_limit "$godot" --headless --path . --script tools/ci/run_tests.gd -- "$@" 2>&1 | tee "$log" || status=$?
if [ "$status" -ne 0 ] || ! grep -q "^ALL STAGES PASSED" "$log"; then
	echo "test: FAILED (exit $status, or no pass marker; 124 or 142 means the ${limit}s limit was hit)" >&2
	exit 1
fi
