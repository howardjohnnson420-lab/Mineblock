# Mechanics coverage and verification ledger

Updated 2026-10-13 after paired-block geometry, state-driven interaction, sensor, candle and composter visual regression updates.

**Status meanings**

- **Source implemented — unverified:** the project code includes this behavior, but Godot 4.7.2 has not been launched here, so parser/import/physics/render correctness is not certified.
- **Partial / approximate:** a simplified implementation exists; the listed deviations are material and it must not be described as vanilla-equivalent.
- **Not implemented / no supplied asset:** code or source content is absent by design or because the supplied library has no required model/animation/data; no fallback proprietary Minecraft files were downloaded.
- **Environment blocked:** requires an engine/editor/device/runtime absent from this build environment.

## Gameplay coverage matrix

| System | Status | Implemented in source | Remaining difference / required verification |
|---|---|---|---|
| Creative first-person loop | Source implemented — unverified | Keyboard/mouse and touch HUD paths; walking, jump, flight, break/place/use, hotbar and targeting | Test pointer capture, touch multitouch, player collision and all screen sizes in Godot and on Android. |
| Classic flat terrain | Source implemented — unverified | Grass `y=0`, dirt `y=-1/-2`, bedrock `y=-3`; 16×16 streamed chunk terrain and editable cell data | Chunk seams, negative coordinates, collision, load/unload and performance are not runtime tested. |
| Full cube/model placement | Source implemented — unverified | Registry-driven GLB scenes, grid cell IDs, approximate bounds-based collisions | Asset pivot/origin corrections and non-cube collision fidelity need visual tests. |
| PBR material resolution | Source implemented — unverified | Supplied base-colour, normal, ORM and height map paths; material cache; optional WebP albedo/normal/roughness/displacement path; blend water shader | Actual import, UVs, shader compilation, roughness/metallic channel appearance, alpha sorting and height-normal details need in-engine QA. |
| Runtime item previews | Source implemented — unverified | Model-based SubViewport previews use real GLB geometry and resolver materials | No rendered thumbnail screenshot has been captured; 1,245 assets must be inspected after import. |
| Axis blocks | Source implemented — unverified | Logs/wood/stems/pillars rotate according to axis derived from placed face | Special blocks such as chains/rods are currently included in a broad family heuristic; validate each shape. |
| Slabs | Source implemented — unverified | Top/bottom half states, half-height custom mesh/collider, double-slab merge on opposite half hit | Merge/input, model material orientation and collision require runtime test; waterlogging and variant merging are not implemented. |
| Stairs | Partial / approximate | Top/bottom state, straight shape and neighbor-derived inner/outer corner state; procedural mesh and multiple collision boxes | Facing/corner generation is simplified and not verified against Bedrock shape tests; upside-down stair and exact selection/collision need engine QA. |
| Doors | Partial / approximate | Two-cell lower/upper occupancy records with one cell-sized panel/collider per half, stored facing/hinge/open/powered fields, use and redstone toggling, paired removal/save; previously placed doors remain after support loss | Placement orientation/hinge choice and swing geometry are approximate; upper-half input and collision need testing. |
| Trapdoors and fence gates | Partial / approximate | Open/closed state, transforms and basic redstone toggle | Mounting face rules, collision on every orientation, hinge behavior, redstone edge cases and visuals are approximate. |
| Fences, walls, iron bars and panes | Partial / approximate | Stored cardinal connection masks, neighbor updates, procedural arms and per-arm approximate colliders/selection tests | Connection eligibility and the exact multiple-height/wall-post rules differ from vanilla; transparent panes need render-order and neighbor tests. |
| Beds | Partial / approximate | Two-cell foot/head occupancy records with distinct per-cell mattress geometry/colliders and a head pillow, facing, paired cleanup and bed interaction setting a saved creative spawn position | Bed yaw/shape/pillow textures and spawn respawn semantics are not vanilla sleeping; respawn/game-over system is absent in Creative scope. |
| Candles and candle cakes | Partial / approximate | Candle counts 1–4 are saved; selecting/using the matching candle adds a candle, other use toggles lit state; candle clusters instantiate the supplied candle GLB and lit candles have a small light; candle cakes toggle lit state | Count layout and light power/range are approximate; flame particles, audio, water extinguishing and exact cake interaction are absent. |
| Tall plants | Partial / approximate | Two-cell lower/upper records, paired deletion and save state, initial ground placement validation; previously placed plants remain after support loss | The model library does not expose separately addressable vanilla foot/head meshes; both halves are generated from the mapped bed material with distinct geometry. Attachment/render fidelity needs testing. |
| Signs and banners | Partial / approximate | Editable text on sign families using Label3D, saved state, basic floor/wall orientation profiles | Front/back text, fonts, line wrapping, glow/sign interactions, banner patterns and exact hanging-sign attachment are incomplete. |
| Containers and shelves | Partial / approximate | 27 saved item-ID slots for container/machine families, three persisted item slots for shelf-family blocks, slot swapping with hotbar and a basic container fullness comparator signal | No item stack counts, item-specific insertion rules, double-chest merge, shulker contents semantics, shelf-specific redstone signal rules, furnace recipes/fuel, brewing, dispenser ejection or crafter recipes. |
| Hopper | Partial / approximate | Transfers one item ID per 0.4 seconds between 27-slot containers above/below | No stack counts, hopper facing/filtering/locking, sided inventory rules, minecart hoppers or item entities; not vanilla hopper simulation. |
| Buttons, levers and pressure plates | Partial / approximate | Lever toggle; timed button; player-overlap pressure-plate detection; powered state persists and triggers recalculation | No entity-weight variants, wooden plate item/projectile sensitivity, exact pulse/tick timings or mounting-face fidelity. |
| Bell and sculk sensor | Partial / approximate | Bell interaction stores a timed ringing state and rotates the supplied model; block edits/player motion in 8-cell range activate sculk sensors with distance-derived 1–15 power and a cooldown | No bell hit-direction/projectile behavior, vibration frequency filtering, occlusion, wool dampening, calibrated sensor frequency, shrieker integration, particles or audio. |
| Composter | Partial / approximate | Creative use advances a saved level 0–8 from a curated whitelist, shows fill using supplied dirt PBR material, ready level can be emptied, comparator output follows level | Compost chances are deterministic rather than randomized; no bone-meal item inventory/result stack, exact Bedrock accepted-item rates, or full composter animation. |
| Redstone dust/wire | Partial / approximate | Fresh-pass power solve with power decay, connections, signal strength and visual glow | Vanilla side/up/down dust routing, quasi-connectivity, repeater locks, conduction rules, update ordering and short-circuit edge cases are not fully modeled. |
| Repeaters/comparators | Partial / approximate | Directional input, delayed repeater output, compare/subtract comparator modes and container fullness level | Exact game-tick timing, diode side-input semantics, comparator target blocks, analog output formula and locks are incomplete. |
| Redstone lamps/torches/copper bulbs | Partial / approximate | Powered lamp glow, torch support inversion and copper-bulb rising-edge toggle that persists when input falls | Exact emissive textures, lighting propagation and full vanilla update/tick order need visual/logic tests. |
| Pistons/sticky pistons | Partial / approximate | Basic extend/retract, up-to-12-cell row movement, piston head, limited sticky pull, pushability-profile check, save states | Does not implement full vanilla push reaction table, slime/honey attachment, quasi-connectivity, block event ordering, block drops, slime block rules, or exact moving animation. |
| TNT | Partial / approximate | Ignition and delayed radius removal; paired structures are removed safely with affected blocks | Explosion force, ray resistance, chain reaction timing, entity damage/knockback/particles/sound and exact blast resistance are absent or approximate. |
| Water/lava | Partial / approximate | Source and level state, deterministic spread through air, bounded flow cells and simple water/lava conversion to obsidian/cobblestone | No true fluid tick model, falling-column edge cases, infinite-source rules, waterlogging, bubble columns, lava lighting/fire, bucket pickup/place or exact Bedrock reaction rules. |
| Falling blocks | Partial / approximate | Sand/gravel/concrete powder/anvil-family cells move down, displace replaceable plants/fluids/dust, and leave ordinary unsupported blocks stationary | One-cell periodic simulation rather than vanilla falling entities/gravity; landing effects, damage, support exceptions and falling animation are absent. |
| Rails | Partial / approximate | Straight/curved neighbor shape inference and basic orientation | No slopes, powered/detector/activator rail power behavior, minecart movement, switches or curves validated. |
| Daylight detector/day-night | Partial / approximate | Simulated 20-minute cycle changes sun/ambient lighting; sensor emits daylight-derived 0–15 level and can invert | Not tied to real elapsed-world time, skylight occlusion/weather/moon/sun calculations or exact in-game tick rate. |
| Armor stand | Partial / approximate | Supplied armor-stand GLB can be displayed in the world and is classified as a display object | No equipment slots, pose editing, physics, damage, gravity or entity AI. |
| Living entities / spawn eggs | Not implemented / no supplied asset | No living-mob spawning; hostile spawning intentionally disabled | The audited registry contains no living-creature model/animation set or spawn-egg assets. Do not invent or download third-party models. |
| Crop growth / farming | Not implemented / partial | Plant-like assets are classified, placed and persisted | No random ticks, farmland moisture, growth stages, harvesting, bonemeal, breeding, mob interactions or crop drops. |
| Crafting, survival, hunger, durability | Not implemented / out of scope | Creative no-consumption placement is the primary mode | Explicitly excluded by the supplied master prompt's first-deliverable priorities. |
| Multiplayer, commands, Nether/End, Mojang sign-in | Not implemented / out of scope | None | Explicitly out of scope for this offline, peaceful first release. |
| Save/load | Source implemented — unverified | Versioned JSON, temp/backup write, placed family state, pair cells, terrain removals, player/spawn/day-cycle/hotbar/settings | Must run the included Godot smoke test and manually exit/relaunch to verify atomicity and round trip. |
| APK/export | Environment blocked | Export-readiness guide and source project | Godot 4.7.2, export templates, Android SDK/JDK and device were unavailable; no APK exists. |

## Explicit support/floating policy

- **Floating ordinary blocks are intentional.** Stone, dirt, planks, slabs, stairs, fences and other ordinary building blocks remain after their support/neighbors are removed. These blocks do not get gravity.
- **Support-dependent blocks** are resolved only when `BlockBehaviors.requires_support(id, state)` marks them as requiring support. Torches, plants, rails, redstone dust, carpets/thin layers, pressure plates, signs, doors, beds and similar attachments are removed if their required support is no longer valid. No arbitrary adjacent block is cascade-deleted.
- Pair cleanup is atomic for doors, beds and two-cell tall plants. Sand, gravel, concrete powder and anvils use a separate falling-block simulation and can displace replaceable plants/fluids.
- The support/falling behaviors, per-cell door/bed geometry, copper-bulb edge state, shelf slots, candle count rendering, composter levels, bell state and sculk event path have source-contract checks and a Godot runtime smoke test authored; that runtime test remains unexecuted until Godot 4.7.2 is available.

## Asset coverage remains separate from mechanics coverage

- Model registry: 1,245 stable IDs; all are reachable in the inventory catalog.
- Source files: 1,983, each with one audit/coverage disposition.
- Core PNG sets: 90 each base colour, normal, ORM, height.
- Optional WebP sets: 90 each albedo, normal, roughness, displacement.
- Files excluded from runtime gameplay: supporting docs/catalogues/manifests/checksums, audit/template files, the legacy preview scene/scripts and legacy `project.godot`. They are preserved in source assets where supplied and explicitly listed in `reports/asset_usage_and_nonuse.md`.
- `thumbnail_verified`, `world_placement_verified`, and `material_verified` remain `false` until real Godot-rendered/placed tests are completed; existence of a GLB or a source code path is not visual proof.

## Verification performed in this environment

- `python tests/test_project_consistency.py` — passed static filesystem/registry/map-path consistency checks.
- `python tests/test_mechanics_contracts.py` — checks expected functions/families, floating-after-support-removal contract, paired visuals, redstone logic, item/container interactions, candle/composter visuals and sculk/bell state paths. The latest run result is recorded in `reports/latest_static_tests.json`.
- `tests/runtime_smoke.gd` — written for Godot, but **not executed** because Godot 4.7.2 is not installed and the release download host could not be resolved from this environment.
- No claim of parser success, visual correctness, Android performance, or playability is made until the runtime gates pass.