#!/usr/bin/env python3
"""Static source-contract tests, distinct from the unexecuted Godot runtime suite."""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAMILIES = {
    "slab": ["oak_slab", "stone_slab"],
    "stairs": ["oak_stairs", "stone_stairs"],
    "door": ["oak_door", "iron_door"],
    "trapdoor": ["oak_trapdoor", "iron_trapdoor"],
    "fence": ["oak_fence"],
    "connected_barrier": ["glass_pane", "iron_bars", "cobblestone_wall"],
    "bed": ["white_bed"],
    "tall_plant": ["sunflower", "tall_grass", "large_fern"],
    "fluid": ["water", "lava"],
    "redstone_wire": ["redstone_wire"],
    "repeater": ["redstone_repeater"],
    "comparator": ["redstone_comparator"],
    "piston": ["piston", "sticky_piston"],
    "piston_head": ["piston_head"],
    "container": ["chest", "barrel"],
    "machine_container": ["hopper", "furnace", "dispenser", "dropper"],
    "daylight_sensor": ["daylight_detector"],
    "copper_bulb": ["copper_bulb"],
    "shelf": ["oak_shelf"],
    "explosive": ["tnt"],
}


def require(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)


def main() -> int:
    behavior = (ROOT / "scripts/block_behaviors.gd").read_text(encoding="utf-8")
    world = (ROOT / "scripts/world_manager.gd").read_text(encoding="utf-8")
    main_gd = (ROOT / "scripts/main.gd").read_text(encoding="utf-8")
    materials = (ROOT / "scripts/material_resolver.gd").read_text(encoding="utf-8")
    registry = json.loads((ROOT / "data/asset_registry.json").read_text(encoding="utf-8"))
    ids = {m["id"] for m in registry.get("models", [])}

    require("static func family_for_id" in behavior, "family resolver missing")
    for family, examples in FAMILIES.items():
        require(f'"{family}"' in behavior, f"family missing: {family}")
        for block_id in examples:
            require(block_id in ids, f"sample model is absent from supplied registry: {block_id}")

    functions = [
        "place_block", "remove_block", "use_block", "_update_connections_near",
        "_simulate_falling_blocks", "_recalculate_redstone", "_set_piston_extended",
        "_resolve_fluid_reactions", "_rebuild_fluid_spread", "_update_hoppers",
        "all_placed_for_save", "restore_state", "set_container_contents", "set_sign_text",
        "_has_valid_support", "_resolve_support_loss_near", "_trigger_sculk_sensors_near",
        "_trigger_sculk_sensors_from_player", "_activate_sculk_sensor", "_update_pressure_plates_and_buttons",
    ]
    for fn in functions:
        require(re.search(rf"func\s+{re.escape(fn)}\s*\(", world) is not None, f"missing world method: {fn}")

    # Target selection, UI interaction and map/material pathways.
    for token in ["world_time_seconds", "_update_day_night", "_build_selection_outline", "_commit_sign_text"]:
        require(token in main_gd, f"main script interaction path missing: {token}")
    require('model_id == "water": alpha_mode = "BLEND"' in materials, "water transparency path missing")
    require("float(cell.y) - 0.5 + fluid_height * 0.5" in world, "fluid cell Y alignment missing")
    require('state.has("pair_cell")' in world, "paired block removal missing")
    require("BlockBehaviors.is_virtual_pair_cell(state)" in world, "virtual upper-cell visual guard missing")

    # Crucial support behavior: ordinary blocks may float, attachments with explicit
    # support requirements must break when their support is removed. No blanket cascade.
    require("ordinary blocks (stone, planks, slabs, stairs, fences, etc.) intentionally stay" in world.lower(),
            "ordinary blocks must remain floating")
    require("if not BlockBehaviors.requires_support(candidate_id, candidate_state): continue" in world,
            "support resolver must only inspect explicitly dependent families")
    require("func remove_block(cell: Vector3i, resolve_neighbor_support: bool = true) -> bool:" in world,
            "guarded support cleanup signature missing")
    require("if resolve_neighbor_support:" in world and "remove_block(candidate, false)" in world,
            "support cleanup must avoid recursive cleanup loops")
    require("_resolve_support_loss_near(cell)" in world, "support resolver not called after edit")

    # Separate render records for one-cell pieces; virtual half applies only to tall plants.
    require('upper_state["paired_visual"] = false' in world, "door upper visual is not instantiated")
    require('head_state["paired_visual"] = false' in world, "bed head visual is not instantiated")
    require('upper_state["paired_visual"] = true' in world, "tall plant virtual upper state missing")
    require("model_root.scale.y *= 2.0" in world, "tall plant does not reuse a full-height model")
    require("# The supplied model is a single-cell panel." in world, "door geometry must remain cell-sized")
    require('Vector3(0.94, 0.375, 0.94)' in world and 'String(state.get("part", "foot")) == "head"' in world,
            "bed foot/head meshes must use per-cell geometry")
    require('Vector3(0.94, 0.5625, 0.94)' in world, "bed collider must be limited to one cell")
    require('var door_base_yaw := _yaw_for_facing(String(state.get("facing", BlockBehaviors._facing_from_yaw(yaw))))' in main_gd,
            "door target hit-test must use saved facing like the rendered panel")
    require('root_rotation.y = _yaw_for_facing(String(state.get("facing", BlockBehaviors._facing_from_yaw(yaw))))' in main_gd,
            "target outline must use saved facing for directional families")
    require("func _has_due_redstone_timer" in world, "repeater pending-time update missing")
    require('elif family == "copper_bulb":' in world and "previous_input" in world,
            "copper bulb does not implement rising-edge toggle")
    require('var max_slots := 3 if family == "shelf" else 27' in world,
            "three-slot shelf profile missing")
    require('''"door", "trapdoor", "fence_gate":
            if bool(state.get("powered", false)):
                action = "redstone_controlled"''' in world,
            "manually operated doors/gates must not override power")
    require("BlockBehaviors.is_replaceable(below_id)" in world, "falling blocks do not displace replaceable cells")
    require("_model_by_material_key" in materials, "material mode switch does not retain model metadata")
    require("_hopper_elapsed" in world and "_hopper_elapsed >= 0.4" in world, "hopper cadence missing")
    require("static func is_compostable_item" in behavior, "compost item whitelist missing")
    require('''"composter":''' in behavior and '"bell":' in behavior and '"sculk_sensor":' in behavior,
            "composter/bell/sculk default states missing")
    require('''"candle", "candle_cake":''' in world, "candle/candle-cake interaction missing")
    require('''"composter":''' in world and "composter_bone_meal" in world, "composter progression missing")
    require('''"bell":''' in world and "ring_until_ms" in world, "bell timed state missing")
    require("_activate_sculk_sensor" in world and 'family == "sculk_sensor"' in world,
            "sculk proximity event path missing")
    require("BlockBehaviors.is_pushable(moving_id, moving_state)" in world,
            "piston should consult block pushability profiles")
    require('''extra_candle.name = "CandleVariant_%d"''' in world and "range(1, candle_count)" in world,
            "candle block count must render additional supplied model instances")
    require('''fill_mesh.name = "ComposterFill"''' in world and "resolver.material_for_model(dirt_definition)" in world,
            "composter fill visual must use the supplied dirt material")

    smoke = (ROOT / "tests/runtime_smoke.gd").read_text(encoding="utf-8")
    smoke_tokens = [
        "world.ensure_around", "all six adjacent cell placements", "negative-coordinate block placement",
        "container IDs survive save/restore data round trip", "ordinary block stays floating after support removal",
        "attached torch is removed when its support disappears", "falling sand passes through and replaces a plant",
        "copper bulb toggles on redstone rising edge", "shelf persists exactly three visible slots",
        "door lower and upper panels both render", "door lower panel remains one cell tall",
        "both bed cells render their own half", "bed head uses per-cell geometry",
        "saved door restores both cell visuals", "saved bed restores both cell visuals",
        "white candle places", "same candle item adds a candle up to four",
        "composter reaches level eight", "ready composter can be emptied",
        "bell interaction starts ringing state", "sculk sensor receives event power",
        "candle count renders an extra supplied model", "composter level renders with supplied dirt material",
    ]
    for token in smoke_tokens:
        require(token in smoke, f"runtime smoke test missing: {token}")

    coverage = (ROOT / "reports/mechanic_coverage.md").read_text(encoding="utf-8").lower()
    for token in ["slabs", "stairs", "pistons", "water/lava", "living entities / spawn eggs",
                  "environment blocked", "floating ordinary blocks", "support-dependent blocks"]:
        require(token in coverage, f"mechanic coverage report missing: {token}")
    readme = (ROOT / "README.md").read_text(encoding="utf-8").lower()
    require("state-driven behaviors" in readme, "README must describe state-driven behaviors")

    print(json.dumps({
        "result": "PASS",
        "type": "static source-contract check (not Godot execution)",
        "registered_models": len(ids),
        "mechanic_families_checked": len(FAMILIES),
        "example_ids_checked": sum(map(len, FAMILIES.values())),
        "world_functions_checked": len(functions),
        "runtime_smoke_contracts_checked": len(smoke_tokens),
        "godot_runtime_tested": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)