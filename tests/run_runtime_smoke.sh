#!/usr/bin/env sh
set -eu
GODOT_BIN="${GODOT_BIN:-godot}"
"$GODOT_BIN" --headless --editor --path "$(dirname "$0")/.." --quit --import
"$GODOT_BIN" --headless --path "$(dirname "$0")/.." --script res://tests/runtime_smoke.gd