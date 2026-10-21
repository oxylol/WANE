#!/usr/bin/env bash
# Performance gate, the CPU half (BUILD.md section 13, "Testing and CI" and "Frame budget";
# docs/adr/0020): import the project, then run two benches. tools/bench/stress_bench.gd plays the
# stress room's scripted run (200 enemies, 150 of them walking, a 39-proc chain per Taper hit,
# ADR-0020 Decision 15), reports the same room under the proc storm (every proc event chains;
# measured, never gated), plays the zone 1 loop, times every tick's input plus Simulation.step
# and compares the 99th percentile and the worst tick with content/perf/budget.tres.
# tools/bench/frame_bench.gd plays the same run
# through the game's real scene tree (views, camera, feedback, VFX budget, voices, HUD, the
# lighting pass, LightField held at Pitch) and gates the presentation's script time (sprites 2.0 + VFX 2.0 +
# audio and UI 1.0 = 5.0 ms at the 99th percentile). tools/bench/door_bench.gd times the first
# crossing into each room of zone 1 at Pitch (the door spike: the lighting's occluders were once
# rebuilt on the door tick, 4 to 12 ms) against budget.door_max_us. All of them always run; either failing fails the
# script. The GPU stages (lighting, sprites, post, the 16.0 ms frame) need a GPU runner and are
# not measured here (PROGRESS.md, Blocked 2); a windowed, software-rendered frame run is recorded
# by hand: see docs/adr/0020.
#
# Quiet by default: the gate lines and the closing marker. --verbose adds the slowest ticks and
# what happened on them. The full report goes to reports/perf.txt either way (CI uploads it).
# The run must exit 0 AND print the marker: if the bench does not compile, Godot idles instead of
# exiting, so a time limit and the marker are what keep that from looking green.
# Usage: [PERF_LIB=release] GODOT=/path/to/godot ci/perf.sh [--verbose] [--only stress|zone|frame] [--repeats N]
# --only stress: the stress room (and the storm) alone (the CI job that is red until the enemies'
# steps and the proc path are native too, ADR-0020 Decision 15); --only zone: the 5-minute zone 1 run alone; --only frame: the presentation and the door crossings alone.
# CI runs the stress room apart from the other two so that a red stress gate cannot hide the
# presentation gate or the spike line (ADR-0020 Decision 14).
set -euo pipefail
cd "$(dirname "$0")/.."
. ci/timing.sh
timing_init ci/perf.sh
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
# PERF_LIB=release: time the library an export ships (docs/adr/0022). The editor binary loads the
# debug library, so the release build stands in under the debug file name for the run, as in
# ci/native_release_check.sh; the debug library is put back afterwards, whatever happens.
if [ "${PERF_LIB:-debug}" = "release" ]; then
	case "$(uname -s)" in
		Linux*) lib_pair=("native/bin/libwane.linux.template_release.x86_64.so" "native/bin/libwane.linux.template_debug.x86_64.so") ;;
		MINGW*|MSYS*|CYGWIN*) lib_pair=("native/bin/libwane.windows.template_release.x86_64.dll" "native/bin/libwane.windows.template_debug.x86_64.dll") ;;
		Darwin*) lib_pair=("native/bin/libwane.macos.template_release.framework" "native/bin/libwane.macos.template_debug.framework") ;;
		*) echo "perf: unknown platform $(uname -s)" >&2; exit 2 ;;
	esac
	ci/build_native.sh template_release
	if [ ! -e "${lib_pair[1]}" ]; then ci/build_native.sh template_debug; fi
	lib_backup="$(mktemp -d)"
	cp -R "${lib_pair[1]}" "$lib_backup/"
	restore_lib() {
		rm -rf "${lib_pair[1]}"
		cp -R "$lib_backup/$(basename "${lib_pair[1]}")" "${lib_pair[1]}"
		rm -rf "$lib_backup" "$log"
	}
	trap restore_lib EXIT
	rm -rf "${lib_pair[1]}"
	cp -R "${lib_pair[0]}" "${lib_pair[1]}"
fi
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
	local script="$1" report="$2" marker="$3" code=0 started
	shift 3
	started="$(timing_now)"
	"${run[@]}" "$godot" --headless --path . --script "$script" -- "${args[@]/reports\/perf.txt/$report}" "$@" > "$log" 2>&1 || code=$?
	local elapsed
	elapsed="$(timing_since "$started")"
	grep -v -e '^Godot Engine v' -e '^$' -e '^WARNING: .* ObjectDB' -e '^ERROR: .* resources still in use' -e '^   at: ' "$log" || true
	if [ "$code" -ne 0 ] || ! grep -q "^$marker" "$log"; then
		echo "perf: $script FAILED (exit $code, or no pass marker; 124 or 142 means the ${limit}s limit was hit)" >&2
		status=1
	else
		# The library the bench ran on, and any arguments that change its length (--repeats), are
		# part of what the time means.
		timing_log perf bench "$(basename "$script")" "${PERF_LIB:-debug}${*:+ $*}" "$elapsed"
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
	run_bench tools/bench/door_bench.gd reports/door.txt "DOOR GATE PASSED"
fi
exit "$status"
