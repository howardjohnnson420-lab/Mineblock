extends Node3D

const REGISTRY_PATH := "res://data/asset_registry.json"
const SAVE_PATH := "user://creative_flatworld_save.json"
const TEMP_SAVE_PATH := "user://creative_flatworld_save.tmp"
const SAVE_BACKUP_PATH := "user://creative_flatworld_save.bak"
const PLAYER_SCRIPT := preload("res://scripts/player_controller.gd")
const WORLD_SCRIPT := preload("res://scripts/world_manager.gd")
const INVENTORY_SCRIPT := preload("res://scripts/inventory_panel.gd")
const JOYSTICK_SCRIPT := preload("res://scripts/virtual_joystick.gd")

var resolver := MaterialResolver.new()
var world: CreativeWorldManager
var player: PlayerController
var inventory: CreativeInventoryPanel
var camera: Camera3D
var definitions: Dictionary = {}
var model_items: Array[Dictionary] = []
var hotbar: Array[String] = ["grass_block", "dirt", "stone", "oak_planks", "oak_log", "glass", "bricks", "sand", "glowstone"]
var selected_slot: int = 0
var hotbar_buttons: Array[Button] = []
var target_outline: MeshInstance3D
var target_cell: Vector3i = Vector3i.ZERO
var target_normal: Vector3i = Vector3i.UP
var target_point: Vector3 = Vector3.ZERO
var interaction_panel: PanelContainer
var container_grid: GridContainer
var active_container_cell: Vector3i = Vector3i.ZERO
var container_slot_buttons: Array[Button] = []
var sign_dialog: ConfirmationDialog
var sign_editor: TextEdit
var spawn_position: Vector3 = Vector3(0.0, 0.51, 7.0)
var has_target: bool = false
var diagnostics_label: Label
var status_label: Label
var title_label: Label
var pause_panel: PanelContainer
var options_panel: PanelContainer
var autosave_timer: float = 0.0
var dirty_status_timer: float = 0.0
var diagnostics_visible: bool = false
var render_distance: int = 3
var look_sensitivity: float = 0.0022
var touch_sensitivity: float = 0.0030
var ui_scale: float = 1.0
var world_name: String = "My Creative World"
var _last_target_cell: Vector3i = Vector3i(2147483647, 0, 0)
var _last_target_id: String = ""
var _last_target_state_key: String = ""
var _diagnostics_start_time: int = 0
var _world_time_seconds: float = 600.0
var _sun_light: DirectionalLight3D
var _world_environment_resource: Environment

func _ready() -> void:
    _diagnostics_start_time = Time.get_ticks_msec()
    _set_world_environment()
    if not _load_registry():
        _show_boot_error("Could not read the asset registry. See reports/asset_audit.md.")
        return
    resolver = MaterialResolver.new()
    var world_node := Node3D.new()
    world_node.set_script(WORLD_SCRIPT)
    world_node.name = "WorldManager"
    add_child(world_node)
    world = world_node as CreativeWorldManager
    world.configure(definitions, resolver)
    world.render_radius_chunks = render_distance
    _create_player()
    _create_target_outline()
    _create_hud()
    _connect_player_signals()
    world.world_dirty_changed.connect(_on_dirty_changed)
    world.block_used.connect(_on_block_used)
    world.ensure_around(player.global_position)
    _load_world_save(false)
    var inventory_node := Control.new()
    inventory_node.set_script(INVENTORY_SCRIPT)
    inventory_node.name = "CreativeInventory"
    inventory = inventory_node as CreativeInventoryPanel
    add_child(inventory)
    inventory.build(model_items, resolver)
    inventory.visible = false
    inventory.item_chosen.connect(_on_inventory_item_chosen)
    inventory.close_requested.connect(_close_inventory)
    inventory.settings_changed.connect(_mark_settings_dirty)
    _refresh_hotbar()
    _set_status("Creative flat world ready")
    _refresh_target()

func _process(delta: float) -> void:
    if player == null or world == null: return
    _update_day_night(delta)
    world.ensure_around(player.global_position)
    world.set_player_position(player.global_position)
    _refresh_target()
    autosave_timer += delta
    if autosave_timer >= 45.0:
        autosave_timer = 0.0
        if world.dirty: save_world(true)
    if dirty_status_timer > 0.0:
        dirty_status_timer -= delta
        if dirty_status_timer <= 0.0: status_label.text = ""
    if diagnostics_visible:
        _update_diagnostics()

func _unhandled_input(event: InputEvent) -> void:
    if inventory == null or player == null: return
    if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
        var key := (event as InputEventKey).keycode
        if key == KEY_F3:
            diagnostics_visible = not diagnostics_visible
            diagnostics_label.visible = diagnostics_visible
            get_viewport().set_input_as_handled()

func _load_registry() -> bool:
    if not FileAccess.file_exists(REGISTRY_PATH): return false
    var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
    if file == null: return false
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary or not (parsed as Dictionary).has("models"): return false
    var raw_models: Array = (parsed as Dictionary)["models"]
    model_items.clear(); definitions.clear()
    for value in raw_models:
        if not value is Dictionary: continue
        var item: Dictionary = value
        var id := String(item.get("id", ""))
        if id.is_empty() or String(item.get("model_path", "")).is_empty(): continue
        definitions[id] = item
        if bool(item.get("inventory_visible", true)) and bool(item.get("searchable", true)):
            model_items.append(item)
    model_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a.get("display_name", a.get("id", ""))).to_lower() < String(b.get("display_name", b.get("id", ""))).to_lower()
    )
    return not model_items.is_empty()

func _set_world_environment() -> void:
    var world_env := WorldEnvironment.new()
    var environment := Environment.new()
    _world_environment_resource = environment
    environment.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color(0.16, 0.42, 0.76)
    sky_material.sky_horizon_color = Color(0.68, 0.82, 0.96)
    sky_material.ground_bottom_color = Color(0.18, 0.24, 0.18)
    sky_material.ground_horizon_color = Color(0.58, 0.66, 0.56)
    sky.sky_material = sky_material
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    environment.ambient_light_energy = 0.7
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world_env.environment = environment
    add_child(world_env)
    _sun_light = DirectionalLight3D.new()
    _sun_light.name = "Daylight"
    _sun_light.rotation_degrees = Vector3(-52, -32, 0)
    _sun_light.light_energy = 1.2
    _sun_light.shadow_enabled = true
    add_child(_sun_light)

func _update_day_night(delta: float) -> void:
    # A complete 20-minute creative day/night cycle with daylight-sensor output.
    _world_time_seconds = fposmod(_world_time_seconds + delta, 1200.0)
    var phase := _world_time_seconds / 1200.0
    var altitude := sin((phase - 0.25) * TAU)
    var daylight := clampf((altitude + 0.12) / 0.55, 0.0, 1.0)
    if is_instance_valid(_sun_light):
        _sun_light.rotation_degrees.x = 90.0 * altitude
        _sun_light.light_energy = 0.04 + 1.25 * daylight
    if _world_environment_resource != null:
        _world_environment_resource.ambient_light_energy = 0.18 + 0.60 * daylight
    if world != null:
        world.set_daylight_strength(daylight)

func _create_player() -> void:
    var player_node := CharacterBody3D.new()
    player_node.name = "Player"
    player_node.set_script(PLAYER_SCRIPT)
    player = player_node as PlayerController
    player.position = Vector3(0.0, 0.51, 7.0)
    player.floor_snap_length = 0.2
    player.safe_margin = 0.001
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.31
    capsule.height = 1.82
    var collision := CollisionShape3D.new()
    collision.name = "BodyCollision"
    collision.shape = capsule
    collision.position.y = 0.91
    player.add_child(collision)
    camera = Camera3D.new()
    camera.name = "Camera3D"
    camera.position = Vector3(0, 1.61, 0)
    camera.fov = 75.0
    camera.current = true
    player.add_child(camera)
    add_child(player)
    player.apply_saved_view(0.0, -0.28)
    player.mouse_sensitivity = look_sensitivity
    player.touch_sensitivity = touch_sensitivity

func _create_target_outline() -> void:
    target_outline = MeshInstance3D.new()
    target_outline.name = "TargetOutline"
    var box := BoxMesh.new()
    box.size = Vector3(1.015, 1.015, 1.015)
    target_outline.mesh = box
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(0.85, 0.97, 1.0, 0.48)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.wireframe = true
    material.no_depth_test = true
    target_outline.material_override = material
    target_outline.visible = false
    add_child(target_outline)

func _create_hud() -> void:
    var layer := CanvasLayer.new()
    layer.name = "HUD"
    add_child(layer)
    var root := Control.new()
    root.name = "HUDRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_PASS
    layer.add_child(root)
    title_label = Label.new()
    title_label.text = "CREATIVE  •  FLAT WORLD"
    title_label.position = Vector2(18, 14)
    title_label.add_theme_font_size_override("font_size", 16)
    title_label.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
    title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
    title_label.add_theme_constant_override("shadow_offset_x", 1)
    title_label.add_theme_constant_override("shadow_offset_y", 1)
    root.add_child(title_label)
    status_label = Label.new()
    status_label.position = Vector2(18, 38)
    status_label.add_theme_font_size_override("font_size", 13)
    status_label.add_theme_color_override("font_color", Color(0.66, 0.92, 0.78))
    root.add_child(status_label)
    var crosshair := Label.new()
    crosshair.text = "+"
    crosshair.set_anchors_preset(Control.PRESET_CENTER)
    crosshair.position = Vector2(-8, -15)
    crosshair.size = Vector2(16, 30)
    crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    crosshair.add_theme_font_size_override("font_size", 24)
    crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
    crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(crosshair)
    diagnostics_label = Label.new()
    diagnostics_label.position = Vector2(18, 62)
    diagnostics_label.add_theme_font_size_override("font_size", 13)
    diagnostics_label.add_theme_color_override("font_color", Color(0.9, 0.98, 1.0))
    diagnostics_label.visible = false
    root.add_child(diagnostics_label)
    _create_hotbar(root)
    _create_mobile_controls(root)
    _create_pause_panel(root)
    _create_options_panel(root)
    _create_interaction_ui(root)

func _create_hotbar(root: Control) -> void:
    var row := HBoxContainer.new()
    row.name = "Hotbar"
    row.anchor_left = 0.5; row.anchor_right = 0.5
    row.anchor_top = 1.0; row.anchor_bottom = 1.0
    var viewport_width: float = get_viewport().get_visible_rect().size.x
    var row_width := minf(630.0, maxf(338.0, viewport_width * 0.82))
    row.offset_left = -row_width * 0.5; row.offset_right = row_width * 0.5
    row.offset_top = -84; row.offset_bottom = -12
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 4)
    root.add_child(row)
    hotbar_buttons.clear()
    for slot in range(9):
        var slot_index := slot
        var button := Button.new()
        button.toggle_mode = true
        button.custom_minimum_size = Vector2(maxf(28.0, (row_width - 32.0) / 9.0), 66)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.clip_text = true
        button.add_theme_font_size_override("font_size", 10)
        button.pressed.connect(func(): _select_hotbar(slot_index))
        row.add_child(button)
        hotbar_buttons.append(button)

func _create_mobile_controls(root: Control) -> void:
    var joystick_node := Control.new()
    joystick_node.set_script(JOYSTICK_SCRIPT)
    joystick_node.name = "VirtualJoystick"
    var joystick := joystick_node as MineblockVirtualJoystick
    joystick.anchor_left = 0.015; joystick.anchor_right = 0.015
    joystick.anchor_top = 1.0; joystick.anchor_bottom = 1.0
    joystick.offset_left = 8; joystick.offset_right = 174
    joystick.offset_top = -190; joystick.offset_bottom = -16
    joystick.value_changed.connect(func(value: Vector2): player.set_mobile_move(value))
    root.add_child(joystick)
    var right_group := VBoxContainer.new()
    right_group.anchor_left = 1.0; right_group.anchor_right = 1.0
    right_group.anchor_top = 1.0; right_group.anchor_bottom = 1.0
    right_group.offset_left = -142; right_group.offset_right = -10
    right_group.offset_top = -338; right_group.offset_bottom = -96
    right_group.add_theme_constant_override("separation", 6)
    root.add_child(right_group)
    _add_action_button(right_group, "Break", func(): _break_target(), Color(0.58, 0.24, 0.22))
    _add_action_button(right_group, "Place / Use", func(): _place_target(), Color(0.18, 0.42, 0.32))
    _add_action_button(right_group, "Jump", func(): _jump_or_rise(), Color(0.22, 0.35, 0.55))
    _add_action_button(right_group, "Fly", func(): player.toggle_flight(), Color(0.3, 0.32, 0.48))
    var vertical_row := HBoxContainer.new()
    vertical_row.add_theme_constant_override("separation", 5)
    right_group.add_child(vertical_row)
    _add_action_button(vertical_row, "Rise", func(): _set_vertical_for_moment(1.0), Color(0.26, 0.34, 0.47), 62)
    _add_action_button(vertical_row, "Down", func(): _set_vertical_for_moment(-1.0), Color(0.26, 0.34, 0.47), 62)
    var top_right := HBoxContainer.new()
    top_right.anchor_left = 1.0; top_right.anchor_right = 1.0
    top_right.anchor_top = 0.0; top_right.anchor_bottom = 0.0
    top_right.offset_left = -244; top_right.offset_right = -12
    top_right.offset_top = 12; top_right.offset_bottom = 56
    top_right.add_theme_constant_override("separation", 6)
    root.add_child(top_right)
    _add_action_button(top_right, "Inventory", func(): _open_inventory(), Color(0.15, 0.26, 0.34), 114)
    _add_action_button(top_right, "Menu", func(): _open_pause(), Color(0.15, 0.26, 0.34), 72)

func _add_action_button(parent: Container, text_value: String, action: Callable, color: Color, width: float = 128.0) -> Button:
    var button := Button.new()
    button.text = text_value
    button.custom_minimum_size = Vector2(width, 42)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_size_override("font_size", 13)
    button.add_theme_stylebox_override("normal", _style_button(color))
    button.add_theme_stylebox_override("hover", _style_button(color.lightened(0.14)))
    button.add_theme_stylebox_override("pressed", _style_button(color.darkened(0.14)))
    button.pressed.connect(action)
    parent.add_child(button)
    return button

func _style_button(color: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = color.lightened(0.22)
    style.set_border_width_all(1)
    style.set_corner_radius_all(9)
    style.content_margin_left = 7; style.content_margin_right = 7
    style.content_margin_top = 5; style.content_margin_bottom = 5
    return style

func _create_pause_panel(root: Control) -> void:
    pause_panel = PanelContainer.new()
    pause_panel.name = "PauseMenu"
    pause_panel.anchor_left = 0.5; pause_panel.anchor_right = 0.5
    pause_panel.anchor_top = 0.5; pause_panel.anchor_bottom = 0.5
    var menu_width := minf(380.0, maxf(280.0, get_viewport().get_visible_rect().size.x - 20.0))
    var menu_height := minf(504.0, maxf(360.0, get_viewport().get_visible_rect().size.y - 24.0))
    pause_panel.offset_left = -menu_width * 0.5; pause_panel.offset_right = menu_width * 0.5
    pause_panel.offset_top = -menu_height * 0.5; pause_panel.offset_bottom = menu_height * 0.5
    pause_panel.add_theme_stylebox_override("panel", _panel_style())
    pause_panel.visible = false
    root.add_child(pause_panel)
    var pause_scroll := ScrollContainer.new()
    pause_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pause_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    pause_panel.add_child(pause_scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 8)
    pause_scroll.add_child(column)
    var title := Label.new()
    title.text = "WORLD MENU"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 24)
    column.add_child(title)
    var world_name_edit := LineEdit.new()
    world_name_edit.placeholder_text = "World name"
    world_name_edit.text = world_name
    world_name_edit.custom_minimum_size.y = 38
    column.add_child(world_name_edit)
    _add_menu_button(column, "Apply world name", func(): world_name = world_name_edit.text.strip_edges() if not world_name_edit.text.strip_edges().is_empty() else "My Creative World"; _mark_settings_dirty(); _set_status("World renamed to " + world_name))
    _add_menu_button(column, "Resume", func(): _resume_game())
    _add_menu_button(column, "Save world now", func(): save_world(false))
    _add_menu_button(column, "Reload saved world", func(): _load_world_save(true); _resume_game())
    _add_menu_button(column, "Inventory", func(): _open_inventory())
    _add_menu_button(column, "Settings", func(): options_panel.visible = true)
    _add_menu_button(column, "New flat world", func(): _new_world())
    _add_menu_button(column, "Save and close menu", func(): save_world(false); _resume_game())
    var note := Label.new()
    note.text = "No hostile mobs • Creative flight • Infinite block usage"
    note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.add_theme_font_size_override("font_size", 12)
    column.add_child(note)

func _create_options_panel(root: Control) -> void:
    options_panel = PanelContainer.new()
    options_panel.name = "Settings"
    options_panel.anchor_left = 0.5; options_panel.anchor_right = 0.5
    options_panel.anchor_top = 0.5; options_panel.anchor_bottom = 0.5
    var options_width := minf(440.0, maxf(280.0, get_viewport().get_visible_rect().size.x - 20.0))
    var options_height := minf(470.0, maxf(360.0, get_viewport().get_visible_rect().size.y - 24.0))
    options_panel.offset_left = -options_width * 0.5; options_panel.offset_right = options_width * 0.5
    options_panel.offset_top = -options_height * 0.5; options_panel.offset_bottom = options_height * 0.5
    options_panel.add_theme_stylebox_override("panel", _panel_style())
    options_panel.visible = false
    root.add_child(options_panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 9)
    options_panel.add_child(col)
    var title := Label.new()
    title.text = "SETTINGS"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 22)
    col.add_child(title)
    _add_slider_option(col, "Mouse look sensitivity", 0.0008, 0.006, look_sensitivity, func(v: float): look_sensitivity = v; player.mouse_sensitivity = v; _mark_settings_dirty())
    _add_slider_option(col, "Touch look sensitivity", 0.001, 0.008, touch_sensitivity, func(v: float): touch_sensitivity = v; player.touch_sensitivity = v; _mark_settings_dirty())
    _add_slider_option(col, "Chunk render radius", 1.0, 5.0, float(render_distance), func(v: float): render_distance = int(round(v)); world.render_radius_chunks = render_distance; world._last_center_chunk = Vector2i(2147483647, 2147483647); _mark_settings_dirty())
    var webp := CheckBox.new()
    webp.text = "Use optional WebP map exports"
    webp.button_pressed = resolver.use_webp_maps
    webp.toggled.connect(func(v: bool): resolver.set_webp_mode(v); _mark_settings_dirty())
    col.add_child(webp)
    _add_menu_button(col, "Save settings", func(): save_world(false); options_panel.visible = false)
    _add_menu_button(col, "Back", func(): options_panel.visible = false)

func _add_slider_option(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, initial: float, callback: Callable) -> void:
    var label := Label.new()
    label.text = label_text
    parent.add_child(label)
    var slider := HSlider.new()
    slider.min_value = minimum; slider.max_value = maximum; slider.step = 0.0001 if maximum < 0.01 else 1.0
    slider.value = initial
    slider.custom_minimum_size.y = 22
    slider.value_changed.connect(callback)
    parent.add_child(slider)

func _add_menu_button(parent: VBoxContainer, caption: String, callback: Callable) -> void:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size = Vector2(260, 40)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.pressed.connect(callback)
    parent.add_child(button)

func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.055, 0.085, 0.12, 0.98)
    style.border_color = Color(0.34, 0.52, 0.64, 1)
    style.set_border_width_all(2)
    style.set_corner_radius_all(12)
    style.content_margin_left = 20; style.content_margin_right = 20
    style.content_margin_top = 18; style.content_margin_bottom = 18
    return style

func _connect_player_signals() -> void:
    player.break_requested.connect(_break_target)
    player.place_requested.connect(_place_target)
    player.inventory_requested.connect(func():
        if inventory != null and inventory.visible: _close_inventory()
        else: _open_inventory()
    )
    player.pause_requested.connect(func():
        if inventory != null and inventory.visible: _close_inventory()
        elif options_panel != null and options_panel.visible: options_panel.visible = false
        elif pause_panel != null and pause_panel.visible: _resume_game()
        else: _open_pause()
    )
    player.fly_changed.connect(func(enabled: bool): _set_status("Flight enabled" if enabled else "Flight disabled"))
    player.selected_hotbar_changed.connect(_select_hotbar)

func _refresh_hotbar() -> void:
    for slot in range(hotbar_buttons.size()):
        var button := hotbar_buttons[slot]
        var id := hotbar[slot] if slot < hotbar.size() else ""
        if id.is_empty() or not definitions.has(id):
            button.text = "Empty"
            button.icon = null
        else:
            var data: Dictionary = definitions[id]
            button.text = "%d\n%s" % [slot + 1, _short_name(String(data.get("display_name", id)))]
            var icon_path := String(data.get("base_color_path", data.get("icon_path", "")))
            var texture := load(icon_path) as Texture2D if not icon_path.is_empty() else null
            button.icon = texture
            button.expand_icon = true
        button.button_pressed = slot == selected_slot
        button.add_theme_stylebox_override("normal", _hotbar_style(slot == selected_slot))
        button.add_theme_stylebox_override("pressed", _hotbar_style(true))

func _hotbar_style(selected: bool) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.19, 0.31, 0.39, 0.94) if selected else Color(0.035, 0.055, 0.075, 0.82)
    style.border_color = Color(0.91, 0.98, 1, 1) if selected else Color(0.48, 0.62, 0.69, 0.85)
    style.set_border_width_all(3 if selected else 1)
    style.set_corner_radius_all(5)
    style.content_margin_left = 2; style.content_margin_right = 2
    style.content_margin_top = 2; style.content_margin_bottom = 2
    return style

func _short_name(value: String) -> String:
    var name := value.replace(" ", "\n")
    return name if name.length() <= 24 else name.substr(0, 22) + "…"

func _select_hotbar(slot: int) -> void:
    selected_slot = clampi(slot, 0, 8)
    _refresh_hotbar()
    if world != null: world._set_dirty(true)
    if selected_slot < hotbar.size() and definitions.has(hotbar[selected_slot]):
        _set_status("Selected " + String(definitions[hotbar[selected_slot]].get("display_name", hotbar[selected_slot])))

func _on_inventory_item_chosen(id: String) -> void:
    if not definitions.has(id): return
    hotbar[selected_slot] = id
    _refresh_hotbar()
    if world != null: world._set_dirty(true)

func _open_inventory() -> void:
    if inventory == null or pause_panel == null: return
    inventory.visible = true
    pause_panel.visible = false
    options_panel.visible = false
    player.set_mouse_capture(false)
    player.look_enabled = false
    player.set_gameplay_paused(true)

func _close_inventory() -> void:
    if inventory == null: return
    inventory.visible = false
    player.look_enabled = true
    if not pause_panel.visible:
        player.set_gameplay_paused(false)
        player.set_mouse_capture(true)

func _open_pause() -> void:
    if pause_panel == null or inventory == null: return
    inventory.visible = false
    pause_panel.visible = true
    player.set_mouse_capture(false)
    player.look_enabled = false
    player.set_gameplay_paused(true)

func _resume_game() -> void:
    pause_panel.visible = false
    options_panel.visible = false
    inventory.visible = false
    player.set_mouse_capture(true)
    player.look_enabled = true
    player.set_gameplay_paused(false)

func _new_world() -> void:
    if world.dirty: save_world(false)
    world.restore_state([], [])
    player.position = Vector3(0.0, 0.51, 7.0)
    spawn_position = player.position
    player.apply_saved_view(0.0, -0.28)
    player.is_flying = false
    hotbar = ["grass_block", "dirt", "stone", "oak_planks", "oak_log", "glass", "bricks", "sand", "glowstone"]
    selected_slot = 0
    world_name = "My Creative World"
    _refresh_hotbar()
    save_world(false)
    _set_status("New flat world created")
    _resume_game()

func _refresh_target() -> void:
    has_target = false
    var origin := camera.global_position
    var direction := -camera.global_transform.basis.z.normalized()
    var last_cell := _cell_from_world(origin)
    var cell_entry_normal := Vector3i.ZERO
    var distance := 0.0
    while distance <= 7.0:
        var point := origin + direction * distance
        var cell := _cell_from_world(point)
        if cell != last_cell:
            cell_entry_normal = _normal_from_cell_delta(cell - last_cell)
            last_cell = cell
        if world.has_block(cell) and _point_hits_target(cell, point):
            target_normal = cell_entry_normal if cell_entry_normal != Vector3i.ZERO else Vector3i.UP
            target_cell = cell
            target_point = point
            has_target = true
            break
        distance += 0.025
    target_outline.visible = has_target and (inventory == null or not inventory.visible) and not pause_panel.visible and (interaction_panel == null or not interaction_panel.visible)
    if target_outline.visible:
        var target_id := world.get_block_id(target_cell)
        var target_state := world.get_block_state(target_cell)
        var target_row: Dictionary = world.placed_blocks.get(target_cell, {})
        var target_yaw := float(target_row.get("yaw", target_state.get("yaw", 0.0)))
        target_outline.global_position = Vector3(target_cell)
        var state_key := "%s|%s|%s|%.4f" % [target_id, str(target_cell), str(target_state), target_yaw]
        if state_key != _last_target_state_key:
            _last_target_state_key = state_key
            _build_selection_outline(target_id, target_state, definitions.get(target_id, {}), target_yaw)
        _last_target_cell = target_cell
        _last_target_id = target_id
    else:
        _last_target_state_key = ""

func _build_selection_outline(id: String, state: Dictionary, definition: Dictionary, yaw: float) -> void:
    var mesh := ImmediateMesh.new()
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(0.8, 0.96, 1.0, 0.9)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.no_depth_test = true
    mesh.surface_begin(Mesh.PRIMITIVE_LINES)
    var family := BlockBehaviors.family_for_id(id)
    var root_rotation := Vector3(0.0, yaw, 0.0)
    if family in ["stairs", "door", "bed", "trapdoor", "fence_gate", "rail", "piston", "repeater", "comparator", "machine_container", "container", "shelf", "daylight_sensor", "piston_head", "bell"]:
        root_rotation.y = _yaw_for_facing(String(state.get("facing", BlockBehaviors._facing_from_yaw(yaw))))
    if family in ["fence", "connected_barrier", "redstone_wire"]: root_rotation.y = 0.0
    if family == "axis_block":
        root_rotation = Vector3.ZERO
        var axis := String(state.get("axis", "y"))
        if axis == "x": root_rotation.z = PI * 0.5
        elif axis == "z": root_rotation.x = PI * 0.5
    var root_offset := Vector3.ZERO
    if family in ["button", "lever", "sign", "hanging_sign", "torch", "redstone_source"] and (String(state.get("face", "wall")) == "wall" or bool(state.get("wall_mounted", false)) or id.find("wall_torch") >= 0):
        var mounted_facing := String(state.get("facing", "north"))
        root_rotation = Vector3(0, _yaw_for_facing(mounted_facing), 0)
        root_offset = -Vector3(BlockBehaviors.direction_for_facing(mounted_facing)) * 0.47
    if family == "door" and bool(state.get("open", false)):
        var door_base_yaw := _yaw_for_facing(String(state.get("facing", BlockBehaviors._facing_from_yaw(yaw))))
        var hinge_local := Vector3(-0.5 if String(state.get("hinge", "left")) == "left" else 0.5, 0.0, 0.0)
        root_rotation.y = door_base_yaw + (PI * 0.5 if String(state.get("hinge", "left")) == "left" else -PI * 0.5)
        root_offset = Basis(Vector3.UP, door_base_yaw) * hinge_local - Basis(Vector3.UP, root_rotation.y) * hinge_local
    if family == "fence_gate" and bool(state.get("open", false)): root_rotation.y += PI * 0.5
    if family == "trapdoor" and bool(state.get("open", false)):
        root_rotation.x = PI * 0.5
        root_offset.y = 0.25 if String(state.get("half", "bottom")) == "bottom" else -0.25
    match family:
        "slab":
            if bool(state.get("double", false)):
                _emit_box_edges(mesh, Vector3.ZERO, Vector3.ONE, root_rotation, root_offset)
            else:
                _emit_box_edges(mesh, Vector3(0, -0.25 if String(state.get("half", "bottom")) == "bottom" else 0.25, 0), Vector3(1, 0.5, 1), root_rotation, root_offset)
        "stairs":
            var top_half := String(state.get("half", "bottom")) == "top"
            var base_y := 0.25 if top_half else -0.25
            var step_y := -0.25 if top_half else 0.25
            var forward_z := 0.25 if top_half else -0.25
            _emit_box_edges(mesh, Vector3(0, base_y, 0), Vector3(1, 0.5, 1), root_rotation, root_offset)
            var shape := String(state.get("shape", "straight"))
            if shape.begins_with("outer"):
                var side := -1.0 if shape == "outer_left" else 1.0
                _emit_box_edges(mesh, Vector3(side * 0.25, step_y, forward_z), Vector3(0.5, 0.5, 0.5), root_rotation, root_offset)
            elif shape.begins_with("inner"):
                _emit_box_edges(mesh, Vector3(0, step_y, forward_z), Vector3(1, 0.5, 0.5), root_rotation, root_offset)
                var side := -1.0 if shape == "inner_left" else 1.0
                _emit_box_edges(mesh, Vector3(side * 0.25, step_y, -forward_z), Vector3(0.5, 0.5, 0.5), root_rotation, root_offset)
            else:
                _emit_box_edges(mesh, Vector3(0, step_y, forward_z), Vector3(1, 0.5, 0.5), root_rotation, root_offset)
        "fence", "connected_barrier":
            if family == "fence":
                _emit_box_edges(mesh, Vector3.ZERO, Vector3(0.22, 1.0, 0.22), root_rotation, root_offset)
                var connections: Dictionary = state.get("connections", {})
                for key in ["east", "west", "south", "north"]:
                    if not bool(connections.get(key, false)): continue
                    var d: Vector3i = _horizontal_dirs_from_key(key)
                    var arm_size := Vector3(0.39, 0.11, 0.11) if d.x != 0 else Vector3(0.11, 0.11, 0.39)
                    var arm_center := Vector3(d) * 0.305
                    _emit_box_edges(mesh, arm_center + Vector3(0, 0.21, 0), arm_size, root_rotation, root_offset)
                    _emit_box_edges(mesh, arm_center + Vector3(0, -0.12, 0), arm_size, root_rotation, root_offset)
            else:
                var is_wall_shape := id.ends_with("_wall") or id == "wall"
                _emit_box_edges(mesh, Vector3.ZERO, Vector3(0.48, 0.78, 0.48) if is_wall_shape else Vector3(0.06, 0.875, 0.06), root_rotation, root_offset)
                var connections: Dictionary = state.get("connections", {})
                for key in ["east", "west", "south", "north"]:
                    if not bool(connections.get(key, false)): continue
                    var d: Vector3i = _horizontal_dirs_from_key(key)
                    var arm_size := (Vector3(0.50, 0.60, 0.28) if is_wall_shape else Vector3(0.47, 0.875, 0.055)) if d.x != 0 else (Vector3(0.28, 0.60, 0.50) if is_wall_shape else Vector3(0.055, 0.875, 0.47))
                    _emit_box_edges(mesh, Vector3(d) * (0.25 if is_wall_shape else 0.265), arm_size, root_rotation, root_offset)
        "trapdoor":
            var trap_center := Vector3(0, 0.0 if bool(state.get("open", false)) else (-0.40625 if String(state.get("half", "bottom")) == "bottom" else 0.40625), 0)
            _emit_box_edges(mesh, trap_center, Vector3(1, 0.1875, 1), root_rotation, root_offset)
        "door":
            var door_bounds: Array = definition.get("bounds", [[-0.5, -0.5, -0.5], [0.5, 0.5, -0.4375]])
            var door_center := Vector3(0, 0, -0.46875)
            var door_size := Vector3(1, 1, 0.0625)
            if door_bounds.size() >= 2 and (door_bounds[0] as Array).size() >= 3 and (door_bounds[1] as Array).size() >= 3:
                var door_lo: Array = door_bounds[0]; var door_hi: Array = door_bounds[1]
                door_center = Vector3((float(door_lo[0]) + float(door_hi[0])) * 0.5, (float(door_lo[1]) + float(door_hi[1])) * 0.5, (float(door_lo[2]) + float(door_hi[2])) * 0.5)
                door_size = Vector3(float(door_hi[0]) - float(door_lo[0]), float(door_hi[1]) - float(door_lo[1]), float(door_hi[2]) - float(door_lo[2]))
            _emit_box_edges(mesh, door_center, door_size, root_rotation, root_offset)
        "redstone_wire":
            var wire_connections: Dictionary = state.get("connections", {})
            _emit_box_edges(mesh, Vector3(0, -0.455, 0), Vector3(0.24, 0.025, 0.24), root_rotation, root_offset)
            for key in ["east", "west", "south", "north"]:
                if not bool(wire_connections.get(key, false)): continue
                var direction: Vector3i = _horizontal_dirs_from_key(key)
                var arm_size := Vector3(0.40, 0.025, 0.075) if direction.x != 0 else Vector3(0.075, 0.025, 0.40)
                _emit_box_edges(mesh, Vector3(direction) * 0.30 + Vector3(0, -0.455, 0), arm_size, root_rotation, root_offset)
        "bed":
            _emit_box_edges(mesh, Vector3(0, -0.25, 0), Vector3(1, 0.5, 1), root_rotation, root_offset)
        "fluid":
            var fluid_height := maxf(0.125, 1.0 - 0.125 * float(state.get("level", 0)))
            _emit_box_edges(mesh, Vector3(0, -0.5 + fluid_height * 0.5, 0), Vector3(1, fluid_height, 1), root_rotation, root_offset)
        "fence_gate":
            _emit_box_edges(mesh, Vector3.ZERO, Vector3(1, 0.85, 0.15), root_rotation, root_offset)
        _:
            var bounds: Array = definition.get("bounds", [[-0.5, -0.5, -0.5], [0.5, 0.5, 0.5]])
            var center := Vector3.ZERO
            var size := Vector3.ONE
            if bounds.size() >= 2 and (bounds[0] as Array).size() >= 3 and (bounds[1] as Array).size() >= 3:
                var lo: Array = bounds[0]; var hi: Array = bounds[1]
                center = Vector3((float(lo[0]) + float(hi[0])) * 0.5, (float(lo[1]) + float(hi[1])) * 0.5, (float(lo[2]) + float(hi[2])) * 0.5)
                size = Vector3(maxf(0.03, float(hi[0]) - float(lo[0])), maxf(0.03, float(hi[1]) - float(lo[1])), maxf(0.03, float(hi[2]) - float(lo[2])))
            _emit_box_edges(mesh, center, size, root_rotation, root_offset)
    mesh.surface_end()
    target_outline.mesh = mesh
    target_outline.material_override = material

func _emit_box_edges(mesh: ImmediateMesh, center: Vector3, size: Vector3, rotation: Vector3, offset: Vector3) -> void:
    var half := size * 0.5
    var points: Array[Vector3] = [
        center + Vector3(-half.x, -half.y, -half.z), center + Vector3(half.x, -half.y, -half.z),
        center + Vector3(half.x, half.y, -half.z), center + Vector3(-half.x, half.y, -half.z),
        center + Vector3(-half.x, -half.y, half.z), center + Vector3(half.x, -half.y, half.z),
        center + Vector3(half.x, half.y, half.z), center + Vector3(-half.x, half.y, half.z)
    ]
    var basis := Basis.from_euler(rotation)
    for index in range(points.size()): points[index] = basis * points[index] + offset
    var edges: Array[int] = [0,1, 1,2, 2,3, 3,0, 4,5, 5,6, 6,7, 7,4, 0,4, 1,5, 2,6, 3,7]
    for index in edges: mesh.surface_add_vertex(points[index])

func _horizontal_dirs_from_key(key: String) -> Vector3i:
    match key:
        "east": return Vector3i.RIGHT
        "west": return Vector3i.LEFT
        "south": return Vector3i(0,0,1)
        _: return Vector3i(0,0,-1)


func _yaw_for_facing(facing: String) -> float:
    match facing:
        "north": return 0.0
        "east": return -PI * 0.5
        "south": return PI
        "west": return PI * 0.5
    return 0.0


func _point_hits_target(cell: Vector3i, point: Vector3) -> bool:
    var id := world.get_block_id(cell)
    if id.is_empty(): return false
    if not world.placed_blocks.has(cell) and not world.removed_cells.has(cell): return true
    var state := world.get_block_state(cell)
    var family := BlockBehaviors.family_for_id(id)
    var local_point := point - Vector3(cell)
    var row: Dictionary = world.placed_blocks.get(cell, {})
    var yaw := float(row.get("yaw", state.get("yaw", 0.0)))
    var mounted := family in ["button", "lever", "sign", "torch", "redstone_source"] and (String(state.get("face", "wall")) == "wall" or bool(state.get("wall_mounted", false)) or id.find("wall_torch") >= 0)
    if mounted:
        local_point += Vector3(BlockBehaviors.direction_for_facing(String(state.get("facing", "north")))) * 0.47
    if family in ["fence", "connected_barrier"]:
        if family == "fence":
            if absf(local_point.x) <= 0.11 and absf(local_point.z) <= 0.11 and absf(local_point.y) <= 0.5: return true
        else:
            var is_wall := id.ends_with("_wall") or id == "wall"
            var center_half := 0.24 if is_wall else 0.03
            var center_height := 0.39 if is_wall else 0.4375
            if absf(local_point.y) <= center_height and absf(local_point.x) <= center_half and absf(local_point.z) <= center_half: return true
        var connections: Dictionary = state.get("connections", {})
        var is_wall_shape := family == "connected_barrier" and (id.ends_with("_wall") or id == "wall")
        for key in connections:
            if not bool(connections[key]): continue
            var axis_hit := false
            match String(key):
                "east": axis_hit = local_point.x >= 0.0 and local_point.x <= 0.5 and absf(local_point.z) <= (0.14 if is_wall_shape else 0.06)
                "west": axis_hit = local_point.x <= 0.0 and local_point.x >= -0.5 and absf(local_point.z) <= (0.14 if is_wall_shape else 0.06)
                "south": axis_hit = local_point.z >= 0.0 and local_point.z <= 0.5 and absf(local_point.x) <= (0.14 if is_wall_shape else 0.06)
                "north": axis_hit = local_point.z <= 0.0 and local_point.z >= -0.5 and absf(local_point.x) <= (0.14 if is_wall_shape else 0.06)
            if axis_hit:
                if is_wall_shape and absf(local_point.y) <= 0.30: return true
                if family == "fence" and (absf(local_point.y - 0.21) <= 0.06 or absf(local_point.y + 0.12) <= 0.06): return true
                if family == "connected_barrier" and not is_wall_shape and absf(local_point.y) <= 0.4375: return true
        return false
    var effective_yaw := yaw
    var root_rotation := Vector3(0, yaw, 0)
    var root_offset: Vector3 = Vector3.ZERO
    if family in ["stairs", "door", "bed", "trapdoor", "fence_gate", "rail", "piston", "repeater", "comparator", "machine_container", "container", "shelf", "daylight_sensor", "piston_head", "bell"]:
        effective_yaw = _yaw_for_facing(String(state.get("facing", BlockBehaviors._facing_from_yaw(yaw))))
        root_rotation = Vector3(0, effective_yaw, 0)
    if mounted:
        effective_yaw = _yaw_for_facing(String(state.get("facing", "north")))
        root_rotation = Vector3(0, effective_yaw, 0)
    var door_open := family == "door" and bool(state.get("open", false))
    var door_hinge_local := Vector3.ZERO
    var door_hinge_world_offset := Vector3.ZERO
    if family == "door":
        # Target geometry uses the same stored cardinal facing as the rendered panel.
        effective_yaw = _yaw_for_facing(String(state.get("facing", BlockBehaviors._facing_from_yaw(yaw))))
        door_hinge_local.x = -0.5 if String(state.get("hinge", "left")) == "left" else 0.5
        door_hinge_world_offset = Basis(Vector3.UP, effective_yaw) * door_hinge_local
        if door_open:
            effective_yaw += PI * 0.5 * (1.0 if String(state.get("hinge", "left")) == "left" else -1.0)
        root_rotation.y = effective_yaw
    if family == "fence_gate" and bool(state.get("open", false)):
        effective_yaw += PI * 0.5
        root_rotation.y = effective_yaw
    if family == "trapdoor" and bool(state.get("open", false)):
        root_rotation.x = PI * 0.5
        root_offset.y = 0.25 if String(state.get("half", "bottom")) == "bottom" else -0.25
    if family == "axis_block":
        root_rotation = Vector3.ZERO
        var axis := String(state.get("axis", "y"))
        if axis == "x": root_rotation.z = PI * 0.5
        elif axis == "z": root_rotation.x = PI * 0.5
    if door_open:
        local_point = door_hinge_local + Basis(Vector3.UP, effective_yaw).inverse() * (local_point - door_hinge_world_offset)
    else:
        local_point = Basis.from_euler(root_rotation).inverse() * (local_point - root_offset)
    if family == "slab":
        return bool(state.get("double", false)) or (local_point.y <= 0.0 if String(state.get("half", "bottom")) == "bottom" else local_point.y >= 0.0)
    if family == "stairs":
        var bottom_half := String(state.get("half", "bottom")) == "bottom"
        if bottom_half and local_point.y <= 0.0: return true
        if not bottom_half and local_point.y >= 0.0: return true
        var forward_half := local_point.z <= 0.0 if bottom_half else local_point.z >= 0.0
        if not forward_half: return false
        var shape := String(state.get("shape", "straight"))
        if shape == "outer_left" or shape == "inner_left": return local_point.x <= 0.0
        if shape == "outer_right" or shape == "inner_right": return local_point.x >= 0.0
        return true
    if family == "trapdoor":
        if bool(state.get("open", false)): return absf(local_point.z) < 0.12 and absf(local_point.y) < 0.5
    if family == "bed":
        return local_point.y >= -0.5 and local_point.y <= 0.17 and absf(local_point.x) <= 0.48 and absf(local_point.z) <= 0.48
    if family == "tall_plant":
        return absf(local_point.x) <= 0.5 and absf(local_point.z) <= 0.5 and absf(local_point.y) <= 0.5
    var bounds: Array = definitions.get(id, {}).get("bounds", [[-0.5,-0.5,-0.5],[0.5,0.5,0.5]])
    if bounds.size() >= 2 and (bounds[0] as Array).size() >= 3 and (bounds[1] as Array).size() >= 3:
        var lo: Array = bounds[0]; var hi: Array = bounds[1]
        return local_point.x >= float(lo[0]) - 0.02 and local_point.x <= float(hi[0]) + 0.02 and local_point.y >= float(lo[1]) - 0.02 and local_point.y <= float(hi[1]) + 0.02 and local_point.z >= float(lo[2]) - 0.02 and local_point.z <= float(hi[2]) + 0.02
    return absf(local_point.x) <= 0.5 and absf(local_point.y) <= 0.5 and absf(local_point.z) <= 0.5

func _cell_from_world(position_value: Vector3) -> Vector3i:
    return Vector3i(floori(position_value.x + 0.5), floori(position_value.y + 0.5), floori(position_value.z + 0.5))

func _normal_from_cell_delta(delta_cell: Vector3i) -> Vector3i:
    var ax := absi(delta_cell.x); var ay := absi(delta_cell.y); var az := absi(delta_cell.z)
    if ax >= ay and ax >= az: return Vector3i(-signi(delta_cell.x), 0, 0)
    if ay >= ax and ay >= az: return Vector3i(0, -signi(delta_cell.y), 0)
    return Vector3i(0, 0, -signi(delta_cell.z))

func _facing_from_normal(normal: Vector3i) -> String:
    if normal.x > 0: return "east"
    if normal.x < 0: return "west"
    if normal.z > 0: return "south"
    return "north"

func _break_target() -> void:
    if inventory != null and inventory.visible: return
    if not has_target: return
    if world.remove_block(target_cell): _set_status("Block removed")
    else: _set_status("This block cannot be removed")
    _refresh_target()

func _place_target() -> void:
    if inventory != null and inventory.visible: return
    if interaction_panel != null and interaction_panel.visible: return
    if not has_target or selected_slot >= hotbar.size(): return
    var id := hotbar[selected_slot]
    if id.is_empty() or not definitions.has(id): return

    # Right-click/tap uses interactable blocks first; ordinary blocks fall back to placement.
    var target_family := BlockBehaviors.family_for_id(world.get_block_id(target_cell))
    if target_family == "slab" and world.get_block_id(target_cell) == id:
        var current_slab_state := world.get_block_state(target_cell)
        var hit_half := "top" if target_point.y > float(target_cell.y) else "bottom"
        if not bool(current_slab_state.get("double", false)) and String(current_slab_state.get("half", "bottom")) != hit_half:
            if world.merge_slab(target_cell):
                _set_status("Merged into a double slab")
                _refresh_target()
                return
    var action := world.use_block(target_cell, id)
    if action != "none":
        # WorldManager emits block_used synchronously; its connected handler owns UI actions.
        _refresh_target()
        return

    var cell := target_cell + target_normal
    var p := player.global_position
    if absf(float(cell.x) - p.x) < 0.48 and absf(float(cell.z) - p.z) < 0.48 and float(cell.y) >= p.y - 0.2 and float(cell.y) <= p.y + 1.7:
        _set_status("Can't place a block inside yourself")
        return
    var yaw := snappedf(player.rotation.y, PI / 2.0)
    var state_override: Dictionary = {"facing": BlockBehaviors._facing_from_yaw(yaw)}
    var family := BlockBehaviors.family_for_id(id)
    if family in ["button", "lever", "sign", "hanging_sign", "torch", "redstone_source"] and target_normal.y == 0:
        state_override["facing"] = _facing_from_normal(target_normal)
    if id in ["vine", "glow_lichen", "cocoa"]:
        state_override["face"] = ("floor" if target_normal.y > 0 else "ceiling") if target_normal.y != 0 else "wall"
        if target_normal.y == 0: state_override["facing"] = _facing_from_normal(target_normal)
    if id in ["weeping_vines", "twisting_vines", "cave_vines", "cave_vines_plant", "weeping_vines_plant", "twisting_vines_plant"]:
        state_override["face"] = "ceiling"
    if family == "axis_block":
        state_override["axis"] = "y" if target_normal.y != 0 else ("x" if target_normal.x != 0 else "z")
    if family in ["slab", "stairs"]:
        var half := "top" if target_normal == Vector3i.DOWN or (target_normal.y == 0 and target_point.y > float(target_cell.y)) else "bottom"
        if target_normal == Vector3i.UP: half = "bottom"
        state_override["half"] = half
    if family in ["button", "lever", "sign", "hanging_sign", "torch", "redstone_source"]:
        state_override["face"] = ("floor" if target_normal.y > 0 else "ceiling") if target_normal.y != 0 else "wall"
    if world.place_block(cell, id, yaw, state_override, target_normal):
        _set_status("Placed " + String(definitions[id].get("display_name", id)))
    else:
        _set_status("Can't place there: occupied cell, missing support, or invalid state")
    _refresh_target()


func _create_interaction_ui(root: Control) -> void:
    interaction_panel = PanelContainer.new()
    interaction_panel.name = "ContainerInventory"
    interaction_panel.anchor_left = 0.5; interaction_panel.anchor_right = 0.5
    interaction_panel.anchor_top = 0.5; interaction_panel.anchor_bottom = 0.5
    interaction_panel.offset_left = -260; interaction_panel.offset_right = 260
    interaction_panel.offset_top = -205; interaction_panel.offset_bottom = 205
    interaction_panel.add_theme_stylebox_override("panel", _panel_style())
    interaction_panel.visible = false
    root.add_child(interaction_panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 8)
    interaction_panel.add_child(column)
    var header := HBoxContainer.new()
    column.add_child(header)
    var title := Label.new()
    title.name = "ContainerTitle"
    title.text = "CONTAINER"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 20)
    header.add_child(title)
    var close := Button.new()
    close.text = "Close"
    close.pressed.connect(_close_container)
    header.add_child(close)
    var note := Label.new()
    note.text = "Tap a slot to swap it with the selected hotbar item. Creative mode keeps items unlimited."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(note)
    container_grid = GridContainer.new()
    container_grid.columns = 9
    container_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    container_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(container_grid)
    container_slot_buttons.clear()
    for slot in range(27):
        var index := slot
        var button := Button.new()
        button.custom_minimum_size = Vector2(42, 46)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.pressed.connect(func(): _toggle_container_slot(index))
        container_grid.add_child(button)
        container_slot_buttons.append(button)

    sign_dialog = ConfirmationDialog.new()
    sign_dialog.title = "Edit sign"
    sign_dialog.ok_button_text = "Apply"
    sign_editor = TextEdit.new()
    sign_editor.custom_minimum_size = Vector2(360, 120)
    sign_editor.placeholder_text = "Enter sign text (up to 384 characters)"
    sign_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    sign_dialog.add_child(sign_editor)
    sign_dialog.confirmed.connect(_commit_sign_text)
    root.add_child(sign_dialog)

func _on_block_used(cell: Vector3i, id: String, action: String) -> void:
    _handle_block_action(cell, id, action)

func _handle_block_action(cell: Vector3i, id: String, action: String) -> void:
    match action:
        "open_container":
            active_container_cell = cell
            _refresh_container_slots()
            interaction_panel.visible = true
            inventory.visible = false
            pause_panel.visible = false
            options_panel.visible = false
            player.set_gameplay_paused(true)
            player.set_mouse_capture(false)
            player.look_enabled = false
        "edit_sign":
            active_container_cell = cell
            sign_editor.text = String(world.get_block_state(cell).get("text", ""))
            sign_dialog.popup_centered(Vector2i(430, 270))
            player.set_gameplay_paused(true)
            player.set_mouse_capture(false)
            player.look_enabled = false
        "set_spawn":
            var bed_state: Dictionary = world.get_block_state(cell)
            var foot_cell := cell
            if String(bed_state.get("part", "foot")) == "head":
                var pair: Array = bed_state.get("pair_cell", [])
                if pair.size() >= 3: foot_cell = Vector3i(int(pair[0]), int(pair[1]), int(pair[2]))
            # CharacterBody origin sits at foot height; bed cell y is already the top-support level.
            # Bed mattress top is about 0.5625 units above its support surface.
            # Keep the player's feet a little clear of the bed collider on respawn.
            spawn_position = Vector3(float(foot_cell.x), float(foot_cell.y) + 0.13, float(foot_cell.z))
            save_world(true)
            _set_status("Creative spawn point set at bed")
        "display_entity":
            _set_status("Armor stand display object placed — no living entity AI asset was supplied")
        "opened": _set_status(String(definitions.get(id, {}).get("display_name", id)) + " opened")
        "closed": _set_status(String(definitions.get(id, {}).get("display_name", id)) + " closed")
        "powered_on": _set_status(String(definitions.get(id, {}).get("display_name", id)) + " powered on")
        "powered_off": _set_status(String(definitions.get(id, {}).get("display_name", id)) + " powered off")
        "pressed": _set_status("Button pressed")
        "comparator_subtract": _set_status("Comparator: subtract mode")
        "comparator_compare": _set_status("Comparator: compare mode")
        "daylight_sensor_inverted": _set_status("Daylight sensor: inverted mode")
        "daylight_sensor_normal": _set_status("Daylight sensor: daylight mode")
        "ignited": _set_status("TNT ignited — move away")
        "already_ignited": _set_status("TNT is already ignited")
        "candle_added": _set_status("Candle added (up to four per block)")
        "candle_lit": _set_status("Candle lit")
        "candle_extinguished": _set_status("Candle extinguished")
        "composter_filled": _set_status("Composter level increased")
        "composter_ready": _set_status("Composter ready — use it again for bone meal")
        "composter_bone_meal": _set_status("Bone meal produced; composter emptied")
        "bell_ringing": _set_status("Bell rung")
        _:
            _set_status(action.replace("_", " ").capitalize())

func _refresh_container_slots() -> void:
    if not is_instance_valid(interaction_panel): return
    var title := interaction_panel.find_child("ContainerTitle", true, false) as Label
    if title != null: title.text = "CONTAINER — %s" % String(definitions.get(world.get_block_id(active_container_cell), {}).get("display_name", "Block"))
    var contents := world.container_contents(active_container_cell)
    var is_shelf := BlockBehaviors.family_for_id(world.get_block_id(active_container_cell)) == "shelf"
    var slot_count := 3 if is_shelf else 27
    if title != null and is_shelf: title.text = "SHELF — %s" % String(definitions.get(world.get_block_id(active_container_cell), {}).get("display_name", "Shelf"))
    while contents.size() < slot_count: contents.append("")
    for i in range(container_slot_buttons.size()):
        container_slot_buttons[i].visible = i < slot_count
        if i >= slot_count: continue
        var item_id := String(contents[i]) if i < contents.size() else ""
        container_slot_buttons[i].text = str(i + 1) + "\n" + ("Empty" if item_id.is_empty() else _short_name(String(definitions.get(item_id, {}).get("display_name", item_id))).replace("\n", " "))
        container_slot_buttons[i].tooltip_text = item_id

func _toggle_container_slot(index: int) -> void:
    var contents := world.container_contents(active_container_cell)
    while contents.size() < 27: contents.append("")
    var stored := String(contents[index])
    var held := String(hotbar[selected_slot])
    contents[index] = held
    hotbar[selected_slot] = stored
    if not definitions.has(hotbar[selected_slot]): hotbar[selected_slot] = ""
    world.set_container_contents(active_container_cell, contents)
    _refresh_container_slots()
    _refresh_hotbar()

func _close_container() -> void:
    if interaction_panel != null: interaction_panel.visible = false
    player.set_gameplay_paused(false)
    player.set_mouse_capture(true)
    player.look_enabled = true
    if world.placed_blocks.has(active_container_cell):
        var state := world.get_block_state(active_container_cell)
        state["open"] = false
        world._replace_state_visual(active_container_cell, state)

func _commit_sign_text() -> void:
    world.set_sign_text(active_container_cell, sign_editor.text)
    _set_status("Sign text saved")
    player.set_gameplay_paused(false)
    player.set_mouse_capture(true)
    player.look_enabled = true

func _jump_or_rise() -> void:
    if player.is_flying:
        player.set_mobile_vertical(1.0)
        await get_tree().create_timer(0.28).timeout
        if is_instance_valid(player): player.set_mobile_vertical(0.0)
    else:
        player.velocity.y = player.jump_velocity

func _set_vertical_for_moment(direction_value: float) -> void:
    if not player.is_flying:
        player.toggle_flight()
    player.set_mobile_vertical(direction_value)
    await get_tree().create_timer(0.35).timeout
    if is_instance_valid(player): player.set_mobile_vertical(0.0)

func _mark_settings_dirty() -> void:
    if world != null: world._set_dirty(true)

func _on_dirty_changed(value: bool) -> void:
    if status_label == null: return
    if value: status_label.text = "Unsaved changes"
    else: status_label.text = "Saved"
    dirty_status_timer = 4.0

func _set_status(message: String) -> void:
    if status_label == null: return
    status_label.text = message
    dirty_status_timer = 3.0

func _update_diagnostics() -> void:
    var fps := Engine.get_frames_per_second()
    var used_memory := OS.get_static_memory_usage() / 1048576.0
    var pos := player.global_position
    diagnostics_label.text = "Godot %s  |  FPS %d  |  RAM %.0f MB\n" % [Engine.get_version_info().get("string", "unknown"), fps, used_memory]
    diagnostics_label.text += "Player: %.1f, %.1f, %.1f  |  Chunks %d  |  Models %d\n" % [pos.x, pos.y, pos.z, world.chunks.size(), model_items.size()]
    diagnostics_label.text += "Placed: %d  |  Removed: %d  |  Materials %s  |  Save: %s" % [world.placed_blocks.size(), world.removed_cells.size(), str(resolver.cache_counts()), world_name]

func save_world(silent: bool = false) -> bool:
    if world == null: return false
    var camera_pitch := float(player.camera_pitch)
    var data := {
        "schema_version": 2,
        "world_name": world_name,
        "saved_at_unix": int(Time.get_unix_time_from_system()),
        "world_time_seconds": _world_time_seconds,
        "world_preset": "classic_flat",
        "ground_layers": [{"y": 0, "id": "grass_block"}, {"y": -1, "id": "dirt"}, {"y": -2, "id": "dirt"}, {"y": -3, "id": "bedrock"}],
        "placed_blocks": world.all_placed_for_save(),
        "removed_cells": world.removed_for_save(),
        "player": {"position": [player.position.x, player.position.y, player.position.z], "yaw": player.rotation.y, "pitch": camera_pitch, "flying": player.is_flying, "spawn_position": [spawn_position.x, spawn_position.y, spawn_position.z]},
        "hotbar": hotbar,
        "selected_slot": selected_slot,
        "settings": {"render_distance": render_distance, "look_sensitivity": look_sensitivity, "touch_sensitivity": touch_sensitivity, "use_webp_maps": resolver.use_webp_maps, "ui_scale": ui_scale}
    }
    var file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
    if file == null:
        _set_status("Save failed: could not open temporary file")
        return false
    file.store_string(JSON.stringify(data))
    file.flush()
    file.close()
    var absolute_save := ProjectSettings.globalize_path(SAVE_PATH)
    var absolute_temp := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
    var absolute_backup := ProjectSettings.globalize_path(SAVE_BACKUP_PATH)
    if FileAccess.file_exists(SAVE_PATH):
        if FileAccess.file_exists(SAVE_BACKUP_PATH): DirAccess.remove_absolute(absolute_backup)
        var backup_error := DirAccess.rename_absolute(absolute_save, absolute_backup)
        if backup_error != OK:
            _set_status("Save failed: could not create backup")
            return false
    var error := DirAccess.rename_absolute(absolute_temp, absolute_save)
    if error != OK:
        if FileAccess.file_exists(SAVE_BACKUP_PATH): DirAccess.rename_absolute(absolute_backup, absolute_save)
        _set_status("Save failed: could not replace world file")
        return false
    if FileAccess.file_exists(SAVE_BACKUP_PATH): DirAccess.remove_absolute(absolute_backup)
    world.mark_saved()
    if not silent: _set_status("World saved successfully")
    return true

func _load_world_save(show_message: bool = true) -> void:
    if not FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(SAVE_BACKUP_PATH):
        DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_BACKUP_PATH), ProjectSettings.globalize_path(SAVE_PATH))
    if not FileAccess.file_exists(SAVE_PATH):
        if show_message: _set_status("No saved world found; starting a new flat world")
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        _set_status("Load failed: save file could not be opened")
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        _set_status("Load failed: save file is malformed")
        return
    var data: Dictionary = parsed
    if int(data.get("schema_version", 0)) not in [1, 2]:
        _set_status("Load failed: unsupported save schema")
        return
    world_name = String(data.get("world_name", "My Creative World"))
    _world_time_seconds = fposmod(float(data.get("world_time_seconds", 600.0)), 1200.0)
    var placed_rows: Array = data.get("placed_blocks", [])
    var removed_rows: Array = data.get("removed_cells", [])
    world.restore_state(placed_rows, removed_rows)
    var p: Dictionary = data.get("player", {})
    var pos: Array = p.get("position", [0.0, 0.51, 7.0])
    if pos.size() >= 3: player.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
    player.apply_saved_view(float(p.get("yaw", 0.0)), float(p.get("pitch", -0.28)))
    player.is_flying = bool(p.get("flying", false))
    var saved_spawn: Array = p.get("spawn_position", [0.0, 0.51, 7.0])
    if saved_spawn.size() >= 3: spawn_position = Vector3(float(saved_spawn[0]), float(saved_spawn[1]), float(saved_spawn[2]))
    var saved_hotbar: Array = data.get("hotbar", hotbar)
    for i in range(mini(9, saved_hotbar.size())):
        var id := String(saved_hotbar[i])
        if definitions.has(id): hotbar[i] = id
    selected_slot = clampi(int(data.get("selected_slot", 0)), 0, 8)
    var settings: Dictionary = data.get("settings", {})
    render_distance = clampi(int(settings.get("render_distance", render_distance)), 1, 5)
    world.render_radius_chunks = render_distance
    look_sensitivity = clampf(float(settings.get("look_sensitivity", look_sensitivity)), 0.0008, 0.006)
    touch_sensitivity = clampf(float(settings.get("touch_sensitivity", touch_sensitivity)), 0.001, 0.008)
    resolver.set_webp_mode(bool(settings.get("use_webp_maps", false)))
    ui_scale = float(settings.get("ui_scale", 1.0))
    player.mouse_sensitivity = look_sensitivity
    player.touch_sensitivity = touch_sensitivity
    _refresh_hotbar()
    world.ensure_around(player.global_position)
    world.mark_saved()
    if show_message: _set_status("Loaded " + world_name)

func _show_boot_error(message: String) -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var label := Label.new()
    label.text = "VOXEL CREATIVE FLATWORLD\n\n" + message
    label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    label.size = Vector2(650, 200)
    label.position = Vector2(-325, -100)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layer.add_child(label)
