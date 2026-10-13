#!/usr/bin/env bash
# Local Godot 4.7.2 validation and Android debug export.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-godot}"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "ERROR: Godot 4.7.2 is not found. Set GODOT_BIN=/path/to/Godot_v4.7.2-stable." >&2
  exit 2
fi
VERSION="$("$GODOT_BIN" --version | tr -d '\r')"
if [[ "$VERSION" != 4.7.2.stable* ]]; then
  echo "ERROR: expected Godot 4.7.2 stable, got $VERSION" >&2
  exit 2
fi

python3 tools/audit_assets.py
python3 tests/test_project_consistency.py
python3 tests/test_mechanics_contracts.py
python3 tests/test_android_pipeline.py
"$GODOT_BIN" --headless --editor --path . --import --quit
"$GODOT_BIN" --headless --path . --script res://tests/runtime_smoke.gd
mkdir -p exports
"$GODOT_BIN" --headless --path . --export-debug "Android" exports/Mineblock-debug.apk
test -s exports/Mineblock-debug.apk
sha256sum exports/Mineblock-debug.apk | tee exports/Mineblock-debug.apk.sha256
echo "SUCCESS: exports/Mineblock-debug.apk"