#!/usr/bin/env bash
# Build the native extension (native/, ADR-0021) into native/bin/. Fetches the pinned godot-cpp
# first (ci/setup_godot_cpp.sh), then runs SCons (pinned in tools/requirements.txt). Quiet: one
# line on success, the last 40 lines of the build log and a non-zero exit on failure.
# Usage: ci/build_native.sh [template_debug|template_release|all]
#   template_debug (default) is what the editor binary and the headless tests load.
#   NATIVE_PLATFORM=linux|windows|macos  override the detected platform
#   NATIVE_ARCH=<arch>                   override the arch (macOS defaults to universal)
#   NATIVE_JOBS=<n>                      parallel jobs (default: all cores)
#   WANE_NATIVE_CACHE=<dir>|off          the cache shared by every worktree (ci/native_cache.sh,
#                                        docs/adr/0021): objects another worktree built are copied
#                                        from it, not compiled. Default: <main checkout>/.git/
#                                        wane-native-cache; off on CI, which has its own cache.
set -euo pipefail
cd "$(dirname "$0")/.."
. ci/timing.sh
. ci/native_cache.sh
timing_init ci/build_native.sh
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
# godot-cpp's SConstruct turns SCONS_CACHE into SCons's CacheDir (and the MD5 decider that goes
# with it). The folder is named for the compiler and platform so that objects made by another
# compiler are never offered.
cache="$(native_cache_dir)"
if [ -n "$cache" ]; then
	export SCONS_CACHE="$cache/scons-$(native_cache_key "$platform" "${NATIVE_ARCH:-}")"
	mkdir -p "$SCONS_CACHE"
fi
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
start=$SECONDS
compiled=0
fetched=0
for target in "${targets[@]}"; do
	target_started="$(timing_now)"
	if ! (cd native && "${scons[@]}" -Q -j"$jobs" "platform=$platform" "target=$target" ${arch_args[@]+"${arch_args[@]}"}) > "$log" 2>&1; then
		tail -n 40 "$log" >&2
		echo "build_native: $target failed" >&2
		exit 1
	fi
	# A build that compiled, one that took everything from the cache, one with nothing to do:
	# their times are not comparable, so they are three series in the timing log.
	built_now="$(grep -c "Compiling " "$log" || true)"
	fetched_now="$(grep -c "^Retrieved " "$log" || true)"
	compiled=$((compiled + built_now))
	fetched=$((fetched + fetched_now))
	how="up-to-date"
	if [ "$built_now" -gt 0 ]; then how="built"; elif [ "$fetched_now" -gt 0 ]; then how="cache"; fi
	timing_log native build "$target" "$platform $how" "$(timing_since "$target_started")"
done
note=""
if [ "$((compiled + fetched))" -gt 0 ]; then note=" ($fetched objects from the cache, $compiled compiled)"; fi
echo "native: built ${targets[*]} for $platform in $((SECONDS - start)) s$note -> native/bin/"
