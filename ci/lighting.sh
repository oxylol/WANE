#!/usr/bin/env bash
# The lighting pass's GPU check (docs/adr/0023; BUILD.md section 13, Testing and CI): the baked
# room distance field and the shadow buffer against their CPU twin, the lit surface shader against
# its numbers, and every shader of the pass compiling, on GL Compatibility under a virtual display
# (llvmpipe). The headless unit suite (tests/unit/game/test_lighting.gd) holds everything that
# needs no renderer; this holds the rest. Any shader or script error in the output fails it.
# Usage: GODOT=/path/to/godot ci/lighting.sh
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT:-godot}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if ! "$godot" --headless --path . --import > "$log" 2>&1; then
	cat "$log" >&2
	echo "lighting: import failed" >&2
	exit 1
fi
status=0
timeout "${LIGHTING_TIME_LIMIT:-300}" xvfb-run -a -s "-screen 0 1920x1080x24" "$godot" --path . \
	--rendering-driver opengl3 --audio-driver Dummy --resolution 1920x1080 \
	--script tools/lighting/gpu_check.gd > "$log" 2>&1 || status=$?
# The native library is optional (docs/adr/0021): its absence is not a lighting problem.
noise='dynamic library|GDExtension|wane.gdextension|V-Sync|set_use_vsync|OpenGL API|^Godot Engine|^$'
grep -v -E "$noise" "$log" || true
if grep -E "SHADER ERROR|SCRIPT ERROR|Parse Error|Compile Error" "$log" > /dev/null; then
	echo "lighting: shader or script errors in the run" >&2
	exit 1
fi
if [ "$status" -ne 0 ] || ! grep -q "^LIGHTING GPU CHECK PASSED" "$log"; then
	echo "lighting: FAILED (exit $status)" >&2
	exit 1
fi
# The three-size review (docs/adr/0023 Decision 5) on the committed test prop: the pictures must be
# there, drawn (not one flat colour) and the silhouette white on black. The 4x masters are a
# review product of the art build, so the detail is not asserted here.
out="$(mktemp -d)"
trap 'rm -f "$log"; rm -rf "$out"' EXIT
timeout "${LIGHTING_TIME_LIMIT:-300}" xvfb-run -a -s "-screen 0 1920x1080x24" "$godot" --path . \
	--rendering-driver opengl3 --audio-driver Dummy --resolution 1920x1080 \
	--script tools/artbuild/review.gd -- candle_stump --root res://tests/art/build --out "$out" \
	> "$log" 2>&1 || status=$?
if grep -E "SHADER ERROR|SCRIPT ERROR|Parse Error|Compile Error" "$log" > /dev/null; then
	grep -E "SHADER ERROR|SCRIPT ERROR|Parse Error|Compile Error" "$log" >&2
	echo "lighting: shader or script errors in the review" >&2
	exit 1
fi
python3 - "$out" <<'PY'
import sys
from pathlib import Path
from PIL import Image

out = Path(sys.argv[1])
for name in ("sil64", "dusk1x", "pitch1x", "idle", "flicker"):
    path = out / f"{name}.png"
    if not path.exists():
        sys.exit(f"lighting: the review did not write {name}.png")
    colours = len(Image.open(path).convert("RGB").getcolors(1 << 24) or [])
    if colours < 16:
        sys.exit(f"lighting: {name}.png is nearly one flat colour ({colours} colours)")
sil = Image.open(out / "sil64.png").convert("L")
white = sum(1 for v in sil.tobytes() if v > 200)
if not 200 < white < sil.width * sil.height // 2:
    sys.exit(f"lighting: sil64.png has {white} white pixels, not a figure on black")
print("review: sil64, dusk1x, pitch1x and the contact sheets drawn")
PY
if [ "$status" -ne 0 ]; then
	echo "lighting: review FAILED (exit $status)" >&2
	exit 1
fi
