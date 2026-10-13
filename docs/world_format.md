# World and Save Format

## Coordinates and base terrain

- Cell coordinates are integer `Vector3i(x, y, z)` values.
- Cell centers are integer world coordinates. World-to-cell rounding uses `floor(position + 0.5)` for the centered-cell convention, including negative positions.
- One block is 1×1×1 world units at the maximum block envelope; partial models retain their source geometry/pivot and use audited bounds for approximate collision.
- Base terrain is data-driven by `CreativeWorldManager.GROUND_IDS`: `grass_block` at y=0, `dirt` at y=-1, `dirt` at y=-2, and unbreakable `bedrock` at y=-3 by default.
- X/Z terrain is generated lazily in 16×16 chunks. The underlying terrain exists at every X/Z coordinate. Only chunks near the player are rendered/collidable at a given moment.
- Terrain visuals are rebuilt from exposed faces and the chunk mesh's triangle geometry is also used to rebuild static collision after a terrain edit.

## Edits

- `placed_blocks`: cell -> stable model ID, yaw, and a placed-state dictionary (facing/axis/half/shape/open/power/connection masks/pair coordinates/container item IDs/fluid source+level and family-specific state where applicable).
- `removed_cells`: cells removed from the four-layer base terrain.
- Imported GLB scenes are created lazily for placed assets. The asset registry is the source of their model and texture paths.
- Full cubes use imported GLB geometry; state families with custom block silhouettes (slabs, stairs, fences/walls/panes and redstone wire) use state-driven procedural geometry with the resolved source material. Doors, trapdoors, gates, beds, tall plants, fluids, rails and mounted objects apply family transforms and approximate collision/selection profiles. These are source implementations pending Godot import and in-engine geometry/physics tests; they are not asserted to be pixel- or behavior-identical to vanilla.

## Persistence

Save path: `user://creative_flatworld_save.json`.

Schema version 1 stores world name/preset/layer descriptions, placed block records including family state and paired cells, removed base cells, player position/yaw/pitch/flight/spawn point, simulated day-cycle time, nine hotbar IDs, selected slot, render distance, look sensitivity, touch sensitivity, optional WebP material mode and UI scale. Saving writes a temporary file first and uses a backup rename flow before replacing the latest save. Autosave runs every 45 seconds while the world is dirty, in addition to manual save and menu transitions.

The data format has defensive JSON/schema checks, but the round-trip has not been executed under Godot 4.7.2 in this environment. Treat this schema as an initial implementation pending engine/device QA.