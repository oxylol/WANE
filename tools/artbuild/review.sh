#!/usr/bin/env bash
# The three-size review of a built asset (docs/adr/0023 Decision 5): builds the asset with its 4x
# masters (gitignored review products), then renders the 64 px silhouette, 1x lit at Dusk and at
# Pitch, the 4x detail and a contact sheet per action under a virtual display (tools/artbuild/
# review.gd has the options). The engine's own noise about the native library is filtered out.
# Exits with the review's own status (2 for bad arguments, 1 for no build of the asset or a script
# or shader error), so a review that drew nothing is never reported as done.
# Usage: tools/artbuild/review.sh <asset> [--root res://dir] [--out dir] [--carries-ember] [action...]
set -euo pipefail
cd "$(dirname "$0")/../.."
godot="${GODOT:-godot}"
if [ "$#" -lt 1 ]; then
	echo "usage: tools/artbuild/review.sh <asset> [--root res://dir] [--out dir] [--carries-ember] [action...]" >&2
	exit 2
fi
asset="$1"
python3 tools/artbuild/build.py --masters "$asset" lit_test_room
"$godot" --headless --path . --import > /dev/null 2>&1
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
status=0
xvfb-run -a -s "-screen 0 1920x1080x24" "$godot" --path . --rendering-driver opengl3 \
	--audio-driver Dummy --resolution 1920x1080 --script tools/artbuild/review.gd -- "$@" > "$log" 2>&1 \
	|| status=$?
grep -v -i "dynamic library\|GDExtension\|extension\|^     at:\|^$\|V-Sync\|OpenGL API\|^Godot Engine" "$log" || true
if [ "$status" -eq 0 ] && grep -qE "SHADER ERROR|SCRIPT ERROR|Parse Error|Compile Error" "$log"; then
	echo "review: shader or script errors in the run" >&2
	status=1
fi
exit "$status"
