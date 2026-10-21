#!/usr/bin/env bash
# Renders a room or a fixture's frame lit by the lighting pass, under a virtual display
# (tools/lighting/render_room.gd has the options). The engine's own noise about the native library
# is filtered out; the exit status is the script's.
# Usage: tools/lighting/render.sh <out prefix> (--room <id> | --fixture <path>) [--tick N] [--dark ...] [--debug]
set -euo pipefail
cd "$(dirname "$0")/../.."
godot="${GODOT:-godot}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
# The script's own exit status is the tool's: 1 for a room that does not load (nothing is
# written), 2 for a usage mistake. The filter below only hides the engine's noise.
status=0
xvfb-run -a -s "-screen 0 1920x1080x24" "$godot" --path . --rendering-driver opengl3 \
	--audio-driver Dummy --resolution 1920x1080 --script tools/lighting/render_room.gd -- "$@" \
	> "$log" 2>&1 || status=$?
grep -v -i "dynamic library\|GDExtension\|extension\|^     at:\|^$\|V-Sync\|OpenGL API\|^Godot Engine" "$log" || true
exit "$status"
