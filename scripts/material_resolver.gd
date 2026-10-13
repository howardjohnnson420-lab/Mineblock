extends RefCounted
class_name MaterialResolver

const SHADER_OPAQUE: Shader = preload("res://shaders/voxel_pbr_opaque.gdshader")
const SHADER_MASK: Shader = preload("res://shaders/voxel_pbr_mask.gdshader")
const SHADER_BLEND: Shader = preload("res://shaders/voxel_pbr_blend.gdshader")
var use_webp_maps: bool = false
var _texture_cache: Dictionary = {}
var _material_cache: Dictionary = {}
var _model_by_material_key: Dictionary = {}

func _texture(path: String) -> Texture2D:
    if path.is_empty(): return null
    if _texture_cache.has(path): return _texture_cache[path] as Texture2D
    var loaded: Resource = load(path)
    if loaded is Texture2D:
        _texture_cache[path] = loaded
        return loaded as Texture2D
    push_warning("Material texture failed to load: " + path)
    return null

func _get_shader(alpha_mode: String) -> Shader:
    if alpha_mode == "MASK": return SHADER_MASK
    if alpha_mode == "BLEND": return SHADER_BLEND
    return SHADER_OPAQUE

func _apply_material_textures(sm: ShaderMaterial, model: Dictionary) -> void:
    # Load only the selected map set, with the PNG ORM retained for AO/metallic in both modes.
    var webp: Dictionary = model.get("webp_maps", {})
    sm.set_shader_parameter("orm_texture", _texture(String(model.get("orm_path", ""))))
    if use_webp_maps:
        var webp_albedo := String(webp.get("albedo", ""))
        var webp_normal := String(webp.get("normal", ""))
        var webp_roughness := String(webp.get("roughness", ""))
        var webp_displacement := String(webp.get("displacement", ""))
        sm.set_shader_parameter("webp_albedo_texture", _texture(webp_albedo if not webp_albedo.is_empty() else String(model.get("base_color_path", ""))))
        sm.set_shader_parameter("webp_normal_texture", _texture(webp_normal if not webp_normal.is_empty() else String(model.get("normal_path", ""))))
        sm.set_shader_parameter("webp_roughness_texture", _texture(webp_roughness if not webp_roughness.is_empty() else String(model.get("orm_path", ""))))
        sm.set_shader_parameter("webp_displacement_texture", _texture(webp_displacement if not webp_displacement.is_empty() else String(model.get("height_path", ""))))
    else:
        sm.set_shader_parameter("albedo_texture", _texture(String(model.get("base_color_path", ""))))
        sm.set_shader_parameter("normal_texture", _texture(String(model.get("normal_path", ""))))
        sm.set_shader_parameter("height_texture", _texture(String(model.get("height_path", ""))))
    sm.set_shader_parameter("use_webp_maps", use_webp_maps)

func _make_material(model: Dictionary, source_material: Material) -> ShaderMaterial:
    var alpha_mode := String(model.get("alpha_mode", "OPAQUE"))
    var model_id := String(model.get("id", ""))
    if model_id == "water": alpha_mode = "BLEND"
    var source_color := Color.WHITE
    if source_material is BaseMaterial3D:
        source_color = (source_material as BaseMaterial3D).albedo_color
    if model_id == "water": source_color.a = 0.48
    var cache_key := "%s|%s|%s" % [model_id if not model_id.is_empty() else "unknown", alpha_mode, str(source_color)]
    if _material_cache.has(cache_key):
        var cached := _material_cache[cache_key] as ShaderMaterial
        _apply_material_textures(cached, model)
        return cached
    var sm := ShaderMaterial.new()
    sm.shader = _get_shader(alpha_mode)
    _apply_material_textures(sm, model)
    sm.set_shader_parameter("base_color_factor", source_color)
    sm.set_shader_parameter("roughness_factor", maxf(0.04, float(model.get("roughness", 0.8))))
    sm.set_shader_parameter("metallic_factor", maxf(0.0, float(model.get("metallic", 1.0))))
    sm.set_shader_parameter("height_normal_strength", 0.18)
    if alpha_mode == "MASK": sm.set_shader_parameter("alpha_cutoff", 0.42)
    _material_cache[cache_key] = sm
    _model_by_material_key[cache_key] = model.duplicate(true)
    return sm

func material_for_model(model: Dictionary, source_material: Material = null) -> ShaderMaterial:
    return _make_material(model, source_material)

func prepare_mesh(model: Dictionary, source_mesh: Mesh, mesh_instance: MeshInstance3D) -> Mesh:
    if source_mesh == null: return null
    var result := source_mesh.duplicate() as Mesh
    if result == null: return source_mesh
    for index in range(result.get_surface_count()):
        result.surface_set_material(index, _make_material(model, mesh_instance.get_active_material(index)))
    return result

func set_webp_mode(enabled: bool) -> void:
    if use_webp_maps == enabled: return
    use_webp_maps = enabled
    for key in _material_cache.keys():
        var material := _material_cache[key] as ShaderMaterial
        var model: Dictionary = _model_by_material_key.get(key, {})
        if material != null and not model.is_empty(): _apply_material_textures(material, model)

func texture_for_inventory(model: Dictionary) -> Texture2D:
    return _texture(String(model.get("icon_path", model.get("base_color_path", ""))))

func cache_counts() -> Dictionary:
    return {"textures": _texture_cache.size(), "materials": _material_cache.size()}
