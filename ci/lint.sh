#!/usr/bin/env bash
# Static analysis gate (BUILD.md section 13): gdlint and gdformat with zero findings over every
# first-party GDScript file in the repository (everything except vendored gdUnit4 and Godot's
# cache), plus project rules that no linter knows about:
#   - no @warning_ignore and no gdlint/gdformat suppression comments (ADR-0002)
#   - no untyped Array or Dictionary declarations, parameters or return types (CLAUDE.md:
#     "typed arrays")
set -euo pipefail
cd "$(dirname "$0")/.."
files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(
	find . -name '*.gd' -not -path './.godot/*' -not -path './addons/gdUnit4/*' \
		-not -path './.git/*' -print0 | sort -z
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
[ "$status" -eq 0 ] && echo "lint: ${#files[@]} files clean"
exit "$status"
