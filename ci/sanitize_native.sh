#!/usr/bin/env bash
# Build native/src/sweep.cpp with UBSan and ASan (no recovery) together with the random harness
# native/tests/sweep_sanitize.cpp and run it (docs/adr/0022). Fails on any sanitiser report, or if
# the harness's checksum is not EXPECTED: the sweep core is deterministic integer code, so the
# checksum moves only when its behaviour does (then run the differential tests, bump
# NATIVE_VERSION, and update EXPECTED). Needs g++ or clang++; one line on success.
set -euo pipefail
cd "$(dirname "$0")/.."
EXPECTED=66817297
cxx="${CXX:-$(command -v g++ || command -v clang++ || true)}"
if [ -z "$cxx" ]; then
	echo "sanitize_native: no g++ or clang++" >&2
	exit 1
fi
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
"$cxx" -std=c++17 -O1 -g -Wall -Wextra -Werror -fsanitize=undefined,address -fno-sanitize-recover=all \
	-Inative/src native/tests/sweep_sanitize.cpp native/src/sweep.cpp -o "$out/harness"
got="$("$out/harness")"
if [ "$got" != "$EXPECTED" ]; then
	echo "sanitize_native: checksum $got, expected $EXPECTED" >&2
	exit 1
fi
# The query cells (docs/adr/0020 Decision 15): a self-checking harness against a brute force.
"$cxx" -std=c++17 -O1 -g -Wall -Wextra -Werror -fsanitize=undefined,address -fno-sanitize-recover=all \
	-Inative/src native/tests/cells_sanitize.cpp native/src/cells.cpp -o "$out/cells_harness"
cells="$("$out/cells_harness")"
if [ "$cells" != "OK" ]; then
	echo "sanitize_native: the cells harness said: $cells" >&2
	exit 1
fi
echo "sanitize_native: clean ($cxx, checksum $got, cells OK)"
