#!/usr/bin/env bash
# Headless test gate: import the project, then run tools/ci/run_tests.gd (script compile check,
# content schemas, replay fixtures, gdUnit4 unit suites). Extra arguments go to run_tests.gd,
# e.g. `ci/test.sh --stage compile --stage fixtures`.
# Usage: GODOT=/path/to/godot ci/test.sh [--stage <name>]...
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT:-godot}"
if ! "$godot" --headless --path . --import > .godot-import.log 2>&1; then
	cat .godot-import.log >&2
	rm -f .godot-import.log
	echo "test: project import failed" >&2
	exit 1
fi
rm -f .godot-import.log
"$godot" --headless --path . --script tools/ci/run_tests.gd -- "$@"
