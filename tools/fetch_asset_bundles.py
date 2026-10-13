#!/usr/bin/env python3
"""Download and safely merge the eight source asset bundles into the Godot project tree.

Populate tools/asset_bundle_urls.json with direct downloadable HTTPS links (Dropbox shared
links can be converted to direct download links) before running this in a clean CI runner.
If the source tree is already present, this script leaves it untouched.
"""
from __future__ import annotations
import json
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
URLS_PATH = ROOT / "tools/asset_bundle_urls.json"
CACHE = Path("/tmp/mineblock-asset-bundles")
BUNDLES = {
    "01_models_and_documentation": "Minecraft_Creative_Flatworld_Assets_01_Models_and_Documentation.zip",
    "02_base_color": "Minecraft_Creative_Flatworld_Assets_02_BaseColor.zip",
    "03A_normal_part1": "Minecraft_Creative_Flatworld_Assets_03A_Normal_Part1.zip",
    "03B_normal_part2": "Minecraft_Creative_Flatworld_Assets_03B_Normal_Part2.zip",
    "03C_normal_part3": "Minecraft_Creative_Flatworld_Assets_03C_Normal_Part3.zip",
    "04_orm": "Minecraft_Creative_Flatworld_Assets_04_ORM.zip",
    "05_height": "Minecraft_Creative_Flatworld_Assets_05_Height.zip",
    "06_optional_webp": "Minecraft_Creative_Flatworld_Assets_06_Optional_WebP.zip",
}
EXPECTED_ROOT = ROOT / "assets/source_library/Minecraft_Realistic_Voxel_Assets_AI_Handoff"

def inside_root(path: Path) -> bool:
    try:
        path.resolve().relative_to(ROOT.resolve())
        return True
    except ValueError:
        return False

def download(url: str, dest: Path) -> None:
    if not url.startswith("https://"):
        raise ValueError(f"URL must use HTTPS: {url[:80]}")
    request = urllib.request.Request(url, headers={"User-Agent": "Mineblock-AssetBootstrap/1.0"})
    with urllib.request.urlopen(request, timeout=90) as response, dest.open("wb") as stream:
        shutil.copyfileobj(response, stream, length=1024 * 1024)
    if not zipfile.is_zipfile(dest):
        dest.unlink(missing_ok=True)
        raise ValueError(f"Downloaded content is not a ZIP file: {dest.name}")

def safe_extract(zf: zipfile.ZipFile) -> None:
    # One supplied normal-map bundle uses the asset-root-relative path while the
    # other bundles include "assets/source_library/" already. Normalize both
    # layouts to the same project-relative destination.
    infos = zf.infolist()
    bad_member = zf.testzip()
    if bad_member:
        raise ValueError(f"Corrupt ZIP member: {bad_member}")
    for info in infos:
        if info.is_dir():
            continue
        name = info.filename.replace("\\", "/")
        prefix = "Minecraft_Realistic_Voxel_Assets_AI_Handoff/"
        if name.startswith(prefix):
            name = "assets/source_library/" + name
        target = ROOT / name
        if not inside_root(target):
            raise ValueError(f"Unsafe ZIP member path: {info.filename}")
    for info in infos:
        if info.is_dir():
            continue
        name = info.filename.replace("\\", "/")
        prefix = "Minecraft_Realistic_Voxel_Assets_AI_Handoff/"
        if name.startswith(prefix):
            name = "assets/source_library/" + name
        target = ROOT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(info, "r") as src, target.open("wb") as dst:
            shutil.copyfileobj(src, dst, length=1024 * 1024)

def main() -> int:
    if EXPECTED_ROOT.is_dir() and any(EXPECTED_ROOT.rglob("*.glb")):
        print("Source asset library already exists; skipping bundle download.")
        return 0
    if not URLS_PATH.is_file():
        print("ERROR: tools/asset_bundle_urls.json is missing.", file=sys.stderr)
        return 2
    urls = json.loads(URLS_PATH.read_text(encoding="utf-8"))
    absent = [key for key in BUNDLES if not str(urls.get(key, "")).strip()]
    if absent:
        print("ERROR: no downloadable asset bundle URL for: " + ", ".join(absent), file=sys.stderr)
        print("Connect the storage containing the supplied ZIPs, upload all eight bundles, and populate tools/asset_bundle_urls.json.", file=sys.stderr)
        return 3
    CACHE.mkdir(parents=True, exist_ok=True)
    for key, filename in BUNDLES.items():
        dest = CACHE / filename
        print(f"Downloading {key}…", flush=True)
        try:
            download(str(urls[key]).strip(), dest)
            with zipfile.ZipFile(dest) as archive:
                safe_extract(archive)
            print(f"Extracted {filename}", flush=True)
        except Exception as exc:
            print(f"ERROR: bundle {key} failed: {exc}", file=sys.stderr)
            return 4
    if not EXPECTED_ROOT.is_dir():
        print("ERROR: asset bundles extracted but expected source root is still absent.", file=sys.stderr)
        return 5
    print("PASS: all eight source bundles extracted; next step verifies every file hash.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
