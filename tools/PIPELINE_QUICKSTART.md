# Mineblock direct publish → CI build → APK download

The `deploy_and_get_apk.sh` script joins the local project, GitHub and the Android build into one repeatable command. It does **not** need any secret to be pasted into this chat. It uses the GitHub CLI's normal browser/device authorization on the computer where you run it and requests the `workflow` OAuth scope needed to push the Actions workflow file.

## One command

From the assembled project directory, run:

```bash
bash tools/deploy_and_get_apk.sh
```

The script will:

1. Verify all 1,983 supplied source-file records and run the three static test suites.
2. Authenticate with GitHub CLI if needed, configure Git's credential helper, and verify that the logged-in account can read `howardjohnnson420-lab/Mineblock`.
3. Stage and commit the project and all extracted source assets.
4. Push `main` without force-pushing. If remote `main` contains unrelated commits, it stops safely and asks you to reconcile them.
5. Wait for the `android-apk.yml` GitHub Actions run for the pushed commit.
6. If CI passes import and Godot runtime smoke tests and creates the Android APK, download it and save it at `exports/Mineblock-debug.apk`.

## Install prerequisites

- Git
- Python 3
- GitHub CLI (`gh`)
- All eight source asset bundles extracted into the project root

On Windows, use Git Bash. On macOS/Linux, use Terminal. On Android, this is possible only in a suitable Termux setup and requires substantial free storage (the expanded supplied assets alone are approximately 880 MB); a computer is easier for the first upload.

If the script opens a browser or displays a device code, finish GitHub's authorization flow there. Do not send passwords or access tokens in chat. Use the account that owns or can write to `howardjohnnson420-lab/Mineblock`.

## Failure handling

- A static audit failure stops before the push.
- A permission/push failure stops before waiting for CI.
- A failed workflow prints the failed logs and its run URL. It does not claim there is an APK.
- The script never force-pushes and never replaces a remote branch that contains commits not in the local branch.
- CI output is a **debug APK**. It still needs installing and manual device QA before calling the game fully usable.

Workflow page: https://github.com/howardjohnnson420-lab/Mineblock/actions