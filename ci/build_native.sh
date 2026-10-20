#!/usr/bin/env bash
# Build the native extension (native/, ADR-0021) into native/bin/. Fetches the pinned godot-cpp
# first (ci/setup_godot_cpp.sh), then runs SCons (pinned in tools/requirements.txt). Quiet: one
# line on success, the last 40 lines of the build log and a non-zero exit on failure.
# Usage: ci/build_native.sh [template_debug|template_release|all]
#   template_debug (default) is what the editor binary and the headless tests load.
#   NATIVE_PLATFORM=linux|windows|macos  override the detected platform
#   NATIVE_ARCH=<arch>                   override the arch (macOS defaults to universal)
#   NATIVE_JOBS=<n>                      parallel jobs (default: all cores)
set -euo pipefail
cd "$(dirname "$0")/.."
which_target="${1:-template_debug}"
case "$which_target" in
	template_debug|template_release) targets=("$which_target") ;;
	all) targets=(template_debug template_release) ;;
	*) echo "usage: ci/build_native.sh [template_debug|template_release|all]" >&2; exit 2 ;;
esac
if command -v scons > /dev/null 2>&1; then
	scons=(scons)
else
	py="$(command -v python3 || command -v python)"
	if ! "$py" -c "import SCons" > /dev/null 2>&1; then
		echo "build_native: SCons not found; pip install \"\$(grep -i '^SCons==' tools/requirements.txt)\"" >&2
		exit 1
	fi
	scons=("$py" -m SCons)
fi
platform="${NATIVE_PLATFORM:-}"
if [ -z "$platform" ]; then
	case "$(uname -s)" in
		Linux*) platform=linux ;;
		Darwin*) platform=macos ;;
		MINGW*|MSYS*|CYGWIN*) platform=windows ;;
		*) echo "build_native: unknown platform $(uname -s)" >&2; exit 2 ;;
	esac
fi
arch_args=()
if [ -n "${NATIVE_ARCH:-}" ]; then
	arch_args=("arch=$NATIVE_ARCH")
elif [ "$platform" = macos ]; then
	arch_args=("arch=universal")
fi
jobs="${NATIVE_JOBS:-$( (nproc || getconf _NPROCESSORS_ONLN || echo 2) 2> /dev/null)}"
ci/setup_godot_cpp.sh > /dev/null
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
start=$SECONDS
for target in "${targets[@]}"; do
	if ! (cd native && "${scons[@]}" -Q -j"$jobs" "platform=$platform" "target=$target" "${arch_args[@]}") > "$log" 2>&1; then
		tail -n 40 "$log" >&2
		echo "build_native: $target failed" >&2
		exit 1
	fi
done
echo "native: built ${targets[*]} for $platform in $((SECONDS - start)) s -> native/bin/"
