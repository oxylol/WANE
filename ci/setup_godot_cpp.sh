#!/usr/bin/env bash
# Clone godot-cpp at the tag and commit pinned in native/.godot-cpp-version into native/godot-cpp
# (git-ignored, never vendored: CLAUDE.md rule 10, ADR-0021). Idempotent: an existing checkout at
# the pinned commit is left alone, one at another commit is moved to it. Prints the folder on the
# last line. Usage: ci/setup_godot_cpp.sh
#
# The first checkout on a machine is fetched from GitHub into the shared native cache
# (ci/native_cache.sh, ADR-0021 "Shared build cache"); every other worktree clones that local copy,
# in a fraction of a second and without the network. WANE_NATIVE_CACHE=off fetches every time.
set -euo pipefail
cd "$(dirname "$0")/.."
. ci/native_cache.sh
read -r tag commit < native/.godot-cpp-version
dir="${GODOT_CPP_DIR:-native/godot-cpp}"
url="https://github.com/godotengine/godot-cpp.git"
cache="$(native_cache_dir)"
if [ ! -d "$dir/.git" ]; then
	rm -rf "$dir"
	if [ -n "$cache" ]; then
		mirror="$cache/godot-cpp-${commit:0:12}.git"
		if [ ! -d "$mirror" ]; then
			mkdir -p "$cache"
			tmp="$mirror.$$.tmp"
			ok=0
			for attempt in 1 2 3 4; do
				if git -c advice.detachedHead=false clone --quiet --bare --depth 1 --branch "$tag" "$url" "$tmp"; then ok=1; break; fi
				rm -rf "$tmp"
				sleep 2
			done
			[ "$ok" = 1 ] || { echo "could not clone godot-cpp $tag" >&2; exit 1; }
			# Another worktree may have got there first; the commit is the folder's name, so the
			# two are the same.
			mv "$tmp" "$mirror" 2> /dev/null || rm -rf "$tmp"
		fi
		git -c advice.detachedHead=false clone --quiet --no-checkout "$mirror" "$dir"
		git -C "$dir" checkout --quiet --detach "$commit" 2> /dev/null || true
	else
		ok=0
		for attempt in 1 2 3 4; do
			if git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$url" "$dir"; then ok=1; break; fi
			rm -rf "$dir"
			sleep 2
		done
		[ "$ok" = 1 ] || { echo "could not clone godot-cpp $tag" >&2; exit 1; }
	fi
fi
actual="$(git -C "$dir" rev-parse HEAD)"
if [ "$actual" != "$commit" ]; then
	git -C "$dir" fetch --quiet --depth 1 origin "refs/tags/$tag:refs/tags/$tag"
	git -C "$dir" checkout --quiet --detach "$commit"
	actual="$(git -C "$dir" rev-parse HEAD)"
fi
# A moved tag would change the binary interface under us: the commit is the pin, the tag its name.
[ "$actual" = "$commit" ] || { echo "godot-cpp is at $actual, pinned $commit ($tag)" >&2; exit 1; }
# Godot must not scan godot-cpp's own test project (scripts, a .gdextension) as part of ours.
: > "$dir/.gdignore"
echo "$dir"
