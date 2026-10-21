#!/usr/bin/env bash
# Sourced by ci/setup_godot_cpp.sh and ci/build_native.sh (never run): where the native build's
# shared cache lives, and what keys it (docs/adr/0021, "Shared build cache").
#
# Every git worktree of this repository builds godot-cpp and the extension from cold, 40 to 100
# seconds each, and agents make a worktree per task. The cache is one folder outside the worktrees:
#   godot-cpp-<commit>.git   a bare clone of godot-cpp at the pinned commit (no network after the
#                            first worktree has fetched it)
#   scons-<key>/             SCons's CacheDir (godot-cpp's SConstruct reads SCONS_CACHE): the
#                            objects, by the hash of the source, the command line and the headers
# SCons's own signature makes a hit correct for the same sources and flags; what it does not see is
# the compiler, so <key> hashes the platform, the compiler's version line, the SCons version and
# the godot-cpp commit: a compiler upgrade starts a fresh folder instead of reusing objects it
# did not make.
#
#   WANE_NATIVE_CACHE=<dir>  use this folder (CI can point it at a folder it caches)
#   WANE_NATIVE_CACHE=off    no cache: build as before, fetch godot-cpp from GitHub
#   unset                    <the main checkout's .git>/wane-native-cache, or ~/.cache/wane/native
#                            without git; off on CI (CI=true), whose jobs keep their own cache in
#                            .github/actions/native-build
#   WANE_NATIVE_CACHE_DAYS=60  cache files untouched this long are deleted after a build

# native_cache_dir: the cache folder (absolute), or nothing when the cache is off.
native_cache_dir() {
	local dir="${WANE_NATIVE_CACHE:-}" common
	case "$dir" in
		off | none | 0 | false) return 0 ;;
		'') ;;
		*) printf '%s\n' "$dir"; return 0 ;;
	esac
	if [ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then return 0; fi
	if common="$(git rev-parse --git-common-dir 2> /dev/null)" && [ -d "$common" ]; then
		printf '%s/wane-native-cache\n' "$(cd "$common" && pwd)"
	else
		printf '%s/wane/native\n' "${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}"
	fi
}

# native_cache_hash: SHA-256 of stdin, hex (sha256sum, shasum or openssl, whichever exists).
native_cache_hash() {
	if command -v sha256sum > /dev/null 2>&1; then sha256sum | cut -d ' ' -f 1
	elif command -v shasum > /dev/null 2>&1; then shasum -a 256 | cut -d ' ' -f 1
	else openssl dgst -sha256 | sed 's/^.* //'
	fi
}

# native_cache_key <platform> <arch>: 16 hex digits naming what the cached objects were made with.
# The compiler is the one SCons will find: $CXX, else the first of g++, clang++, c++, cl.
native_cache_key() {
	local cxx compiler="" commit scons_pin
	for cxx in "${CXX:-}" g++ clang++ c++ cl; do
		if [ -n "$cxx" ] && command -v "$cxx" > /dev/null 2>&1; then
			compiler="$cxx: $("$cxx" --version 2>&1 | head -n 1)"
			[ "$cxx" = cl ] && compiler="cl: $(cl 2>&1 | head -n 1)"
			break
		fi
	done
	read -r _ commit < native/.godot-cpp-version
	scons_pin="$(grep -i '^SCons==' tools/requirements.txt 2> /dev/null || true)"
	printf '%s\n' "$1" "${2:-}" "$(uname -sm 2> /dev/null)" "$compiler" "$scons_pin" "$commit" \
		| native_cache_hash | cut -c 1-16
}

# native_cache_prune <dir>: deletes cache files not touched for $WANE_NATIVE_CACHE_DAYS days, at most
# once a day (a stamp file in <dir> says when). A cache hit refreshes a file's time, so what goes is
# what no build has used.
native_cache_prune() {
	local dir="$1" days="${WANE_NATIVE_CACHE_DAYS:-60}"
	[ -d "$dir" ] || return 0
	if [ -f "$dir/.pruned" ] && [ -z "$(find "$dir/.pruned" -mtime +0 2> /dev/null)" ]; then return 0; fi
	find "$dir" -type f -mtime "+$days" -not -name .pruned -delete 2> /dev/null || true
	find "$dir" -mindepth 1 -type d -empty -delete 2> /dev/null || true
	: > "$dir/.pruned" 2> /dev/null || true
}
