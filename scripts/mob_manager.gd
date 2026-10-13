extends Node3D
class_name MineblockMobManager

signal mob_died(kind: String, position: Vector3)
signal mob_hit(kind: String, remaining_health: int)

const PASSIVE_KINDS: Array[String] = ["pig", "cow", "sheep", "chicken"]
const HOSTILE_KINDS: Array[String] = ["zombie", "skeleton", "creeper", "spider"]
const MAX_PASSIVE_MOBS: int = 5
const MAX_HOSTILE_MOBS: int = 4

var world: CreativeWorldManager
var player: PlayerController
var daylight_strength: float = 1.0
var _spawn_elapsed: float = 0.0
var _rng := RandomNumberGenerator.new()
var mobs: Array[Dictionary] = []

func _ready() -> void:
    _rng.randomize()
    _spawn_elapsed = 2.0

func configure(world_ref: CreativeWorldManager, player_ref: PlayerController) -> void:
    world = world_ref
    player = player_ref

func set_daylight_strength(value: float) -> void:
    daylight_strength = clampf(value, 0.0, 1.0)

func get_mob_count() -> int:
    var count := 0
    for row in mobs:
        if is_instance_valid(row.get("node") as Node3D):
            count += 1
    return count

func get_mob_counts() -> Dictionary:
    var result := {"passive": 0, "hostile": 0}
    for row in mobs:
        var node := row.get("node") as Node3D
        if not is_instance_valid(node):
            continue
        var kind := String(row.get("kind", ""))
        if kind in HOSTILE_KINDS:
            result["hostile"] = int(result["hostile"]) + 1
        else:
            result["passive"] = int(result["passive"]) + 1
    return result

func spawn_mob(kind: String, at: Vector3, natural: bool = false, saved_health: int = -1) -> Node3D:
    if kind not in PASSIVE_KINDS and kind not in HOSTILE_KINDS:
        return null
    if world == null:
        return null
    var spawn_position := at
    if natural:
        var surface_y := _surface_y(at.x, at.z)
        if surface_y < -100.0:
            return null
        spawn_position.y = surface_y
    var root := Node3D.new()
    root.name = "Mob_" + kind
    root.set_meta("mob_kind", kind)
    _build_mob_model(root, kind)
    add_child(root)
    root.global_position = spawn_position
    var hostile := kind in HOSTILE_KINDS
    var max_health := 20 if hostile else 10
    mobs.append({
        "node": root,
        "kind": kind,
        "health": clampi(saved_health, 1, max_health) if saved_health > 0 else max_health,
        "max_health": max_health,
        "attack_elapsed": _rng.randf_range(0.3, 1.0),
        "wander_elapsed": 0.0,
        "wander_direction": Vector3.ZERO,
        "fuse_elapsed": 0.0,
        "hostile": hostile
    })
    return root

func clear_mobs() -> void:
    for row in mobs:
        var node := row.get("node") as Node3D
        if is_instance_valid(node):
            node.queue_free()
    mobs.clear()
    _spawn_elapsed = 2.0

func save_state() -> Array[Dictionary]:
    var saved: Array[Dictionary] = []
    for row in mobs:
        var node := row.get("node") as Node3D
        if not is_instance_valid(node):
            continue
        saved.append({
            "kind": String(row.get("kind", "")),
            "position": [node.global_position.x, node.global_position.y, node.global_position.z],
            "health": int(row.get("health", 10))
        })
    return saved

func restore_state(rows: Array) -> void:
    clear_mobs()
    for value in rows:
        if not value is Dictionary:
            continue
        var row: Dictionary = value
        var kind := String(row.get("kind", ""))
        var position_values: Array = row.get("position", [])
        if position_values.size() < 3:
            continue
        var at := Vector3(float(position_values[0]), float(position_values[1]), float(position_values[2]))
        spawn_mob(kind, at, false, int(row.get("health", -1)))

func attack_mob_from_ray(origin: Vector3, direction: Vector3, max_distance: float = 7.0, damage: int = 4) -> String:
    if mobs.is_empty():
        return ""
    var ray_direction := direction.normalized()
    var closest_index := -1
    var closest_distance := max_distance + 1.0
    for index in range(mobs.size()):
        var node := mobs[index].get("node") as Node3D
        if not is_instance_valid(node):
            continue
        var kind := String(mobs[index].get("kind", ""))
        var center_height := 0.55 if kind in ["pig", "chicken", "spider"] else 0.92
        var mob_center := node.global_position + Vector3.UP * center_height
        var to_center := mob_center - origin
        var along := to_center.dot(ray_direction)
        if along < 0.0 or along > max_distance or along >= closest_distance:
            continue
        var closest_point := origin + ray_direction * along
        var radius := 0.78 if kind in ["cow", "sheep", "zombie", "skeleton"] else 0.66
        if mob_center.distance_to(closest_point) <= radius:
            closest_index = index
            closest_distance = along
    if closest_index < 0:
        return ""
    var row: Dictionary = mobs[closest_index]
    var kind := String(row.get("kind", ""))
    var remaining := int(row.get("health", 10)) - maxi(1, damage)
    if remaining <= 0:
        var node := row.get("node") as Node3D
        var death_position := node.global_position if is_instance_valid(node) else Vector3.ZERO
        if is_instance_valid(node):
            node.queue_free()
        mobs.remove_at(closest_index)
        mob_died.emit(kind, death_position)
    else:
        row["health"] = remaining
        mobs[closest_index] = row
        mob_hit.emit(kind, remaining)
    return kind

func _process(delta: float) -> void:
    if world == null or player == null or not is_instance_valid(player):
        return
    if player.gameplay_paused:
        return
    _spawn_elapsed -= delta
    if _spawn_elapsed <= 0.0:
        _spawn_elapsed = 5.0
        _try_natural_spawn()
    for index in range(mobs.size() - 1, -1, -1):
        if index >= mobs.size():
            continue
        var row: Dictionary = mobs[index]
        var node := row.get("node") as Node3D
        if not is_instance_valid(node):
            mobs.remove_at(index)
            continue
        var kind := String(row.get("kind", ""))
        var hostile := bool(row.get("hostile", false))
        var attack_elapsed := float(row.get("attack_elapsed", 0.0)) - delta
        var wander_elapsed := float(row.get("wander_elapsed", 0.0)) - delta
        var target_direction := Vector3.ZERO
        var to_player := player.global_position - node.global_position
        to_player.y = 0.0
        var distance_to_player := to_player.length()
        if hostile and distance_to_player < 16.0:
            target_direction = to_player.normalized()
            var speed := 2.15 if kind == "zombie" else (1.85 if kind == "spider" else 1.65)
            _move_mob(node, target_direction, speed, delta)
            if kind == "creeper":
                var fuse := float(row.get("fuse_elapsed", 0.0))
                if distance_to_player <= 3.0:
                    fuse += delta
                    if fuse >= 1.6:
                        _detonate_creeper(index)
                        continue
                    node.scale = Vector3.ONE * (1.0 + 0.06 * sin(fuse * 24.0))
                else:
                    fuse = maxf(0.0, fuse - delta * 2.5)
                    node.scale = Vector3.ONE
                row["fuse_elapsed"] = fuse
            elif kind == "skeleton":
                if distance_to_player <= 11.0 and attack_elapsed <= 0.0:
                    if player.has_method("apply_damage"):
                        player.apply_damage(3)
                    attack_elapsed = 2.0
            elif distance_to_player <= 1.45 and attack_elapsed <= 0.0:
                if player.has_method("apply_damage"):
                    player.apply_damage(2 if kind == "spider" else 3)
                attack_elapsed = 1.2
        else:
            if wander_elapsed <= 0.0:
                target_direction = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
                wander_elapsed = _rng.randf_range(1.2, 3.5)
            else:
                target_direction = (row.get("wander_direction", Vector3.ZERO) as Vector3)
                if target_direction.length_squared() > 0.01:
                    _move_mob(node, target_direction, 0.65 if not hostile else 0.45, delta)
        row["wander_direction"] = target_direction
        row["wander_elapsed"] = wander_elapsed
        row["attack_elapsed"] = attack_elapsed
        mobs[index] = row

func _try_natural_spawn() -> void:
    var counts := get_mob_counts()
    var kind := ""
    if daylight_strength >= 0.28 and int(counts["passive"]) < MAX_PASSIVE_MOBS:
        kind = PASSIVE_KINDS[_rng.randi_range(0, PASSIVE_KINDS.size() - 1)]
    elif daylight_strength <= 0.09 and int(counts["hostile"]) < MAX_HOSTILE_MOBS:
        kind = HOSTILE_KINDS[_rng.randi_range(0, HOSTILE_KINDS.size() - 1)]
    if kind.is_empty():
        return
    for attempt in range(8):
        var angle := _rng.randf_range(0.0, TAU)
        var radius := _rng.randf_range(7.0, 13.0)
        var x := player.global_position.x + cos(angle) * radius
        var z := player.global_position.z + sin(angle) * radius
        var surface_y := _surface_y(x, z)
        if surface_y < -100.0:
            continue
        if _surface_y(player.global_position.x, player.global_position.z) < -100.0:
            continue
        spawn_mob(kind, Vector3(x, surface_y, z), true)
        return

func _move_mob(node: Node3D, direction: Vector3, speed: float, delta: float) -> void:
    if direction.length_squared() < 0.01:
        return
    var step := direction.normalized() * speed * delta
    var target_x := node.global_position.x + step.x
    var target_z := node.global_position.z + step.z
    var target_y := _surface_y(target_x, target_z)
    if target_y < -100.0 or absf(target_y - node.global_position.y) > 1.05:
        return
    node.global_position = Vector3(target_x, target_y, target_z)
    node.rotation.y = atan2(direction.x, direction.z)

func _surface_y(x: float, z: float) -> float:
    if world == null:
        return -999.0
    var cell_x := floori(x + 0.5)
    var cell_z := floori(z + 0.5)
    for y in range(32, -5, -1):
        if world.has_block(Vector3i(cell_x, y, cell_z)):
            return float(y) + 0.5
    return -999.0

func _detonate_creeper(index: int) -> void:
    if index < 0 or index >= mobs.size():
        return
    var row: Dictionary = mobs[index]
    var node := row.get("node") as Node3D
    if not is_instance_valid(node):
        mobs.remove_at(index)
        return
    var center := node.global_position
    if player != null and center.distance_to(player.global_position) <= 3.5 and player.has_method("apply_damage"):
        player.apply_damage(8)
    var cells_to_break: Array[Vector3i] = []
    for cell_value in world.placed_blocks.keys():
        var cell: Vector3i = cell_value
        if Vector3(cell).distance_to(center) <= 2.8:
            cells_to_break.append(cell)
    # Copy first, then remove; paired structures clean themselves up atomically.
    for cell in cells_to_break:
        if world.has_block(cell):
            world.remove_block(cell)
    var kind := String(row.get("kind", "creeper"))
    node.queue_free()
    mobs.remove_at(index)
    mob_died.emit(kind, center)

func _build_mob_model(root: Node3D, kind: String) -> void:
    match kind:
        "pig":
            _box(root, "Body", Vector3(0.92, 0.58, 1.12), Vector3(0, 0.62, 0), Color(0.91, 0.55, 0.60))
            _box(root, "Head", Vector3(0.50, 0.46, 0.43), Vector3(0, 0.82, -0.63), Color(0.96, 0.64, 0.68))
            _box(root, "Snout", Vector3(0.27, 0.19, 0.12), Vector3(0, 0.68, -0.90), Color(0.77, 0.34, 0.41))
            _eyes(root, 0.12, 0.88, -0.83, Color(0.08, 0.06, 0.07))
            _four_legs(root, Color(0.79, 0.41, 0.47), 0.36)
        "cow":
            _box(root, "Body", Vector3(1.02, 0.78, 1.22), Vector3(0, 0.74, 0), Color(0.89, 0.86, 0.79))
            _box(root, "Head", Vector3(0.52, 0.55, 0.47), Vector3(0, 0.99, -0.69), Color(0.83, 0.73, 0.62))
            _box(root, "Muzzle", Vector3(0.32, 0.20, 0.18), Vector3(0, 0.79, -0.98), Color(0.73, 0.52, 0.43))
            _box(root, "SpotLeft", Vector3(0.22, 0.28, 0.055), Vector3(-0.34, 0.81, -0.14), Color(0.23, 0.15, 0.11))
            _box(root, "SpotRight", Vector3(0.25, 0.25, 0.055), Vector3(0.33, 0.66, 0.25), Color(0.23, 0.15, 0.11))
            _eyes(root, 0.14, 1.05, -0.88, Color(0.10, 0.07, 0.05))
            _four_legs(root, Color(0.28, 0.20, 0.15), 0.39)
        "sheep":
            _box(root, "WoolBody", Vector3(1.02, 0.76, 1.12), Vector3(0, 0.75, 0), Color(0.91, 0.91, 0.87))
            _box(root, "Head", Vector3(0.42, 0.44, 0.43), Vector3(0, 0.94, -0.66), Color(0.72, 0.60, 0.55))
            _eyes(root, 0.13, 0.99, -0.88, Color(0.12, 0.10, 0.10))
            _four_legs(root, Color(0.56, 0.43, 0.39), 0.38)
        "chicken":
            _box(root, "Body", Vector3(0.48, 0.54, 0.58), Vector3(0, 0.58, 0), Color(0.92, 0.91, 0.86))
            _box(root, "Head", Vector3(0.30, 0.30, 0.30), Vector3(0, 0.98, -0.23), Color(0.95, 0.92, 0.86))
            _box(root, "Beak", Vector3(0.17, 0.10, 0.17), Vector3(0, 0.93, -0.44), Color(0.95, 0.57, 0.10))
            _box(root, "Comb", Vector3(0.10, 0.12, 0.09), Vector3(0, 1.18, -0.23), Color(0.76, 0.12, 0.10))
            _eyes(root, 0.08, 1.01, -0.38, Color(0.09, 0.07, 0.06))
            _box(root, "LegLeft", Vector3(0.08, 0.24, 0.08), Vector3(-0.13, 0.12, 0), Color(0.90, 0.54, 0.12))
            _box(root, "LegRight", Vector3(0.08, 0.24, 0.08), Vector3(0.13, 0.12, 0), Color(0.90, 0.54, 0.12))
        "zombie":
            _humanoid(root, Color(0.25, 0.52, 0.28), Color(0.17, 0.31, 0.67), Color(0.16, 0.39, 0.19))
        "skeleton":
            _humanoid(root, Color(0.79, 0.78, 0.71), Color(0.81, 0.80, 0.74), Color(0.22, 0.22, 0.20))
        "creeper":
            _box(root, "Body", Vector3(0.48, 0.74, 0.34), Vector3(0, 0.82, 0), Color(0.19, 0.56, 0.22))
            _box(root, "Head", Vector3(0.50, 0.48, 0.48), Vector3(0, 1.40, -0.02), Color(0.23, 0.62, 0.26))
            _box(root, "EyeLeft", Vector3(0.11, 0.09, 0.025), Vector3(-0.12, 1.48, -0.268), Color(0.04, 0.12, 0.05))
            _box(root, "EyeRight", Vector3(0.11, 0.09, 0.025), Vector3(0.12, 1.48, -0.268), Color(0.04, 0.12, 0.05))
            _box(root, "Mouth", Vector3(0.21, 0.13, 0.025), Vector3(0, 1.31, -0.268), Color(0.04, 0.12, 0.05))
            for x in [-0.15, 0.15]:
                for z in [-0.10, 0.12]:
                    _box(root, "Leg", Vector3(0.18, 0.34, 0.18), Vector3(x, 0.20, z), Color(0.18, 0.49, 0.19))
        "spider":
            _box(root, "Abdomen", Vector3(0.66, 0.36, 0.68), Vector3(0, 0.42, 0.20), Color(0.13, 0.10, 0.09))
            _box(root, "Head", Vector3(0.42, 0.30, 0.38), Vector3(0, 0.45, -0.36), Color(0.18, 0.13, 0.11))
            _box(root, "EyeLeft", Vector3(0.10, 0.06, 0.025), Vector3(-0.12, 0.49, -0.56), Color(0.85, 0.05, 0.035))
            _box(root, "EyeRight", Vector3(0.10, 0.06, 0.025), Vector3(0.12, 0.49, -0.56), Color(0.85, 0.05, 0.035))
            for side in [-1.0, 1.0]:
                for index in range(4):
                    var z := -0.34 + float(index) * 0.22
                    _box(root, "Leg_%s_%d" % [str(side), index], Vector3(0.58, 0.09, 0.10), Vector3(side * 0.48, 0.31, z), Color(0.10, 0.08, 0.07), Vector3(0, 0, side * 0.22))
        _:
            _humanoid(root, Color(0.3, 0.5, 0.3), Color(0.3, 0.3, 0.6), Color(0.15, 0.3, 0.2))

func _humanoid(root: Node3D, head_color: Color, body_color: Color, leg_color: Color) -> void:
    _box(root, "Head", Vector3(0.42, 0.42, 0.42), Vector3(0, 1.72, 0), head_color)
    _box(root, "Body", Vector3(0.48, 0.64, 0.26), Vector3(0, 1.16, 0), body_color)
    _box(root, "ArmLeft", Vector3(0.16, 0.64, 0.18), Vector3(-0.34, 1.18, -0.10), head_color, Vector3(0, 0, -0.22))
    _box(root, "ArmRight", Vector3(0.16, 0.64, 0.18), Vector3(0.34, 1.18, -0.10), head_color, Vector3(0, 0, 0.22))
    _box(root, "LegLeft", Vector3(0.20, 0.60, 0.22), Vector3(-0.13, 0.39, 0), leg_color)
    _box(root, "LegRight", Vector3(0.20, 0.60, 0.22), Vector3(0.13, 0.39, 0), leg_color)
    _eyes(root, 0.11, 1.76, -0.224, Color(0.13, 0.04, 0.03))

func _four_legs(root: Node3D, color: Color, z_offset: float) -> void:
    for x in [-0.28, 0.28]:
        for z in [-z_offset, z_offset]:
            _box(root, "Leg", Vector3(0.18, 0.36, 0.18), Vector3(x, 0.18, z), color)

func _eyes(root: Node3D, half_spacing: float, y: float, front_z: float, color: Color) -> void:
    _box(root, "EyeLeft", Vector3(0.055, 0.06, 0.025), Vector3(-half_spacing, y, front_z), color)
    _box(root, "EyeRight", Vector3(0.055, 0.06, 0.025), Vector3(half_spacing, y, front_z), color)

func _box(root: Node3D, part_name: String, size: Vector3, part_position: Vector3, color: Color, part_rotation: Vector3 = Vector3.ZERO) -> void:
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = part_name
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.92
    mesh_instance.material_override = material
    mesh_instance.position = part_position
    mesh_instance.rotation = part_rotation
    root.add_child(mesh_instance)
