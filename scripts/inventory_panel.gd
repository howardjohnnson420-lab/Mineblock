extends Control
class_name CreativeInventoryPanel

signal item_chosen(id: String)
signal close_requested
signal settings_changed

var page_size: int = 30
const CATEGORIES: Array[String] = ["Construction", "Equipment", "Items", "Nature", "All"]
var all_items: Array[Dictionary] = []
var resolver: MaterialResolver
var category: String = "All"
var page: int = 0
var search_text: String = ""
var filtered: Array[Dictionary] = []
var search_box: LineEdit
var grid: GridContainer
var page_label: Label
var detail_label: Label
var selected_id: String = ""
var panel_box: PanelContainer
var use_webp_toggle: CheckBox

func build(items: Array[Dictionary], material_resolver: MaterialResolver) -> void:
    all_items = items
    resolver = material_resolver
    _build_layout()
    _apply_filter()

func _build_layout() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    var dim := ColorRect.new()
    dim.color = Color(0.015, 0.025, 0.045, 0.78)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    panel_box = PanelContainer.new()
    panel_box.anchor_left = 0.04; panel_box.anchor_top = 0.04
    panel_box.anchor_right = 0.96; panel_box.anchor_bottom = 0.96
    panel_box.add_theme_stylebox_override("panel", _style_box(Color(0.08, 0.12, 0.17, 0.98), Color(0.36, 0.52, 0.63, 0.95), 2, 12))
    add_child(panel_box)
    var main_col := VBoxContainer.new()
    main_col.add_theme_constant_override("separation", 8)
    panel_box.add_child(main_col)
    var header := HBoxContainer.new()
    main_col.add_child(header)
    var title := Label.new()
    title.text = "CREATIVE INVENTORY"
    title.add_theme_font_size_override("font_size", 24)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    use_webp_toggle = CheckBox.new()
    use_webp_toggle.text = "Use optional WebP maps"
    use_webp_toggle.button_pressed = resolver.use_webp_maps
    use_webp_toggle.toggled.connect(func(value: bool): resolver.set_webp_mode(value); settings_changed.emit())
    header.add_child(use_webp_toggle)
    var close := Button.new()
    close.text = "Close  ×"
    close.custom_minimum_size = Vector2(96, 42)
    close.pressed.connect(func(): close_requested.emit())
    header.add_child(close)
    var tabs := HFlowContainer.new()
    tabs.add_theme_constant_override("h_separation", 6)
    tabs.add_theme_constant_override("v_separation", 6)
    main_col.add_child(tabs)
    for cat in CATEGORIES:
        var category_value := cat
        var tab := Button.new()
        tab.text = category_value
        tab.custom_minimum_size = Vector2(110, 42)
        tab.toggle_mode = true
        tab.button_pressed = category_value == category
        tab.pressed.connect(func():
            category = category_value
            page = 0
            _apply_filter()
            _sync_tab_states(tabs)
        )
        tabs.add_child(tab)
    var search_row := HBoxContainer.new()
    main_col.add_child(search_row)
    search_box = LineEdit.new()
    search_box.placeholder_text = "Search 1,245 models by name, material, family or tag…"
    search_box.clear_button_enabled = true
    search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    search_box.custom_minimum_size.y = 42
    search_box.text_changed.connect(func(value: String): search_text = value; page = 0; _apply_filter())
    search_row.add_child(search_box)
    var count_label := Label.new()
    count_label.text = "Asset library"
    count_label.custom_minimum_size.x = 110
    search_row.add_child(count_label)
    var detail := HBoxContainer.new()
    main_col.add_child(detail)
    detail_label = Label.new()
    detail_label.text = "Tap a model to assign it to your selected hotbar slot."
    detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    detail.add_child(detail_label)
    var clear := Button.new()
    clear.text = "Clear search"
    clear.pressed.connect(func(): search_box.clear())
    detail.add_child(clear)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    main_col.add_child(scroll)
    grid = GridContainer.new()
    grid.columns = clampi(int((get_viewport_rect().size.x * 0.92 - 50.0) / 155.0), 2, 6)
    page_size = grid.columns * 5
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 8)
    scroll.add_child(grid)
    var footer := HBoxContainer.new()
    footer.alignment = BoxContainer.ALIGNMENT_CENTER
    main_col.add_child(footer)
    var prev := Button.new()
    prev.text = "‹ Previous"
    prev.custom_minimum_size = Vector2(120, 40)
    prev.pressed.connect(func(): page = maxi(0, page - 1); _populate_grid())
    footer.add_child(prev)
    page_label = Label.new()
    page_label.custom_minimum_size.x = 220
    page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    footer.add_child(page_label)
    var next := Button.new()
    next.text = "Next ›"
    next.custom_minimum_size = Vector2(120, 40)
    next.pressed.connect(func():
        var pages := maxi(1, ceili(filtered.size() / float(page_size)))
        page = mini(pages - 1, page + 1)
        _populate_grid()
    )
    footer.add_child(next)

func _style_box(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(border_width)
    style.set_corner_radius_all(radius)
    style.content_margin_left = 14
    style.content_margin_right = 14
    style.content_margin_top = 12
    style.content_margin_bottom = 12
    return style

func _sync_tab_states(tabs: HFlowContainer) -> void:
    for child in tabs.get_children():
        var button := child as Button
        button.button_pressed = button.text == category

func _apply_filter() -> void:
    filtered.clear()
    var query := search_text.strip_edges().to_lower()
    for item in all_items:
        if category != "All" and String(item.get("category", "")) != category:
            continue
        if query.is_empty():
            filtered.append(item)
            continue
        var haystack := "%s %s %s %s %s %s" % [String(item.get("id", "")), String(item.get("display_name", "")), String(item.get("material_key", "")), String(item.get("classification", "")), " ".join(PackedStringArray(item.get("search_tokens", []))), String(item.get("category", ""))]
        if haystack.to_lower().contains(query): filtered.append(item)
    page = clampi(page, 0, maxi(0, ceili(filtered.size() / float(page_size)) - 1))
    _populate_grid()

func _populate_grid() -> void:
    if grid == null: return
    for child in grid.get_children(): child.queue_free()
    var pages := maxi(1, ceili(filtered.size() / float(page_size)))
    page_label.text = "Page %d / %d   •   %d results" % [page + 1, pages, filtered.size()]
    var first := page * page_size
    var last := mini(filtered.size(), first + page_size)
    for i in range(first, last):
        var item: Dictionary = filtered[i]
        grid.add_child(_make_item_card(item))

func _make_item_card(item: Dictionary) -> Button:
    var id := String(item.get("id", ""))
    var button := Button.new()
    var available_width := get_viewport_rect().size.x * 0.92 - 85.0 - float(maxi(0, grid.columns - 1) * 8)
    var card_width := maxf(125.0, available_width / float(grid.columns))
    button.custom_minimum_size = Vector2(card_width, 128)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.clip_contents = true
    button.add_theme_stylebox_override("normal", _style_box(Color(0.12, 0.18, 0.24, 0.96), Color(0.23, 0.35, 0.42, 0.8), 1, 8))
    button.add_theme_stylebox_override("hover", _style_box(Color(0.19, 0.29, 0.36, 1), Color(0.55, 0.82, 0.98, 1), 2, 8))
    button.add_theme_stylebox_override("pressed", _style_box(Color(0.21, 0.36, 0.43, 1), Color(0.74, 0.9, 1, 1), 2, 8))
    var preview_container := SubViewportContainer.new()
    preview_container.anchor_left = 0.08; preview_container.anchor_top = 0.02
    preview_container.anchor_right = 0.92; preview_container.anchor_bottom = 0.66
    preview_container.stretch = true
    preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.add_child(preview_container)
    var preview := SubViewport.new()
    preview.size = Vector2i(128, 86)
    preview.transparent_bg = true
    preview.own_world_3d = true
    preview.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
    preview_container.add_child(preview)
    var stage := Node3D.new()
    preview.add_child(stage)
    var packed := load(String(item.get("model_path", ""))) as PackedScene
    if packed != null:
        var model_root := packed.instantiate() as Node3D
        if model_root != null:
            _apply_preview_materials(model_root, item)
            var bounds: Array = item.get("bounds", [[-0.5,-0.5,-0.5],[0.5,0.5,0.5]])
            var center := Vector3.ZERO
            var size := Vector3.ONE
            if bounds.size() >= 2:
                var lo: Array = bounds[0]; var hi: Array = bounds[1]
                if lo.size() >= 3 and hi.size() >= 3:
                    center = Vector3((float(lo[0])+float(hi[0]))*0.5, (float(lo[1])+float(hi[1]))*0.5, (float(lo[2])+float(hi[2]))*0.5)
                    size = Vector3(absf(float(hi[0])-float(lo[0])), absf(float(hi[1])-float(lo[1])), absf(float(hi[2])-float(lo[2])))
            model_root.position = -center
            stage.add_child(model_root)
            var camera := Camera3D.new()
            var max_dim := maxf(size.x, maxf(size.y, size.z))
            var distance := maxf(0.28, max_dim * 2.1)
            camera.position = Vector3(distance * 0.85, distance * 0.62, distance * 1.05)
            camera.fov = 38.0
            stage.add_child(camera)
            camera.look_at(Vector3.ZERO, Vector3.UP)
            camera.current = true
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-42, -28, 0)
    light.light_energy = 1.25
    stage.add_child(light)
    var fill := OmniLight3D.new()
    fill.position = Vector3(-1.5, 1.2, 1.8)
    fill.light_energy = 0.55
    fill.omni_range = 6.0
    stage.add_child(fill)
    var label := Label.new()
    label.anchor_left = 0.03; label.anchor_top = 0.68
    label.anchor_right = 0.97; label.anchor_bottom = 0.98
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.text = String(item.get("display_name", id))
    label.add_theme_font_size_override("font_size", 12)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.add_child(label)
    button.pressed.connect(func():
        selected_id = id
        detail_label.text = "%s  •  %s  •  %s" % [String(item.get("display_name", id)), String(item.get("category", "Uncategorised")), String(item.get("classification", "asset"))]
        item_chosen.emit(id)
    )
    return button

func _apply_preview_materials(root: Node, definition: Dictionary) -> void:
    if resolver == null: return
    if root is MeshInstance3D:
        var mi := root as MeshInstance3D
        mi.mesh = resolver.prepare_mesh(definition, mi.mesh, mi)
    for child in root.get_children(): _apply_preview_materials(child, definition)
