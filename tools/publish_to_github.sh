#!/usr/bin/env bash
# Safely publish the fully assembled project to the currently empty Mineblock repo.
# Run from any location; this script changes to the Godot project root first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="https://github.com/howardjohnnson420-lab/Mineblock.git"
cd "$ROOT"

if [[ ! -f project.godot || ! -f assets/source_library/Minecraft_Realistic_Voxel_Assets_AI_Handoff/SHA256SUMS.txt ]]; then
  echo "ERROR: incomplete project. Extract all eight source asset bundles into this project first." >&2
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required. Install Git and retry." >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: Python 3 is required to validate the source assets before publishing." >&2
  exit 2
fi

# Run the full asset audit and contract tests before creating a commit.
python3 tools/audit_assets.py
python3 tests/test_project_consistency.py
python3 tests/test_mechanics_contracts.py
python3 tests/test_android_pipeline.py

if [[ ! -d .git ]]; then
  git init
fi

if git remote get-url origin >/dev/null 2>&1; then
  current_origin="$(git remote get-url origin)"
  if [[ "$current_origin" != "$REPO_URL" && "$current_origin" != "https://github.com/howardjohnnson420-lab/Mineblock" && "$current_origin" != "git@github.com:howardjohnnson420-lab/Mineblock.git" ]]; then
    echo "ERROR: origin already points to $current_origin; refusing to overwrite it." >&2
    exit 3
  fi
else
  git remote add origin "$REPO_URL"
fi

# Keep a normal Git push; every source file is below GitHub's per-file limit.
# Do not include editor caches, generated APKs or local signing keys.
git branch -M main
git add -A
if git diff --cached --quiet; then
  echo "No new staged changes; nothing to commit."
  exit 0
fi

git commit -m "Add Godot 4.7.2 creative flatworld and Android CI"

echo "Pushing to $REPO_URL (Git will request your normal GitHub authentication if needed)."
# No force push: this must stop if the repository has changed or is not empty.
git push -u origin main