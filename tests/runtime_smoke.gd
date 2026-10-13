extends SceneTree

const BehaviorScript = preload("res://scripts/block_behaviors.gd")
const WorldScript = preload("res://scripts/world_manager.gd")
const MaterialResolverScript = preload("res://scripts/material_resolver.gd")
const REGISTRY_PATH := "res://data/asset_registry.json"

var failures: int = 0

func _initialize() -> void:
    call_deferred("_run_tests")

func _check(condition: bool, label: String) -> void:
    if condition:
        print("PASS: ", label)
    else:
        failures += 1
        push_error("FAIL: " + label)

func _run_tests() -> void:
    _check(BehaviorScript.family_for_id("oak_slab") == "slab", "slab family")
    _check(BehaviorScript.family_for_id("oak_stairs") == "stairs", "stairs family")
    _check(BehaviorScript.family_for_id("oak_door") == "door", "door family")
    _check(BehaviorScript.family_for_id("glass_pane") == "connected_barrier", "pane family")
    _check(BehaviorScript.family_for_id("water") == "fluid", "water family")
    _check(BehaviorScript.family_for_id("piston_head") == "piston_head", "piston head classification")
    _check(BehaviorScript.family_for_id("sunflower") == "tall_plant", "tall plant family")
    _check(BehaviorScript.requires_support("torch"), "torch has a support requirement")
    _check(not BehaviorScript.requires_support("stone"), "ordinary stone is allowed to float without support")
    _check(BehaviorScript.direction_for_facing("east") == Vector3i.RIGHT, "east-facing placement vector")
    _check(BehaviorScript.direction_for_facing("west") == Vector3i.LEFT, "west-facing placement vector")

    var registry_file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
    if registry_file == null:
        _check(false, "asset registry opens")
        quit(1)
        return
    var parsed: Variant = JSON.parse_string(registry_file.get_as_text())
    _check(parsed is Dictionary and (parsed as Dictionary).has("models"), "asset registry parses")
    if not parsed is Dictionary:
        quit(1)
        return
    var definitions: Dictionary = {}
    for model in (parsed as Dictionary).get("models", []):
        if model is Dictionary:
            definitions[String(model.get("id", ""))] = model
    _check(definitions.size() == 1245, "all supplied model definitions loaded")

    var world = WorldScript.new()
    root.add_child(world)
    world.configure(definitions, MaterialResolverScript.new())
    world.render_radius_chunks = 1
    world.ensure_around(Vector3(0.0, 1.0, 0.0))
    await process_frame
    _check(world.get_block_id(Vector3i(0, 0, 0)) == "grass_block", "flat world surface layer")
    _check(world.get_block_id(Vector3i(0, -1, 0)) == "dirt", "flat world first dirt layer")
    _check(world.get_block_id(Vector3i(0, -2, 0)) == "dirt", "flat world second dirt layer")
    _check(world.get_block_id(Vector3i(0, -3, 0)) == "bedrock", "flat world bedrock layer")

    # Requires the project's first editor import to have completed successfully.
    var slab_cell := Vector3i(2, 1, 2)
    var slab_placed := world.place_block(slab_cell, "oak_slab", 0.0, {}, Vector3i.UP)
    _check(slab_placed, "real oak slab model imports and places")
    if slab_placed:
        _check(world.placed_nodes.has(slab_cell), "slab has a real instantiated GLB-backed node")
        _check(String(world.get_block_state(slab_cell).get("half", "")) == "bottom", "bottom slab state stored")
        _check(world.merge_slab(slab_cell), "slab double merge")
        _check(bool(world.get_block_state(slab_cell).get("double", false)), "double slab state persists")

    var door_cell := Vector3i(5, 1, 5)
    var door_placed := world.place_block(door_cell, "oak_door", PI, {"facing": "south"}, Vector3i.UP)
    _check(door_placed, "real oak door model places as paired structure")
    if door_placed:
        var upper := world.get_block_state(door_cell + Vector3i.UP)
        _check(String(world.get_block_state(door_cell).get("part", "")) == "lower", "door lower-half state exists")
        _check(String(upper.get("part", "")) == "upper", "door upper-half state exists")
        _check(not bool(upper.get("paired_visual", false)), "door upper half has its own cell-sized visual")
        _check(world.placed_nodes.has(door_cell) and world.placed_nodes.has(door_cell + Vector3i.UP), "door lower and upper panels both render")
        _check(absf((world.placed_nodes[door_cell] as Node3D).scale.y - 1.0) < 0.001, "door lower panel remains one cell tall")
        _check(absf((world.placed_nodes[door_cell + Vector3i.UP] as Node3D).scale.y - 1.0) < 0.001, "door upper panel remains one cell tall")
        _check(Vector3i(int(upper["pair_cell"][0]), int(upper["pair_cell"][1]), int(upper["pair_cell"][2])) == door_cell, "door upper half points back to lower cell")
        _check(world.remove_block(door_cell + Vector3i.UP), "breaking upper door removes structure")
        _check(not world.has_block(door_cell) and not world.has_block(door_cell + Vector3i.UP), "door pair removal is atomic")

    var bed_cell := Vector3i(6, 1, 9)
    var bed_placed := world.place_block(bed_cell, "white_bed", PI, {"facing": "south"}, Vector3i.UP)
    _check(bed_placed, "bed places as a two-cell structure")
    if bed_placed:
        var bed_head_cell := bed_cell + BehaviorScript.direction_for_facing("south")
        _check(String(world.get_block_state(bed_head_cell).get("part", "")) == "head", "bed head cell is stored")
        _check(not bool(world.get_block_state(bed_head_cell).get("paired_visual", false)), "bed head has its own cell-sized visual")
        _check(world.placed_nodes.has(bed_cell) and world.placed_nodes.has(bed_head_cell), "both bed cells render their own half")
        _check((world.placed_nodes[bed_cell] as Node3D).get_node_or_null("BedStateGeometry") != null, "bed foot uses per-cell geometry")
        _check((world.placed_nodes[bed_head_cell] as Node3D).get_node_or_null("BedStateGeometry") != null, "bed head uses per-cell geometry")
        _check(world.remove_block(bed_head_cell), "breaking either bed half removes the full bed")
        _check(not world.has_block(bed_cell) and not world.has_block(bed_head_cell), "bed pair removal is atomic")

    var tall_cell := Vector3i(8, 1, 8)
    var tall_placed := world.place_block(tall_cell, "sunflower", 0.0, {}, Vector3i.UP)
    _check(tall_placed, "real sunflower places as two-cell plant")
    if tall_placed:
        _check(world.placed_nodes.has(tall_cell), "sunflower lower model is instantiated")
        _check(String(world.get_block_state(tall_cell).get("part", "")) == "lower", "tall plant lower state exists")
        _check(String(world.get_block_state(tall_cell + Vector3i.UP).get("part", "")) == "upper", "tall plant upper state exists")
        var second_tall_cell := Vector3i(9, 1, 8)
        _check(world.place_block(second_tall_cell, "tall_grass"), "second tall plant places")
        _check(world.remove_block(second_tall_cell + Vector3i.UP), "breaking either tall-plant half removes the structure")
        _check(not world.has_block(second_tall_cell) and not world.has_block(second_tall_cell + Vector3i.UP), "tall-plant pair removal is atomic")

    # Project creative rule: already-placed blocks stay floating after support is removed.
    var support_cell := Vector3i(14, 7, 14)
    var floating_cell := support_cell + Vector3i.UP
    var wall_torch_cell := support_cell + Vector3i.RIGHT
    _check(world.place_block(support_cell, "stone"), "support block places")
    _check(world.place_block(floating_cell, "stone"), "ordinary block above support places")
    _check(world.place_block(wall_torch_cell, "torch", 0.0, {"facing": "east", "face": "wall"}, Vector3i.RIGHT), "wall torch places against support")
    _check(world.remove_block(support_cell), "support block can be removed")
    _check(world.get_block_id(floating_cell) == "stone", "ordinary block stays floating after support removal")
    _check(world.get_block_id(wall_torch_cell) == "", "attached torch is removed when its support disappears")

    # Falling sand displaces replaceable plants but does not affect ordinary unsupported cubes.
    var plant_column := Vector3i(15, 1, 14)
    var sand_cell := plant_column + Vector3i.UP
    _check(world.place_block(plant_column, "short_grass"), "ground-supported plant places")
    _check(world.place_block(sand_cell, "sand"), "sand places over plant")
    world._simulate_falling_blocks()
    _check(world.get_block_id(plant_column) == "sand", "falling sand passes through and replaces a plant")


    # Regression: removing support does not delete any neighboring placed block.
    # Falling blocks use their own independent gravity simulation.
    var regression_support_cell := Vector3i(20, 1, 20)
    var regression_torch_cell := Vector3i(20, 2, 20)
    _check(world.place_block(regression_support_cell, "stone"), "support block for floating attachment regression test places")
    _check(world.place_block(regression_torch_cell, "torch", 0.0, {"face": "floor"}, Vector3i.UP), "torch places on a support block")
    _check(world.remove_block(regression_support_cell), "support removal succeeds")
    _check(world.get_block_id(regression_torch_cell) == "", "unsupported torch is removed after support removal")

    # Exercise six-axis cell placement, negative coordinates, and persisted container item IDs.
    var anchor := Vector3i(12, 6, 12)
    var faces: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
    var all_faces_placed := true
    for offset in faces:
        var position := anchor + offset
        all_faces_placed = world.place_block(position, "stone") and all_faces_placed
        _check(world.get_block_id(position) == "stone", "cell placement at face offset %s" % str(offset))
    _check(all_faces_placed, "all six adjacent cell placements accepted")
    var negative_cell := Vector3i(-17, 3, -31)
    _check(world.place_block(negative_cell, "stone"), "negative-coordinate block placement")
    _check(world.get_block_id(negative_cell) == "stone", "negative coordinates round-trip in world data")

    var chest_cell := Vector3i(10, 1, 10)
    var chest_placed := world.place_block(chest_cell, "chest")
    _check(chest_placed, "container model places")
    if chest_placed:
        _check(world.set_container_contents(chest_cell, ["oak_planks", "stone"]), "container contents accept valid model IDs")
        var stored_items := world.container_contents(chest_cell)
        _check(String(stored_items[0]) == "oak_planks" and String(stored_items[1]) == "stone", "container item IDs persist in state")

    # Copper bulb toggles only on a redstone rising edge, not on power removal.
    var bulb_cell := Vector3i(30, 1, 30)
    var redstone_power_cell := bulb_cell + Vector3i(0, 0, 1)
    var bulb_placed := world.place_block(bulb_cell, "copper_bulb")
    _check(bulb_placed, "copper bulb places")
    if bulb_placed:
        _check(world.place_block(redstone_power_cell, "redstone_block"), "redstone power source places beside copper bulb")
        _check(bool(world.get_block_state(bulb_cell).get("lit", false)), "copper bulb toggles on redstone rising edge")
        _check(world.remove_block(redstone_power_cell), "redstone source can be removed")
        _check(bool(world.get_block_state(bulb_cell).get("lit", false)), "copper bulb stays lit when power is removed")
        _check(world.place_block(redstone_power_cell, "redstone_block"), "second redstone rising edge is applied")
        _check(not bool(world.get_block_state(bulb_cell).get("lit", false)), "second rising edge toggles copper bulb off")

    var shelf_cell := Vector3i(32, 1, 30)
    var shelf_placed := world.place_block(shelf_cell, "oak_shelf")
    _check(shelf_placed, "shelf model places")
    if shelf_placed:
        _check(world.set_container_contents(shelf_cell, ["stone", "oak_planks", "dirt", "sand"]), "shelf accepts item IDs")
        var shelf_items := world.container_contents(shelf_cell)
        _check(shelf_items.size() == 3 and String(shelf_items[2]) == "dirt", "shelf persists exactly three visible slots")

    # New interaction regressions: candles, composter, bell and sculk sensor.
    var candle_cell := Vector3i(40, 1, 40)
    var candle_placed := world.place_block(candle_cell, "white_candle")
    _check(candle_placed, "white candle places")
    if candle_placed:
        _check(world.use_block(candle_cell, "white_candle") == "candle_added", "same candle item adds a candle up to four")
        _check(int(world.get_block_state(candle_cell).get("count", 0)) == 2, "candle count state is stored")
        _check((world.placed_nodes[candle_cell] as Node3D).get_node_or_null("CandleVariant_1") != null, "candle count renders an extra supplied model")
        _check(world.use_block(candle_cell, "stone") == "candle_lit", "alternate use lights candle")
        _check(bool(world.get_block_state(candle_cell).get("lit", false)), "lit candle state persists")

    var composter_cell := Vector3i(42, 1, 40)
    var composter_placed := world.place_block(composter_cell, "composter")
    _check(composter_placed, "composter places")
    if composter_placed:
        for i in range(8): world.use_block(composter_cell, "short_grass")
        _check(int(world.get_block_state(composter_cell).get("level", 0)) == 8, "composter reaches level eight")
        _check(bool(world.get_block_state(composter_cell).get("ready", false)), "composter ready state stored")
        _check((world.placed_nodes[composter_cell] as Node3D).get_node_or_null("ComposterFill") != null, "composter level renders with supplied dirt material")
        _check(world.use_block(composter_cell, "") == "composter_bone_meal", "ready composter can be emptied")
        _check(int(world.get_block_state(composter_cell).get("level", -1)) == 0, "composter reset state stored")
        _check(BehaviorScript.is_compostable_item("short_grass"), "plant material is compostable")
        _check(not BehaviorScript.is_compostable_item("stone"), "stone is not compostable")

    var bell_cell := Vector3i(44, 1, 40)
    var bell_placed := world.place_block(bell_cell, "bell")
    _check(bell_placed, "bell places")
    if bell_placed:
        _check(world.use_block(bell_cell) == "bell_ringing", "bell interaction starts ringing state")
        _check(bool(world.get_block_state(bell_cell).get("ringing", false)), "bell ringing state persists")

    var sensor_cell := Vector3i(48, 1, 40)
    var sensor_placed := world.place_block(sensor_cell, "sculk_sensor")
    _check(sensor_placed, "sculk sensor places")
    if sensor_placed:
        _check(world.place_block(sensor_cell + Vector3i.RIGHT, "stone"), "nearby edit triggers sensor event")
        _check(bool(world.get_block_state(sensor_cell).get("powered", false)), "sculk sensor receives event power")
        _check(int(world.get_block_state(sensor_cell).get("power", 0)) > 0, "sculk sensor emits strength")

    var saved_door_cell := Vector3i(24, 1, 24)
    var saved_bed_cell := Vector3i(27, 1, 24)
    _check(world.place_block(saved_door_cell, "oak_door", 0.0, {"facing": "north"}, Vector3i.UP), "second door placed for paired-state persistence")
    _check(world.place_block(saved_bed_cell, "white_bed", -PI * 0.5, {"facing": "east"}, Vector3i.UP), "second bed placed for paired-state persistence")
    var saved_bed_head := saved_bed_cell + BehaviorScript.direction_for_facing("east")
    var saved_rows := world.all_placed_for_save()
    var removed_rows := world.removed_for_save()
    world.restore_state(saved_rows, removed_rows)
    if tall_placed:
        _check(String(world.get_block_state(tall_cell).get("part", "")) == "lower", "paired lower state survives restore")
        _check(String(world.get_block_state(tall_cell + Vector3i.UP).get("part", "")) == "upper", "paired upper state survives restore")
        _check(not world.placed_nodes.has(tall_cell + Vector3i.UP), "restore doesn't duplicate the tall plant render")
    _check(world.get_block_id(floating_cell) == "stone", "ordinary floating block survives save/restore")
    if chest_placed:
        var restored_items := world.container_contents(chest_cell)
        _check(String(restored_items[0]) == "oak_planks" and String(restored_items[1]) == "stone", "container IDs survive save/restore data round trip")
    _check(world.get_block_id(negative_cell) == "stone", "negative-coordinate blocks survive restore")
    _check(String(world.get_block_state(saved_door_cell).get("part", "")) == "lower", "saved door lower state restores")
    _check(String(world.get_block_state(saved_door_cell + Vector3i.UP).get("part", "")) == "upper", "saved door upper state restores")
    _check(world.placed_nodes.has(saved_door_cell) and world.placed_nodes.has(saved_door_cell + Vector3i.UP), "saved door restores both cell visuals")
    _check(String(world.get_block_state(saved_bed_head).get("part", "")) == "head", "saved bed head state restores")
    _check(world.placed_nodes.has(saved_bed_cell) and world.placed_nodes.has(saved_bed_head), "saved bed restores both cell visuals")

    world.queue_free()
    await process_frame
    if failures == 0:
        print("RUNTIME SMOKE TESTS PASSED")
        quit(0)
    else:
        push_error("RUNTIME SMOKE TESTS FAILED: %d failure(s)" % failures)
        quit(1)