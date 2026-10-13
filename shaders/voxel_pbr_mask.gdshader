shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, depth_draw_opaque, cull_back;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D height_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D webp_albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D webp_normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D webp_roughness_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D webp_displacement_texture : filter_linear_mipmap_anisotropic;
uniform bool use_webp_maps = false;
uniform vec4 base_color_factor : source_color = vec4(1.0);
uniform float roughness_factor = 1.0;
uniform float metallic_factor = 1.0;
uniform float height_normal_strength = 0.18;
uniform float alpha_cutoff = 0.42;
void fragment() {
    vec4 base_sample; vec3 tangent_normal; float rough_sample;
    float h_left; float h_right; float h_up; float h_down;
    if (use_webp_maps) {
        base_sample = texture(webp_albedo_texture, UV); tangent_normal = texture(webp_normal_texture, UV).rgb * 2.0 - 1.0;
        rough_sample = texture(webp_roughness_texture, UV).r;
        h_left = texture(webp_displacement_texture, UV - vec2(0.00035, 0.0)).r; h_right = texture(webp_displacement_texture, UV + vec2(0.00035, 0.0)).r;
        h_up = texture(webp_displacement_texture, UV - vec2(0.0, 0.00070)).r; h_down = texture(webp_displacement_texture, UV + vec2(0.0, 0.00070)).r;
    } else {
        base_sample = texture(albedo_texture, UV); tangent_normal = texture(normal_texture, UV).rgb * 2.0 - 1.0;
        rough_sample = texture(orm_texture, UV).g;
        h_left = texture(height_texture, UV - vec2(0.00035, 0.0)).r; h_right = texture(height_texture, UV + vec2(0.00035, 0.0)).r;
        h_up = texture(height_texture, UV - vec2(0.0, 0.00070)).r; h_down = texture(height_texture, UV + vec2(0.0, 0.00070)).r;
    }
    vec4 tinted = base_sample * base_color_factor;
    ALBEDO = tinted.rgb; ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
    tangent_normal.xy += vec2(h_left - h_right, h_up - h_down) * height_normal_strength;
    NORMAL_MAP = normalize(tangent_normal) * 0.5 + 0.5;
    AO = texture(orm_texture, UV).r; ROUGHNESS = clamp(rough_sample * roughness_factor, 0.04, 1.0);
    METALLIC = clamp(texture(orm_texture, UV).b * metallic_factor, 0.0, 1.0);
}
