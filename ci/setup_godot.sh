#!/usr/bin/env bash
# Fetch the Godot version pinned in .godot-version, verify it against ci/godot.sha512, and
# install it to $GODOT_HOME (default ~/.local/godot). Prints the binary path on the last line.
# Usage: ci/setup_godot.sh [linux|windows|macos]
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(tr -d '[:space:]' < .godot-version)"
platform="${1:-linux}"
case "$platform" in
	linux) archive="Godot_v${version}_linux.x86_64.zip"; binary="Godot_v${version}_linux.x86_64" ;;
	windows) archive="Godot_v${version}_win64.exe.zip"; binary="Godot_v${version}_win64_console.exe" ;;
	macos) archive="Godot_v${version}_macos.universal.zip"; binary="Godot.app/Contents/MacOS/Godot" ;;
	*) echo "unknown platform: $platform" >&2; exit 2 ;;
esac
home="${GODOT_HOME:-$HOME/.local/godot}/${version}"
mkdir -p "$home"
if [ ! -e "$home/$binary" ]; then
	urls=(
		"https://github.com/godotengine/godot/releases/download/${version}/${archive}"
		"https://sourceforge.net/projects/godot-engine.mirror/files/${version}/${archive}/download"
	)
	ok=0
	for url in "${urls[@]}"; do
		if curl -fsSL --retry 4 --retry-delay 2 -o "$home/$archive" "$url"; then ok=1; break; fi
	done
	[ "$ok" = 1 ] || { echo "could not download $archive" >&2; exit 1; }
	expected="$(grep " ${archive}\$" ci/godot.sha512 | awk '{print $1}')"
	[ -n "$expected" ] || { echo "no pinned checksum for $archive in ci/godot.sha512" >&2; exit 1; }
	actual="$( (sha512sum "$home/$archive" 2>/dev/null || shasum -a 512 "$home/$archive") | awk '{print $1}')"
	if [ "$expected" != "$actual" ]; then
		echo "checksum mismatch for $archive" >&2; rm -f "$home/$archive"; exit 1
	fi
	py="$(command -v python3 || command -v python)"
	"$py" -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$home/$archive" "$home"
	rm -f "$home/$archive"
	chmod +x "$home/$binary" 2>/dev/null || true
fi
echo "$home/$binary"
