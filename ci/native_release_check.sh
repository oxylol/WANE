#!/usr/bin/env bash
# Build the release native library (the one an export ships, ADR-0021) and run the replay
# fixtures on it against the golden hashes, with WANE_NATIVE=on (so a library that does not
# load, or loads stale, fails instead of falling back). The editor binary loads the debug
# library, so the release build stands in under the debug file name for the run; the debug
# library is put back afterwards, whatever happens.
# Usage: GODOT=/path/to/godot ci/native_release_check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ci/build_native.sh template_release
case "$(uname -s)" in
	Linux*) pair=("native/bin/libwane.linux.template_release.x86_64.so" "native/bin/libwane.linux.template_debug.x86_64.so") ;;
	MINGW*|MSYS*|CYGWIN*) pair=("native/bin/libwane.windows.template_release.x86_64.dll" "native/bin/libwane.windows.template_debug.x86_64.dll") ;;
	Darwin*) pair=("native/bin/libwane.macos.template_release.framework" "native/bin/libwane.macos.template_debug.framework") ;;
	*) echo "native_release_check: unknown platform $(uname -s)" >&2; exit 2 ;;
esac
release="${pair[0]}"
debug="${pair[1]}"
if [ ! -e "$release" ]; then
	echo "native_release_check: $release was not built" >&2
	exit 1
fi
if [ ! -e "$debug" ]; then
	ci/build_native.sh template_debug
fi
backup="$(mktemp -d)"
restore() {
	rm -rf "$debug"
	cp -R "$backup/$(basename "$debug")" "$debug"
	rm -rf "$backup"
}
cp -R "$debug" "$backup/"
trap restore EXIT
rm -rf "$debug"
cp -R "$release" "$debug"
WANE_NATIVE=on ci/test.sh --quiet --stage compile --stage fixtures
echo "native_release_check: the release library passes the fixtures"
