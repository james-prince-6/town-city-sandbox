// magic_portal.gdshader
// Swirling vortex disc for teleporters / dungeon entrances. Maps a polar swirl
// over UV space, brightest in the centre, fading to a clean circular edge.
// Best on a QuadMesh / PlaneMesh facing the player. Pairs with global/teleport area.
// Apply via res://assets/materials/PortalMaterial.tres.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

uniform vec3 inner_color : source_color = vec3(0.55, 0.15, 0.95);
uniform vec3 outer_color : source_color = vec3(0.10, 0.60, 1.0);
uniform float swirl_speed = 1.0;
uniform float arms = 5.0;
uniform float emission_strength : hint_range(0.0, 6.0) = 2.0;

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float a = atan(c.y, c.x);
	float swirl = sin(a * arms + r * 6.0 - TIME * swirl_speed * 3.0);
	float glow = smoothstep(1.0, 0.0, r);     // bright core
	float ring = 0.5 + 0.5 * swirl;
	vec3 col = mix(outer_color, inner_color, glow);
	col *= (0.4 + 0.6 * ring);
	float disc = smoothstep(1.0, 0.85, r);     // soft circular cutoff
	ALBEDO = col * (1.0 + glow * emission_strength);
	ALPHA = disc;
}
