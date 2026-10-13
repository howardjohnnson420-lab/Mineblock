# Mineblock

Godot 4.7.2 Android-first creative flatworld project.

## Project status
This repository is being initialized for the Mineblock creative-building game. The complete source assets must be included before a build can be considered complete. An APK should only be published after Godot import, runtime smoke tests, and Android export all pass.

## Target
- Godot 4.7.2
- Android creative flatworld
- No hostile mob spawns
- Ordinary unsupported blocks float; support-required blocks react to support removal; gravity-affected blocks fall.

## Build pipeline
See `.github/workflows/android-apk.yml` in the project source package. It is intended to run a verified Godot import and Android export, and to publish an APK artifact only when the checks pass.
