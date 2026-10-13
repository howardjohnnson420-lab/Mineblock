# Reference Profile

## Target

- Primary behavioral reference: Minecraft Bedrock Edition on Android/mobile, Creative mode, Classic Flat world.
- Target engine: Godot 4.7.2 stable, GDScript, Mobile renderer as initial choice.
- Source assets: only the user-supplied archive set for models and material maps. No Mojang proprietary assets, downloaded third-party model packs, or external runtime add-ons are used.
- No hostile creature spawning. The supplied registry contains no living-creature model/animation set, so living-mob AI/spawn eggs are not fabricated; the supplied armor stand is a static display prop and not a simulated living entity.
- Intended play loop: first-person movement/flying, model selection from a searchable creative catalog, direct block placement/removal, and local world persistence.

## Flat-world convention

The grid uses integer cell centers. One world unit represents one Minecraft-like block. The classic four-layer profile is grass at `y=0`, dirt at `y=-1`, dirt at `y=-2`, and bedrock at `y=-3`. The player starts just above the grass surface. Missing terrain edits are stored separately so procedural ground remains effectively unbounded in X/Z and can be streamed as nearby chunks are needed.

## Mobile controls

Large on-screen touch controls provide movement, look drag, jump, flight toggle, rise/descend, break, place/use, hotbar select, inventory and menu. This HUD is a first implementation and has not been tested on a phone; safe-area, touch conflict and accessibility validation remain outstanding.

## Inventory semantics

The supplied registry contains 1,245 models: 944 in Construction, 240 in Nature, 56 in Equipment, and 5 in Items. The game exposes these registry entries through Construction, Equipment, Items, Nature and All tabs plus case-insensitive search. Entries remain discoverable even when their per-family Minecraft-like behavior is not implemented. Model presence is not proof that the matching Minecraft mechanic is implemented.

## Intentional exclusions and deviations

The first deliverable prioritizes creative building and peaceful construction. Survival progression, hunger, durability loss, crafting requirements, hostile AI, multiplayer, Nether/End gameplay, commands with side effects, achievements and official account integration are out of scope. Family-specific source logic now covers slab/stair geometry and state, axis-oriented blocks, paired doors/beds/tall plants, connected barriers, interactable signs and container-like objects, basic buttons/levers/plates and redstone circuits, pistons/TNT, simple flowing fluids and reactions, falling blocks, rails, hoppers, daylight sensors and a day/night cycle. These systems remain runtime-unverified and several intentionally approximate vanilla behavior; see `reports/mechanic_coverage.md`.

## Reference sources

- Minecraft official controls: https://www.minecraft.net/en-us/article/minecraft-controls
- Microsoft Creator control schemes: https://github.com/MicrosoftDocs/minecraft-creator/blob/main/creator/Documents/ControlSchemes.md
- Bedrock flat-world release context: https://feedback.minecraft.net/hc/en-us/articles/36236281562637-Minecraft-1-21-80-Bedrock
- Bedrock block listing reference: https://learn.microsoft.com/en-us/minecraft/creator/reference/content/vanillalistingsreference/blocks?view=minecraft-bedrock-stable
- Bedrock item listing reference: https://learn.microsoft.com/en-us/minecraft/creator/reference/content/vanillalistingsreference/items?view=minecraft-bedrock-stable
- Godot 4.7 GLB/import, rendering and scene API reference: https://docs.godotengine.org/en/4.7/classes/index.html
- Godot 4.7 GridMap reference used as an architecture comparison (not as an external plugin dependency): https://docs.godotengine.org/en/4.7/classes/class_gridmap.html

The links are implementation references, not evidence that this project has passed runtime tests.