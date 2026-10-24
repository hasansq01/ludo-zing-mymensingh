#!/bin/sh
# Runs the Godot rule tests headless (macOS / Linux). Exit code 1 when any check fails, or when Godot reports a
# script error (a parse error or a runtime error inside a test can otherwise leave the suite looking green).
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/../godot" || exit 1
"$GODOT" --headless --import >/dev/null 2>&1 || true   # registers the class_name scripts on a fresh checkout
log="$(mktemp)"
"$GODOT" --headless -s res://tests/run_tests.gd 2>&1 | tee "$log"
status=$?
# the runner's own exit code is lost in the pipe: read the result from the log
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$log"; then
	echo "godot-test: script errors above (failing the run)"
	status=1
fi
if ! grep -qE "TOTAL: [0-9]+ passed, 0 failed" "$log"; then
	status=1
fi
rm -f "$log"
exit $status
