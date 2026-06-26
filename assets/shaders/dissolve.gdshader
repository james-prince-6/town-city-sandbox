// dissolve.gdshader
// Noise-driven dissolve/burn with a glowing leading edge. Drive `dissolve` from
// 0.0 (solid) -> 1.0 (gone) via a Tween or AnimationPlayer for enemy deaths,
// harvestable breaks, teleport-in effects, etc.
//
//   var mat := mesh.get_active_material(0)
//   create_tween().tween_method(func(v): mat.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.6)
//
// Apply via res://assets/materials/DissolveMaterial.tres.
shader_type spatial;
render_mode blend_mix, cull_back;

uniform vec3 albedo : source_color = vec3(0.55, 0.55, 0.60);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 edge_color : source_color = vec3(1.0, 0.5, 0.1);
uniform float edge_width : hint_range(0.0, 0.3) = 0.06;
uniform float edge_strength : hint_range(0.0, 8.0) = 4.0;
uniform float noise_scale = 8.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			   mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float n = vnoise(UV * noise_scale);
	if (n < dissolve) {
		discard;
	}
	ALBEDO = albedo;
	ROUGHNESS = 0.7;
	float edge = smoothstep(dissolve, dissolve + edge_width, n);
	EMISSION = edge_color * (1.0 - edge) * edge_strength;
}
