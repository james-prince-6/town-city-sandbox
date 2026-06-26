// energy_crystal.gdshader
// Translucent glowing gemstone — fresnel-tinted faces, a pulsing inner core and
// rim light. Used by the new Crystal Cluster harvestable and the Crystal Lamp prop.
// Apply via res://assets/materials/EnergyCrystalMaterial.tres.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley;

uniform vec3 crystal_color : source_color = vec3(0.40, 0.90, 1.0);
uniform vec3 core_color : source_color = vec3(0.80, 0.95, 1.0);
uniform float emission_strength : hint_range(0.0, 6.0) = 1.6;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;
uniform float pulse_speed = 1.5;
uniform float alpha : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
	vec3 col = mix(crystal_color, core_color, fres);
	ALBEDO = col;
	ROUGHNESS = 0.15;
	METALLIC = 0.0;
	EMISSION = mix(crystal_color, core_color, pulse) * emission_strength * (0.4 + fres);
	ALPHA = clamp(alpha + fres * 0.15, 0.0, 1.0);
	RIM = 0.6;
}
