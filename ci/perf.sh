#!/usr/bin/env bash
# Performance gate, the CPU half (BUILD.md section 13, "Testing and CI" and "Frame budget";
# docs/adr/0020): import the project, then run tools/bench/stress_bench.gd, which plays the stress
# room's scripted run (200 enemies, 150 of them walking, the 39-proc Votive set) and the zone 1
# loop, times every tick's input plus Simulation.step and compares the 99th percentile and the
# worst tick with content/perf/budget.tres. The GPU stages (lighting, sprites, post) need a GPU
# runner and are not measured here (PROGRESS.md, Blocked 2).
#
# Quiet by default: the gate lines and the closing marker. --verbose adds the slowest ticks and
# what happened on them. The full report goes to reports/perf.txt either way (CI uploads it).
# The run must exit 0 AND print the marker: if the bench does not compile, Godot idles instead of
# exiting, so a time limit and the marker are what keep that from looking green.
# Usage: GODOT=/path/to/godot ci/perf.sh [--verbose] [bench options: --repeats N --only stress|zone]
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT:-godot}"
limit="${PERF_TIME_LIMIT:-900}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
args=(--quiet --report reports/perf.txt)
extra=()
for arg in "$@"; do
	if [ "$arg" = "--verbose" ]; then args=(--report reports/perf.txt); else extra+=("$arg"); fi
done
mkdir -p reports
if ! "$godot" --headless --path . --import > "$log" 2>&1; then
	tail -n 30 "$log" >&2
	echo "perf: project import failed" >&2
	exit 1
fi
if command -v timeout > /dev/null 2>&1; then
	run=(timeout "$limit")
elif command -v gtimeout > /dev/null 2>&1; then
	run=(gtimeout "$limit")
else
	run=(perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$limit")
fi
status=0
"${run[@]}" "$godot" --headless --path . --script tools/bench/stress_bench.gd -- "${args[@]}" ${extra[@]+"${extra[@]}"} > "$log" 2>&1 || status=$?
grep -v -e '^Godot Engine v' -e '^$' -e '^WARNING: .* ObjectDB' -e '^ERROR: .* resources still in use' -e '^   at: ' "$log" || true
if [ "$status" -ne 0 ] || ! grep -q "^PERF GATE PASSED" "$log"; then
	echo "perf: FAILED (exit $status, or no pass marker; 124 or 142 means the ${limit}s limit was hit)" >&2
	exit 1
fi
