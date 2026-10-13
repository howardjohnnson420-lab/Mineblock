# MASTER BUILD PROMPT — Minecraft-style Creative Flat World for Android

**Engine target: Godot 4.7.2 specifically. Primary reference: Minecraft Bedrock Edition on Android/mobile, Creative mode, Flat World.**  
**Project type:** a real, playable 3D block-building game, not an asset viewer or demonstration scene.

---

## 0. Your assignment and non-negotiable outcome

You are the lead gameplay engineer, technical artist, build engineer, asset librarian, and QA engineer. Build a polished Android-first creative-building game that behaves as closely as practical to the *Minecraft Bedrock mobile Creative + Flat World* experience, using the supplied asset library as the content source. Write original game code; do not depend on the faulty/old preview scene or its scripts. Do not merely create a pretty sample scene, a block showcase, a poster, a static plane, or a menu mock-up.

The required product is a working first-person, block-grid creative sandbox where the player can move and fly, browse a complete usable creative inventory sourced from the provided files, select blocks, place them on a grid, break them instantly, build large structures, save the world, close the app, and resume exactly where they left off.

The user is developing on Android and has Godot 4.7.2 installed. The project must explicitly target **Godot 4.7.2**, not Godot 4.3, 4.4, or a generic unspecified Godot 4 version. Use GDScript and built-in Godot features by default. Add-ons/native extensions are allowed only if they are compatible with Godot 4.7.2, their licensing and installation requirements are documented, and the project remains reproducible. Do not make the app depend on an internet connection to run.

### Fidelity and scope priorities

1. **Core building loop must work perfectly first:** look, move, fly, select an item, point at a block, get a clear target outline, place the selected block on the correct adjacent cell, break a block instantly, and repeat without missed inputs or coordinate errors.
2. **Real supplied assets must be used.** Actual imported model geometry, correct materials, color, normal detail, roughness/metallic/AO where supported, and correct orientation take priority over dummy cubes. A simple cube is permissible only as an explicit fallback for an asset that has been audited and proven missing/broken; it must be logged and must never silently replace a valid model.
3. **Inventory coverage:** every relevant asset discovered in the provided library must be represented in a searchable catalog and made available through the game when it is a valid block/item/decorative object. Do not stop at the ~20 demo blocks in the old preview.
4. **World editing and persistence:** use a real coordinate-based block world, not a decorative plane with independent untracked meshes. Save world edits, block states, hotbar, selected slot, and player position.
5. **Android usability and performance:** touch-first controls, scalable UI, and a chunked/instanced world architecture. Never instantiate thousands of separate expensive scene nodes if chunk meshes or batching are more appropriate.
6. **Honest verification:** report what was actually tested. Do not call this a finished game, APK, or complete asset catalog unless the corresponding tests passed.

### Game rules requested by the user

- Make **Creative mode** the default and primary/only game mode for the first deliverable. Do not add survival progression, hunger, durability loss, crafting requirements, or hostile monster encounters to the core game.
- Use a flat world intended for unrestricted building. Default terrain should follow the familiar Classic Flat profile: grass surface, two dirt layers below it, then bedrock at the bottom. Make the flat-world layer setup data-driven so it can be verified/adjusted without rewriting the engine.
- **No hostile monsters should spawn.** The focus is peaceful building. Do not spend time implementing survival combat or hostile AI. If non-hostile entities and decorative objects exist in the supplied assets, inventory classification can expose them as a later milestone; they must not spawn spontaneously in the default world.
- The look should preserve readable Minecraft-like block silhouettes, scale, grid alignment, and visual clarity while using the supplied higher-detail/realistic PBR materials where their matching maps are available. Do not make the world look like randomly arranged colored placeholder cubes.
- The main target is Android touch gameplay. Also provide keyboard/mouse input in the editor/development build for efficient testing.

## 1. Start with an evidence-based asset audit — do not code blindly

Before replacing or restructuring any project files, inspect the entire assembled project folder and all extracted parts. The user downloaded Part 01, Parts 02, 03A, 03B, 03C, 04, 05 and optional Part 06. Folder names may vary; discover actual paths from the filesystem. **Do not assume a path is correct merely because an older README says so.**

### 1.1 Preserve source assets

- Treat the supplied models, textures, catalogues, manifests, readmes and checksums as source material. Do not rename, move, overwrite, recompress, recolor, or modify source assets destructively.
- Make a version-control commit or a full copy/backup before edits. Keep source assets immutable and create generated import files, thumbnails, normalized metadata, collision proxies and derived materials in separate generated folders.
- If several copies of the same named file exist, compare size and SHA-256 before deciding which is canonical. Record duplicates, do not silently discard unique files.
- Do not use the old Godot preview scene as a source of truth for asset coverage. It showed only a tiny list of colored sample cubes and a floor; it is not the finished project architecture.

### 1.2 Inventory every file

Recursively enumerate all files, including nested folders and filenames with spaces or unusual capitalization. Produce a machine-readable `reports/asset_inventory.json` and a human-readable `reports/asset_audit.md`. Record relative path, extension, size, SHA-256, parse/load result, resource type, and classification. Scan at least:

- `.glb`, `.gltf`, `.obj`, `.fbx`, `.tscn`, `.tres`, `.res`, `.blend` (if present), and other geometry/model/scene formats;
- `.png`, `.webp`, `.jpg`, `.jpeg`, `.tga`, `.exr`, `.hdr`, and other image files;
- manifests/catalogues such as `.json`, `.csv`, `.md`, `.txt` and checksum files;
- scripts/configuration files and any import metadata.

The prior documentation reports approximately **1,245 GLB model files**, **90 maps per core PBR map type** (base color, normal, ORM and height; verify actual counts), and **360 optional WebP exports**. These figures are expectations to audit, not facts to assume. Verify the real counts from disk, compare checksums if present, and state discrepancies.

### 1.3 Create an asset-to-game registry

Create a stable internal resource registry with at minimum:

- unique internal ID that remains stable when display names change;
- display name and normalized search tokens;
- exact source model path(s) and SHA-256;
- exact texture paths for base color, normal, ORM/roughness/metallic/AO, and height/displacement, when they exist;
- model bounding box, dimensions, origin/pivot, transforms, material count, surface count, transparency classification, and whether animations are present;
- provisional type: full block, partial block, connected block, multi-block object, item/handheld, decoration, entity, UI/icon asset, material-only, unknown/unclassified;
- intended inventory category and family;
- placement/rotation/state/collision profile, if applicable;
- current validation state: `verified`, `needs_import_test`, `missing_texture`, `missing_model`, `ambiguous_match`, `non_block_asset`, `unsupported`, or `unknown`;
- proof of actual use: inventory entry, in-world render test, and material test (separate booleans).

Use the supplied manifest and catalogue as hints, not as unquestionable truth. Validate each relationship against actual file names and content. Match textures by exact stem or explicit manifest records; do not associate maps just because their names are vaguely similar. Where the manifest is ambiguous, create a report and use a labelled manual mapping table instead of guessing silently.

### 1.4 Import test and visuals gallery

- Use Godot 4.7.2's supported 3D import pipeline for GLB/glTF and check the official version-specific documentation before depending on importer behavior.
- Import every model or run an available batch validator over every model. Capture load errors, empty meshes, broken materials, invalid transforms, extreme scales, and missing dependencies.
- Generate a thumbnail for each model and a contact-sheet/gallery index in `reports/asset_gallery/`. Thumbnails must depict the **actual model with its actual material**, not a poster/collage or hand-drawn substitute. A generated gallery is for audit; the in-game inventory must still use real assets or model-based thumbnails.
- Test representative asset types: a full cube, a log/pillar with axis rotation, a stair, slab, fence/pane, door, glass/transparent asset, sign/container, non-cube decoration, and entity/item model if present.
- Keep a missing/unsupported report. If a model is not a block, don't force it into a 1×1×1 collision cube; classify it appropriately.

## 2. Technical reference target and version discipline

Use **Minecraft Bedrock Edition on Android/mobile** as the primary behavioral target because this game is intended to run and be controlled on an Android phone. Reference Minecraft Java Edition only as a secondary source for mechanics or creator details when the behavior is equivalent; explicitly note and resolve edition differences rather than mixing controls or inventory conventions at random.

Research current controls, creative inventory organization, flat-world preset behavior, block placement states, UI interactions and game settings using the linked sources in the research register. Use a consistent target profile documented in `docs/reference_profile.md` that states:

- reference edition: Minecraft Bedrock mobile Creative + Classic Flat;
- no hostile mob spawning in this project per the user's requirements;
- world layer profile and build-space conventions;
- mobile look/movement/action control conventions;
- inventory category/search behavior to emulate;
- intentionally out-of-scope systems for the first deliverable (survival, multiplayer, hostile mobs, Nether/End, commands with side effects, achievements and official Mojang account integration).

Do not copy Mojang source code or fetch/use unprovided Minecraft proprietary assets. Implement equivalent gameplay behavior with original code and the supplied user-provided assets. Do not download random model/texture packs as a shortcut. If the user-provided asset library lacks a required icon, audio or model, document the gap and either create an original neutral UI element or request an explicit decision; do not pretend it was supplied.

## 3. Correct Godot project and version checks

Create a clean project if the old preview architecture is flawed, but preserve the entire asset source. At project root:

- `project.godot` must target Godot **4.7.2-compatible settings/APIs** and point to the true main scene.
- Add `README.md`, `docs/`, `scripts/`, `scenes/`, `assets/` or a well-documented arrangement that preserves original asset paths, `data/`, `tests/`, `reports/`, and `exports/` (as needed).
- Define all input actions in a consistent input map. Avoid magic keycodes or mobile-only hard-coded input paths inside gameplay systems.
- Pick Godot's **Mobile** renderer as the starting point for Android devices that support Vulkan; test **Compatibility** as a fallback if performance/device compatibility requires it. Do not choose Forward+ just because it looks more advanced; measure the actual target device and use the renderer that works. Document trade-offs.
- Use typed GDScript where it improves correctness, explicit null/error checks, clear ownership of nodes/resources, and version-compatible APIs only.
- No external plugin may be essential to the startup loop unless it has been checked for Godot 4.7.2, committed or installation-documented, and smoke-tested. If a voxel plugin is selected, verify 4.7.2 compatibility, Android support, licensing, export requirements and maintenance status first; build a working baseline with built-in Godot tools if no suitable plugin can be confirmed.
- Add a startup diagnostics overlay/toggle that displays engine version, renderer, asset load state, chunk/mesh counts, visible blocks, draw calls if available, FPS/frame time, memory where available, and current save name.

**Critical:** Do not merely alter a comment or feature flag and say the project is “converted”. Run the project using Godot 4.7.2 (or state honestly when the engine isn't available), resolve parse/import/runtime errors, and prove the configured main scene launches.

## 4. Asset appearance: actual models and PBR materials must show

The user rejected the previous preview because it showed a small pile of flat-colored fallback cubes, a large gray plane, no visible realistic textures, and only around twenty labels. Prevent this failure explicitly.

### 4.1 Material matching

- Assign each GLB's embedded material when valid and preserve its texture slots, then compare against the separate PBR maps. Do not overwrite a correct embedded material blindly.
- For texture maps stored separately, use a deterministic mapping table. Verify texture dimensions, image decoding, color space, alpha, channel packing and naming.
- Base color/albedo should use the correct color-space handling. Normal maps must be imported as normal maps, not treated like colored albedo. ORM maps require correctly verified AO/roughness/metallic channel interpretation for the supplied map convention and Godot material API. Never assume a channel order without checking the asset generator/readme and inspecting representative maps. Height/displacement maps are not automatically normal maps; use them only through a compatible material technique and never deform standard block silhouettes or destabilize collisions.
- Use `ORMMaterial3D` where its ORM texture layout fits; use `StandardMaterial3D` or a suitable shader when maps are separate or packed differently. Create a central material factory/cache so hundreds of models do not create duplicate material resources unnecessarily.
- Do not make every material shiny. Use the supplied roughness/metallic data, fix out-of-range/mispacked values, and test wood, stone, dirt, metals, foliage and glass separately.
- Configure alpha/cutout/blend correctly for glass, leaves, water-like and foliage assets, if present. Avoid enabling transparency on every material; it can cause sorting and performance problems.
- Preserve block-grid form. PBR realism comes from real texture detail and plausible lighting, not from rounding all edges or turning blocks into amorphous meshes.
- Use readable daytime lighting, sky/background, shadows and ambient illumination. The main gameplay viewport must never render as an empty black void with a single plane. Provide visual diagnostics when an asset cannot be rendered.

### 4.2 Models, orientation and scale

- Determine the canonical grid size (one cell is one Minecraft-like block unit) and normalize model transforms in generated metadata—not by destructively editing the source files.
- Use actual meshes and material surfaces wherever suitable. Create collision shapes from bounding boxes or hand-authored profiles. Prefer simple collision proxies over triangle-mesh collision for common blocks.
- Define axis/orientation corrections per asset when its pivot or forward direction differs from the project's convention. Keep those corrections in metadata.
- For cube blocks, build a chunked world representation that preserves each model's actual material and relevant geometry. Consider greedy face merging for simple opaque cubes **only if** the resulting mesh can preserve the same materials/UVs and doesn't discard custom geometry or block states. Use instanced/custom mesh variants for repeated partial blocks where feasible. Avoid rendering internal faces between adjacent opaque full-cube blocks. Do not merge across transparent/custom models in a way that damages the view.
- A fallback cube is only a diagnosed exception, visibly marked in the asset audit. It must not become the default for all blocks.

## 5. Build a real Minecraft-like flat block world

### 5.1 World coordinate system and classic flat profile

- Use integer block coordinates `(x, y, z)` and one world unit per block. Define one canonical conversion between world positions and integer cell positions; use floor-based conversion consistently for negative coordinates too.
- Generate the default Classic Flat ground as four layers: grass at the surface, two dirt layers below, and bedrock at the bottom. Record the exact y-levels and spawn height in `docs/world_format.md`. The world must be flat, not hills/noise terrain and not only a rendered rectangle.
- The build area should behave as a horizontal world that can expand as the player explores/builds, using lazily created chunks. If truly unbounded storage is unrealistic, create a very large chunked build space and make its boundaries explicit in settings/UI; don't secretly limit it to the showcase plane.
- Organize block data by chunks (a 16×16 horizontal section/chunk convention is a reasonable starting point; choose vertical section sizing based on implementation). Avoid one Node per block for the whole map. Use per-chunk data arrays/dictionaries plus merged mesh/instance rendering and collision only where needed.
- Track air as an explicit empty block state; place/remove operations must update the data model first and then update visuals, collision, adjacency/state variants, and save dirty state reliably.
- Keep the ground fixed and flat unless the user intentionally edits/breaks it. Creative mode should allow removing and rebuilding cells like Minecraft except where an optional bedrock lock is deliberately configured; default bedrock can be unbreakable if matching Classic Flat behavior is desired.
- The game begins on the world at a safe position, with enough ground visible to make the scene immediately recognizable as a block world.

### 5.2 Block data model

Implement a stable `BlockDefinition`/registry and separate placed-instance `BlockState` data. A definition contains identity, display name, tags, mesh/model, material profile, collision profile, selection profile, placement behavior, render category, sound identifiers if supplied/created, transparency class, inventory categories and allowed state properties. A placed state contains the definition ID and relevant instance state values (orientation, half, variant, connection mask, open/powered/age/etc. where supported).

Do not use asset filenames as the only gameplay database. Use stable IDs, human-readable names and a data-driven registry. Multiple visual variants of one family should be discoverable with sensible display names. Do not imply that a visual model grants its real Minecraft gameplay behavior automatically; implement behavior explicitly and document the coverage status.

### 5.3 Chunk rendering and updates

- Only render block surfaces/faces that can actually be seen for ordinary opaque cubes. Hide interior faces between solid neighbors.
- Maintain correct face normals, UVs, texture repeat/scale and world-space alignment. Avoid texture stretching across an entire chunk when each block is meant to show its own material tile.
- Keep special/partial/transparent shapes as their actual geometry or state variants. Make collision, ray selection and rendered geometry agree.
- When a block changes, rebuild only the affected cell/chunk and the neighboring chunks whose borders or connected states are affected. Don't regenerate the whole world after each tap.
- Add frustum/distance-based chunk visibility and a safe configurable render distance. Load neighboring chunks incrementally to avoid long Android freezes.
- Profile on device. Use MultiMesh, batched chunk meshes, simplified collision and resource/material caching where appropriate. Keep editable world data separate from the render mesh so meshes can be regenerated.

## 6. Player controls: first-person creative fly/build loop

### Touch-first Android control scheme

Implement a responsive mobile HUD inspired by Minecraft Bedrock touch controls. Do not put tiny desktop buttons on mobile. Support screen aspect ratios and UI safe areas. Controls must be large enough to use and configurable for sensitivity/button opacity/size if reasonable.

Required touch interactions:

- virtual movement joystick at lower left (forward/back/strafe);
- drag in the gameplay view to turn camera/look, with configurable sensitivity;
- a clear central crosshair/target reticle and a block-selection outline;
- jump button;
- fly toggle by a familiar double-tap on jump or an explicit flight toggle, plus clearly labelled rise and descend controls while flying;
- break/destroy button: immediately remove the targeted breakable block in Creative mode;
- place/use button: place selected block at the cell adjacent to the targeted face, or perform the selected object's use interaction;
- visible 9-slot hotbar at the bottom, selected-slot highlight, block icons that match actual models/materials, and tap-to-select slots;
- inventory button that opens the creative inventory and closes cleanly with a back/close button;
- optional sprint button only if movement tuning works well;
- menu/pause, save indication, and settings entry.

Required desktop/development controls:

- WASD movement, mouse look, Space jump/fly rise, Shift descend while flying (or an equivalent documented mapping), left click break, right click place/use, number keys 1–9 hotbar selection, E inventory, Escape pause. These may be remapped.
- Prevent gameplay clicks from firing while the player is interacting with inventory UI buttons; manage input capture/release correctly.

### Player movement behavior

- Creative walking does not require stamina, hunger, or survival health.
- In flight mode, movement is responsive, stable and six-directional, with deliberate rise/descend controls, collision behavior documented, and no falling back to the ground after every input release. Free-flight camera pitch may influence forward movement if it matches the reference profile; tune and test this rather than guess.
- Creative mode is not damaged by falling; no death or dropped-item loop. No random hostile creatures spawn.
- Set a target reach distance and block interaction timing close to the reference experience. Prevent ray selection from hitting the player's own body or UI.
- Support head-height/camera positioning with correct player capsule size and grounded start. Avoid camera jitter, crossing the ground, accidental upside-down pitch, or touch-input conflicts.

## 7. Block targeting, breaking and placing — the core loop

Implement targeting through a physics ray or custom voxel-grid traversal from the camera through the block data. A hit must provide exact integer cell coordinates, surface face normal/direction, block definition/state, and any special model interaction metadata.

### Breaking

- A valid target gets a clear selection outline that matches the selected block's real bounding/selection shape (not always a full cube for stairs, panes or decorative models).
- Press/tap break in Creative mode removes the block immediately, updates neighboring faces/connections, collision and chunk meshes, and marks its chunk dirty for saving.
- Do not spawn survival drops or require mining time. Provide subtle feedback only if a sound/particle asset or original effect is available and stable.
- Prevent breaking when no valid target exists; avoid breaking through transparent/partial block geometry if the actual ray has hit a nearer target.

### Placing

- Place the selected block into the adjacent cell based on the hit face; if the target face normal is `+X`, place at `(x+1,y,z)`, etc. Use cell coordinates, not floating-point rounding from the hit point alone. Handle the top/bottom faces and negative coordinates correctly.
- Do not place into occupied cells unless the target block supports replacement/use semantics; implement replaceable plants/fluids only if the corresponding profiles exist.
- Respect player collision or provide the same placement tolerance as the chosen Minecraft reference. Avoid trapping the player inside a full solid block unless the reference behavior permits it.
- Orientation must match the camera/player direction for logs, stairs, slabs, doors, trapdoors, furnaces and other orientable assets; slabs need top/bottom/merged rules; doors/beds need multi-cell placement and cleanup; connected blocks need neighbor updates.
- Placement should feel direct on touch. Avoid requiring double-taps except for controls whose reference behavior needs it. Prevent one held finger from triggering repeated destructive/placement inputs unintentionally unless continuous placement is deliberately supported.

### Block state families to support when matching assets/data are available

Do not claim that all these are present in the asset library. First map available definitions to state families, then implement the families that occur, report what does not occur, and build the data architecture so missing ones can be added without rewriting the world engine:

- full cube with standard material;
- logs/pillars with axis/facing;
- stairs (facing, top/bottom half, inner/outer corner if connection data and geometry support it);
- slabs (top/bottom/double/merge);
- doors and trapdoors (orientation/open, two-cell upper/lower for doors);
- fences, walls, iron bars and glass panes (dynamic connections to neighbors);
- torches and wall-mounted attachments, buttons/levers/pressure plates (support face/facing and pressed/on state if implementing interaction);
- signs (correct surface orientation and editable text if asset/implementation supports it);
- chests/container-shaped blocks with a functional UI and persisted contents if included in scope;
- glass/leaves/foliage and other transparent/cutout assets;
- water/lava or other fluid-like assets: don't fake full fluid simulation with a static tile; if fluid simulation is not in the first build, make the current limitation explicit;
- decorative and multi-part blocks (beds, plants, tall flowers, hanging/standing signs, candles, rails, carpets, frames) when appropriate assets exist;
- non-block items, entity spawn items, handheld objects and other assets should be classified as such rather than forced to act like full blocks.

## 8. Creative inventory — comprehensive, searchable and driven by all assets

The old preview displayed only a small, hard-coded sample. Do not repeat that. Inventory content must be data-driven from the validated registry and include every asset classified as an in-game block/item/placement object that can reasonably be exposed. Every valid entry must be reachable either through categories or search; none may be silently omitted.

### Inventory interface

- Use a Minecraft Bedrock mobile-inspired panel and large touch targets.
- Provide category tabs using the Bedrock-style organization as the primary reference: **Construction, Equipment, Items, Nature, and All**. Use sensible subgroups/family sorting within categories. The list of content must follow the actual audited asset set and a separate target Minecraft-version coverage list; do not invent a false claim of vanilla completeness.
- Add a reliable search input with case-insensitive filtering over display name, synonyms, tags, family, material and aliases. Search must include all catalogued valid entries, including entries that appear in multiple categories; avoid duplicate spam in All/Search unless the reference expects it.
- Grid each item with a clear icon rendered from the real imported model/material (or a correctly mapped supplied icon when available). Do not use a colored blank tile as the default icon. Use a selected-item panel/tooltip showing name and key state/asset notes.
- Tapping an item fills the selected hotbar slot. Tapping a hotbar slot selects it. Make duplicate selection intuitive. If the inventory has more items than fit on screen, make the grid scroll smoothly and keep category/search controls visible.
- Include “clear hotbar” and slot management controls. Where sensible, mirror creative inventory semantics: infinite block usage, items aren't consumed on placement, and a 9-slot hotbar for the initial target.
- Preserve hotbar selection and inventory-related state between sessions.
- Operator-only items should not be fabricated if the model is absent. You may provide a documented optional “technical objects” category for assets that are clearly barriers, structure markers or similar, but label them carefully and don't invent actual commands without implementing them.

### Asset coverage gates

- Generate `reports/inventory_coverage.csv`: one row per discovered model/file and a column for `inventory_visible`, `category`, `searchable`, `thumbnail_verified`, `world_placement_verified`, `material_verified`, `behavior_implemented`, and `reason_if_not_usable`.
- Generate a discrepancy list comparing the number of actual models/maps against the manifest/catalogue. Include every rejected or duplicate file and why.
- Acceptance target: **100% of the supplied files have an audit disposition**, not “100% of all Minecraft blocks exist” unless verified against a separately defined target registry. At least every supported valid asset must be findable in inventory or explicitly classified as a non-inventory resource.

## 9. Materials, visual tone and scene quality

The user asked for a recognizable Minecraft creative flat-world experience, but expects the supplied realistic asset library and PBR textures to be visible. Make it look intentionally designed:

- Use a clear blue/daylight sky or appropriate light environment, directional sunlight, contact shadows, sensible ambient light, and a horizon/sky that feels like a flat outdoor world—not a dark showroom.
- The surface must consist of actual grid-aligned textured blocks, not just a featureless plane. A subtle unobtrusive void/far horizon is fine, but it cannot replace world ground geometry.
- Correctly apply base-color, normal, ORM and optional height maps to the models. Include material diagnostic mode (e.g. show base color / normals / roughness) for debugging, but normal gameplay shows final material output.
- Test in-world samples in sunlight, shadow, and close view. Keep PBR quality but preserve Minecraft-like pixel/grid readability; prevent excessive gloss, overdarkening, muddy colors, texture misalignment, visible gaps, z-fighting, incorrect normal orientation or texture stretching.
- Build inventory thumbnails and in-world renders from the same canonical material/model definitions. This ensures that an inventory icon and placed block look like the same item.
- Include a basic options menu for look sensitivity, touch sensitivity, UI scale, render distance, shadows, texture quality and frame rate cap where feasible. Options should be persistent.

## 10. Sound and feedback

If the supplied library includes suitable sounds, audit and use them with their licenses. If it does not, generate/implement a very small set of original, understated sounds or leave sound muted/toggleable until assets are available. Do not download copyrighted Minecraft audio as a shortcut.

Required feedback: placement feedback, break feedback, inventory opening/closing, hotbar selection, UI confirm/back, save success/failure, load success/failure and clear errors for unsupported assets. Avoid making missing sound a blocker for the core building loop.

## 11. World saving, loading and reliability

- Implement new world, load world, save world, rename world if feasible, and return to title/menu. Autosave on a safe interval and at important transitions; support manual save. Provide a clear unsaved-changes/saving indicator.
- Persist world dimensions/preset, chunk/block data, block states, multi-block objects, player position/rotation, flight state if desired, selected hotbar slot and hotbar contents, settings and schema version.
- Use Godot `user://` storage for user data. Use a versioned and validated save schema. Write temporary file then atomic replacement where supported, so a crash during save doesn't destroy the prior working save. Catch malformed/old files gracefully and create a diagnostic report instead of crashing.
- Save only changed chunks; don't serialize the rendered mesh as the sole world source of truth. On load, rebuild chunk meshes/collision from the data model.
- Test a real persistence round trip: place blocks in far-apart coordinates (including a negative coordinate), save, exit app, relaunch, load, verify all blocks/states/player/hotbar. Provide backup/export of user worlds if practical.
- Do not add cloud accounts or network features to the first release.

## 12. Architecture recommendation (choose based on tests, document why)

Use clean, replaceable modules such as:

- `AssetAudit` / `AssetRegistry`: scan and validate sources, catalog models/materials and write reports;
- `BlockDefinitionDB`: definitions, tags, state schemas, categories, interaction/collision/render profiles;
- `MaterialResolver`: deterministic PBR map matching, conversion and shared material caching;
- `WorldData`: integer coordinate and per-chunk block-state storage;
- `ChunkMesher` / `ChunkRenderer`: opaque face culling, partial/transparent special meshes, mesh rebuilds and collision generation;
- `WorldGenerator`: Classic Flat base layers and chunk initialization;
- `BlockRaycaster`: accurate targeting and face-normal calculation;
- `BlockInteraction`: placement/removal/use, state updates, connected blocks and multi-cell blocks;
- `PlayerController`: first-person walking/flying and desktop/mobile input;
- `CreativeInventory`: data-driven categories, item tiles, search/filter/hotbar;
- `WorldSaveManager`: versioned save/load and backup;
- `MobileHUD`: virtual joystick, look drag, jump/fly, break/place, hotbar, inventory and menu;
- `Diagnostics`, `Tests`, and `AssetCoverageReport`.

This is a proposal, not a requirement to over-engineer. If a different design produces a simpler, more reliable mobile game, use it and explain why. Do not make a separate `Node3D`/`MeshInstance3D` for every ordinary block in an enormous world without measuring and justifying it. A chunked mesh architecture is usually a better fit for a Minecraft-like world; instance real imported models for non-cube or rare blocks where that preserves geometry.

## 13. Phased execution — continue without asking for permission after each stage

Create a `reports/BUILD_STATUS.md` and update it after each phase. Do the work, don't just describe plans.

### Phase 0 — Forensics and safety

1. Discover actual root and folder structure.
2. Verify engine version/settings and current project state.
3. Back up source files or commit to version control.
4. Run the complete file/model/texture audit and hash checks.
5. Produce registry, source-vs-manifest discrepancy report, and import smoke-test results.
6. Never delete source files or “fix” source images in place.

**Gate:** 100% of files have an inventory record; issues and asset counts are explicit.

### Phase 1 — Correct Godot 4.7.2 clean start + render proof

1. Set valid Godot 4.7.2 project settings and main scene.
2. Import all assets; verify model/material load.
3. Create a representative real-textured sample field using the real assets (dozens, then category samples), on real block-grid terrain under proper lighting.
4. Add a model gallery/inspection mode to quickly validate all GLBs without forcing all objects into the same category.
5. Add error logs and visible diagnostics, not silent colored cubes.

**Gate:** the main scene opens; representative complex models show correct color/material; errors are visible and recorded.

### Phase 2 — Core player and block interaction

1. First-person controller and Android touch HUD.
2. Grid-based target ray, outline, break and place.
3. Exact coordinate/face behavior and orientation tests.
4. 9-slot hotbar select/place and no-consumption creative semantics.

**Gate:** user can build and demolish a 10×10 test structure, with correct rotations and no phantom cells, using touch and desktop inputs.

### Phase 3 — Flat world and chunk system

1. Correct default layer profile.
2. Chunk data and block edits.
3. Opaque-face culling and partial/transparent model handling.
4. Neighbor connections, chunk border changes and collision.
5. Render-distance/loading behavior and performance profile.

**Gate:** flat terrain visually extends beyond the camera's initial view and can be built on; moving across chunk boundaries doesn't create holes, gaps or input errors.

### Phase 4 — Real asset catalog and inventory

1. Build all inventory items from the validated registry, not a hand-written short demo array.
2. Generate real model thumbnails with materials.
3. Implement categories, scrolling, search, family grouping, tooltips and hotbar assignment.
4. Run catalog coverage checks and sample every category.

**Gate:** 100% of valid inventory assets appear in either categories or search; unsupported files are explicitly documented and no supported asset is silently omitted.

### Phase 5 — Block state families and interactions

Implement the state families that are supported by the supplied asset library, in order of usefulness: logs/orientation; slab/stair; doors/trapdoors; fences/walls/panes; lights/buttons/levers/pressure plates; signs/containers; decorative multi-cell pieces; fluid-like special cases if feasible. Add any state family only with appropriate geometry, collision, targeting, placement and save/load support.

**Gate:** each implemented state family has automated or manual test cases documented, and visual state matches stored data.

### Phase 6 — Save/load and Android reliability

1. Create/load/save menu.
2. Versioned world schema, autosave, error handling and backup.
3. Options/settings and touch scaling.
4. Full save/load round trip, app restart, and large-world tests.
5. Test on the target Android editor/device if available.

**Gate:** save/load round trip passes; no corrupt save or unexplained crash during repeated edits.

### Phase 7 — Android export and final QA

1. Verify Android export templates/SDK requirements for the actual installed Godot 4.7.2 environment.
2. Build an APK only if the build environment, templates and required configuration exist. If they don't, explain exactly what's missing and give the user the full export-ready source; never claim an APK was built when it wasn't.
3. Confirm renderer fallbacks, asset inclusion, startup scene, screen scaling, permissions, package ID and app launch.
4. Run the acceptance checklist below and write a candid final report with screenshots/video if supported.

## 14. Automated and manual test requirements

Implement a lightweight test harness or test scripts if possible. At minimum cover:

### Asset and material
- every asset file has a hash/record;
- every GLB can be imported or has a logged reason it cannot;
- every model's external texture dependencies resolve;
- no valid assigned material silently replaced with a debug color;
- maps matched by deterministic path/metadata, with ambiguous ones reported;
- thumbnails and in-world render verified for representative classes.

### Grid/world
- positive and negative coordinate conversion;
- correct face-neighbor placement for all six faces;
- correct removal and neighbor-face update;
- chunk boundary rebuild at edge/corner;
- chunk unload/reload preserves blocks;
- ground layer y positions and spawn position are correct;
- no player stuck/falls through on spawn.

### Controls/inventory
- touch drag rotates camera without moving the player unless the movement joystick is held;
- placing/breaking triggers once correctly;
- inventory UI interaction doesn't accidentally break/place in the background;
- selecting each hotbar slot works;
- search is case-insensitive and recognizes aliases;
- every valid registry entry is discoverable;
- flight toggling and rise/descend work reliably.

### Block states
- each supported directional block orientation;
- slab top/bottom/merge;
- stairs facing/half/corners where implemented;
- doors/beds multi-cell placement/removal consistency;
- fence/wall/pane connections and updates;
- transparent geometry selection and render order;
- selection/collision profile is consistent with actual geometry.

### Save/load/performance
- place many blocks in multiple chunks, save, quit, restart, reload and verify exact state;
- malformed save is handled without taking down the game;
- profile target Android device, record FPS/frame time and startup/import time;
- test a stress structure and distant edits; avoid uncontrolled memory growth;
- run for several minutes of continuous building and inventory searching without crashes or broken input.

## 15. Final deliverables

Do not stop at the first preview. Deliver:

1. Full Godot **4.7.2** source project that can be imported by selecting its `project.godot`.
2. A clear `README.md` with Android and desktop/development controls, import steps, how to run, how to save/load and known limitations.
3. Asset inventory/coverage reports and missing asset issues.
4. Reproducible build/test scripts and logs.
5. Screenshot(s) of the actual game running with real textured models in world, plus inventory search and placement/break interaction, if the environment supports screenshots.
6. APK only if truly built and tested; otherwise provide a clear export-readiness checklist and exact blockers.
7. A final status table with `implemented + tested`, `implemented but untested`, `partial`, `missing`, and `blocked by environment` states. Include exact Godot version used.

### Definition of done

The first deliverable is done only when the user can open the Godot 4.7.2 project, enter a flat creative world on Android, move/look/fly, search an inventory sourced from the complete audited library, place and break real textured blocks correctly, and save/reload a build without losing changes. Screenshots of an attractive block gallery, project configuration edits, a successful ZIP extraction, or a lone gray ground plane do **not** meet the definition of done.

---

## Research/use instructions for you, the coding AI

Before implementing each uncertain behavior, consult the primary/current source links in `docs/research_sources.md` or the source register accompanying this prompt. Prioritize official Minecraft/Microsoft Creator documents for Bedrock mobile and flat-world behavior, and official Godot **4.7** documentation for engine API usage. Community wikis and projects are secondary cross-checks, not automatically authoritative. If current sources disagree, document the difference and use the documented Bedrock mobile target for this project.

At the start, produce a short source-grounded technical plan and then begin Phase 0 immediately. Continue phase-by-phase without asking the user to approve every small decision. Ask a question only when a critical ambiguity cannot be resolved from this prompt, project files, or reliable documentation.

Do not overclaim “exactly Minecraft” as a legally or technically perfect recreation. The goal is high behavioral fidelity to the specified Minecraft creative flat-world experience, using original implementation and the user's supplied assets. Record deviations clearly and keep the architecture extensible.

---

## Reference sources (primary and supporting)

This reference set underpins the gameplay, versioning, asset and architecture requirements. A source register file can be maintained/extended during implementation. Some topics differ between Bedrock and Java; use the profile in Section 2 to resolve those differences.

### Minecraft / Microsoft — controls, creative inventory, flat worlds, blocks and item data

1. [Minecraft Controls — official Minecraft website](https://www.minecraft.net/en-us/article/minecraft-controls) — touch, keyboard/mouse and controller conventions.
2. [Minecraft — 1.21.80 Bedrock release notes](https://feedback.minecraft.net/hc/en-us/articles/36236281562637-Minecraft-1-21-80-Bedrock) — flat world presets in Bedrock.
3. [Minecraft — 1.21.100 Bedrock release notes](https://feedback.minecraft.net/hc/en-us/articles/38581287884557-Minecraft-1-21-100-Bedrock) — Void preset and current flat-world development context.
4. [Bedrock control schemes](https://github.com/MicrosoftDocs/minecraft-creator/blob/main/creator/Documents/ControlSchemes.md) — mobile/control modes.
5. [Java and Bedrock differences](https://learn.microsoft.com/en-us/minecraft/creator/documents/differencesbetweenbedrockandjava) — avoid merging edition-specific details.
6. [World generation overview](https://learn.microsoft.com/en-us/minecraft/creator/documents/world-generation?view=minecraft-bedrock-stable) — generation concepts.
7. [Default Minecraft block listings](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/vanillalistingsreference/blocks?view=minecraft-bedrock-stable) — block IDs and states reference.
8. [Default Minecraft item listings](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/vanillalistingsreference/items?view=minecraft-bedrock-stable) — item inventory cross-reference.
9. [Default Minecraft entity listings](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/vanillalistingsreference/entities?view=minecraft-bedrock-stable) — optional entity coverage reference; no hostile spawns in the default project.
10. [Vanilla content listings overview](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/vanillalistingsreference/?view=minecraft-bedrock-stable).
11. [Block JSON documentation](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/).
12. [Block states and permutations](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/examples/blockstatesandpermutations?view=minecraft-bedrock-stable).
13. [Block components list](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/examples/blockcomponents/blockcomponentslist).
14. [Block description](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/examples/blockdescription?view=minecraft-bedrock-stable).
15. [Block collision box](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/examples/blockcomponents/minecraftblock_collision_box?view=minecraft-bedrock-stable).
16. [Block selection box](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/examples/blockcomponents/minecraftblock_selection_box?view=minecraft-bedrock-stable).
17. [Block geometry](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/examples/blockcomponents/minecraftblock_geometry?view=minecraft-bedrock-stable).
18. [Block material instances](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/examples/blockcomponents/minecraftblock_material_instances?view=minecraft-bedrock-stable).
19. [Block traits](https://learn.microsoft.com/en-us/minecraft/creator/documents/intro-block-traits?view=minecraft-bedrock-stable).
20. [Placement direction trait](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/examples/traits/placement_direction?view=minecraft-bedrock-stable).
21. [Vanilla block tags](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/blockreference/examples/vanillablocktags?view=minecraft-bedrock-stable).
22. [Item JSON documentation](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/itemreference/examples/itemdefinition?view=minecraft-bedrock-stable).
23. [Item component list](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/itemreference/examples/itemcomponentlist?view=minecraft-bedrock-stable).
24. [Item `minecraft:item` schema](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/itemreference/examples/itemcomponents/minecraft_item?view=minecraft-bedrock-stable).
25. [Block placer component](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/itemreference/examples/itemcomponents/minecraft_block_placer?view=minecraft-bedrock-stable).
26. [Entity placer component](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/itemreference/examples/itemcomponents/minecraft_entity_placer?view=minecraft-bedrock-stable).
27. [Creative crafting item catalog](https://github.com/MicrosoftDocs/minecraft-creator/blob/main/creator/Documents/CraftingItemCatalogDocumentation.md) — grouping and ordering concepts.
28. [Item menu category](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/itemreference/examples/itemcomponents/description_component?view=minecraft-bedrock-stable).
29. [Resource pack comprehensive contents](https://learn.microsoft.com/en-us/minecraft/creator/documents/comprehensivepackcontents?view=minecraft-bedrock-stable).
30. [Entity JSON documentation](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/entityreference/).
31. [Entity components guide](https://learn.microsoft.com/en-us/minecraft/creator/documents/entitycomponentsguide?view=minecraft-bedrock-stable).
32. [Creating new entity types](https://learn.microsoft.com/minecraft/creator/documents/introductiontoaddentity).
33. [Animations overview](https://learn.microsoft.com/en-us/minecraft/creator/documents/animations/animationsoverview?view=minecraft-bedrock-stable).
34. [Animation controllers](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/animationsreference/examples/animationcontroller?view=minecraft-bedrock-stable).
35. [Animation vs. animation controllers](https://learn.microsoft.com/en-us/minecraft/creator/documents/animationsvscontrollers?view=minecraft-bedrock-stable).
36. [Particle introduction](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/particlesreference/particlesintroduction?view=minecraft-bedrock-stable).
37. [Particle document](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/particlesreference/examples/particlecomponents/particle_document?view=minecraft-bedrock-stable).
38. [Structure blocks introduction](https://learn.microsoft.com/en-us/minecraft/creator/documents/structures/introductiontostructureblocks?view=minecraft-bedrock-stable).
39. [Structure command tutorial](https://learn.microsoft.com/en-us/minecraft/creator/documents/structures/structureblockscommandtutorial?view=minecraft-bedrock-stable).
40. [Command introduction](https://learn.microsoft.com/en-us/minecraft/creator/documents/commandsintroduction?view=minecraft-bedrock-stable).
41. [Command list reference](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/commandsreference/examples/commandlist?view=minecraft-bedrock-stable).
42. [`/setblock` reference](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/commandsreference/examples/commands/setblock?view=minecraft-bedrock-stable).
43. [`/summon` reference](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/commandsreference/examples/commands/summon?view=minecraft-bedrock-stable).
44. [Minecraft Java 26.3 release notes — creative inventory order](https://www.minecraft.net/en-us/article/minecraft-java-edition-26-3) — only for the comparative inventory principles, not as the Bedrock UI specification.
45. [Creative inventory rework snapshot notes](https://feedback.minecraft.net/hc/en-us/articles/9994475500301-Minecraft-Java-Edition-Snapshot-22w42a).
46. [Bedrock flat presets 1.21.80 beta notes](https://feedback.minecraft.net/hc/en-us/articles/35325653515149-Minecraft-Beta-Preview-1-21-80-22).
47. [Bedrock flat preset feedback/context](https://feedback.minecraft.net/hc/en-us/community/posts/34913377078157).
48. [Official Java/Bedrock keyboard and mobile controls, alternate article path](https://www.minecraft.net/article/minecraft-controls).

### Minecraft Wiki / technical cross-checks

49. [Superflat](https://minecraft.wiki/w/Superflat).
50. [Flat level generator preset tag](https://minecraft.wiki/w/Flat_level_generator_preset_tag_%28Java_Edition%29).
51. [Block states](https://minecraft.fandom.com/wiki/Block_states).
52. [Stairs](https://minecraft.fandom.com/wiki/Stairs).
53. [Fence block states](https://minecraft.wiki/w/Fence/BS).
54. [Water block states](https://minecraft.wiki/w/Water/BS).
55. [Waterlogging](https://minecraft.fandom.com/wiki/Waterlogging).
56. [Resource pack](https://minecraft.fandom.com/wiki/Resource_pack).
57. [Tutorial: models](https://minecraft.fandom.com/wiki/Tutorials/Models).
58. [Blockstates definition format](https://minecraft.wiki/w/Blockstates_definition/format).
59. [Creative mode](https://minecraft.fandom.com/wiki/Creative).
60. [Inventory](https://minecraft.fandom.com/wiki/Inventory).
61. [Tutorial: Bedrock menu screen](https://minecraft.wiki/w/Tutorial%3AMenu_screen/Bedrock_Edition).
62. [Tutorial: Java menu screen](https://minecraft.wiki/w/Tutorial%3AMenu_screen/Java_Edition).
63. [Create New World](https://minecraft.fandom.com/wiki/Create_New_World).
64. [Crafting](https://minecraft.fandom.com/wiki/Crafting).
65. [Crafting table](https://minecraft.fandom.com/wiki/Crafting_Table).
66. [Redstone repeater](https://minecraft.fandom.com/wiki/Redstone_Repeater).
67. [Glass overview](https://minecraft.wiki/w/Glass_%28disambiguation%29).
68. [World boundary](https://minecraft.fandom.com/wiki/World_boundary).
69. [Block hardness](https://minecraft.wiki/w/Block_hardness).
70. [Block properties: legacy solid](https://minecraft.wiki/w/Block_properties/Solid_%28legacy%29).
71. [Control schemes reference](https://github.com/MicrosoftDocs/minecraft-creator/blob/main/creator/Documents/ControlSchemes.md).
72. [Pick block controls/mechanics](https://wiki.ronlab.site/content/minecraftwiki_en_all_maxi_2025-11/Pick_Block).
73. [Superflat survival tutorial](https://minecraft.wiki/w/Tutorial%3ASuperflat_survival).
74. [Flat survival tutorial](https://minecraft.wiki/w/Tutorial%3AFlat_survival).
75. [Beginner's guide](https://minecraft.wiki/w/Tutorial%3ABeginner%27s_guide).
76. [Saved Hotbar inventory concepts](https://minecraft.fandom.com/wiki/Inventory).
77. [Model systems reference from MinecraftForge documentation](https://docs.minecraftforge.net/en/1.21.x/resources/client/models/).

### Godot engine documentation — version-specific implementation

**Prefer Godot 4.7 documentation and the actual 4.7.2 engine for implementation choices. Stable/latest docs can lag a specific release; verify each API in the installed build.**

78. [Godot 4.7 project organization](https://docs.godotengine.org/en/4.7/tutorials/best_practices/project_organization.html).
79. [Godot 4.7 rendering architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html).
80. [Renderer overview](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html).
81. [Godot system requirements](https://github.com/godotengine/godot-docs/blob/master/about/system_requirements.rst).
82. [Importing 3D scenes](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html).
83. [Importing scenes (older, secondary cross-check)](https://docs.godotengine.org/en/3.6/tutorials/assets_pipeline/importing_scenes.html).
84. [Model export considerations](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.html).
85. [Import configuration](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html).
86. [Importing images](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html).
87. [StandardMaterial3D](https://docs.godotengine.org/en/stable/classes/class_standardmaterial3d.html).
88. [ORMMaterial3D](https://docs.godotengine.org/en/stable/classes/class_ormmaterial3d.html).
89. [Image](https://docs.godotengine.org/en/stable/classes/class_image.html).
90. [ImageTexture](https://docs.godotengine.org/en/stable/classes/class_imagetexture.html).
91. [Texture](https://docs.godotengine.org/en/stable/classes/class_texture.html).
92. [MeshInstance3D](https://docs.godotengine.org/en/stable/classes/class_meshinstance3d.html).
93. [GridMap](https://docs.godotengine.org/en/stable/classes/class_gridmap.html).
94. [Using GridMaps](https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html).
95. [MultiMesh optimization](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).
96. [MultiMesh class](https://docs.godotengine.org/en/stable/classes/class_multimesh.html).
97. [Optimizing 3D performance](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html).
98. [General performance optimization](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization_tips.html).
99. [Using servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html).
100. [Physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html).
101. [Ray casting](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html).
102. [RayCast3D class](https://docs.godotengine.org/en/stable/classes/class_raycast3d.html).
103. [PhysicsDirectSpaceState3D](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html).
104. [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html).
105. [InputEventScreenTouch](https://docs.godotengine.org/en/stable/classes/class_inputeventscreentouch.html).
106. [InputEventScreenDrag](https://docs.godotengine.org/en/stable/classes/class_inputeventscreendrag.html).
107. [InputMap](https://docs.godotengine.org/en/stable/classes/class_inputmap.html).
108. [Input event tutorial](https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html).
109. [Controller/gamepad input](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html).
110. [Touchscreen button class](https://docs.godotengine.org/en/stable/classes/class_touchscreenbutton.html).
111. [SpringArm3D](https://docs.godotengine.org/en/stable/classes/class_springarm3d.html).
112. [WorldEnvironment](https://docs.godotengine.org/en/stable/classes/class_worldenvironment.html).
113. [Environment](https://docs.godotengine.org/en/stable/classes/class_environment.html).
114. [FastNoiseLite](https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html) — relevant for comparison but **not** to generate hills in the required flat world.
115. [ArrayMesh](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html).
116. [ImmediateMesh](https://docs.godotengine.org/en/stable/classes/class_immediatemesh.html).
117. [PackedScene](https://docs.godotengine.org/en/stable/classes/class_packedscene.html).
118. [ResourceUID](https://docs.godotengine.org/en/stable/classes/class_resourceuid.html).
119. [JSON](https://docs.godotengine.org/en/stable/classes/class_json.html).
120. [FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html).
121. [DirAccess](https://docs.godotengine.org/en/stable/classes/class_diraccess.html).
122. [ConfigFile](https://docs.godotengine.org/en/stable/classes/class_configfile.html).
123. [Runtime file loading and saving](https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html).
124. [Saving games](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html).
125. [Godot file/data I/O overview](https://docs.godotengine.org/en/stable/tutorials/io/).
126. [AnimationPlayer and AnimationTree overview](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html).
127. [AnimationTree class](https://docs.godotengine.org/en/stable/classes/class_animationtree.html).
128. [AudioStreamPlayer](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer.html).
129. [Reducing pipeline compilation stutter](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html).
130. [Android export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html).
131. [Android Gradle builds](https://docs.godotengine.org/en/stable/tutorials/export/android_gradle_build.html).
132. [Exporting projects](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html).
133. [Physics interpolation quick start](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_quick_start_guide.html).
134. [Decals](https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html) — optional visual technique only, not a replacement for block textures.

### Voxel/block-world architecture and data schemas

135. [Zylann Voxel Tools repository](https://github.com/Zylann/godot_voxel) — inspect compatibility/licensing before depending on the extension.
136. [Voxel Tools overview](https://github.com/Zylann/godot_voxel/blob/master/doc/source/overview.md).
137. [Voxel Tools blocky terrain](https://github.com/Zylann/godot_voxel/blob/master/doc/source/blocky_terrain.md).
138. [Voxel Tools quick start](https://github.com/Zylann/godot_voxel/blob/master/doc/source/quick_start.md).
139. [VoxelTerrain API](https://github.com/Zylann/godot_voxel/blob/master/doc/source/api/VoxelTerrain.md).
140. [PrismarineJS minecraft-data docs](https://prismarinejs.github.io/minecraft-data/).
141. [minecraft-data API documentation](https://github.com/PrismarineJS/minecraft-data/blob/master/doc/api.md).
142. [minecraft-data block schema](https://github.com/PrismarineJS/minecraft-data/blob/master/schemas/blocks_schema.json).
143. [minecraft-data Bedrock reference](https://github.com/PrismarineJS/minecraft-data/blob/master/doc/bedrock.md).
144. [Minecraft blockstates/model system — Forge docs](https://github.com/MinecraftForge/Documentation/blob/1.21.x/docs/resources/client/models/index.md).
145. [Minecraft Wiki technical details and mechanics project](https://minecraft.wiki/w/Minecraft_Wiki%3AProjects/Technical_details_and_mechanics).
146. [Minecraft Flat world preset generator](https://mctools.gg/flat-world-generator).

### Notes on the breadth of the web research

Searches covered official Minecraft/Microsoft Creator reference material, Minecraft wiki mechanics, Godot API/tutorial pages, and voxel-engine/data-schema projects. Results include overlapping pages and versioned variants; do not infer that the number of search-result entries equals the number of distinct sources. For any implementation claim that may have changed in a recent release, verify the relevant current page directly and record the version/date in the build report. If more source review is needed for a specific complex feature (e.g. every redstone component), extend this register with the exact pages consulted before implementing it.