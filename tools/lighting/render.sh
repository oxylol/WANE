#!/usr/bin/env bash
# Renders a room or a fixture's frame lit by the lighting pass, under a virtual display
# (tools/lighting/render_room.gd has the options). The engine's own noise about the native library
# is filtered out.
# Usage: tools/lighting/render.sh <out prefix> (--room <id> | --fixture <path>) [--tick N] [--dark ...] [--debug]
set -euo pipefail
cd "$(dirname "$0")/../.."
godot="${GODOT:-godot}"
xvfb-run -a -s "-screen 0 1920x1080x24" "$godot" --path . --rendering-driver opengl3 \
	--audio-driver Dummy --resolution 1920x1080 --script tools/lighting/render_room.gd -- "$@" 2>&1 \
	| grep -v -i "dynamic library\|GDExtension\|extension\|^     at:\|^$\|V-Sync\|OpenGL API\|^Godot Engine" || true
