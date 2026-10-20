#!/usr/bin/env bash
# Build the release native library (the one an export ships, ADR-0021) and run the replay
# fixtures on it against the golden hashes, with WANE_NATIVE=on (so a library that does not
# load, or loads stale, fails instead of falling back). The editor binary loads the "debug"
# entries of native/wane.gdextension, so for the run those entries point at the release library;
# the file is put back afterwards, whatever happens. Pointing the entries (rather than copying
# the release library over the debug one) keeps the library as the build made it: a macOS
# framework names its binary after the folder, so a renamed copy would not load. No debug
# library is needed, and none is built.
# Usage: GODOT=/path/to/godot ci/native_release_check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ci/build_native.sh template_release
case "$(uname -s)" in
	Linux*) platform=linux; release="native/bin/libwane.linux.template_release.x86_64.so" ;;
	MINGW*|MSYS*|CYGWIN*) platform=windows; release="native/bin/libwane.windows.template_release.x86_64.dll" ;;
	Darwin*) platform=macos; release="native/bin/libwane.macos.template_release.framework" ;;
	*) echo "native_release_check: unknown platform $(uname -s)" >&2; exit 2 ;;
esac
if [ ! -e "$release" ]; then
	echo "native_release_check: $release was not built" >&2
	exit 1
fi
ext="native/wane.gdextension"
backup="$(mktemp)"
cp "$ext" "$backup"
restore() {
	cp "$backup" "$ext"
	rm -f "$backup"
}
trap restore EXIT
# Only the lines that name a debug library (linux.debug.x86_64 = ..., macos.debug = ...).
sed '/^[a-z0-9_]*\.debug[. =]/ s/template_debug/template_release/g' "$backup" > "$ext"
if grep -q "^[a-z0-9_]*\.debug.*template_debug" "$ext"; then
	echo "native_release_check: a debug entry of $ext still names the debug library" >&2
	exit 1
fi
if ! grep -q "^$platform\.debug.*template_release" "$ext"; then
	echo "native_release_check: the $platform debug entry of $ext does not name the release library" >&2
	exit 1
fi
WANE_NATIVE=on ci/test.sh --quiet --stage compile --stage fixtures
echo "native_release_check: the release library passes the fixtures"
