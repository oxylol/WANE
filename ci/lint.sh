#!/usr/bin/env bash
# Static analysis gate (BUILD.md section 13): gdlint and gdformat with zero findings over every
# first-party GDScript file in the repository (everything except vendored gdUnit4, Godot's cache,
# agent worktrees under .claude/ and the fetched native/godot-cpp), plus project rules that no
# linter knows about:
#   - no @warning_ignore and no gdlint/gdformat suppression comments (ADR-0002)
#   - no untyped Array or Dictionary declarations, parameters or return types (CLAUDE.md:
#     "typed arrays")
#   - native/src obeys the determinism rules of ADR-0021 Decision 4: no float or double, no
#     unordered containers, no time or randomness
set -euo pipefail
cd "$(dirname "$0")/.."
files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(
	find . -name '*.gd' -not -path './.godot/*' -not -path './addons/gdUnit4/*' \
		-not -path './.git/*' -not -path './.claude/*' -not -path './native/godot-cpp/*' -print0 | sort -z
)
if [ "${#files[@]}" -eq 0 ]; then echo "lint: no GDScript files"; exit 0; fi
status=0
gdlint "${files[@]}" || status=1
gdformat --check "${files[@]}" || status=1
if grep -n '@warning_ignore' "${files[@]}"; then
	echo "lint: @warning_ignore is forbidden (ADR-0002)" >&2; status=1
fi
if grep -nE '#\s*(gdlint|gdformat)\s*:' "${files[@]}"; then
	echo "lint: linter suppression comments are forbidden (ADR-0002)" >&2; status=1
fi
if grep -nP '(:|->)\s*(Array|Dictionary)\b(?!\s*\[)' "${files[@]}" | grep -vP '^\S+:\d+:\s*##'; then
	echo "lint: untyped Array/Dictionary; use Array[T] or Dictionary[K, V] (CLAUDE.md)" >&2; status=1
fi
if [ -d native/src ]; then
	if grep -nE '\b(float|double|long double|std::unordered_\w+|std::rand|rand|srand|time|clock|random_device|mt19937|thread|atomic)\b' native/src/*.cpp native/src/*.h \
		| grep -vE '^[^:]+:[0-9]+:\s*(//|\*)'; then
		echo "lint: native/src breaks the determinism rules (ADR-0021 Decision 4)" >&2; status=1
	fi
fi
[ "$status" -eq 0 ] && echo "lint: ${#files[@]} files clean"
exit "$status"
