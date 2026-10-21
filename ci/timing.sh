#!/usr/bin/env bash
# Sourced by ci/test.sh, ci/unit.sh, ci/perf.sh and ci/build_native.sh (never run): the timing log's
# writer for the shell (BUILD.md section 13, "Testing and CI"; docs/adr/0023). One line of JSON
# per measured item is appended to reports/timings.jsonl, in the fields tools/ci/timing_log.gd
# (the Godot side) and tools/ci/timing_report.py (the reader) use:
#   ts run commit tool stage kind item variant seconds processors load
# The caller has done `cd` to the repository root. Logging never fails a script: every problem
# (no git, an unwritable folder) is swallowed.
#   WANE_TIMING_LOG=<path>  write there instead; WANE_TIMING_LOG=off writes nothing
#   WANE_TIMING_TOOL=<name> the script that started the run (ci/unit.sh sets it for ci/test.sh)
#   WANE_TIMING_RUN=<id>    the run id (exported by timing_init so that the Godot side shares it)

# timing_init <default tool name>: fixes the invocation's time stamp, run id, commit, processor
# count and load average (the 1-minute average at this moment: the run's own work is not in it).
timing_init() {
	TIMING_TOOL="${WANE_TIMING_TOOL:-$1}"
	TIMING_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2> /dev/null || echo unknown)"
	TIMING_RUN="${WANE_TIMING_RUN:-$(date -u +%Y%m%dT%H%M%S 2> /dev/null || echo unknown)-$$}"
	TIMING_COMMIT="$(git rev-parse --short HEAD 2> /dev/null || echo unknown)"
	TIMING_PROCESSORS="$( (nproc || getconf _NPROCESSORS_ONLN || sysctl -n hw.ncpu) 2> /dev/null | head -n 1)"
	TIMING_PROCESSORS="${TIMING_PROCESSORS:-1}"
	TIMING_LOAD=null
	local load=""
	if [ -r /proc/loadavg ]; then
		load="$(cut -d ' ' -f 1 /proc/loadavg 2> /dev/null || true)"
	elif command -v sysctl > /dev/null 2>&1; then
		load="$(sysctl -n vm.loadavg 2> /dev/null | tr -d '{}' | awk '{print $1}' || true)"
	fi
	case "$load" in
		'' | *[!0-9.]*) ;;
		*) TIMING_LOAD="$load" ;;
	esac
	export WANE_TIMING_TOOL="$TIMING_TOOL" WANE_TIMING_RUN="$TIMING_RUN"
}

# timing_now: a clock reading to give timing_since. Nanoseconds where `date` has %N, otherwise
# whole seconds scaled to the same unit (macOS), which suits a build or a bench.
timing_now() {
	local t
	t="$(date +%s%N 2> /dev/null || true)"
	case "$t" in
		'' | *N) echo $((SECONDS * 1000000000)) ;;
		*) echo "$t" ;;
	esac
}

# timing_since <reading from timing_now>: the seconds since then, as 12.345.
timing_since() {
	local d=$(($(timing_now) - $1))
	printf '%d.%03d' $((d / 1000000000)) $((d % 1000000000 / 1000000))
}

# timing_log <stage> <kind> <item> <variant> <seconds>
timing_log() {
	local file="${WANE_TIMING_LOG:-reports/timings.jsonl}"
	if [ "$file" = "off" ] || [ -z "${TIMING_RUN:-}" ]; then return 0; fi
	local stage="$1" kind="$2" item="$3" variant="$4" seconds="$5"
	item="${item//\\/\\\\}"
	item="${item//\"/\\\"}"
	variant="${variant//\\/\\\\}"
	variant="${variant//\"/\\\"}"
	mkdir -p "$(dirname "$file")" 2> /dev/null || return 0
	if [ -f "$file" ] && [ "$(wc -c < "$file" 2> /dev/null || echo 0)" -gt 8388608 ]; then
		mv -f "$file" "$file.1" 2> /dev/null || true
	fi
	printf '{"ts":"%s","run":"%s","commit":"%s","tool":"%s","stage":"%s","kind":"%s","item":"%s","variant":"%s","seconds":%s,"processors":%s,"load":%s}\n' \
		"$TIMING_TS" "$TIMING_RUN" "$TIMING_COMMIT" "$TIMING_TOOL" "$stage" "$kind" "$item" "$variant" \
		"$seconds" "$TIMING_PROCESSORS" "$TIMING_LOAD" >> "$file" 2> /dev/null || true
	return 0
}
