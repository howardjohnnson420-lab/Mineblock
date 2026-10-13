extends RefCounted
class_name BlockBehaviors

# Gameplay state schemas for the supplied model library. The GLB source remains immutable;
# these profiles describe how a placed block occupies a grid cell and reacts to interactions.
const HORIZONTAL_DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const HORIZONTAL_KEYS: Array[String] = ["east", "west", "south", "north"]

static func family_for_id(id: String) -> String:
    var value := id.to_lower()
    if value in ["water", "lava", "bubble_column"]: return "fluid"
    if value in ["sand", "red_sand", "gravel", "suspicious_sand", "suspicious_gravel", "white_concrete_powder", "orange_concrete_powder", "magenta_concrete_powder", "light_blue_concrete_powder", "yellow_concrete_powder", "lime_concrete_powder", "pink_concrete_powder", "gray_concrete_powder", "light_gray_concrete_powder", "cyan_concrete_powder", "purple_concrete_powder", "blue_concrete_powder", "brown_concrete_powder", "green_concrete_powder", "red_concrete_powder", "black_concrete_powder"] or value.ends_with("_anvil"):
        return "falling_block"
    if value.ends_with("_slab") or value == "slab": return "slab"
    if value.ends_with("_stairs") or value == "stairs": return "stairs"
    if value.ends_with("_carpet"): return "carpet"
    if value == "snow": return "thin_layer"
    if value.ends_with("_candle_cake"): return "candle_cake"
    if value.ends_with("_candle"): return "candle"
    if value.ends_with("_banner"): return "banner"
    if value.ends_with("_door") or value == "door": return "door"
    if value.ends_with("_trapdoor") or value == "trapdoor": return "trapdoor"
    if value.ends_with("_fence_gate") or value == "fence_gate": return "fence_gate"
    if value.ends_with("_fence") or value == "fence": return "fence"
    if value.ends_with("_wall") or value == "wall" or value == "iron_bars" or value.ends_with("_pane") or value.ends_with("_bars"):
        return "connected_barrier"
    if value.ends_with("_leaves") or value in ["azalea_leaves", "flowering_azalea_leaves"]: return "foliage"
    if value.begins_with("potted_") or value == "flower_pot": return "potted_plant"
    if value.ends_with("_bed") or value == "bed": return "bed"
    if value.ends_with("_hanging_sign"): return "hanging_sign"
    if value.ends_with("_sign"): return "sign"
    if value.ends_with("_button") or value == "button": return "button"
    if value == "lever": return "lever"
    if value.ends_with("_pressure_plate") or value == "pressure_plate": return "pressure_plate"
    if value in ["redstone_torch", "redstone_wall_torch"]: return "redstone_source"
    if value.ends_with("_torch") or value == "torch": return "torch"
    if value.ends_with("_rail") or value == "rail": return "rail"
    if value in ["redstone_dust", "redstone_wire"]: return "redstone_wire"
    if value.find("repeater") >= 0: return "repeater"
    if value.find("comparator") >= 0: return "comparator"
    if value.find("redstone_lamp") >= 0: return "redstone_lamp"
    if value == "copper_bulb" or value.ends_with("_copper_bulb"): return "copper_bulb"
    if value == "piston_head" or value == "moving_piston": return "piston_head"
    if value in ["piston", "sticky_piston"]: return "piston"
    if value in ["chest", "trapped_chest", "ender_chest", "copper_chest", "barrel", "beehive", "bee_nest", "bookshelf", "chiseled_bookshelf"] or value.ends_with("_shulker_box"):
        return "container"
    if value.ends_with("_shelf"): return "shelf"
    if value in ["sculk_sensor", "calibrated_sculk_sensor"]: return "sculk_sensor"
    if value == "composter": return "composter"
    if value == "bell": return "bell"
    if value in ["dispenser", "dropper", "hopper", "furnace", "blast_furnace", "smoker", "brewing_stand", "crafter"]: return "machine_container"
    if value == "tnt": return "explosive"
    if value == "armor_stand": return "display_entity"
    if value in ["minecart", "chest_minecart", "hopper_minecart", "tnt_minecart", "command_block_minecart", "furnace_minecart"]: return "vehicle_entity"
    if value in ["dragon_egg", "sniffer_egg", "turtle_egg"]: return "egg_decor"
    if value in ["daylight_detector", "daylight_sensor"]: return "daylight_sensor"
    if value in ["grass_block", "grass_path", "dirt_path", "podzol", "mycelium", "coarse_dirt", "rooted_dirt"] or value.ends_with("_grass_block"):
        return "solid_or_decoration"
    if value.ends_with("_log") or value.ends_with("_wood") or value.ends_with("_stem") or value.ends_with("_hyphae") or value.ends_with("_pillar") or value in ["hay_block", "bone_block", "chain", "lightning_rod", "end_rod"]:
        return "axis_block"
    if value in ["sunflower", "lilac", "rose_bush", "peony", "tall_grass", "large_fern", "pitcher_plant", "tall_seagrass"]:
        return "tall_plant"
    if value in ["short_grass", "fern", "dead_bush", "seagrass", "kelp", "vine", "glow_lichen", "lily_pad", "cactus", "bamboo", "sugar_cane", "cocoa", "wheat", "carrots", "potatoes", "beetroots", "melon_stem", "pumpkin_stem", "sweet_berry_bush", "nether_wart", "torchflower_crop", "pitcher_crop", "weeping_vines", "twisting_vines", "cave_vines", "cave_vines_plant", "weeping_vines_plant", "twisting_vines_plant"] or value.find("sapling") >= 0 or value.find("flower") >= 0 or value.find("mushroom") >= 0 or value.ends_with("_plant") or value.ends_with("_roots"):
        return "plant"
    return "solid_or_decoration"

static func default_state(id: String, yaw: float = 0.0) -> Dictionary:
    var family := family_for_id(id)
    var face := "wall" if id.find("wall_") >= 0 or id == "redstone_wall_torch" else "floor"
    var state: Dictionary = {"family": family, "facing": _facing_from_yaw(yaw), "yaw": yaw, "waterlogged": false}
    match family:
        "falling_block": state.merge({"falling": false}, true)
        "axis_block": state.merge({"axis": "y"}, true)
        "slab": state.merge({"half": "bottom", "double": false}, true)
        "stairs": state.merge({"half": "bottom", "shape": "straight"}, true)
        "door": state.merge({"open": false, "hinge": "left", "upper": false, "part": "lower", "powered": false}, true)
        "trapdoor": state.merge({"open": false, "half": "bottom", "powered": false}, true)
        "fence_gate": state.merge({"open": false, "powered": false}, true)
        "fence", "connected_barrier": state.merge({"connections": {"east": false, "west": false, "south": false, "north": false}}, true)
        "bed": state.merge({"part": "foot", "occupied": false}, true)
        "tall_plant": state.merge({"part": "lower", "paired_visual": false}, true)
        "sign": state.merge({"text": "", "wall_mounted": id.find("wall_") >= 0, "face": face}, true)
        "hanging_sign": state.merge({"text": "", "wall_mounted": id.find("wall_") >= 0, "face": "wall" if id.find("wall_") >= 0 else "ceiling"}, true)
        "banner": state.merge({"text": "", "wall_mounted": id.find("wall_") >= 0, "face": face}, true)
        "button": state.merge({"powered": false, "face": face, "pressed_until": 0}, true)
        "lever": state.merge({"powered": false, "face": face}, true)
        "pressure_plate": state.merge({"powered": false}, true)
        "fluid": state.merge({"source": true, "level": 0}, true)
        "redstone_source": state.merge({"powered": true, "lit": true, "face": face}, true)
        "redstone_wire": state.merge({"power": 0, "connections": {"east": false, "west": false, "south": false, "north": false}}, true)
        "repeater": state.merge({"powered": false, "delay": 2, "input_powered": false, "pending_power": false, "pending_until_ms": 0}, true)
        "comparator": state.merge({"powered": false, "mode": "compare", "signal_level": 0}, true)
        "redstone_lamp": state.merge({"powered": false, "signal_level": 0}, true)
        "copper_bulb": state.merge({"lit": false, "input_powered": false}, true)
        "piston": state.merge({"extended": false, "sticky": id.find("sticky") >= 0}, true)
        "piston_head": state.merge({"facing": _facing_from_yaw(yaw), "sticky": false}, true)
        "container": state.merge({"items": [], "open": false}, true)
        "shelf": state.merge({"items": ["", "", ""], "open": false, "powered": false}, true)
        "machine_container": state.merge({"items": [], "open": false, "facing": _facing_from_yaw(yaw), "machine_enabled": false}, true)
        "explosive": state.merge({"armed": false}, true)
        "rail": state.merge({"shape": "north_south", "powered": false}, true)
        "plant": state.merge({"age": 0, "stage": 0}, true)
        "daylight_sensor": state.merge({"powered": true, "inverted": false, "signal_level": 15}, true)
        "carpet": state.merge({"thickness": 0.0625}, true)
        "thin_layer": state.merge({"layers": 1}, true)
        "candle": state.merge({"count": 1, "lit": false, "waterlogged": false}, true)
        "candle_cake": state.merge({"lit": false}, true)
        "sculk_sensor": state.merge({"powered": false, "power": 0, "cooldown_until_ms": 0}, true)
        "composter": state.merge({"level": 0, "ready": false}, true)
        "bell": state.merge({"ringing": false, "ring_until_ms": 0}, true)
    return state

static func _facing_from_yaw(yaw: float) -> String:
    var normalized := wrapf(yaw, -PI, PI)
    var quadrant := int(round(normalized / (PI * 0.5)))
    match posmod(quadrant, 4):
        0: return "north"
        1: return "west"
        2: return "south"
        _: return "east"

static func direction_for_facing(facing: String) -> Vector3i:
    match facing:
        "east": return Vector3i.RIGHT
        "west": return Vector3i.LEFT
        "south": return Vector3i(0, 0, 1)
        "north": return Vector3i(0, 0, -1)
    return Vector3i(0, 0, 1)

static func opposite_facing(facing: String) -> String:
    match facing:
        "north": return "south"
        "south": return "north"
        "east": return "west"
        _: return "east"

static func is_replaceable(id: String) -> bool:
    var family := family_for_id(id)
    return family in ["plant", "tall_plant", "potted_plant", "fluid", "carpet", "thin_layer", "redstone_wire"] or id in ["snow", "dead_bush", "short_grass", "tall_grass"]

static func is_compostable_item(id: String) -> bool:
    # Creative composting does not consume inventory items. This curated family whitelist
    # covers the supplied plant/foliage models and common vanilla compost inputs; it avoids
    # incorrectly accepting ordinary stone/wood/metal blocks as compost material.
    if id.is_empty(): return false
    var value := id.to_lower()
    var family := family_for_id(value)
    if family in ["plant", "tall_plant", "foliage", "potted_plant", "candle", "candle_cake"]:
        return true
    if value.ends_with("_sapling") or value.ends_with("_leaves") or value.ends_with("_flower") or value.ends_with("_roots"):
        return true
    return value in ["wheat_seeds", "beetroot_seeds", "melon_seeds", "pumpkin_seeds", "bread", "apple", "baked_potato", "cookie", "cake", "moss_block", "moss_carpet", "hanging_roots", "big_dripleaf", "small_dripleaf", "azalea", "flowering_azalea"]

static func is_solid_support(id: String) -> bool:
    if id.is_empty(): return false
    var family := family_for_id(id)
    return family not in ["fluid", "plant", "tall_plant", "potted_plant", "carpet", "thin_layer", "candle", "candle_cake", "torch", "button", "lever", "sign", "hanging_sign", "banner", "rail", "redstone_wire", "pressure_plate", "vehicle_entity", "display_entity", "piston_head", "sculk_sensor"]

static func is_redstone_source(id: String, state: Dictionary) -> bool:
    var family := family_for_id(id)
    if family == "redstone_source": return bool(state.get("lit", true))
    if family == "redstone_wire": return int(state.get("power", 0)) > 0
    if family == "daylight_sensor": return int(state.get("signal_level", 0)) > 0
    return family in ["lever", "button", "pressure_plate", "repeater", "comparator", "sculk_sensor", "shelf"] and bool(state.get("powered", false))

static func selection_size(id: String, state: Dictionary, definition: Dictionary) -> Vector3:
    var size := Vector3.ONE
    var dims: Array = definition.get("dimensions", [1.0, 1.0, 1.0])
    if dims.size() >= 3: size = Vector3(maxf(0.05, float(dims[0])), maxf(0.05, float(dims[1])), maxf(0.05, float(dims[2])))
    match family_for_id(id):
        "slab": size = Vector3.ONE if bool(state.get("double", false)) else Vector3(1.0, 0.5, 1.0)
        "stairs": size = Vector3.ONE
        "door": size = Vector3(1.0, 1.0, 0.12)
        "tall_plant": size = Vector3(1.0, 1.0, 1.0)
        "bed": size = Vector3(1.0, 0.5, 1.0)
        "trapdoor": size = Vector3(1.0, 0.1875, 1.0)
        "carpet": size = Vector3(1.0, 0.0625, 1.0)
        "thin_layer": size = Vector3(1.0, clampf(float(state.get("layers", 1)) / 8.0, 0.125, 1.0), 1.0)
        "pressure_plate": size = Vector3(1.0, 0.0625, 1.0)
        "redstone_wire": size = Vector3(1.0, 0.0625, 1.0)
        "fluid": size = Vector3(1.0, maxf(0.2, 1.0 - 0.125 * float(state.get("level", 0))), 1.0)
    return size

static func requires_support(id: String, state: Dictionary = {}) -> bool:
    var family := family_for_id(id)
    if family in ["door", "bed", "plant", "tall_plant", "potted_plant", "rail", "pressure_plate", "redstone_wire", "repeater", "comparator", "piston", "explosive", "carpet", "thin_layer", "candle", "candle_cake", "shelf", "sculk_sensor", "composter"]:
        return true
    if family in ["button", "lever", "torch", "redstone_source", "sign", "hanging_sign", "banner"]: return true
    return false

static func support_cell(cell: Vector3i, id: String, state: Dictionary = {}) -> Vector3i:
    var family := family_for_id(id)
    var face := String(state.get("face", "floor"))
    var wall_mounted := bool(state.get("wall_mounted", false)) or face == "wall" or id.find("wall_") >= 0 or id.ends_with("_wall_torch") or id == "redstone_wall_torch"
    if family in ["button", "lever", "torch", "redstone_source", "sign", "hanging_sign", "banner"] and wall_mounted:
        return cell - direction_for_facing(String(state.get("facing", "north")))
    if id in ["vine", "glow_lichen", "cocoa"] and face == "wall":
        return cell - direction_for_facing(String(state.get("facing", "north")))
    if id == "glow_lichen" and face == "ceiling": return cell + Vector3i.UP
    if id in ["weeping_vines", "twisting_vines", "cave_vines", "cave_vines_plant", "weeping_vines_plant", "twisting_vines_plant"]:
        return cell + Vector3i.UP
    if family == "hanging_sign" and face == "ceiling": return cell + Vector3i.UP
    return cell + Vector3i.DOWN

static func is_pushable(id: String, state: Dictionary = {}) -> bool:
    if id.is_empty() or id in ["bedrock", "obsidian", "crying_obsidian"]: return false
    var family := family_for_id(id)
    if family in ["container", "machine_container", "shelf", "piston", "piston_head", "door", "bed", "tall_plant", "fluid", "vehicle_entity", "display_entity", "sculk_sensor"]: return false
    if state.has("pair_cell"): return false
    return true

static func is_virtual_pair_cell(state: Dictionary) -> bool:
    # Occupancy is real/saved, but the parent block renders across this cell.
    # This is used by tall flowers and avoids duplicate full-height models.
    return bool(state.get("paired_visual", false))

static func neighbor_offsets() -> Array[Vector3i]:
    return [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
