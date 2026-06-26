// hologram.gdshader
// Sci-fi / arcane hologram: scanlines, fresnel rim, subtle flicker. Great for
// quest markers, shop holograms, claw-machine prize previews, ghost NPCs.
// Apply via res://assets/materials/HologramMaterial.tres.
shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

uniform vec3 holo_color : source_color = vec3(0.3, 0.8, 1.0);
uniform float scan_density = 60.0;
uniform float scan_speed = 3.0;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.15;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.0;
uniform float alpha : hint_range(0.0, 1.0) = 0.7;

float hash(float x) {
	return fract(sin(x) * 43758.5453);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float scan = 0.5 + 0.5 * sin(UV.y * scan_density - TIME * scan_speed);
	float flicker = 1.0 - flicker_strength * hash(floor(TIME * 12.0));
	vec3 col = holo_color * (0.6 + 0.4 * scan + fres);
	ALBEDO = col * flicker;
	ALPHA = clamp((alpha * scan + fres) * flicker, 0.0, 1.0);
}
