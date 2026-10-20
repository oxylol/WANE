#!/usr/bin/env bash
# Performance gate, the CPU half (BUILD.md section 13, "Testing and CI" and "Frame budget";
# docs/adr/0020): import the project, then run two benches. tools/bench/stress_bench.gd plays the
# stress room's scripted run (200 enemies, 150 of them walking, the 39-proc Votive set) and the
# zone 1 loop, times every tick's input plus Simulation.step and compares the 99th percentile and
# the worst tick with content/perf/budget.tres. tools/bench/frame_bench.gd plays the same run
# through the game's real scene tree (views, camera, feedback, VFX budget, voices, HUD, the
# Pitch lighting stand-in) and gates the presentation's script time (sprites 2.0 + VFX 2.0 +
# audio and UI 1.0 = 5.0 ms at the 99th percentile). Both always run; either failing fails the
# script. The GPU stages (lighting, sprites, post, the 16.0 ms frame) need a GPU runner and are
# not measured here (PROGRESS.md, Blocked 2); a windowed, software-rendered frame run is recorded
# by hand: see docs/adr/0020.
#
# Quiet by default: the gate lines and the closing marker. --verbose adds the slowest ticks and
# what happened on them. The full report goes to reports/perf.txt either way (CI uploads it).
# The run must exit 0 AND print the marker: if the bench does not compile, Godot idles instead of
# exiting, so a time limit and the marker are what keep that from looking green.
# Usage: GODOT=/path/to/godot ci/perf.sh [--verbose] [--only stress|zone|frame] [--repeats N]
# --only stress: the stress room alone (the CI job that is red until the C++ decision, ADR-0020
# Decision 8); --only zone: the 5-minute zone 1 run alone; --only frame: the presentation alone.
# CI runs the stress room apart from the other two so that a red stress gate cannot hide the
# presentation gate or the spike line (ADR-0020 Decision 14).
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
# One bench: runs $1 (a script) with its report $2 and marker $3; sets status to 1 on a failure.
status=0
run_bench() {
	local script="$1" report="$2" marker="$3" code=0
	shift 3
	"${run[@]}" "$godot" --headless --path . --script "$script" -- "${args[@]/reports\/perf.txt/$report}" "$@" > "$log" 2>&1 || code=$?
	grep -v -e '^Godot Engine v' -e '^$' -e '^WARNING: .* ObjectDB' -e '^ERROR: .* resources still in use' -e '^   at: ' "$log" || true
	if [ "$code" -ne 0 ] || ! grep -q "^$marker" "$log"; then
		echo "perf: $script FAILED (exit $code, or no pass marker; 124 or 142 means the ${limit}s limit was hit)" >&2
		status=1
	fi
}
only=""
for i in "${!extra[@]}"; do
	if [ "${extra[$i]}" = "--only" ]; then only="${extra[$((i + 1))]-}"; fi
done
case "$only" in
	"" | stress | zone | frame) ;;
	*) echo "perf: --only takes stress, zone or frame, not '$only'" >&2; exit 2 ;;
esac
if [ "$only" = "frame" ]; then
	extra=()
else
	run_bench tools/bench/stress_bench.gd reports/perf.txt "PERF GATE PASSED" ${extra[@]+"${extra[@]}"}
fi
if [ "$only" = "" ] || [ "$only" = "frame" ]; then
	run_bench tools/bench/frame_bench.gd reports/frame.txt "FRAME GATE PASSED"
fi
exit "$status"
