#!/usr/bin/env bash
# Run some gdUnit4 suites without the rest of the gate: each argument is a suite (a .gd file) or a
# folder of suites, as a res:// path (a path from the project root works too).
#
# It is ci/test.sh's compile and unit stages with the unit stage pointed at the given paths: the
# compile stage runs first and stops the run if any script does not compile (a broken suite would
# otherwise print errors until the unit stage's limits stop it), then gdUnit4 runs with the flags
# tools/ci/run_tests.gd gives it (headless, reports in reports/unit/<process>/, -a <suite>) under a
# time limit, in several processes when there are several suites (one per processor, at most four:
# tools/ci/unit_runner.gd, docs/adr/0006). The exit status is non-zero on any failure, error,
# timeout, lost process, suite that did not report, or empty run.
#
# --quiet is for agents: one line ("unit PASS 12 cases 1.3 s") and, for each failing case, its
# "suite > case" and its failure message with the colour codes stripped (see tests/README.md).
# A script that does not compile is reported as the compile stage's line with its error.
# Usage: ci/unit.sh [--quiet] <res:// path>...
#   UNIT_TIME_LIMIT=300  seconds the gdUnit4 run may take before it is stopped
#   UNIT_PROCESSES=<n>   gdUnit4 processes to split the suites over (default: one per processor,
#                        at most four; 1 runs them in one process, as the stage once did)
set -euo pipefail
cd "$(dirname "$0")/.."
limit="${UNIT_TIME_LIMIT:-300}"
quiet=0
args=(--stage compile --stage unit --fail-fast --unit-time-limit "$limit")
if [ -n "${UNIT_PROCESSES:-}" ]; then args+=(--unit-processes "$UNIT_PROCESSES"); fi
paths=0
for arg in "$@"; do
	case "$arg" in
		--quiet) quiet=1 ;;
		--*) echo "usage: ci/unit.sh [--quiet] <res:// path>..." >&2; exit 2 ;;
		res://*) args+=(--unit "$arg"); paths=$((paths + 1)) ;;
		*) args+=(--unit "res://${arg#./}"); paths=$((paths + 1)) ;;
	esac
done
if [ "$paths" -eq 0 ]; then
	echo "usage: ci/unit.sh [--quiet] <res:// path>..." >&2
	exit 2
fi
# The outer limit leaves room for the import and the compile stage; the unit stage's own limit
# (which also kills the gdUnit4 child, as the outer one cannot) is the one that normally fires.
export TEST_TIME_LIMIT=$((limit + 180))
export WANE_TIMING_TOOL=ci/unit.sh
if [ "$quiet" -eq 0 ]; then
	exec ci/test.sh "${args[@]}"
fi
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
status=0
ci/test.sh --quiet "${args[@]}" > "$out" || status=$?
# On success the compile stage's line, the closing marker and the timing line (ci/test.sh's) are
# noise: the unit line is the answer.
grep -v -e '^compile PASS ' -e '^ALL STAGES PASSED' -e '^timing: ' "$out" || true
exit "$status"
