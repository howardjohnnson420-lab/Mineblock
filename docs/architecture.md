# Architecture Notes

- `main.gd`: startup, environment/lighting, player/controller setup, target ray, HUD, hotbar, inventory actions, settings and save/load.
- `world_manager.gd`: sparse edit state including per-block states/pairs, implicit four-layer flat ground, 16×16 streamed terrain chunks, exposed-face meshing, regenerated triangle collision, lazy GLB placement, custom state geometry/colliders, neighbor updates, basic redstone, fluid flow/reactions, falling blocks, pistons, TNT and hopper transfer.
- `asset_registry.json`: stable IDs and paths generated from the supplied catalogue/audit material, augmented with class/category/search tokens, map paths, bounds and placement profile.
- `material_resolver.gd`: shared texture/material caches and selection between core PNG and optional WebP map sets.
- `inventory_panel.gd`: category and free-text filtering across the complete registry. It creates a page of 30 SubViewport model previews at a time to avoid allocating a viewport for all 1,245 items simultaneously.
- `player_controller.gd` + `virtual_joystick.gd`: first-person walking/flying and touch look/movement.

The design deliberately does not use a node per terrain block. Terrain is meshed per chunk; placed objects use individual imported scenes because the supplied library includes partial/custom geometry that should not be collapsed into generic cubes. The current placed-object path does create a lightweight approximate box collision proxy for each instance.


## State-driven mechanics boundary

`BlockBehaviors` assigns families from stable IDs; the placed-state dictionary is saved rather than deriving gameplay from visual names every frame. `CreativeWorldManager` is the authoritative mutation layer for paired structures, connections, state visuals and persistence. This approach makes further family support incremental, but names-based family assignment and approximate simulation do not mean full vanilla coverage. `reports/mechanic_coverage.md` lists which systems are implemented in source, approximate, unavailable, or blocked pending runtime verification.