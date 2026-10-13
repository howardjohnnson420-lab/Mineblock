#!/usr/bin/env python3
"""Restore gzip+base64 metadata committed in small text form for GitHub API transfer."""
from __future__ import annotations
import base64, gzip, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESTORES = {
    ROOT / "data/asset_registry.json.gz.b64": ROOT / "data/asset_registry.json",
    ROOT / "reports/asset_inventory.json.gz.b64": ROOT / "reports/asset_inventory.json",
    ROOT / "reports/inventory_coverage.csv.gz.b64": ROOT / "reports/inventory_coverage.csv",
}

def main() -> int:
    for src, dst in RESTORES.items():
        if not src.is_file():
            print(f"ERROR: required compressed metadata file is missing: {src.relative_to(ROOT)}", file=sys.stderr)
            return 2
        try:
            compressed = base64.b64decode(src.read_text(encoding="ascii"), validate=False)
            data = gzip.decompress(compressed)
        except Exception as exc:
            print(f"ERROR: cannot restore {src.relative_to(ROOT)}: {exc}", file=sys.stderr)
            return 2
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(data)
        print(f"Restored {dst.relative_to(ROOT)} ({len(data)} bytes)")
    registry = json.loads((ROOT / "data/asset_registry.json").read_text(encoding="utf-8"))
    inventory = json.loads((ROOT / "reports/asset_inventory.json").read_text(encoding="utf-8"))
    if registry.get("model_count") != 1245 or len(registry.get("models", [])) != 1245:
        print("ERROR: registry must contain exactly 1,245 models", file=sys.stderr)
        return 3
    records = [r for r in inventory.get("records", []) if r.get("runtime_source_path")]
    if len(records) != 1983:
        print(f"ERROR: expected 1,983 source file records; got {len(records)}", file=sys.stderr)
        return 3
    print(f"PASS: restored {len(registry['models'])} models and {len(records)} file records")
    return 0

if __name__ == "__main__":
    sys.exit(main())
