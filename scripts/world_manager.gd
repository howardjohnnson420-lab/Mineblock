extends Node3D
class_name CreativeWorldManager

signal block_changed(cell: Vector3i, block_id: String)
signal world_dirty_changed(dirty: bool)
signal block_used(cell: Vector3i, block_id: String, action: String)

const CHUNK_SIZE: int = 16
const GROUND_IDS := {0: "grass_block", -1: "dirt", -2: "dirt", -3: "bedrock"}
const FACE_NORMALS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const HORIZONTAL_NEIGHBORS: Dictionary = {"east": Vector3i.RIGHT, "west": Vector3i.LEFT, "south": Vector3i(0, 0, 1), "north": Vector3i(0, 0, -1)}
const MAX_FLUID_CELLS: int = 900
const MAX_PISTON_PUSH: int = 12

var definitions: Dictionary = {}
var resolver: MaterialResolver
var placed_blocks: Dictionary = {} # Vector3i -> {id, yaw, state}
var removed_cells: Dictionary = {} # Vector3i -> true
var placed_nodes: Dictionary = {} # Vector3i -> Node3D
var chunks: Dictionary = {} # Vector2i -> {root,visual,body,collision}
var render_radius_chunks: int = 3
var dirty: bool = false
var bedrock_breakable: bool = true
var _last_center_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _logic_elapsed: float = 0.0
var _hopper_elapsed: float = 0.0
var _player_position: Vector3 = Vector3.ZERO
var _last_sensor_player_position: Vector3 = Vector3.ZERO
var _sensor_position_initialized: bool = false
var _logic_guard: bool = false
var _redstone_dirty: bool = true
var daylight_strength: float = 1.0

func configure(defs: Dictionary, material_resolver: MaterialResolver) -> void:
    definitions = defs
    resolver = material_resolver

func set_daylight_strength(value: float) -> void:
    var next_value := clampf(value, 0.0, 1.0)
    if absf(next_value - daylight_strength) >= 0.035:
        daylight_strength = next_value
        _redstone_dirty = true

func ensure_around(position: Vector3) -> void:
    var center := Vector2i(floori(position.x / float(CHUNK_SIZE)), floori(position.z / float(CHUNK_SIZE)))
    if center == _last_center_chunk:
        return
    _last_center_chunk = center
    for z in range(center.y - render_radius_chunks, center.y + render_radius_chunks + 1):
        for x in range(center.x - render_radius_chunks, center.x + render_radius_chunks + 1):
            var key := Vector2i(x, z)
            if not chunks.has(key):
                _create_chunk(key)
    var remove_keys: Array[Vector2i] = []
    for key: Vector2i in chunks.keys():
        if absi(key.x - center.x) > render_radius_chunks + 1 or absi(key.y - center.y) > render_radius_chunks + 1:
            remove_keys.append(key)
    for key in remove_keys:
        var entry: Dictionary = chunks[key]
        var root := entry.get("root") as Node3D
        if is_instance_valid(root):
            root.queue_free()
        chunks.erase(key)

    # Keep world data independent from scene nodes. Saved builds can be arbitrarily large;
    # only instantiate their imported GLB scenes inside the currently loaded chunk window.
    var unload_cells: Array[Vector3i] = []
    for cell: Vector3i in placed_nodes.keys():
        if not _cell_within_loaded_range(cell):
            unload_cells.append(cell)
    for cell in unload_cells:
        var node := placed_nodes.get(cell) as Node3D
        if is_instance_valid(node):
            node.queue_free()
        placed_nodes.erase(cell)
    for raw_cell in placed_blocks.keys():
        var cell: Vector3i = raw_cell
        if _cell_within_loaded_range(cell) and not placed_nodes.has(cell):
            var record: Dictionary = placed_blocks[cell]
            var state: Dictionary = record.get("state", {})
            if not BlockBehaviors.is_virtual_pair_cell(state):
                _instantiate_model_for_cell(cell, String(record.get("id", "")), float(record.get("yaw", 0.0)), state)

func _cell_within_loaded_range(cell: Vector3i) -> bool:
    if _last_center_chunk.x == 2147483647:
        return false
    var block_chunk_x := floori(cell.x / float(CHUNK_SIZE))
    var block_chunk_z := floori(cell.z / float(CHUNK_SIZE))
    return absi(block_chunk_x - _last_center_chunk.x) <= render_radius_chunks + 1 and absi(block_chunk_z - _last_center_chunk.y) <= render_radius_chunks + 1

func get_block_id(cell: Vector3i) -> String:
    if placed_blocks.has(cell): return String((placed_blocks[cell] as Dictionary).get("id", ""))
    if removed_cells.has(cell): return ""
    return _base_block_id(cell)

func get_block_state(cell: Vector3i) -> Dictionary:
    if placed_blocks.has(cell): return (placed_blocks[cell] as Dictionary).get("state", {}) as Dictionary
    return BlockBehaviors.default_state(_base_block_id(cell)) if not _base_block_id(cell).is_empty() else {}

func has_block(cell: Vector3i) -> bool:
    return not get_block_id(cell).is_empty()

func _base_block_id(cell: Vector3i) -> String:
    return String(GROUND_IDS.get(cell.y, ""))

func _is_base_visible(cell: Vector3i) -> bool:
    return not placed_blocks.has(cell) and not removed_cells.has(cell) and not _base_block_id(cell).is_empty()

func place_block(cell: Vector3i, block_id: String, yaw: float = 0.0, state_override: Dictionary = {}, placement_face: Vector3i = Vector3i.UP) -> bool:
    if block_id.is_empty() or not definitions.has(block_id): return false
    var existing_id := get_block_id(cell)
    var family := BlockBehaviors.family_for_id(block_id)
    if not existing_id.is_empty():
        if BlockBehaviors.is_replaceable(existing_id):
            # Avoid immediately regenerating a source fluid into the target cell before a
            # replacement plant/decorative block is written there.
            if BlockBehaviors.family_for_id(existing_id) == "fluid" and placed_blocks.has(cell):
                _remove_single(cell)
                removed_cells.erase(cell)
                _set_dirty(true)
                _redstone_dirty = true
            elif not remove_block(cell):
                return false
        elif existing_id == block_id and family == "slab":
            var existing_state := get_block_state(cell)
            if not bool(existing_state.get("double", false)):
                existing_state["double"] = true
                _replace_state_visual(cell, existing_state)
                _set_dirty(true)
                _refresh_near_cell(cell)
                return true
            return false
        else:
            return false
    var state := BlockBehaviors.default_state(block_id, yaw)
    for state_key in state_override.keys(): state[state_key] = state_override[state_key]
    if not _can_place_at(cell, block_id, placement_face, state): return false
    for key in state_override.keys(): state[key] = state_override[key]
    state["family"] = family
    state["yaw"] = yaw
    state["facing"] = String(state.get("facing", BlockBehaviors._facing_from_yaw(yaw)))
    if family == "door" and not state_override.has("hinge"):
        state["hinge"] = _choose_door_hinge(cell, String(state["facing"]), block_id)
    if family == "axis_block":
        state["axis"] = "y" if placement_face.y != 0 else ("x" if placement_face.x != 0 else "z")
    if family == "slab" and placement_face == Vector3i.DOWN: state["half"] = "top"
    if family == "slab" and placement_face == Vector3i.UP: state["half"] = "bottom"
    if family == "stairs" and placement_face == Vector3i.DOWN: state["half"] = "top"
    if family == "stairs" and placement_face == Vector3i.UP: state["half"] = "bottom"
    if family == "trapdoor" and placement_face == Vector3i.DOWN: state["half"] = "top"
    if family == "trapdoor" and placement_face == Vector3i.UP: state["half"] = "bottom"
    if not _create_placed_record(cell, block_id, yaw, state): return false

    # Doors and beds are true two-cell structures, saved as paired block states.
    if family == "door":
        var upper_cell := cell + Vector3i.UP
        state["part"] = "lower"
        state["upper"] = false
        var upper_state := state.duplicate(true)
        upper_state["upper"] = true
        upper_state["part"] = "upper"
        upper_state["paired_visual"] = false
        upper_state["pair_cell"] = [cell.x, cell.y, cell.z]
        state["pair_cell"] = [upper_cell.x, upper_cell.y, upper_cell.z]
        _set_record_state(cell, state)
        if not _create_placed_record(upper_cell, block_id, yaw, upper_state):
            _remove_single(cell)
            return false
    elif family == "tall_plant":
        var upper_cell := cell + Vector3i.UP
        state["part"] = "lower"
        state["paired_visual"] = false
        var upper_state := state.duplicate(true)
        upper_state["part"] = "upper"
        upper_state["paired_visual"] = true
        upper_state["pair_cell"] = [cell.x, cell.y, cell.z]
        state["pair_cell"] = [upper_cell.x, upper_cell.y, upper_cell.z]
        _set_record_state(cell, state)
        if not _create_placed_record(upper_cell, block_id, yaw, upper_state):
            _remove_single(cell)
            return false
    elif family == "bed":
        var direction := BlockBehaviors.direction_for_facing(String(state.get("facing", "south")))
        var head_cell := cell + direction
        var head_state := state.duplicate(true)
        head_state["part"] = "head"
        head_state["paired_visual"] = false
        head_state["pair_cell"] = [cell.x, cell.y, cell.z]
        state["paired_visual"] = false
        state["pair_cell"] = [head_cell.x, head_cell.y, head_cell.z]
        _set_record_state(cell, state)
        if not _create_placed_record(head_cell, block_id, yaw, head_state):
            _remove_single(cell)
            return false
    _update_connections_near(cell)
    # Ordinary blocks stay floating; only explicitly support-dependent neighbors are resolved.
    if family == "fluid" or _has_fluid_near(cell): _rebuild_fluid_spread()
    _resolve_support_loss_near(cell)
    _redstone_dirty = true
    _set_dirty(true)
    _refresh_near_cell(cell)
    block_changed.emit(cell, block_id)
    if family != "sculk_sensor": _trigger_sculk_sensors_near(cell)
    _recalculate_redstone()
    return true

func _choose_door_hinge(cell: Vector3i, facing: String, block_id: String) -> String:
    # Prefer facing-compatible outer hinges for adjacent double doors. If no matching
    # neighbor exists, use the default left hinge; explicit state overrides remain respected.
    var forward := BlockBehaviors.direction_for_facing(facing)
    var left_side := Vector3i(forward.z, 0, -forward.x)
    var right_side := -left_side
    var left_cell := cell + left_side
    var right_cell := cell + right_side
    if get_block_id(left_cell) == block_id and String(get_block_state(left_cell).get("facing", facing)) == facing:
        return "right"
    if get_block_id(right_cell) == block_id and String(get_block_state(right_cell).get("facing", facing)) == facing:
        return "left"
    return "left"

func _can_place_at(cell: Vector3i, id: String, placement_face: Vector3i, state: Dictionary) -> bool:
    var family := BlockBehaviors.family_for_id(id)
    if family == "torch" and placement_face == Vector3i.DOWN:
        return false # ordinary torch models are floor- or wall-mounted, never ceiling-mounted
    if family == "redstone_source" and placement_face == Vector3i.DOWN and id == "redstone_torch":
        return false
    if id == "vine" and placement_face.y != 0:
        return false # Vines attach to vertical faces, not the top/bottom of a block.
    if id in ["weeping_vines", "twisting_vines", "cave_vines", "cave_vines_plant", "weeping_vines_plant", "twisting_vines_plant"] and placement_face != Vector3i.DOWN:
        return false # Hanging vines require the underside of a support block.
    if BlockBehaviors.requires_support(id, state) and not _has_valid_support(cell, id, state):
        return false
    if family == "door":
        if has_block(cell + Vector3i.UP): return false
        if not has_block(cell + Vector3i.DOWN): return false
    if family == "bed":
        var facing_cell := cell + BlockBehaviors.direction_for_facing(String(state.get("facing", "south")))
        if has_block(facing_cell) or not BlockBehaviors.is_solid_support(get_block_id(facing_cell + Vector3i.DOWN)): return false
    if family == "tall_plant" and has_block(cell + Vector3i.UP): return false
    if family in ["door", "bed", "tall_plant"] and not get_block_id(cell + Vector3i.DOWN).is_empty() and not BlockBehaviors.is_solid_support(get_block_id(cell + Vector3i.DOWN)):
        return false
    return true

func _create_placed_record(cell: Vector3i, id: String, yaw: float, state: Dictionary) -> bool:
    if has_block(cell): return false
    var row := {"id": id, "yaw": yaw, "state": state.duplicate(true)}
    placed_blocks[cell] = row
    removed_cells.erase(cell)
    if BlockBehaviors.is_virtual_pair_cell(state):
        return true
    if not _cell_within_loaded_range(cell):
        return true # model scene is lazily instantiated when its chunk enters the render window
    if not _instantiate_model_for_cell(cell, id, yaw, state):
        placed_blocks.erase(cell)
        return false
    return true

func _set_record_state(cell: Vector3i, state: Dictionary) -> void:
    if not placed_blocks.has(cell): return
    var record: Dictionary = placed_blocks[cell]
    record["state"] = state.duplicate(true)
    placed_blocks[cell] = record

func _instantiate_model_for_cell(cell: Vector3i, block_id: String, yaw: float, state: Dictionary = {}) -> bool:
    if BlockBehaviors.is_virtual_pair_cell(state):
        return true
    var definition: Dictionary = definitions.get(block_id, {})
    var model_path := String(definition.get("model_path", ""))
    if model_path.is_empty():
        push_warning("No model path for block: " + block_id)
        return false
    var packed := load(model_path) as PackedScene
    if packed == null:
        push_warning("Could not load model scene: " + model_path)
        return false
    var model_root := packed.instantiate() as Node3D
    if model_root == null:
        push_warning("Model root is not Node3D: " + model_path)
        return false
    _apply_materials(model_root, definition)
    model_root.name = "Placed_%s_%d_%d_%d" % [block_id, cell.x, cell.y, cell.z]
    model_root.position = Vector3(cell)
    model_root.rotation.y = yaw
    model_root.set_meta("block_id", block_id)
    model_root.set_meta("grid_cell", cell)
    model_root.set_meta("block_state", state.duplicate(true))

    var family := String(state.get("family", BlockBehaviors.family_for_id(block_id)))
    # Stored cardinal facing is the authoritative placement state. Deriving render
    # orientation from it (rather than trusting an independent yaw alone) keeps blocks
    # correct after restore and for scripted/test placements with explicit state overrides.
    if family in ["stairs", "door", "bed", "trapdoor", "fence_gate", "rail", "piston", "piston_head", "repeater", "comparator", "machine_container", "container", "shelf", "daylight_sensor", "bell"]:
        model_root.rotation.y = _yaw_for_facing(String(state.get("facing", BlockBehaviors._facing_from_yaw(yaw))))
    if family == "fence" or family == "connected_barrier" or family == "redstone_wire":
        model_root.rotation.y = 0.0 # connection masks are stored in world cardinal directions
    if family == "axis_block":
        model_root.rotation = Vector3.ZERO
        var axis := String(state.get("axis", "y"))
        if axis == "x": model_root.rotation.z = PI * 0.5
        elif axis == "z": model_root.rotation.x = PI * 0.5
    if family == "slab":
        _replace_with_slab_geometry(model_root, definition, state)
    if family == "stairs":
        _replace_with_stair_geometry(model_root, definition, state)
    if family == "door":
        # The supplied model is a single-cell panel. Lower and upper cells each render
        # their own panel so occupancy, selection and collision all agree with the grid.
        # Apply the hinge transform separately at each cell's height; never stretch a
        # single model through both cells or a paired save would duplicate the doorway.
        var base_yaw := _yaw_for_facing(String(state.get("facing", BlockBehaviors._facing_from_yaw(yaw))))
        var hinge_local := Vector3(-0.5 if String(state.get("hinge", "left")) == "left" else 0.5, 0.0, 0.0)
        model_root.rotation.y = base_yaw
        model_root.position = Vector3(cell)
        if bool(state.get("open", false)):
            var open_yaw := base_yaw + (PI * 0.5 if String(state.get("hinge", "left")) == "left" else -PI * 0.5)
            var hinge_offset := Basis(Vector3.UP, base_yaw) * hinge_local
            model_root.rotation.y = open_yaw
            model_root.position = Vector3(cell) + hinge_offset - Basis(Vector3.UP, open_yaw) * hinge_local
    if family == "bed":
        _replace_with_bed_geometry(model_root, definition, state)
    if family == "tall_plant":
        # Model is normalized to one cell tall; render it across the lower+upper cells.
        model_root.scale.y *= 2.0
        model_root.position.y += 0.5
    if family == "trapdoor":
        if not bool(state.get("open", false)) and String(state.get("half", "bottom")) == "top": model_root.scale.y = -1.0
        if bool(state.get("open", false)):
            model_root.rotation.x = PI * 0.5
            model_root.position.y += 0.25 if String(state.get("half", "bottom")) == "bottom" else -0.25
    if family == "fence_gate" and bool(state.get("open", false)): model_root.rotation.y += PI * 0.5
    if family == "rail":
        var rail_shape := String(state.get("shape", "north_south"))
        if rail_shape == "east_west": model_root.rotation.y += PI * 0.5
        elif rail_shape in ["north_east", "north_west", "south_east", "south_west"]:
            # Supplied rails are straight meshes; keep a stable visible orientation for turns.
            model_root.rotation.y += PI * 0.5 if rail_shape in ["north_east", "south_west"] else 0.0
    if family in ["button", "lever", "sign", "hanging_sign", "torch", "redstone_source"] and (String(state.get("face", "wall")) == "wall" or bool(state.get("wall_mounted", false)) or block_id.find("wall_torch") >= 0):
        var mounted_facing := String(state.get("facing", "north"))
        model_root.rotation.y = _yaw_for_facing(mounted_facing)
        model_root.position -= Vector3(BlockBehaviors.direction_for_facing(mounted_facing)) * 0.47

    add_child(model_root)
    if family in ["fence", "connected_barrier"]:
        _replace_with_connected_geometry(model_root, definition, state, family)
    elif family == "redstone_wire":
        _replace_with_redstone_wire_geometry(model_root, definition, state)
    if family in ["sign", "hanging_sign"] and not String(state.get("text", "")).is_empty():
        var sign_text := Label3D.new()
        sign_text.name = "SignText"
        sign_text.text = String(state.get("text", ""))
        sign_text.font_size = 24
        sign_text.pixel_size = 0.008
        sign_text.position = Vector3(0, 0.03, -0.065)
        sign_text.modulate = Color(0.12, 0.08, 0.04)
        model_root.add_child(sign_text)
    if family == "fluid":
        var fluid_height := maxf(0.125, 1.0 - 0.125 * float(state.get("level", 0)))
        model_root.scale.y *= fluid_height
        model_root.position.y = float(cell.y) - 0.5 + fluid_height * 0.5
    _add_collision_proxy(model_root, definition, state)
    if family == "candle":
        # The supplied candle GLB represents one candle. Render the saved count with
        # additional instances of that supplied model, using no extra colliders so the
        # whole candle cluster remains one interactable block cell.
        var candle_count := clampi(int(state.get("count", 1)), 1, 4)
        var candle_offsets: Array[Vector3] = [Vector3.ZERO, Vector3(0.17, 0.0, 0.0), Vector3(-0.17, 0.0, 0.0), Vector3(0.0, 0.0, 0.17)]
        for candle_index in range(1, candle_count):
            var extra_candle := packed.instantiate() as Node3D
            if extra_candle == null: continue
            _apply_materials(extra_candle, definition)
            extra_candle.name = "CandleVariant_%d" % candle_index
            extra_candle.position = candle_offsets[candle_index]
            extra_candle.scale = Vector3.ONE * 0.78
            model_root.add_child(extra_candle)
    if family == "composter":
        # Composter levels are visible, not merely metadata. The fill mesh samples the
        # supplied dirt PBR maps and stays inside the composter's rim.
        var compost_level := clampi(int(state.get("level", 0)), 0, 8)
        if compost_level > 0 and resolver != null and definitions.has("dirt"):
            var dirt_definition: Dictionary = definitions["dirt"]
            var compost_material: Material = resolver.material_for_model(dirt_definition)
            var fill_height := 0.10 + float(compost_level) * 0.0875
            _add_box_mesh(model_root, Vector3(0.66, fill_height, 0.66), Vector3(0.0, -0.45 + fill_height * 0.5, 0.0), compost_material)
            var fill_mesh := model_root.get_child(model_root.get_child_count() - 1) as MeshInstance3D
            if fill_mesh != null: fill_mesh.name = "ComposterFill"
    if family == "button" and bool(state.get("powered", false)):
        model_root.position += Vector3(0.0, 0.0, 0.035) if String(state.get("face", "floor")) == "wall" else Vector3(0.0, -0.035, 0.0)
    if family == "lever" and bool(state.get("powered", false)):
        model_root.rotation.x += deg_to_rad(-25.0)
    var emits_small_glow := family in ["candle", "candle_cake"] and bool(state.get("lit", false))
    var emits_powered_glow := (family == "redstone_lamp" and bool(state.get("powered", false))) or (family == "copper_bulb" and bool(state.get("lit", false)))
    if emits_powered_glow or emits_small_glow:
        var glow := OmniLight3D.new()
        glow.name = "PoweredGlow" if emits_powered_glow else "CandleGlow"
        glow.light_color = Color(1.0, 0.72, 0.34)
        glow.light_energy = 1.4 if emits_powered_glow else 0.65
        glow.omni_range = 4.0 if emits_powered_glow else 2.0
        glow.position.y = 0.28 if emits_small_glow else 0.0
        model_root.add_child(glow)
    if family == "bell" and bool(state.get("ringing", false)):
        model_root.rotation.z += deg_to_rad(10.0)
    placed_nodes[cell] = model_root
    return true

func _yaw_for_facing(facing: String) -> float:
    match facing:
        "north": return 0.0
        "east": return -PI * 0.5
        "south": return PI
        "west": return PI * 0.5
    return 0.0

func _replace_with_connected_geometry(root: Node3D, definition: Dictionary, state: Dictionary, family: String) -> void:
    # Procedural connection arms retain the supplied material and texture maps.
    _hide_model_meshes(root)
    var material: Material = resolver.material_for_model(definition) if resolver != null else null
    var parts := Node3D.new()
    parts.name = "ConnectedShape"
    root.add_child(parts)
    var connections: Dictionary = state.get("connections", {})
    if family == "fence":
        _add_box_mesh(parts, Vector3(0.22, 1.0, 0.22), Vector3.ZERO, material)
        for key in HORIZONTAL_NEIGHBORS:
            if not bool(connections.get(key, false)): continue
            var d: Vector3i = HORIZONTAL_NEIGHBORS[key]
            var arm_size := Vector3(0.39, 0.11, 0.11) if d.x != 0 else Vector3(0.11, 0.11, 0.39)
            var arm_center := Vector3(d) * 0.305
            _add_box_mesh(parts, arm_size, arm_center + Vector3(0, 0.21, 0), material)
            _add_box_mesh(parts, arm_size, arm_center + Vector3(0, -0.12, 0), material)
    elif String(definition.get("id", "")).find("wall") >= 0:
        _add_box_mesh(parts, Vector3(0.48, 0.78, 0.48), Vector3.ZERO, material)
        for key in HORIZONTAL_NEIGHBORS:
            if not bool(connections.get(key, false)): continue
            var d: Vector3i = HORIZONTAL_NEIGHBORS[key]
            var arm_size := Vector3(0.50, 0.60, 0.28) if d.x != 0 else Vector3(0.28, 0.60, 0.50)
            _add_box_mesh(parts, arm_size, Vector3(d) * 0.25, material)
    else:
        _add_box_mesh(parts, Vector3(0.06, 0.875, 0.06), Vector3.ZERO, material)
        for key in HORIZONTAL_NEIGHBORS:
            if not bool(connections.get(key, false)): continue
            var d: Vector3i = HORIZONTAL_NEIGHBORS[key]
            var arm_size := Vector3(0.47, 0.875, 0.055) if d.x != 0 else Vector3(0.055, 0.875, 0.47)
            _add_box_mesh(parts, arm_size, Vector3(d) * 0.265, material)

func _replace_with_slab_geometry(root: Node3D, definition: Dictionary, state: Dictionary) -> void:
    _hide_model_meshes(root)
    var material: Material = resolver.material_for_model(definition) if resolver != null else null
    var parts := Node3D.new()
    parts.name = "SlabStateGeometry"
    root.add_child(parts)
    if bool(state.get("double", false)):
        _add_box_mesh(parts, Vector3.ONE, Vector3.ZERO, material)
    else:
        var top_half := String(state.get("half", "bottom")) == "top"
        _add_box_mesh(parts, Vector3(1.0, 0.5, 1.0), Vector3(0, 0.25 if top_half else -0.25, 0), material)

func _replace_with_bed_geometry(root: Node3D, definition: Dictionary, state: Dictionary) -> void:
    # Every occupied bed cell owns exactly one half-cell of mesh. The GLB catalog has a
    # generic bed model, so create a material-matched procedural mattress and pillow rather
    # than duplicating a two-cell mesh on both the foot and head records.
    _hide_model_meshes(root)
    var material: Material = resolver.material_for_model(definition) if resolver != null else null
    var parts := Node3D.new()
    parts.name = "BedStateGeometry"
    root.add_child(parts)
    _add_box_mesh(parts, Vector3(0.94, 0.375, 0.94), Vector3(0.0, -0.3125, 0.0), material)
    _add_box_mesh(parts, Vector3(0.94, 0.1875, 0.94), Vector3(0.0, -0.03125, 0.0), material)
    if String(state.get("part", "foot")) == "head":
        _add_box_mesh(parts, Vector3(0.78, 0.075, 0.26), Vector3(0.0, 0.095, -0.30), material)

func _replace_with_redstone_wire_geometry(root: Node3D, definition: Dictionary, state: Dictionary) -> void:
    _hide_model_meshes(root)
    var material: Material = resolver.material_for_model(definition) if resolver != null else null
    var parts := Node3D.new()
    parts.name = "RedstoneWireGeometry"
    root.add_child(parts)
    var connections: Dictionary = state.get("connections", {})
    var power := int(state.get("power", 0))
    var center_y := -0.455
    var wire_material := material
    _add_box_mesh(parts, Vector3(0.24, 0.025, 0.24), Vector3(0, center_y, 0), wire_material)
    for key in HORIZONTAL_NEIGHBORS:
        if not bool(connections.get(key, false)): continue
        var direction: Vector3i = HORIZONTAL_NEIGHBORS[key]
        var arm_size := Vector3(0.40, 0.025, 0.075) if direction.x != 0 else Vector3(0.075, 0.025, 0.40)
        _add_box_mesh(parts, arm_size, Vector3(direction) * 0.30 + Vector3(0, center_y, 0), wire_material)
    if power > 0:
        var glow := OmniLight3D.new()
        glow.name = "PoweredWireGlow"
        glow.light_color = Color(1.0, 0.08, 0.04)
        glow.light_energy = 0.2 + float(power) / 15.0 * 0.5
        glow.omni_range = 1.5
        glow.position.y = -0.30
        parts.add_child(glow)

func _replace_with_stair_geometry(root: Node3D, definition: Dictionary, state: Dictionary) -> void:
    _hide_model_meshes(root)
    var material: Material = resolver.material_for_model(definition) if resolver != null else null
    var parts := Node3D.new()
    parts.name = "StairStateGeometry"
    root.add_child(parts)
    var top_half := String(state.get("half", "bottom")) == "top"
    var base_y := 0.25 if top_half else -0.25
    var step_y := -0.25 if top_half else 0.25
    var forward := Vector3(0, 0, 1) if top_half else Vector3(0, 0, -1)
    _add_box_mesh(parts, Vector3(1.0, 0.5, 1.0), Vector3(0.0, base_y, 0.0), material)
    var shape := String(state.get("shape", "straight"))
    if shape.begins_with("outer"):
        var side := -1.0 if shape == "outer_left" else 1.0
        var tread_center := forward * 0.25 + Vector3(side * 0.25, step_y, 0)
        _add_box_mesh(parts, Vector3(0.5, 0.5, 0.5), tread_center, material)
    elif shape.begins_with("inner"):
        var side := -1.0 if shape == "inner_left" else 1.0
        _add_box_mesh(parts, Vector3(1.0, 0.5, 0.5), Vector3(0, step_y, 0) + forward * 0.25, material)
        _add_box_mesh(parts, Vector3(0.5, 0.5, 0.5), Vector3(side * 0.25, step_y, 0.25 if top_half else -0.25), material)
    else:
        _add_box_mesh(parts, Vector3(1.0, 0.5, 0.5), Vector3(0, step_y, 0) + forward * 0.25, material)

func _hide_model_meshes(node: Node) -> void:
    if node is MeshInstance3D: (node as MeshInstance3D).visible = false
    for child in node.get_children(): _hide_model_meshes(child)

func _add_box_mesh(parent: Node3D, size: Vector3, center: Vector3, material: Material) -> void:
    var instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    instance.mesh = mesh
    instance.position = center
    if material != null: instance.material_override = material
    parent.add_child(instance)

func _apply_materials(root: Node, definition: Dictionary) -> void:
    if resolver == null: return
    if root is MeshInstance3D:
        var mesh_instance := root as MeshInstance3D
        mesh_instance.mesh = resolver.prepare_mesh(definition, mesh_instance.mesh, mesh_instance)
    for child in root.get_children(): _apply_materials(child, definition)

func _add_collision_proxy(model_root: Node3D, definition: Dictionary, state: Dictionary) -> void:
    var id := String(definition.get("id", model_root.get_meta("block_id", "")))
    var family := String(state.get("family", BlockBehaviors.family_for_id(id)))
    if family in ["fluid", "display_entity", "redstone_wire", "torch", "redstone_source"]: return
    var body := StaticBody3D.new()
    body.name = "CollisionProxy"
    body.collision_layer = 1
    body.collision_mask = 0
    model_root.add_child(body)
    if family == "bed":
        # Each bed part is a single occupied cell; avoid a two-cell collider per half.
        _add_collision_box(body, Vector3(0.94, 0.5625, 0.94), Vector3(0, -0.21875, 0))
    elif family == "door":
        # One panel per occupied cell; the paired record supplies the other half.
        var bounds: Array = definition.get("bounds", [[-0.5, -0.5, -0.5], [0.5, 0.5, -0.4375]])
        var lower: Array = bounds[0]; var upper: Array = bounds[1]
        _add_collision_box(body, Vector3(float(upper[0])-float(lower[0]), float(upper[1])-float(lower[1]), float(upper[2])-float(lower[2])), Vector3((float(upper[0])+float(lower[0]))*0.5, 0.0, (float(upper[2])+float(lower[2]))*0.5))
    elif family == "tall_plant":
        return
    elif family == "pressure_plate":
        _add_collision_box(body, Vector3(0.98, 0.0625, 0.98), Vector3(0, -0.46875, 0))
    elif family == "slab":
        var slab_shape := BoxShape3D.new()
        slab_shape.size = Vector3.ONE if bool(state.get("double", false)) else Vector3(1.0, 0.5, 1.0)
        var slab_collision := CollisionShape3D.new()
        slab_collision.shape = slab_shape
        slab_collision.position.y = 0.0 if bool(state.get("double", false)) else (-0.25 if String(state.get("half", "bottom")) == "bottom" else 0.25)
        body.add_child(slab_collision)
    elif family == "stairs":
        var top_half := String(state.get("half", "bottom")) == "top"
        _add_collision_box(body, Vector3(1.0, 0.5, 1.0), Vector3(0, 0.25 if top_half else -0.25, 0))
        var step_center := Vector3(0, -0.25 if top_half else 0.25, 0) + Vector3(0, 0, 0.25 if top_half else -0.25)
        var shape := String(state.get("shape", "straight"))
        if shape.begins_with("outer"):
            var side := -1.0 if shape == "outer_left" else 1.0
            _add_collision_box(body, Vector3(0.5, 0.5, 0.5), step_center + Vector3(side * 0.25, 0, 0))
        elif shape.begins_with("inner"):
            _add_collision_box(body, Vector3(1.0, 0.5, 0.5), step_center)
            var side := -1.0 if shape == "inner_left" else 1.0
            _add_collision_box(body, Vector3(0.5, 0.5, 0.5), Vector3(side * 0.25, -0.25 if top_half else 0.25, 0.25 if top_half else -0.25))
        else:
            _add_collision_box(body, Vector3(1.0, 0.5, 0.5), step_center)
    elif family in ["fence", "connected_barrier"]:
        var connections: Dictionary = state.get("connections", {})
        if family == "fence":
            _add_collision_box(body, Vector3(0.22, 1.0, 0.22), Vector3.ZERO)
            for key in HORIZONTAL_NEIGHBORS:
                if not bool(connections.get(key, false)): continue
                var d: Vector3i = HORIZONTAL_NEIGHBORS[key]
                var arm_size := Vector3(0.39, 0.35, 0.11) if d.x != 0 else Vector3(0.11, 0.35, 0.39)
                _add_collision_box(body, arm_size, Vector3(d) * 0.305 + Vector3(0, 0.02, 0))
        else:
            _add_collision_box(body, Vector3(0.08, 0.875, 0.08), Vector3.ZERO)
            for key in HORIZONTAL_NEIGHBORS:
                if not bool(connections.get(key, false)): continue
                var d: Vector3i = HORIZONTAL_NEIGHBORS[key]
                var arm_size := Vector3(0.47, 0.875, 0.06) if d.x != 0 else Vector3(0.06, 0.875, 0.47)
                _add_collision_box(body, arm_size, Vector3(d) * 0.265)
    elif family == "rail":
        _add_collision_box(body, Vector3(0.98, 0.05, 0.98), Vector3(0, -0.46, 0))
    elif family == "button":
        var face := String(state.get("face", "wall"))
        var button_size := Vector3(0.25, 0.125, 0.1) if face == "wall" else Vector3(0.25, 0.08, 0.25)
        var button_center := Vector3(0, 0, -0.44) if face == "wall" else Vector3(0, -0.46, 0)
        _add_collision_box(body, button_size, button_center)
    elif family == "lever":
        _add_collision_box(body, Vector3(0.22, 0.28, 0.22), Vector3(0, -0.34, 0))
    else:
        var dims: Array = definition.get("dimensions", [1.0, 1.0, 1.0])
        var bounds: Array = definition.get("bounds", [[-0.5, -0.5, -0.5], [0.5, 0.5, 0.5]])
        if dims.size() < 3: return
        var size := Vector3(maxf(0.025, float(dims[0])), maxf(0.025, float(dims[1])), maxf(0.025, float(dims[2])))
        var center := Vector3.ZERO
        if bounds.size() >= 2 and (bounds[0] as Array).size() >= 3 and (bounds[1] as Array).size() >= 3:
            var lower: Array = bounds[0]
            var upper: Array = bounds[1]
            center = Vector3((float(lower[0])+float(upper[0]))*0.5, (float(lower[1])+float(upper[1]))*0.5, (float(lower[2])+float(upper[2]))*0.5)
        _add_collision_box(body, size, center)

func _add_collision_box(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(maxf(0.025, size.x), maxf(0.025, size.y), maxf(0.025, size.z))
    collision.shape = shape
    collision.position = center
    body.add_child(collision)

func remove_block(cell: Vector3i, resolve_neighbor_support: bool = true) -> bool:
    var id := get_block_id(cell)
    if id.is_empty() or (id == "bedrock" and not bedrock_breakable): return false
    var state := get_block_state(cell)
    var paired_cell := Vector3i(2147483647, 2147483647, 2147483647)
    if placed_blocks.has(cell) and state.has("pair_cell"):
        var pair_array: Array = state.get("pair_cell", [])
        if pair_array.size() >= 3:
            paired_cell = Vector3i(int(pair_array[0]), int(pair_array[1]), int(pair_array[2]))
            if paired_cell != cell and placed_blocks.has(paired_cell): _remove_single(paired_cell)
    if placed_blocks.has(cell):
        _remove_single(cell)
    elif not _base_block_id(cell).is_empty():
        removed_cells[cell] = true
    else:
        return false
    _update_connections_near(cell)
    if paired_cell.x != 2147483647: _update_connections_near(paired_cell)
    if BlockBehaviors.family_for_id(id) == "fluid" or _has_fluid_near(cell): _rebuild_fluid_spread()
    if resolve_neighbor_support:
        _resolve_support_loss_near(cell)
        if paired_cell.x != 2147483647: _resolve_support_loss_near(paired_cell)
    _refresh_near_cell(cell)
    if paired_cell.x != 2147483647: _refresh_near_cell(paired_cell)
    _set_dirty(true)
    _redstone_dirty = true
    block_changed.emit(cell, "")
    if BlockBehaviors.family_for_id(id) != "sculk_sensor": _trigger_sculk_sensors_near(cell)
    _recalculate_redstone()
    return true

func _has_valid_support(cell: Vector3i, id: String, state: Dictionary) -> bool:
    var family := BlockBehaviors.family_for_id(id)
    # The upper cell of a tall plant is a virtual half of the lower model. Its support
    # is the paired lower cell, even though plants are intentionally not solid supports.
    if family == "tall_plant" and String(state.get("part", "lower")) == "upper":
        var pair_array: Array = state.get("pair_cell", [])
        if pair_array.size() >= 3:
            var lower_cell := Vector3i(int(pair_array[0]), int(pair_array[1]), int(pair_array[2]))
            return placed_blocks.has(lower_cell) and BlockBehaviors.family_for_id(get_block_id(lower_cell)) == "tall_plant" and String(get_block_state(lower_cell).get("part", "lower")) == "lower"
        return false
    var support := BlockBehaviors.support_cell(cell, id, state)
    var support_id := get_block_id(support)
    var support_family := BlockBehaviors.family_for_id(support_id)

    if id == "lily_pad":
        return support_id == "water"
    if id in ["wheat", "carrots", "potatoes", "beetroots", "melon_stem", "pumpkin_stem", "torchflower_crop", "pitcher_crop"]:
        return support_id == "farmland"
    if id == "nether_wart":
        return support_id == "soul_sand"
    if id == "cactus":
        if support_id not in ["sand", "red_sand", "cactus"]: return false
        for direction in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
            if has_block(cell + direction): return false
        return true
    if id == "sugar_cane":
        if support_id not in ["grass_block", "dirt", "sand", "red_sand", "podzol", "coarse_dirt", "rooted_dirt", "sugar_cane"]: return false
        var bank_cell := support
        for direction in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
            var beside := get_block_id(bank_cell + direction)
            if beside == "water": return true
        return false
    if id == "bamboo":
        return support_id in ["grass_block", "dirt", "sand", "red_sand", "podzol", "coarse_dirt", "rooted_dirt", "moss_block", "mud", "bamboo"]
    if id in ["kelp", "seagrass", "tall_seagrass"]:
        return support_family == "fluid" and support_id == "water"
    if id == "cocoa":
        return support_id in ["jungle_log", "stripped_jungle_log", "jungle_wood", "stripped_jungle_wood"]
    if id == "vine":
        return String(state.get("face", "floor")) == "wall" and BlockBehaviors.is_solid_support(support_id)
    if id in ["weeping_vines", "twisting_vines", "cave_vines", "cave_vines_plant", "weeping_vines_plant", "twisting_vines_plant"]:
        return BlockBehaviors.is_solid_support(support_id)
    if id == "glow_lichen":
        return BlockBehaviors.is_solid_support(support_id)

    # All other support-using families follow their recorded support cell. Ordinary
    # full blocks, slabs, stairs, fences, etc. never enter this path and remain floating.
    return BlockBehaviors.is_solid_support(support_id)

func _resolve_support_loss_near(changed_cell: Vector3i) -> void:
    # Ordinary blocks (stone, planks, slabs, stairs, fences, etc.) intentionally stay
    # floating when unsupported. Only families explicitly marked as requiring a support
    # cell can be removed here; this is not a generic neighbor cascade.
    var frontier: Array[Vector3i] = [changed_cell]
    var removals := 0
    while not frontier.is_empty() and removals < 512:
        var origin: Vector3i = frontier.pop_front()
        # Diagonal scan accounts for sugar-cane's nearby-water rule and adjacent supports.
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                for dz in range(-1, 2):
                    if dx == 0 and dy == 0 and dz == 0: continue
                    var candidate := origin + Vector3i(dx, dy, dz)
                    if not placed_blocks.has(candidate): continue
                    var candidate_id := get_block_id(candidate)
                    var candidate_state := get_block_state(candidate)
                    if not BlockBehaviors.requires_support(candidate_id, candidate_state): continue
                    if _has_valid_support(candidate, candidate_id, candidate_state): continue
                    var paired_cell := Vector3i(2147483647, 2147483647, 2147483647)
                    var pair_array: Array = candidate_state.get("pair_cell", [])
                    if pair_array.size() >= 3:
                        paired_cell = Vector3i(int(pair_array[0]), int(pair_array[1]), int(pair_array[2]))
                    # false prevents recursion; remove_block still handles paired occupancy and visuals.
                    if remove_block(candidate, false):
                        frontier.append(candidate)
                        if paired_cell.x != 2147483647: frontier.append(paired_cell)
                        removals += 1

func _remove_single(cell: Vector3i) -> void:
    placed_blocks.erase(cell)
    var node := placed_nodes.get(cell) as Node3D
    if is_instance_valid(node): node.queue_free()
    placed_nodes.erase(cell)

func use_block(cell: Vector3i, held_item: String = "") -> String:
    var id := get_block_id(cell)
    if id.is_empty(): return "none"
    var state := get_block_state(cell)
    var family := BlockBehaviors.family_for_id(id)
    var action := "none"
    match family:
        "door", "trapdoor", "fence_gate":
            if bool(state.get("powered", false)):
                action = "redstone_controlled"
            else:
                state["open"] = not bool(state.get("open", false))
                action = "opened" if bool(state["open"]) else "closed"
                _update_pair_state(cell, state, "open", bool(state["open"]))
                _replace_state_visual(cell, state)
        "lever":
            state["powered"] = not bool(state.get("powered", false)); action = "powered_on" if state["powered"] else "powered_off"
            _replace_state_visual(cell, state)
        "button":
            state["powered"] = true
            state["pressed_until"] = Time.get_ticks_msec() + 1000
            action = "pressed"
            _replace_state_visual(cell, state)
        "comparator":
            state["mode"] = "subtract" if String(state.get("mode", "compare")) == "compare" else "compare"
            action = "comparator_subtract" if String(state["mode"]) == "subtract" else "comparator_compare"
            _replace_state_visual(cell, state)
        "daylight_sensor":
            state["inverted"] = not bool(state.get("inverted", false))
            action = "daylight_sensor_inverted" if bool(state["inverted"]) else "daylight_sensor_normal"
            _replace_state_visual(cell, state)
        "pressure_plate":
            action = "none"
        "sign":
            action = "edit_sign"
        "container", "machine_container", "shelf":
            state["open"] = true
            _replace_state_visual(cell, state)
            action = "open_container"
        "bed":
            action = "set_spawn"
        "candle", "candle_cake":
            if family == "candle" and held_item == id and int(state.get("count", 1)) < 4:
                state["count"] = int(state.get("count", 1)) + 1
                action = "candle_added"
            else:
                state["lit"] = not bool(state.get("lit", false))
                action = "candle_lit" if bool(state["lit"]) else "candle_extinguished"
            _replace_state_visual(cell, state)
        "composter":
            var compost_level := int(state.get("level", 0))
            if compost_level >= 8 and bool(state.get("ready", false)):
                state["level"] = 0
                state["ready"] = false
                action = "composter_bone_meal"
            elif BlockBehaviors.is_compostable_item(held_item):
                state["level"] = mini(8, compost_level + 1)
                state["ready"] = int(state["level"]) >= 8
                action = "composter_ready" if bool(state["ready"]) else "composter_filled"
            if action != "none": _replace_state_visual(cell, state)
        "bell":
            state["ringing"] = true
            state["ring_until_ms"] = Time.get_ticks_msec() + 1500
            action = "bell_ringing"
            _replace_state_visual(cell, state)
        "explosive":
            if not bool(state.get("armed", false)):
                state["armed"] = true
                _replace_state_visual(cell, state)
                _explode_tnt.call_deferred(cell)
                action = "ignited"
            else:
                action = "already_ignited"
        "display_entity":
            action = "display_entity"
        "fluid":
            action = "none"
        _:
            action = "none"
    if not action.is_empty() and action != "none":
        if placed_blocks.has(cell): _set_record_state(cell, state)
        _set_dirty(true)
        block_used.emit(cell, id, action)
        _recalculate_redstone()
    return action

func _update_pair_state(cell: Vector3i, state: Dictionary, key: String, value: Variant) -> void:
    if not state.has("pair_cell"): return
    var pair: Array = state["pair_cell"]
    if pair.size() < 3: return
    var other := Vector3i(int(pair[0]), int(pair[1]), int(pair[2]))
    if not placed_blocks.has(other): return
    var other_state := get_block_state(other)
    other_state[key] = value
    _set_record_state(other, other_state)
    _replace_state_visual(other, other_state)

func set_sign_text(cell: Vector3i, text_value: String) -> bool:
    if BlockBehaviors.family_for_id(get_block_id(cell)) not in ["sign", "hanging_sign"]: return false
    var state := get_block_state(cell)
    state["text"] = text_value.substr(0, 384)
    _replace_state_visual(cell, state)
    _set_dirty(true)
    return true

func container_contents(cell: Vector3i) -> Array:
    var state := get_block_state(cell)
    var contents: Array = state.get("items", [])
    var family := BlockBehaviors.family_for_id(get_block_id(cell))
    var max_slots := 3 if family == "shelf" else 27
    var result := contents.duplicate(true)
    while result.size() < max_slots: result.append("")
    return result.slice(0, max_slots)

func set_container_contents(cell: Vector3i, contents: Array) -> bool:
    var family := BlockBehaviors.family_for_id(get_block_id(cell))
    if family not in ["container", "machine_container", "shelf"]: return false
    var max_slots := 3 if family == "shelf" else 27
    var state := get_block_state(cell)
    var valid_contents: Array = []
    for index in range(mini(max_slots, contents.size())):
        var item_id := String(contents[index])
        valid_contents.append(item_id if item_id.is_empty() or definitions.has(item_id) else "")
    while valid_contents.size() < max_slots: valid_contents.append("")
    state["items"] = valid_contents
    _set_record_state(cell, state)
    _set_dirty(true)
    _redstone_dirty = true
    _recalculate_redstone()
    return true

func _replace_state_visual(cell: Vector3i, state: Dictionary) -> void:
    if not placed_blocks.has(cell): return
    if BlockBehaviors.is_virtual_pair_cell(state):
        _set_record_state(cell, state)
        _set_dirty(true)
        return
    var record: Dictionary = placed_blocks[cell]
    var id := String(record.get("id", ""))
    var yaw := float(record.get("yaw", 0.0))
    _set_record_state(cell, state)
    var old := placed_nodes.get(cell) as Node3D
    if is_instance_valid(old): old.queue_free()
    placed_nodes.erase(cell)
    if _cell_within_loaded_range(cell):
        if not _instantiate_model_for_cell(cell, id, yaw, state):
            push_warning("Failed rebuilding block state visual at %s" % str(cell))
    _set_dirty(true)

func _update_connections_near(cell: Vector3i) -> void:
    var affected: Array[Vector3i] = [cell, cell + Vector3i.RIGHT, cell + Vector3i.LEFT, cell + Vector3i.UP, cell + Vector3i.DOWN, cell + Vector3i(0,0,1), cell + Vector3i(0,0,-1)]
    for target in affected:
        if not placed_blocks.has(target): continue
        var id := get_block_id(target)
        var family := BlockBehaviors.family_for_id(id)
        if family not in ["fence", "connected_barrier", "redstone_wire", "stairs", "rail"]: continue
        var state := get_block_state(target)
        if family in ["fence", "connected_barrier", "redstone_wire"]:
            var connections: Dictionary = (state.get("connections", {}) as Dictionary).duplicate(true)
            for key in HORIZONTAL_NEIGHBORS:
                var neighbor := target + HORIZONTAL_NEIGHBORS[key]
                var neighbor_id := get_block_id(neighbor)
                var neighbor_family := BlockBehaviors.family_for_id(neighbor_id)
                var connected := false
                if family == "redstone_wire": connected = neighbor_family in ["redstone_wire", "repeater", "comparator", "redstone_lamp", "lever", "button", "pressure_plate", "redstone_source"] or neighbor_id == "redstone_block"
                else: connected = neighbor_family in ["fence", "connected_barrier"] or BlockBehaviors.is_solid_support(neighbor_id)
                connections[key] = connected
            if state.get("connections", {}) != connections:
                state["connections"] = connections
                _replace_state_visual(target, state)
        elif family == "stairs":
            var next_shape := _stairs_shape(target, String(state.get("facing", "south")))
            if String(state.get("shape", "straight")) != next_shape:
                state["shape"] = next_shape
                _replace_state_visual(target, state)
        elif family == "rail":
            var next_rail_shape := _rail_shape(target)
            if String(state.get("shape", "north_south")) != next_rail_shape:
                state["shape"] = next_rail_shape
                _replace_state_visual(target, state)

func _stairs_shape(cell: Vector3i, facing: String) -> String:
    var forward := BlockBehaviors.direction_for_facing(facing)
    var front_cell := cell + forward
    if BlockBehaviors.family_for_id(get_block_id(front_cell)) == "stairs":
        var front_state := get_block_state(front_cell)
        var front_facing := String(front_state.get("facing", "south"))
        if String(front_state.get("half", "bottom")) == String(get_block_state(cell).get("half", "bottom")) and front_facing != facing and front_facing != _opposite_facing(facing):
            var side_sign := _stairs_side_sign(facing, front_facing)
            return "outer_left" if side_sign < 0 else "outer_right"
    var back_cell := cell - forward
    if BlockBehaviors.family_for_id(get_block_id(back_cell)) == "stairs":
        var back_state := get_block_state(back_cell)
        var back_facing := String(back_state.get("facing", "south"))
        if String(back_state.get("half", "bottom")) == String(get_block_state(cell).get("half", "bottom")) and back_facing != facing and back_facing != _opposite_facing(facing):
            var side_sign := _stairs_side_sign(facing, back_facing)
            return "inner_left" if side_sign < 0 else "inner_right"
    return "straight"

func _stairs_side_sign(facing: String, other_facing: String) -> float:
    var forward := Vector3(BlockBehaviors.direction_for_facing(facing))
    var other := Vector3(BlockBehaviors.direction_for_facing(other_facing))
    var cross_y := forward.cross(other).y
    return -1.0 if cross_y > 0.0 else 1.0

func _rail_shape(cell: Vector3i) -> String:
    var north := BlockBehaviors.family_for_id(get_block_id(cell + Vector3i(0, 0, -1))) == "rail"
    var south := BlockBehaviors.family_for_id(get_block_id(cell + Vector3i(0, 0, 1))) == "rail"
    var east := BlockBehaviors.family_for_id(get_block_id(cell + Vector3i.RIGHT)) == "rail"
    var west := BlockBehaviors.family_for_id(get_block_id(cell + Vector3i.LEFT)) == "rail"
    if north and south and not east and not west: return "north_south"
    if east and west and not north and not south: return "east_west"
    if north and east: return "north_east"
    if north and west: return "north_west"
    if south and east: return "south_east"
    if south and west: return "south_west"
    if east or west: return "east_west"
    return "north_south"

func _opposite_facing(facing: String) -> String:
    match facing:
        "north": return "south"
        "south": return "north"
        "east": return "west"
        _: return "east"

func set_player_position(position_value: Vector3) -> void:
    _player_position = position_value

func _process(delta: float) -> void:
    _logic_elapsed += delta
    _hopper_elapsed += delta
    if _logic_elapsed >= 0.12:
        _logic_elapsed = fposmod(_logic_elapsed, 0.12)
        _update_pressure_plates_and_buttons()
        _simulate_falling_blocks()
        if _redstone_dirty or _has_due_redstone_timer(): _recalculate_redstone()
    # Minecraft-style hopper transfers are slower than the common block-state tick.
    # Counts are not modeled yet, so each successful transfer moves one item ID per slot.
    if _hopper_elapsed >= 0.4:
        _hopper_elapsed = fposmod(_hopper_elapsed, 0.4)
        _update_hoppers()

func _simulate_falling_blocks() -> void:
    var candidates: Array[Vector3i] = []
    for cell: Vector3i in placed_blocks.keys():
        if BlockBehaviors.family_for_id(get_block_id(cell)) == "falling_block": candidates.append(cell)
    candidates.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y)
    var changed := false
    var displaced_fluid := false
    for cell in candidates:
        if not placed_blocks.has(cell): continue
        var below := cell + Vector3i.DOWN
        var below_id := get_block_id(below)
        if not below_id.is_empty() and not BlockBehaviors.is_replaceable(below_id):
            continue
        # A falling block displaces a replaceable block in its path, as sand/gravel do
        # in Minecraft. A non-falling stone block is never moved just for lacking support.
        if not below_id.is_empty():
            if BlockBehaviors.family_for_id(below_id) == "fluid": displaced_fluid = true
            var displaced_state := get_block_state(below)
            if placed_blocks.has(below) and displaced_state.has("pair_cell"):
                var pair_array: Array = displaced_state.get("pair_cell", [])
                if pair_array.size() >= 3:
                    var pair_cell := Vector3i(int(pair_array[0]), int(pair_array[1]), int(pair_array[2]))
                    if pair_cell != below: _remove_single(pair_cell)
            _remove_single(below)
        var row: Dictionary = (placed_blocks[cell] as Dictionary).duplicate(true)
        _remove_single(cell)
        removed_cells.erase(below)
        placed_blocks[below] = row
        var state: Dictionary = row.get("state", {})
        state["falling"] = true
        row["state"] = state
        placed_blocks[below] = row
        if not _instantiate_model_for_cell(below, String(row.get("id", "")), float(row.get("yaw", 0.0)), state):
            placed_blocks.erase(below)
            placed_blocks[cell] = row
            _instantiate_model_for_cell(cell, String(row.get("id", "")), float(row.get("yaw", 0.0)), state)
            continue
        _update_connections_near(cell)
        _update_connections_near(below)
        changed = true
    if changed:
        _set_dirty(true)
        _redstone_dirty = true
        _refresh_all_chunks()
        if displaced_fluid and _has_fluid_sources(): _rebuild_fluid_spread()

func _trigger_sculk_sensors_near(changed_cell: Vector3i) -> void:
    var now := Time.get_ticks_msec()
    for sensor_cell: Vector3i in placed_blocks.keys().duplicate():
        if BlockBehaviors.family_for_id(get_block_id(sensor_cell)) != "sculk_sensor": continue
        if Vector3(sensor_cell).distance_to(Vector3(changed_cell)) > 8.0: continue
        _activate_sculk_sensor(sensor_cell, now, Vector3(sensor_cell).distance_to(Vector3(changed_cell)))

func _trigger_sculk_sensors_from_player(player_position: Vector3) -> void:
    var now := Time.get_ticks_msec()
    for sensor_cell: Vector3i in placed_blocks.keys().duplicate():
        if BlockBehaviors.family_for_id(get_block_id(sensor_cell)) != "sculk_sensor": continue
        var distance := Vector3(sensor_cell).distance_to(player_position)
        if distance <= 8.0:
            _activate_sculk_sensor(sensor_cell, now, distance)

func _activate_sculk_sensor(cell: Vector3i, now_ms: int, distance: float) -> void:
    var state := get_block_state(cell)
    if now_ms < int(state.get("cooldown_until_ms", 0)): return
    state["powered"] = true
    state["power"] = clampi(15 - floori(distance), 1, 15)
    state["cooldown_until_ms"] = now_ms + 1000
    _replace_state_visual(cell, state)
    _set_dirty(true)
    _redstone_dirty = true

func _update_pressure_plates_and_buttons() -> void:
    var changed := false
    var now := Time.get_ticks_msec()
    if not _sensor_position_initialized:
        _last_sensor_player_position = _player_position
        _sensor_position_initialized = true
    elif _player_position.distance_to(_last_sensor_player_position) >= 0.18:
        _trigger_sculk_sensors_from_player(_player_position)
        _last_sensor_player_position = _player_position
    for cell: Vector3i in placed_blocks.keys().duplicate():
        var id := get_block_id(cell)
        var family := BlockBehaviors.family_for_id(id)
        var state := get_block_state(cell)
        if family == "button" and bool(state.get("powered", false)) and now >= int(state.get("pressed_until", 0)):
            state["powered"] = false
            _replace_state_visual(cell, state)
            changed = true
        elif family == "pressure_plate":
            var active := absi(cell.x - floori(_player_position.x + 0.5)) == 0 and absi(cell.z - floori(_player_position.z + 0.5)) == 0 and absf(float(cell.y) - _player_position.y) < 1.45
            if bool(state.get("powered", false)) != active:
                state["powered"] = active
                _replace_state_visual(cell, state)
                changed = true
        elif family == "bell" and bool(state.get("ringing", false)) and now >= int(state.get("ring_until_ms", 0)):
            state["ringing"] = false
            _replace_state_visual(cell, state)
            changed = true
        elif family == "sculk_sensor" and bool(state.get("powered", false)) and now >= int(state.get("cooldown_until_ms", 0)):
            state["powered"] = false
            state["power"] = 0
            _replace_state_visual(cell, state)
            changed = true
    if changed:
        _set_dirty(true)
        _redstone_dirty = true


func _update_hoppers() -> void:
    # A lightweight deterministic hopper model: transfer one occupied slot per logic tick.
    # Item counts/stacks are intentionally not fabricated because inventory data stores item IDs.
    for cell: Vector3i in placed_blocks.keys().duplicate():
        if BlockBehaviors.family_for_id(get_block_id(cell)) != "machine_container" or get_block_id(cell) != "hopper": continue
        var hopper_state := get_block_state(cell)
        var hopper_items: Array = hopper_state.get("items", [])
        while hopper_items.size() < 27: hopper_items.append("")
        var moved := false
        var below := cell + Vector3i.DOWN
        var above := cell + Vector3i.UP
        if placed_blocks.has(below) and BlockBehaviors.family_for_id(get_block_id(below)) in ["container", "machine_container"]:
            var target_state := get_block_state(below)
            var target_items: Array = target_state.get("items", [])
            while target_items.size() < 27: target_items.append("")
            for i in range(hopper_items.size()):
                var item_id := String(hopper_items[i])
                if item_id.is_empty(): continue
                for j in range(target_items.size()):
                    if String(target_items[j]).is_empty():
                        target_items[j] = item_id; hopper_items[i] = ""; moved = true; break
                if moved: break
            if moved:
                target_state["items"] = target_items
                _set_record_state(below, target_state)
        if not moved and placed_blocks.has(above) and BlockBehaviors.family_for_id(get_block_id(above)) in ["container", "machine_container"]:
            var source_state := get_block_state(above)
            var source_items: Array = source_state.get("items", [])
            for i in range(source_items.size()):
                var item_id := String(source_items[i])
                if item_id.is_empty(): continue
                for j in range(hopper_items.size()):
                    if String(hopper_items[j]).is_empty():
                        hopper_items[j] = item_id; source_items[i] = ""; moved = true; break
                if moved: break
            if moved:
                source_state["items"] = source_items
                _set_record_state(above, source_state)
        if moved:
            hopper_state["items"] = hopper_items
            _set_record_state(cell, hopper_state)
            _set_dirty(true)
            _redstone_dirty = true

func _has_due_redstone_timer() -> bool:
    var now := Time.get_ticks_msec()
    for cell: Vector3i in placed_blocks.keys():
        if BlockBehaviors.family_for_id(get_block_id(cell)) != "repeater":
            continue
        var state := get_block_state(cell)
        if now >= int(state.get("pending_until_ms", 0)) and bool(state.get("powered", false)) != bool(state.get("pending_power", false)):
            return true
    return false

func _recalculate_redstone() -> void:
    if _logic_guard: return
    _logic_guard = true
    var wire_cells: Array[Vector3i] = []
    var power_levels: Dictionary = {}
    for cell: Vector3i in placed_blocks.keys():
        if BlockBehaviors.family_for_id(get_block_id(cell)) == "redstone_wire":
            wire_cells.append(cell)
            power_levels[cell] = 0
    # Compute wire power in a fresh map on each pass. Old wire power never acts as a source.
    for pass_index in range(16):
        var next_levels: Dictionary = power_levels.duplicate(true)
        var altered := false
        for cell in wire_cells:
            var level := 0
            for offset in BlockBehaviors.neighbor_offsets():
                var neighbor := cell + offset
                var neighbor_id := get_block_id(neighbor)
                var neighbor_family := BlockBehaviors.family_for_id(neighbor_id)
                if neighbor_family == "redstone_wire":
                    # Dust decays by one level for every dust segment.
                    level = maxi(level, int(power_levels.get(neighbor, 0)) - 1)
                else:
                    level = maxi(level, _signal_strength_to(neighbor, cell))
            level = clampi(level, 0, 15)
            if int(next_levels.get(cell, 0)) != level:
                next_levels[cell] = level
                altered = true
        power_levels = next_levels
        if not altered: break
    for cell in wire_cells:
        var state := get_block_state(cell)
        var next_level := int(power_levels.get(cell, 0))
        if int(state.get("power", 0)) != next_level:
            state["power"] = next_level
            _replace_state_visual(cell, state)
            _set_dirty(true)
    var now := Time.get_ticks_msec()
    for cell: Vector3i in placed_blocks.keys().duplicate():
        if not placed_blocks.has(cell): continue
        var id := get_block_id(cell)
        var family := BlockBehaviors.family_for_id(id)
        if family not in ["door", "trapdoor", "fence_gate", "redstone_lamp", "copper_bulb", "redstone_source", "repeater", "comparator", "piston", "explosive", "rail", "machine_container", "daylight_sensor"]: continue
        var state := get_block_state(cell)
        if family == "daylight_sensor":
            var sunlight_level := clampi(roundi(daylight_strength * 15.0), 0, 15)
            var output_level := 15 - sunlight_level if bool(state.get("inverted", false)) else sunlight_level
            if int(state.get("signal_level", 0)) != output_level or bool(state.get("powered", false)) != (output_level > 0):
                state["signal_level"] = output_level
                state["powered"] = output_level > 0
                _replace_state_visual(cell, state)
                _set_dirty(true)
            continue
        var should_power := _is_powered_near(cell, state, family)
        if family == "repeater":
            if should_power != bool(state.get("input_powered", false)):
                state["input_powered"] = should_power
                state["pending_power"] = should_power
                state["pending_until_ms"] = now + maxi(1, int(state.get("delay", 2))) * 100
                _set_record_state(cell, state)
            if now >= int(state.get("pending_until_ms", 0)) and bool(state.get("powered", false)) != bool(state.get("pending_power", false)):
                state["powered"] = bool(state.get("pending_power", false))
                _replace_state_visual(cell, state)
                _set_dirty(true)
            continue
        if family == "explosive" and should_power and not bool(state.get("armed", false)):
            state["armed"] = true
            _set_record_state(cell, state)
            _replace_state_visual(cell, state)
            _explode_tnt.call_deferred(cell)
            continue
        if family == "redstone_source":
            # A redstone torch is off only when its supporting block is powered.
            var face := String(state.get("face", "floor"))
            var support_offset := Vector3i.DOWN if face == "floor" else (Vector3i.UP if face == "ceiling" else -BlockBehaviors.direction_for_facing(String(state.get("facing", "north"))))
            var support_powered := _is_powered_at(cell + support_offset)
            var should_light := not support_powered
            if bool(state.get("lit", true)) != should_light:
                state["lit"] = should_light
                state["powered"] = should_light
                _replace_state_visual(cell, state)
                _set_dirty(true)
        elif family == "comparator":
            var output_level := _comparator_output_level(cell, state)
            if int(state.get("signal_level", 0)) != output_level or bool(state.get("powered", false)) != (output_level > 0):
                state["signal_level"] = output_level
                state["powered"] = output_level > 0
                _replace_state_visual(cell, state)
                _set_dirty(true)
        elif family == "copper_bulb":
            # Copper bulbs toggle on the rising edge of redstone input; removing power
            # does not toggle them back. Store the previous input to avoid repeated flips.
            var previous_input := bool(state.get("input_powered", false))
            var was_lit := bool(state.get("lit", false))
            if should_power and not previous_input:
                state["lit"] = not was_lit
            if previous_input != should_power:
                state["input_powered"] = should_power
            if previous_input != should_power or bool(state.get("lit", false)) != was_lit:
                _set_record_state(cell, state)
                _replace_state_visual(cell, state)
                _set_dirty(true)
        elif family == "redstone_lamp" or family == "rail":
            if bool(state.get("powered", false)) != should_power:
                state["powered"] = should_power
                _replace_state_visual(cell, state)
                _set_dirty(true)
        elif family in ["door", "trapdoor", "fence_gate"]:
            if should_power and not bool(state.get("powered", false)):
                state["powered"] = true
                state["open"] = true
                _update_pair_state(cell, state, "open", true)
                _replace_state_visual(cell, state)
                _set_dirty(true)
            elif not should_power and bool(state.get("powered", false)):
                state["powered"] = false
                state["open"] = false
                _update_pair_state(cell, state, "open", false)
                _replace_state_visual(cell, state)
                _set_dirty(true)
        elif family == "piston":
            if bool(state.get("extended", false)) != should_power: _set_piston_extended(cell, state, should_power)
        elif family == "machine_container" and id in ["dispenser", "dropper"]:
            # Machine inventory is available, but automatic item ejection is not part of this first implementation.
            if bool(state.get("machine_enabled", false)) != should_power:
                state["machine_enabled"] = should_power
                _replace_state_visual(cell, state)
                _set_dirty(true)
    _logic_guard = false
    _redstone_dirty = false

func _is_powered_near(cell: Vector3i, state: Dictionary, family: String) -> bool:
    var facing := BlockBehaviors.direction_for_facing(String(state.get("facing", "south")))
    if family in ["repeater", "comparator"]:
        return _redstone_level_at(cell - facing, cell) > 0
    for offset in BlockBehaviors.neighbor_offsets():
        if family == "piston" and offset == facing: continue
        var neighbor := cell + offset
        if family == "redstone_source":
            var face := String(state.get("face", "floor"))
            var support_offset := Vector3i.DOWN if face == "floor" else (Vector3i.UP if face == "ceiling" else -facing)
            if offset == support_offset: continue
        if _redstone_level_at(neighbor, cell) > 0: return true
    return false

func _signal_strength_to(source_cell: Vector3i, target_cell: Vector3i) -> int:
    var id := get_block_id(source_cell)
    if id.is_empty(): return 0
    if id == "redstone_block": return 15
    var state := get_block_state(source_cell)
    var family := BlockBehaviors.family_for_id(id)
    if family == "redstone_wire": return maxi(0, int(state.get("power", 0)))
    if family in ["lever", "button", "pressure_plate"]:
        return 15 if bool(state.get("powered", false)) else 0
    if family == "redstone_source":
        if not bool(state.get("lit", true)): return 0
        var face := String(state.get("face", "floor"))
        var support_offset := Vector3i.DOWN if face == "floor" else (Vector3i.UP if face == "ceiling" else -BlockBehaviors.direction_for_facing(String(state.get("facing", "north"))))
        return 0 if target_cell == source_cell + support_offset else 15
    if family == "repeater":
        if not bool(state.get("powered", false)): return 0
        return 15 if source_cell + BlockBehaviors.direction_for_facing(String(state.get("facing", "south"))) == target_cell else 0
    if family == "comparator":
        var level := int(state.get("signal_level", 0))
        return level if source_cell + BlockBehaviors.direction_for_facing(String(state.get("facing", "south"))) == target_cell else 0
    if family == "daylight_sensor": return clampi(int(state.get("signal_level", 0)), 0, 15)
    if family == "sculk_sensor": return clampi(int(state.get("power", 0)), 0, 15) if bool(state.get("powered", false)) else 0
    return 0

func _redstone_level_at(source_cell: Vector3i, target_cell: Vector3i) -> int:
    var id := get_block_id(source_cell)
    if id.is_empty(): return 0
    var family := BlockBehaviors.family_for_id(id)
    if family in ["container", "machine_container"]:
        return _container_signal_level(source_cell) if BlockBehaviors.family_for_id(get_block_id(target_cell)) == "comparator" else 0
    if family == "composter" and BlockBehaviors.family_for_id(get_block_id(target_cell)) == "comparator":
        var level := int(get_block_state(source_cell).get("level", 0))
        return clampi(roundi(float(level) / 8.0 * 15.0), 0, 15)
    return _signal_strength_to(source_cell, target_cell)

func _container_signal_level(cell: Vector3i) -> int:
    var state := get_block_state(cell)
    var items: Array = state.get("items", [])
    var occupied := 0
    for item in items:
        if not String(item).is_empty(): occupied += 1
    if occupied == 0: return 0
    return mini(15, ceili(float(occupied) / 27.0 * 14.0) + 1)

func _comparator_output_level(cell: Vector3i, state: Dictionary) -> int:
    var facing := BlockBehaviors.direction_for_facing(String(state.get("facing", "south")))
    var rear_level := _redstone_level_at(cell - facing, cell)
    var side_a := Vector3i(-facing.z, 0, facing.x)
    var side_level := maxi(_redstone_level_at(cell + side_a, cell), _redstone_level_at(cell - side_a, cell))
    if String(state.get("mode", "compare")) == "subtract": return maxi(0, rear_level - side_level)
    return rear_level if rear_level >= side_level else 0

func _is_powered_at(cell: Vector3i) -> bool:
    var id := get_block_id(cell)
    if id.is_empty(): return false
    if id == "redstone_block": return true
    var state := get_block_state(cell)
    var family := BlockBehaviors.family_for_id(id)
    if family == "redstone_wire": return int(state.get("power", 0)) > 0
    if family in ["comparator", "daylight_sensor"]: return int(state.get("signal_level", 0)) > 0
    return BlockBehaviors.is_redstone_source(id, state)

func _set_piston_extended(cell: Vector3i, state: Dictionary, extend: bool) -> void:
    var id := get_block_id(cell)
    var facing := BlockBehaviors.direction_for_facing(String(state.get("facing", "south")))
    var front := cell + facing
    if extend:
        var line: Array[Vector3i] = []
        var scan := front
        while has_block(scan) and line.size() < MAX_PISTON_PUSH:
            if not placed_blocks.has(scan): return
            var moving_id := get_block_id(scan)
            var moving_state := get_block_state(scan)
            if not BlockBehaviors.is_pushable(moving_id, moving_state): return
            line.append(scan)
            scan += facing
        if has_block(scan): return
        for i in range(line.size() - 1, -1, -1):
            var from_cell: Vector3i = line[i]
            var record: Dictionary = (placed_blocks[from_cell] as Dictionary).duplicate(true)
            var to_cell := from_cell + facing
            _remove_single(from_cell)
            removed_cells.erase(to_cell)
            placed_blocks[to_cell] = record
            _instantiate_model_for_cell(to_cell, String(record["id"]), float(record.get("yaw", 0.0)), record.get("state", {}))
        var head_id := "piston_head" if definitions.has("piston_head") else id
        if not has_block(front):
            var head_state := BlockBehaviors.default_state(head_id, state.get("yaw", 0.0))
            head_state["family"] = "piston_head"
            _create_placed_record(front, head_id, float(state.get("yaw", 0.0)), head_state)
        state["extended"] = true
    else:
        var head_state := get_block_state(front)
        if has_block(front) and (get_block_id(front) == "piston_head" or (head_state as Dictionary).get("family", "") == "piston_head"):
            _remove_single(front)
        state["extended"] = false
        if bool(state.get("sticky", false)):
            var pull_cell := front + facing
            if has_block(pull_cell) and not has_block(front) and BlockBehaviors.is_solid_support(get_block_id(pull_cell)):
                var record: Dictionary = (placed_blocks.get(pull_cell, {}) as Dictionary).duplicate(true)
                if not record.is_empty():
                    _remove_single(pull_cell)
                    placed_blocks[front] = record
                    _instantiate_model_for_cell(front, String(record.get("id", "")), float(record.get("yaw", 0.0)), record.get("state", {}))
    _set_record_state(cell, state)
    _replace_state_visual(cell, state)
    _set_dirty(true)
    _refresh_near_cell(cell)


func merge_slab(cell: Vector3i) -> bool:
    if BlockBehaviors.family_for_id(get_block_id(cell)) != "slab": return false
    var state := get_block_state(cell)
    if bool(state.get("double", false)): return false
    state["double"] = true
    _replace_state_visual(cell, state)
    _set_dirty(true)
    _refresh_near_cell(cell)
    return true

func _has_fluid_near(cell: Vector3i) -> bool:
    for offset in BlockBehaviors.neighbor_offsets():
        if BlockBehaviors.family_for_id(get_block_id(cell + offset)) == "fluid": return true
    return false

func _explode_tnt(cell: Vector3i) -> void:
    await get_tree().create_timer(1.5).timeout
    if not is_inside_tree() or get_block_id(cell) != "tnt" or not bool(get_block_state(cell).get("armed", false)): return
    var affected: Array[Vector3i] = []
    for x in range(cell.x - 3, cell.x + 4):
        for y in range(cell.y - 3, cell.y + 4):
            for z in range(cell.z - 3, cell.z + 4):
                var candidate := Vector3i(x, y, z)
                if Vector3(candidate).distance_to(Vector3(cell)) <= 3.25 and has_block(candidate) and get_block_id(candidate) != "bedrock":
                    affected.append(candidate)
    for candidate in affected:
        var id := get_block_id(candidate)
        if placed_blocks.has(candidate):
            var state := get_block_state(candidate)
            if state.has("pair_cell"):
                var pair_array: Array = state.get("pair_cell", [])
                if pair_array.size() >= 3:
                    var pair_cell := Vector3i(int(pair_array[0]), int(pair_array[1]), int(pair_array[2]))
                    if pair_cell != candidate: _remove_single(pair_cell)
            _remove_single(candidate)
        elif not _base_block_id(candidate).is_empty(): removed_cells[candidate] = true
    # Explosion removes only cells in its blast region; it does not cascade-delete
    # blocks outside that region merely because their support was destroyed.
    _refresh_all_chunks()
    _set_dirty(true)
    _update_connections_near(cell)
    if _has_fluid_sources(): _rebuild_fluid_spread()
    _recalculate_redstone()

func _has_fluid_sources() -> bool:
    for cell: Vector3i in placed_blocks.keys():
        if BlockBehaviors.family_for_id(get_block_id(cell)) == "fluid" and bool(get_block_state(cell).get("source", true)): return true
    return false

func _resolve_fluid_reactions(fluid_rows: Array[Dictionary]) -> void:
    var reactions: Dictionary = {}
    for source in fluid_rows:
        var cell: Vector3i = source["cell"]
        var id := String(source["id"])
        var state: Dictionary = source.get("state", {})
        for offset in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i(0,0,1), Vector3i(0,0,-1)]:
            var neighbor := cell + offset
            var neighbor_id := get_block_id(neighbor)
            if BlockBehaviors.family_for_id(neighbor_id) != "fluid" or neighbor_id == id: continue
            var lava_cell := cell if id == "lava" else neighbor
            var lava_state := get_block_state(lava_cell)
            var result_id := "obsidian" if bool(lava_state.get("source", true)) else "cobblestone"
            reactions[lava_cell] = result_id
    for raw_cell in reactions.keys():
        var cell: Vector3i = raw_cell
        var result_id := String(reactions[cell])
        if not definitions.has(result_id): continue
        if placed_blocks.has(cell): _remove_single(cell)
        removed_cells.erase(cell)
        _create_placed_record(cell, result_id, 0.0, BlockBehaviors.default_state(result_id))
        _set_dirty(true)

func _rebuild_fluid_spread() -> void:
    var all_fluids: Array[Dictionary] = []
    var sources: Array[Dictionary] = []
    for cell: Vector3i in placed_blocks.keys().duplicate():
        if BlockBehaviors.family_for_id(get_block_id(cell)) != "fluid": continue
        var state := get_block_state(cell)
        var record: Dictionary = placed_blocks[cell]
        var row := {"cell": cell, "id": get_block_id(cell), "state": state.duplicate(true), "yaw": float(record.get("yaw", 0.0))}
        all_fluids.append(row)
        if bool(state.get("source", true)): sources.append(row)
    _resolve_fluid_reactions(all_fluids)
    for cell: Vector3i in placed_blocks.keys().duplicate():
        if BlockBehaviors.family_for_id(get_block_id(cell)) == "fluid" and not bool(get_block_state(cell).get("source", true)):
            _remove_single(cell)
    sources.clear()
    for source_cell: Vector3i in placed_blocks.keys():
        if BlockBehaviors.family_for_id(get_block_id(source_cell)) == "fluid" and bool(get_block_state(source_cell).get("source", true)):
            sources.append({"cell": source_cell, "id": get_block_id(source_cell), "state": get_block_state(source_cell).duplicate(true), "yaw": float((placed_blocks[source_cell] as Dictionary).get("yaw", 0.0))})
    var queue: Array[Dictionary] = []
    for source in sources: queue.append({"cell": source["cell"], "id": source["id"], "level": 0, "source": true})
    var visited: Dictionary = {}
    var index := 0
    while index < queue.size() and visited.size() < MAX_FLUID_CELLS:
        var entry: Dictionary = queue[index]
        index += 1
        var cell: Vector3i = entry["cell"]
        var id := String(entry["id"])
        var level := int(entry["level"])
        var key := "%s:%d:%d:%d" % [id, cell.x, cell.y, cell.z]
        if visited.has(key): continue
        visited[key] = true
        if not bool(entry["source"]):
            var occupied := get_block_id(cell)
            if not occupied.is_empty() and BlockBehaviors.family_for_id(occupied) != "fluid": continue
            if not occupied.is_empty() and occupied != id: continue
            if not placed_blocks.has(cell):
                var fluid_state := BlockBehaviors.default_state(id)
                fluid_state["source"] = false
                fluid_state["level"] = level
                fluid_state["flowing"] = true
                _create_placed_record(cell, id, 0.0, fluid_state)
        if level >= (7 if id == "water" else 3): continue
        var down := cell + Vector3i.DOWN
        if get_block_id(down).is_empty():
            queue.append({"cell": down, "id": id, "level": level, "source": false})
            continue
        for d in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i(0,0,1), Vector3i(0,0,-1)]:
            var next_cell: Vector3i = cell + d
            if get_block_id(next_cell).is_empty(): queue.append({"cell": next_cell, "id": id, "level": level + 1, "source": false})
    _refresh_all_chunks()

func _refresh_all_chunks() -> void:
    for key: Vector2i in chunks.keys(): _build_chunk_mesh(key, chunks[key])

func _set_dirty(value: bool) -> void:
    if dirty == value: return
    dirty = value
    world_dirty_changed.emit(dirty)

func mark_saved() -> void:
    _set_dirty(false)

func _refresh_near_cell(cell: Vector3i) -> void:
    var cx := floori(cell.x / float(CHUNK_SIZE))
    var cz := floori(cell.z / float(CHUNK_SIZE))
    for z in range(cz - 1, cz + 2):
        for x in range(cx - 1, cx + 2):
            var key := Vector2i(x, z)
            if chunks.has(key): _build_chunk_mesh(key, chunks[key])

func _create_chunk(key: Vector2i) -> void:
    var root := Node3D.new()
    root.name = "Chunk_%d_%d" % [key.x, key.y]
    add_child(root)
    var visual := MeshInstance3D.new(); visual.name = "TerrainMesh"; root.add_child(visual)
    var body := StaticBody3D.new(); body.name = "TerrainCollision"; body.collision_layer = 1; body.collision_mask = 0
    var collision := CollisionShape3D.new(); collision.name = "CollisionShape"; body.add_child(collision); root.add_child(body)
    chunks[key] = {"root": root, "visual": visual, "body": body, "collision": collision}
    _build_chunk_mesh(key, chunks[key])

func _build_chunk_mesh(key: Vector2i, entry: Dictionary) -> void:
    var ids := ["grass_block", "dirt", "bedrock"]
    var vertices_by_id: Dictionary = {}; var normals_by_id: Dictionary = {}; var uvs_by_id: Dictionary = {}
    for id in ids: vertices_by_id[id] = []; normals_by_id[id] = []; uvs_by_id[id] = []
    var start_x := key.x * CHUNK_SIZE; var start_z := key.y * CHUNK_SIZE
    for lx in range(CHUNK_SIZE):
        for lz in range(CHUNK_SIZE):
            var x := start_x + lx; var z := start_z + lz
            for y in [-3, -2, -1, 0]:
                var cell := Vector3i(x, y, z)
                if not _is_base_visible(cell): continue
                var id := _base_block_id(cell)
                if not vertices_by_id.has(id): continue
                for face_index in range(6):
                    if not get_block_id(cell + FACE_NORMALS[face_index]).is_empty(): continue
                    _append_face(vertices_by_id[id], normals_by_id[id], uvs_by_id[id], Vector3(lx, y, lz), face_index)
    var mesh := ArrayMesh.new(); var used_ids: Array[String] = []
    for id in ids:
        var vertices: Array = vertices_by_id[id]
        if vertices.is_empty(): continue
        var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
        arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals_by_id[id])
        arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uvs_by_id[id])
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        used_ids.append(id)
    for surface_index in range(used_ids.size()):
        var id := used_ids[surface_index]
        var material: Material = resolver.material_for_model(definitions[id]) if definitions.has(id) and resolver != null else null
        if material != null: mesh.surface_set_material(surface_index, material)
    var visual := entry["visual"] as MeshInstance3D
    visual.mesh = mesh if not used_ids.is_empty() else null
    visual.position = Vector3(start_x, 0.0, start_z)
    var body := entry["body"] as StaticBody3D; body.position = Vector3(start_x, 0.0, start_z)
    var collision := entry["collision"] as CollisionShape3D
    collision.shape = mesh.create_trimesh_shape() if mesh.get_surface_count() > 0 else null
    (entry["root"] as Node3D).position = Vector3.ZERO

func _append_face(vertices: Array, normals: Array, uvs: Array, center: Vector3, face_index: int) -> void:
    var h := 0.5
    var q: Array[Vector3] = []
    match face_index:
        0: q = [center + Vector3(h,-h,-h), center + Vector3(h,h,-h), center + Vector3(h,h,h), center + Vector3(h,-h,h)]
        1: q = [center + Vector3(-h,-h,h), center + Vector3(-h,h,h), center + Vector3(-h,h,-h), center + Vector3(-h,-h,-h)]
        2: q = [center + Vector3(-h,h,-h), center + Vector3(-h,h,h), center + Vector3(h,h,h), center + Vector3(h,h,-h)]
        3: q = [center + Vector3(-h,-h,h), center + Vector3(-h,-h,-h), center + Vector3(h,-h,-h), center + Vector3(h,-h,h)]
        4: q = [center + Vector3(-h,-h,h), center + Vector3(h,-h,h), center + Vector3(h,h,h), center + Vector3(-h,h,h)]
        5: q = [center + Vector3(h,-h,-h), center + Vector3(-h,-h,-h), center + Vector3(-h,h,-h), center + Vector3(h,h,-h)]
    var face_normal := FACE_NORMALS[face_index]; var normal := Vector3(face_normal)
    var uv_quads: Array[Vector2] = [Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)]
    for index in [0, 1, 2, 0, 2, 3]:
        vertices.append(q[index]); normals.append(normal); uvs.append(uv_quads[index])

func all_placed_for_save() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for cell: Vector3i in placed_blocks.keys():
        var row: Dictionary = placed_blocks[cell]
        var state: Dictionary = row.get("state", {})
        if bool(state.get("flowing", false)): continue
        out.append({"cell": [cell.x, cell.y, cell.z], "id": String(row.get("id", "")), "yaw": float(row.get("yaw", 0.0)), "state": state.duplicate(true)})
    return out

func removed_for_save() -> Array[Array]:
    var out: Array[Array] = []
    for cell: Vector3i in removed_cells.keys(): out.append([cell.x, cell.y, cell.z])
    return out

func restore_state(placed_rows: Array, removed_rows: Array) -> void:
    for node in placed_nodes.values():
        if is_instance_valid(node): (node as Node3D).queue_free()
    placed_nodes.clear(); placed_blocks.clear(); removed_cells.clear()
    for row in removed_rows:
        if row is Array and row.size() == 3: removed_cells[Vector3i(int(row[0]), int(row[1]), int(row[2]))] = true
    for row in placed_rows:
        if not row is Dictionary: continue
        var c: Array = row.get("cell", [])
        if c.size() < 3: continue
        var cell := Vector3i(int(c[0]), int(c[1]), int(c[2]))
        var id := String(row.get("id", "")); var yaw := float(row.get("yaw", 0.0))
        if not definitions.has(id): continue
        var state: Dictionary = row.get("state", BlockBehaviors.default_state(id, yaw)).duplicate(true)
        removed_cells.erase(cell)
        placed_blocks[cell] = {"id": id, "yaw": yaw, "state": state}
        if not BlockBehaviors.is_virtual_pair_cell(state) and _cell_within_loaded_range(cell) and not _instantiate_model_for_cell(cell, id, yaw, state):
            placed_blocks.erase(cell)
    for key: Vector2i in chunks.keys(): _build_chunk_mesh(key, chunks[key])
    dirty = false
    _last_center_chunk = Vector2i(2147483647, 2147483647)
    for restored_cell: Vector3i in placed_blocks.keys().duplicate():
        _update_connections_near(restored_cell)
    _recalculate_redstone()
    if _has_fluid_sources(): _rebuild_fluid_spread()

func save_changed_state() -> void:
    _set_dirty(true)