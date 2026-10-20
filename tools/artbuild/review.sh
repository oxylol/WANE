#!/usr/bin/env bash
# The three-size review of a built asset (docs/adr/0023 Decision 5): builds the asset with its 4x
# masters (gitignored review products), then renders the 64 px silhouette, 1x lit at Dusk and at
# Pitch, the 4x detail and a contact sheet per action under a virtual display (tools/artbuild/
# review.gd has the options). The engine's own noise about the native library is filtered out.
# Usage: tools/artbuild/review.sh <asset> [--root res://dir] [--out dir] [--carries-ember] [action...]
set -euo pipefail
cd "$(dirname "$0")/../.."
godot="${GODOT:-godot}"
asset="$1"
python3 tools/artbuild/build.py --masters "$asset"
"$godot" --headless --path . --import > /dev/null 2>&1
xvfb-run -a -s "-screen 0 1920x1080x24" "$godot" --path . --rendering-driver opengl3 \
	--audio-driver Dummy --resolution 1920x1080 --script tools/artbuild/review.gd -- "$@" 2>&1 \
	| grep -v -i "dynamic library\|GDExtension\|extension\|^     at:\|^$\|V-Sync\|OpenGL API\|^Godot Engine" || true
