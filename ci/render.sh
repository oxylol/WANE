#!/usr/bin/env bash
# Render tests (need a display, so they are not part of the headless ci/test.sh): what the ink and
# gouache shaders draw, under xvfb on the GL Compatibility renderer with llvmpipe, the same as
# every review render (docs/adr/0023 Decision 6). Prints one line and exits 0 when every check
# passes; on failure the failing checks are listed and it exits 1.
#
#   ci/render.sh                  the checks (tests/screenshot/run_ink_render_tests.gd)
#   ci/render.sh --review <dir> [tick]
#                                 the probe's three-size review: sil64, dusk1x, pitch1x, dusk4x,
#                                 pitch4x and channels4x PNGs in <dir> (tests/screenshot/render_ink.gd)
# Usage: GODOT=/path/to/godot ci/render.sh
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT:-godot}"
limit="${RENDER_TIME_LIMIT:-600}"
if ! command -v xvfb-run > /dev/null 2>&1; then
	echo "render: xvfb-run is not installed (apt-get install xvfb)" >&2
	exit 2
fi
"$godot" --headless --path . --import > /dev/null 2>&1
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
run() {
	timeout "$limit" xvfb-run -a -s "-screen 0 1920x1080x24" "$godot" --path . \
		--rendering-driver opengl3 --audio-driver Dummy --resolution 1920x1080 "$@"
}
if [ "${1:-}" = "--review" ]; then
	run --script tests/screenshot/render_ink.gd -- "${2:?usage: ci/render.sh --review <dir> [tick]}" "${3:-0}" --channels \
		2>&1 | grep -E '^(rendered to|usage|SCRIPT ERROR)'
	exit 0
fi
status=0
run --script tests/screenshot/run_ink_render_tests.gd > "$log" 2>&1 || status=$?
if grep -E '^(ink render:|  FAIL )' "$log"; then :; else
	tail -n 20 "$log" >&2
fi
if [ "$status" -ne 0 ] || ! grep -q '^ink render: .* 0 failed' "$log"; then
	echo "render: FAILED (exit $status)" >&2
	exit 1
fi
