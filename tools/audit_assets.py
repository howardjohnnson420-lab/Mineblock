#!/usr/bin/env python3
"""Verify the immutable supplied asset library against the generated inventory.

Run from any directory: python tools/audit_assets.py
This script validates file provenance and registry paths; it does not replace Godot import/render testing.
"""
from __future__ import annotations

import csv
import hashlib
import json
import struct
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY_PATH = ROOT / "reports" / "asset_inventory.json"
REGISTRY_PATH = ROOT / "data" / "asset_registry.json"
OUT_JSON = ROOT / "reports" / "asset_validation_run.json"
OUT_MD = ROOT / "reports" / "asset_validation_run.md"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def is_valid_glb_header(path: Path) -> tuple[bool, str]:
    try:
        with path.open("rb") as stream:
            header = stream.read(12)
        if len(header) != 12:
            return False, "GLB header shorter than 12 bytes"
        magic, version, declared_length = struct.unpack("<4sII", header)
        if magic != b"glTF":
            return False, "GLB magic is not glTF"
        if version != 2:
            return False, f"GLB version {version}, expected glTF 2"
        if declared_length != path.stat().st_size:
            return False, f"GLB declared length {declared_length} != file size {path.stat().st_size}"
        return True, "header_ok"
    except OSError as exc:
        return False, str(exc)


def main() -> int:
    inventory = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
    registry = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    records = inventory.get("records", [])
    file_records = [r for r in records if r.get("runtime_source_path")]
    missing: list[dict] = []
    size_mismatches: list[dict] = []
    hash_mismatches: list[dict] = []
    verified_count = 0
    bytes_hashed = 0
    ext_counter: Counter[str] = Counter()
    glb_errors: list[dict] = []

    for index, record in enumerate(file_records, 1):
        runtime_path = str(record["runtime_source_path"])
        relative = runtime_path.removeprefix("res://")
        path = ROOT / relative
        ext_counter[path.suffix.lower() or "[no extension]"] += 1
        if not path.is_file():
            missing.append({"path": relative, "archive": record.get("archive"), "archive_path": record.get("archive_path")})
            continue
        actual_size = path.stat().st_size
        expected_size = int(record.get("size_bytes", actual_size))
        if actual_size != expected_size:
            size_mismatches.append({"path": relative, "expected": expected_size, "actual": actual_size})
        actual_hash = sha256_file(path)
        bytes_hashed += actual_size
        expected_hash = str(record.get("sha256", ""))
        if expected_hash and actual_hash != expected_hash:
            hash_mismatches.append({"path": relative, "expected": expected_hash, "actual": actual_hash})
        else:
            verified_count += 1
        if path.suffix.lower() == ".glb":
            valid, reason = is_valid_glb_header(path)
            if not valid:
                glb_errors.append({"path": relative, "reason": reason})
        if index % 250 == 0:
            print(f"Checked {index}/{len(file_records)} files…", flush=True)

    models = registry.get("models", [])
    absent_models: list[dict] = []
    missing_model_textures: list[dict] = []
    classification_counter: Counter[str] = Counter()
    category_counter: Counter[str] = Counter()
    for model in models:
        classification_counter[str(model.get("classification", "unknown"))] += 1
        category_counter[str(model.get("category", "unknown"))] += 1
        model_path = str(model.get("model_path", "")).removeprefix("res://")
        if not model_path or not (ROOT / model_path).is_file():
            absent_models.append({"id": model.get("id"), "path": model_path})
        paths = [model.get("base_color_path"), model.get("normal_path"), model.get("orm_path"), model.get("height_path")]
        paths.extend(str(v) for v in (model.get("webp_maps", {}) or {}).values())
        for value in paths:
            path_string = str(value or "").removeprefix("res://")
            if path_string and not (ROOT / path_string).is_file():
                missing_model_textures.append({"id": model.get("id"), "path": path_string})

    result = {
        "validation_scope": "archive inventory paths, sizes, SHA-256 hashes, GLB headers and registry references",
        "runtime_scope_note": "This is not a Godot import, shader compile, scene launch, render, touch, physics or Android export test.",
        "source_inventory_records": len(records),
        "source_file_records_with_paths": len(file_records),
        "verified_size_and_hash_files": verified_count,
        "bytes_hashed": bytes_hashed,
        "missing_files": missing,
        "size_mismatches": size_mismatches,
        "sha256_mismatches": hash_mismatches,
        "glb_header_errors": glb_errors,
        "registered_models": len(models),
        "registered_model_paths_missing": absent_models,
        "missing_referenced_texture_paths": missing_model_textures,
        "extension_counts": dict(sorted(ext_counter.items())),
        "model_classifications": dict(sorted(classification_counter.items())),
        "inventory_categories": dict(sorted(category_counter.items())),
        "godot_runtime_tested": False,
    }
    OUT_JSON.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    lines = [
        "# Asset Validation Run",
        "",
        "Generated by `tools/audit_assets.py`. This run validates on-disk provenance and resource references, not Godot runtime rendering.",
        "",
        "## Results",
        "",
        f"- Source inventory file records: **{len(records):,}**",
        f"- Actual source file records with paths: **{len(file_records):,}**",
        f"- Files verified against recorded size/SHA-256: **{verified_count:,}**",
        f"- Total bytes hashed: **{bytes_hashed:,}**",
        f"- Missing source files: **{len(missing)}**",
        f"- Size mismatches: **{len(size_mismatches)}**",
        f"- SHA-256 mismatches: **{len(hash_mismatches)}**",
        f"- Invalid GLB headers: **{len(glb_errors)}**",
        f"- Registered models: **{len(models):,}**",
        f"- Missing model paths: **{len(absent_models)}**",
        f"- Missing model-referenced texture paths: **{len(missing_model_textures)}**",
        "",
        "## Inventory categories",
        "",
    ]
    lines.extend(f"- {name}: {count:,}" for name, count in sorted(category_counter.items()))
    lines.extend(["", "## Runtime validation boundary", "", "Godot 4.7.2 import/launch, shader compilation, in-world materials, input, collision, save/reload, performance and APK export are not verified by this Python audit.", ""])
    if missing or size_mismatches or hash_mismatches or glb_errors or absent_models or missing_model_textures:
        lines.extend(["## Issues", ""])
        for title, rows in [("Missing files", missing), ("Size mismatches", size_mismatches), ("SHA-256 mismatches", hash_mismatches), ("Invalid GLB headers", glb_errors), ("Missing model paths", absent_models), ("Missing textures", missing_model_textures)]:
            if rows:
                lines.append(f"### {title}")
                lines.extend(f"- `{row}`" for row in rows[:100])
                lines.append("")
    OUT_MD.write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({k: result[k] for k in ["source_file_records_with_paths", "verified_size_and_hash_files", "missing_files", "size_mismatches", "sha256_mismatches", "glb_header_errors", "registered_models", "registered_model_paths_missing", "missing_referenced_texture_paths"]}, indent=2))
    return 0 if not (missing or size_mismatches or hash_mismatches or glb_errors or absent_models or missing_model_textures) else 1


if __name__ == "__main__":
    sys.exit(main())