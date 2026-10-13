# Publish to GitHub and obtain an Android APK

## Required repository tree

The root of `howardjohnnson420-lab/Mineblock` must contain the complete project source and all supplied assets at the paths declared by `data/asset_registry.json`. In the project directory, run the asset audit and tests before pushing:

```bash
python tools/audit_assets.py
python tests/test_project_consistency.py
python tests/test_mechanics_contracts.py
python tests/test_android_pipeline.py
```

Do not commit `.godot/`, Android debug keystores, private release keys, APKs, or other local build outputs. The source art bundle is around 873 MB expanded; check current GitHub size/upload guidance and use Git LFS if needed for binary asset tracking. The repository's `.gitignore` intentionally does not exclude `assets/source_library/`.

## APK workflow

`.github/workflows/android-apk.yml` downloads the official Godot 4.7.2 Linux editor and export templates, verifies checksums, imports the project, runs the engine smoke suite and exports an ARM64 debug APK. A successful run attaches `Mineblock-debug.apk` and `Mineblock-debug.apk.sha256` as the `Mineblock-Godot-4.7.2-Android-debug-APK` workflow artifact. Open the repository's Actions tab, select the successful `Godot 4.7.2 Android APK` run, and download that artifact ZIP.

If any validation step fails, the APK artifact is deliberately not published; download the `Mineblock-Android-build-diagnostics` artifact and investigate the first failing log. A CI export is not a substitute for installing the APK and performing device QA on the target phone.

## Current limitation

The authenticated GitHub integration in the authoring environment can read `howardjohnnson420-lab/Mineblock` but write operations currently return HTTP 403 (`Resource not accessible by integration`). Therefore no commit or workflow run can be claimed until GitHub write access is restored. The source changes and workflow are prepared in this project package for upload after the connection is authorized.

## Safe publish helper

Once all eight asset bundles are extracted, run `bash tools/publish_to_github.sh` from a shell with Git, Python 3 and GitHub push authentication configured. The helper runs the audit/tests first, refuses to replace an unrelated remote origin, creates a normal commit, and uses a non-force push. On Android/Termux, ensure there is enough free storage and a stable connection before pushing the large asset library. Alternatively, push through GitHub Desktop from a desktop computer.

For a local export after installing Godot 4.7.2 and its Android SDK/export templates, run `GODOT_BIN=/path/to/godot bash tools/build_android_local.sh`. The script exits at the first failure and does not claim an APK exists unless the export command succeeds.


## One-command end-to-end runner

Run `bash tools/deploy_and_get_apk.sh` to validate the complete local project, request GitHub CLI authentication (including the `workflow` scope), safely push `main`, wait for the Actions run tied to that exact commit, and download the APK artifact only when the job succeeds. It refuses force pushes, reports failed workflow logs, validates the APK's zip structure and writes `exports/Mineblock-debug.apk`. The full usage guide is `tools/PIPELINE_QUICKSTART.md`.