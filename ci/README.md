# Android build and validation

The workflow `.github/workflows/android-apk.yml` builds with the official Godot 4.7.2 release and matching export templates, verifies the supplied asset manifest and SHA-256 hashes, runs the static Python checks, performs a headless Godot import, executes `tests/runtime_smoke.gd`, and only then exports/uploads `Mineblock-debug.apk`.

It intentionally fails before APK publication if the full supplied library is not present under `assets/source_library/`, if an audit fails, or if Godot import/runtime checks fail. This prevents publishing an APK that looks buildable but omits the user-provided art library.

The debug APK is for direct device testing/sideloading, not a Play Store release. A production release needs a private signing key, package/version decisions, and device QA.