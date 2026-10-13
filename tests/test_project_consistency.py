#!/usr/bin/env python3
"""Offline project consistency checks; these do not substitute for Godot runtime QA."""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)

def main() -> int:
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    scene = (ROOT / "scenes/main.tscn").read_text(encoding="utf-8")
    require('run/main_scene="res://scenes/main.tscn"' in project, "main scene is not configured")
    require('config/features=PackedStringArray("4.7", "Mobile")' in project, "feature target tag mismatch")
    require('renderer/rendering_method="mobile"' in project, "Mobile renderer isn't configured")
    require('path="res://scripts/main.gd"' in scene, "startup scene doesn't reference main.gd")
    require((ROOT / "scripts/main.gd").is_file(), "main.gd missing")

    registry = json.loads((ROOT / "data/asset_registry.json").read_text(encoding="utf-8"))
    models = registry.get("models", [])
    require(registry.get("model_count") == 1245, f"expected 1245 model registry entries, got {len(models)}")
    require(len(models) == len({m.get("id") for m in models}), "duplicate model IDs")
    by_id = {m["id"]: m for m in models}
    require(all(m.get("inventory_visible") and m.get("searchable") for m in models), "registry entry is not discoverable")
    hotbar = ["grass_block", "dirt", "stone", "oak_planks", "oak_log", "glass", "bricks", "sand", "glowstone"]
    absent_hotbar = [item for item in hotbar if item not in by_id]
    require(not absent_hotbar, f"default hotbar IDs absent from registry: {absent_hotbar}")

    missing_models: list[str] = []
    missing_maps: list[str] = []
    for item in models:
        path_fields = ["model_path", "base_color_path", "normal_path", "orm_path", "height_path"]
        for field in path_fields:
            value = str(item.get(field, "") or "")
            if value:
                local_path = value.removeprefix("res://")
                if not (ROOT / local_path).is_file():
                    (missing_models if field == "model_path" else missing_maps).append(f"{item.get('id')}:{field}:{local_path}")
        webp = item.get("webp_maps", {}) or {}
        for family in ("albedo", "normal", "roughness", "displacement"):
            value = str(webp.get(family, "") or "")
            if value and not (ROOT / value.removeprefix("res://")).is_file():
                missing_maps.append(f"{item.get('id')}:webp_{family}:{value}")
    require(not missing_models, f"missing model paths: {missing_models[:3]}")
    require(not missing_maps, f"missing referenced maps: {missing_maps[:3]}")

    families = {
        "base_color": {m["base_color_path"] for m in models if m.get("base_color_path")},
        "normal": {m["normal_path"] for m in models if m.get("normal_path")},
        "orm": {m["orm_path"] for m in models if m.get("orm_path")},
        "height": {m["height_path"] for m in models if m.get("height_path")},
    }
    webp_families = {family: {m.get("webp_maps", {}).get(family) for m in models if m.get("webp_maps", {}).get(family)} for family in ("albedo", "normal", "roughness", "displacement")}
    require(all(len(paths) == 90 for paths in families.values()), f"core map family count mismatch: { {k: len(v) for k,v in families.items()} }")
    require(all(len(paths) == 90 for paths in webp_families.values()), f"WebP map family count mismatch: { {k: len(v) for k,v in webp_families.items()} }")

    inventory_records = json.loads((ROOT / "reports/asset_inventory.json").read_text(encoding="utf-8")).get("records", [])
    file_records = [r for r in inventory_records if r.get("runtime_source_path")]
    require(len(file_records) == 1983, f"expected 1,983 actual source files, got {len(file_records)}")
    coverage_path = ROOT / "reports/inventory_coverage.csv"
    with coverage_path.open(newline="", encoding="utf-8") as stream:
        coverage = list(csv.DictReader(stream))
    require(len(coverage) == len(file_records), f"coverage row count ({len(coverage)}) != actual source-file count ({len(file_records)}); directory-only ZIP entries are deliberately excluded")
    coverage_by_path = {row.get("source_path", ""): row for row in coverage}
    require(len(coverage_by_path) == len(coverage), "duplicate source_path in inventory coverage")
    source_asset_roots = [path for path in (ROOT / "assets/source_library").iterdir() if path.is_dir()]
    require(len(source_asset_roots) == 1, f"expected one assembled source root, found {len(source_asset_roots)}")
    source_asset_root = source_asset_roots[0]
    for model in models:
        source_rel = str(model["model_path"]).removeprefix("res://")
        model_file = ROOT / source_rel
        relative_source = model_file.relative_to(source_asset_root).as_posix()
        row = coverage_by_path.get(relative_source)
        require(row is not None, f"model missing coverage row: {relative_source}")
        require(row.get("inventory_visible", "").lower() == "true", f"model not visible in coverage: {relative_source}")
        require(row.get("searchable", "").lower() == "true", f"model not searchable in coverage: {relative_source}")

    status = (ROOT / "reports/BUILD_STATUS.md").read_text(encoding="utf-8")
    require("unverified in Godot runtime" in status, "build status should report missing runtime validation")
    require("No APK" in status, "build status should not imply an APK exists")
    print(json.dumps({
        "result": "PASS",
        "target_project": "Godot 4.7 feature line / Mobile renderer (engine launch still untested)",
        "registered_models": len(models),
        "inventory_coverage_rows": len(coverage),
        "source_file_records": len(file_records),
        "core_map_families": {k: len(v) for k, v in families.items()},
        "webp_map_families": {k: len(v) for k, v in webp_families.items()},
        "missing_model_paths": len(missing_models),
        "missing_map_paths": len(missing_maps),
        "default_hotbar_ids_checked": len(hotbar),
        "godot_runtime_tested": False,
    }, indent=2))
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)