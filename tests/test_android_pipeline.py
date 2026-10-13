#!/usr/bin/env python3
"""Static guardrails for the reproducible Android CI pipeline."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

def require(cond: bool, message: str) -> None:
    if not cond:
        errors.append(message)

preset_path = ROOT / "export_presets.cfg"
workflow_path = ROOT / ".github/workflows/android-apk.yml"
require(preset_path.is_file(), "export_presets.cfg exists")
require(workflow_path.is_file(), ".github/workflows/android-apk.yml exists")
if preset_path.exists():
    preset = preset_path.read_text(encoding="utf-8")
    for expected in [
        'name="Android"',
        'platform="Android"',
        'package/unique_name="com.mineblock.creativeflatworld"',
        'architectures/arm64-v8a=true',
        'export_path="exports/Mineblock-debug.apk"',
    ]:
        require(expected in preset, f"Android export preset has {expected}")
if workflow_path.exists():
    workflow = workflow_path.read_text(encoding="utf-8")
    for expected in [
        "Godot_v4.7.2-stable_linux.x86_64.zip",
        "Godot_v4.7.2-stable_export_templates.tpz",
        "tools/audit_assets.py",
        "tests/test_project_consistency.py",
        "tests/test_mechanics_contracts.py",
        "tests/runtime_smoke.gd",
        "--export-debug \"Android\" exports/Mineblock-debug.apk",
        "actions/upload-artifact@v4",
    ]:
        require(expected in workflow, f"workflow includes {expected}")
    require("sha256sum --check" in workflow, "Godot downloads have SHA-256 verification")
    require("if: failure()" in workflow, "workflow collects failure diagnostics")

if errors:
    print("FAIL: Android pipeline static contract checks")
    for error in errors:
        print(f" - {error}")
    sys.exit(1)
print("PASS: Android pipeline static contract checks")
print("Godot/editor/import/export execution remains unverified until the workflow runs in GitHub Actions.")