// force_field.gdshader
// Additive fresnel energy shield with travelling scanlines and a soft pulse.
// Unshaded + additive so it reads as glowing energy on any mesh (dome, wall, bubble).
// Apply via res://assets/materials/ForceFieldMaterial.tres.
shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

uniform vec3 field_color : source_color = vec3(0.2, 0.6, 1.0);
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float scan_speed = 1.5;
uniform float scan_density = 24.0;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.12;
uniform float pulse_strength : hint_range(0.0, 2.0) = 0.6;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float scan = 0.5 + 0.5 * sin(UV.y * scan_density - TIME * scan_speed);
	float pulse = 0.5 + 0.5 * sin(TIME * 2.0);
	vec3 col = field_color * (1.0 + pulse * pulse_strength);
	ALBEDO = col * (fres + scan * 0.3 + base_alpha);
	ALPHA = clamp(base_alpha + fres + scan * 0.15, 0.0, 1.0);
}
