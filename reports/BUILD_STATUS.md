# Mineblock build status

## Current state

- Godot project source and Android CI workflow are committed to GitHub.
- The asset registry contains 1,245 model definitions.
- Source asset payload is not fully present in the GitHub repository yet.
- Godot parser/import/render checks remain **unverified in Godot runtime**.
- **No APK** has been exported or verified yet.

## Required gate

The Android workflow deliberately stops before downloading the engine/export templates if the supplied GLB and texture source library is absent. It must not publish an APK built only from a metadata registry.

Once all source files have been placed under `assets/source_library/Minecraft_Realistic_Voxel_Assets_AI_Handoff/`, the workflow verifies file hashes, runs the static suites, imports resources with Godot 4.7.2, runs the runtime smoke test and exports the Android debug APK.

## Current limitation

The ChatGPT GitHub integration can create text files and commits, but it does not expose a binary release-asset/LFS uploader. The large original model and texture library still needs to be transferred to the repository using a binary-capable route.
