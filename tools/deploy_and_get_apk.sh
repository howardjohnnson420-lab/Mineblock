#!/usr/bin/env bash
# One-command route: validate complete local project, authenticate, push to Mineblock,
# wait for GitHub Actions to build, and download the resulting Android debug APK.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="howardjohnnson420-lab/Mineblock"
REPO_URL="https://github.com/${REPO}.git"
WORKFLOW_FILE="android-apk.yml"
ARTIFACT_NAME="Mineblock-Godot-4.7.2-Android-debug-APK"
POLL_LIMIT="${MINEBLOCK_CI_POLL_LIMIT:-180}" # 180 x 10 seconds = 30 minutes
cd "$ROOT"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
Usage: bash tools/deploy_and_get_apk.sh [--preflight-only]

Default: audit assets, run static tests, authenticate to GitHub, push safely to
howardjohnnson420-lab/Mineblock, wait for its CI build, and download the APK.

--preflight-only: audit and run tests locally without needing gh or network.
HELP
  exit 0
fi
PREFLIGHT_ONLY=0
if [[ "${1:-}" == "--preflight-only" ]]; then PREFLIGHT_ONLY=1; fi

say() { printf '\n\033[1;36m[Mineblock pipeline]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[Mineblock pipeline: ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

say "Project root: $ROOT"
[[ -f project.godot ]] || die "project.godot not found. Run this inside the assembled project."
[[ -f .github/workflows/android-apk.yml ]] || die "Android Actions workflow missing. Use the latest ProjectCore package."
[[ -f assets/source_library/Minecraft_Realistic_Voxel_Assets_AI_Handoff/SHA256SUMS.txt ]] || die "Source asset library is incomplete. Extract all eight asset bundles first."

for tool in git python3; do
  command -v "$tool" >/dev/null 2>&1 || die "Required tool '$tool' is missing. Install Git and Python 3, then retry."
done
if [[ "$PREFLIGHT_ONLY" -ne 1 ]]; then
  command -v gh >/dev/null 2>&1 || die "GitHub CLI 'gh' is missing. Install it, then retry; see tools/PIPELINE_QUICKSTART.md."
fi

say "Auditing all supplied source assets and running static checks."
python3 tools/audit_assets.py
python3 tests/test_project_consistency.py
python3 tests/test_mechanics_contracts.py
python3 tests/test_android_pipeline.py

# GitHub rejects individual files >=100 MiB through ordinary Git; catch this before staging.
if python3 - "$ROOT" <<'PY'
import os, sys
from pathlib import Path
root = Path(sys.argv[1])
limit = 100 * 1024 * 1024
large = []
for base, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if d not in {".git", ".godot", "exports", "__pycache__"}]
    for name in files:
        p = Path(base) / name
        try:
            if p.stat().st_size >= limit:
                large.append((p.stat().st_size, str(p.relative_to(root))))
        except OSError:
            pass
if large:
    for size, path in large:
        print(f"{size} bytes: {path}", file=sys.stderr)
    raise SystemExit(1)
PY
then :; else die "At least one source file exceeds GitHub's 100 MiB per-file limit. Use Git LFS or split/rework that file first."; fi

if [[ "$PREFLIGHT_ONLY" -eq 1 ]]; then
  say "Preflight passed. No GitHub connection was attempted."
  exit 0
fi

say "Checking GitHub CLI authentication. Complete the browser/device authorization if prompted."
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  gh auth login --hostname github.com --git-protocol https --web --scopes workflow
fi
# GitHub requires the workflow OAuth scope when pushing .github/workflows files.
# gh asks for approval if the current token does not already have it.
gh auth refresh --hostname github.com --scopes workflow
# Enable GitHub CLI as the HTTPS credential helper for git push.
gh auth setup-git --hostname github.com

# Ensure the authenticated identity is the expected repository owner or collaborator.
LOGIN="$(gh api user --jq .login)"
[[ -n "$LOGIN" ]] || die "Could not read the authenticated GitHub identity."
REPO_LOGIN="$(gh api "repos/${REPO}" --jq .full_name 2>/dev/null)" || die "Could not read $REPO. Confirm the signed-in GitHub account has repository access."
[[ "$REPO_LOGIN" == "$REPO" ]] || die "Unexpected repository response: $REPO_LOGIN"

# Set local commit identity only if the current checkout has no identity configured.
if ! git config user.name >/dev/null 2>&1; then git config user.name "$LOGIN"; fi
if ! git config user.email >/dev/null 2>&1; then
  USER_ID="$(gh api user --jq .id)"
  git config user.email "${USER_ID}+${LOGIN}@users.noreply.github.com"
fi

if [[ ! -d .git ]]; then
  say "Initializing Git in the project tree."
  git init
fi

if git remote get-url origin >/dev/null 2>&1; then
  ORIGIN="$(git remote get-url origin)"
  case "$ORIGIN" in
    "$REPO_URL"|"https://github.com/${REPO}"|"git@github.com:${REPO}.git") ;;
    *) die "origin is already set to '$ORIGIN'; refusing to overwrite it." ;;
  esac
else
  git remote add origin "$REPO_URL"
fi

git branch -M main
say "Staging project source and all extracted assets (this repository is large)."
git add -A
if ! git diff --cached --quiet; then
  git commit -m "Build Mineblock Godot 4.7.2 creative flatworld"
else
  say "No new staged changes; will still attempt to publish the current main commit."
fi

LOCAL_SHA="$(git rev-parse HEAD 2>/dev/null)" || die "No local commit exists. There is nothing to publish."

# Never force-push. If main already exists remotely, allow only a fast-forward update.
REMOTE_SHA="$(git ls-remote origin refs/heads/main | awk 'NR==1 {print $1}')"
if [[ -n "$REMOTE_SHA" ]]; then
  if ! git merge-base --is-ancestor "$REMOTE_SHA" "$LOCAL_SHA"; then
    die "Remote main ($REMOTE_SHA) has commits not contained in local main ($LOCAL_SHA). No force push was attempted. Fetch/merge the remote before retrying."
  fi
fi

say "Pushing $LOCAL_SHA to $REPO_URL."
git push -u origin main

say "Waiting for GitHub Actions run for commit $LOCAL_SHA (up to 30 minutes)."
RUN_ID=""
for ((i=1; i<=POLL_LIMIT; i++)); do
  RUN_ID="$(gh run list --repo "$REPO" --workflow "$WORKFLOW_FILE" --branch main --limit 15 --json databaseId,headSha --jq ".[] | select(.headSha == \"${LOCAL_SHA}\") | .databaseId" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$RUN_ID" ]]; then break; fi
  sleep 10
done
[[ -n "$RUN_ID" ]] || die "No Actions run appeared for commit $LOCAL_SHA. Check repository Actions settings and workflow permissions: https://github.com/${REPO}/actions"

say "Following workflow run $RUN_ID."
if ! gh run watch "$RUN_ID" --repo "$REPO" --exit-status; then
  echo "\n--- Failed GitHub Actions log ---" >&2
  gh run view "$RUN_ID" --repo "$REPO" --log-failed 2>&1 | tail -n 240 >&2 || true
  die "CI failed. No APK will be claimed. Inspect https://github.com/${REPO}/actions/runs/${RUN_ID}"
fi

DEST="$ROOT/exports/apk-artifact"
mkdir -p "$DEST"
say "Downloading the APK artifact."
gh run download "$RUN_ID" --repo "$REPO" --name "$ARTIFACT_NAME" --dir "$DEST"
APK="$(find "$DEST" -maxdepth 3 -type f -name '*.apk' -print -quit)"
[[ -n "$APK" && -s "$APK" ]] || die "Workflow succeeded but the APK file was not found in the downloaded artifact."

python3 - "$APK" <<'PY'
import sys, zipfile
from pathlib import Path
p = Path(sys.argv[1])
if not zipfile.is_zipfile(p):
    raise SystemExit(f"Downloaded APK is not a valid ZIP container: {p}")
with zipfile.ZipFile(p) as z:
    names = set(z.namelist())
    if "AndroidManifest.xml" not in names:
        raise SystemExit("APK missing AndroidManifest.xml")
print(f"APK container validated: {p} ({p.stat().st_size:,} bytes)")
PY

cp -f "$APK" "$ROOT/exports/Mineblock-debug.apk"
if [[ -f "${APK}.sha256" ]]; then cp -f "${APK}.sha256" "$ROOT/exports/Mineblock-debug.apk.sha256"; else sha256sum "$ROOT/exports/Mineblock-debug.apk" > "$ROOT/exports/Mineblock-debug.apk.sha256"; fi
say "SUCCESS. APK saved to: $ROOT/exports/Mineblock-debug.apk"
say "CI run: https://github.com/${REPO}/actions/runs/${RUN_ID}"